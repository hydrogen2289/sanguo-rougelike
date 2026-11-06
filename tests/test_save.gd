extends "res://tests/test_base.gd"
## test_save(M7,02 §3 / §12.2-1):
## 存档读写往返一致;坏档回退 .bak;version 迁移骨架;幂等 flush;
## roster/squad 校验拦截非法值;原子写无 .tmp 残留;删档重开;
## 局内军资不入库(RunState 与 SaveState 解耦);SceneRouter 模式上下文注入;
## 主城场景冒烟(五入口可见 + TopBar 初始余额 0/0)。
## 存档走测试专用文件名 test_save_unit.json,套件结束清理并恢复默认,不碰玩家真实存档。
## 依赖 run_all.gd 先手动注册 autoload(含 SaveState)。

var _st: SceneTree

func _run() -> void:
	_st = Engine.get_main_loop() as SceneTree
	DataDB.load_all()
	var old_file: String = SaveState.save_file
	SaveState.save_file = "test_save_unit.json"
	_clear()
	_test_new_defaults()
	_test_roundtrip()
	_test_flush_idempotent()
	_test_atomic_and_bak()
	_test_corrupt_fallback()
	_test_migrate_and_normalize()
	_test_validation_rejects()
	_test_delete_and_reopen()
	_test_runstate_decoupled()
	_test_router_prepare()
	await _test_city_and_menu_scene()   # 协程:漏 await 会让 city 残留进全局 group,污染后续套件
	_clear()
	SaveState.save_file = old_file
	SaveState.data = {}
	SaveState.last_note = ""

# ---------------------------------------------------------------- 工具

func _clear() -> void:
	SaveState.delete_save()

func _upath(name: String) -> String:
	return "user://" + name

func _read_user_file(name: String) -> String:
	if not FileAccess.file_exists(_upath(name)):
		return ""
	return FileAccess.get_file_as_string(_upath(name))

func _write_user_file(name: String, content: String) -> void:
	var f := FileAccess.open(_upath(name), FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()

func _find_label_text(root: Node, label_name: String) -> String:
	if root is Label and str(root.name) == label_name:
		return str((root as Label).text)
	for c in root.get_children():
		var t := _find_label_text(c, label_name)
		if t != "":
			return t
	return ""

## 迁移阶梯测试用临时步骤:v1 → v2
func _fake_step_v1_to_v2(d: Dictionary) -> Dictionary:
	d = d.duplicate(true)
	d["future_field"] = true
	d["version"] = 2
	return d

# ---------------------------------------------------------------- 用例

## 新档默认值(02 §3.2 schema + 提案初始值)
func _test_new_defaults() -> void:
	check(not SaveState.has_save(), "清场后无存档文件")
	var r: Dictionary = SaveState.load_game()
	check(bool(r.get("ok", false)), "无档 → 自动建新档 ok")
	check(bool(r.get("created", false)), "无档 → created 标记")
	var d: Dictionary = SaveState.data
	for k in ["version", "updated_at", "wallet", "roster", "squad", "campaign", "tower", "stats", "settings"]:
		check(d.has(k), "schema 顶层字段存在: " + k)
	check(int(d.get("version", 0)) == 1, "新档 version=1")
	check(str(d.get("updated_at", "")).contains("T"), "updated_at 为 ISO 格式")
	check(int(d["wallet"]["junzi"]) == 0 and (d["wallet"]["fragments"] as Dictionary).is_empty(),
		"新档军资 0 / 碎片空(提案初始值,01 §13-2)")
	var hero_ids := {}
	for h in DataDB.heroes:
		hero_ids[str(h.get("id", ""))] = true
	var roster: Dictionary = d["roster"]
	check(roster.size() == hero_ids.size(), "roster 覆盖全部武将 id(%d 名)" % hero_ids.size())
	var covered := true
	for id in hero_ids:
		if not roster.has(id):
			covered = false
	check(covered, "roster id 与 heroes.json 一一对应")
	check(bool(roster["liubei"]["owned"]) and int(roster["liubei"]["level"]) == 1 \
		and int(roster["liubei"]["star"]) == 1 and str(roster["liubei"]["source"]) == "initial",
		"刘备 initial / 1 级 / 1 星")
	check(bool(roster["guanyu"]["owned"]) and bool(roster["zhangfei"]["owned"]), "关羽张飞开局即有")
	check(not bool(roster["zhaoyun"]["owned"]) and int(roster["zhaoyun"]["level"]) == 0, "赵云未拥有 0 级")
	check(d["squad"]["slots"] == ["liubei", "guanyu", "zhangfei"], "初始席位桃园三人组")
	check(int(d["squad"]["slot_cap"]) == 3, "初始席位 3(提案,01 §13-1)")
	check(int(d["tower"]["highest_floor"]) == 0, "塔最高层 0")
	check(not bool(d["settings"]["prologue_seen"]), "序章未播标记 false")
	check(bool(d["campaign"]["chapters"]["ch1"]["unlocked"]), "第一章解锁")
	check((d["campaign"]["chapters"]["ch1"]["stages"] as Dictionary).size() == 8, "第一章 8 关占位(01 §3.5)")

## 读写往返一致(02 §12.2-1)
func _test_roundtrip() -> void:
	SaveState.add_junzi(500)
	SaveState.add_fragments("zhaoyun", 7)
	SaveState.data["roster"]["guanyu"]["level"] = 5
	SaveState.data["campaign"]["chapters"]["ch1"]["stages"]["1-2"]["cleared"] = true
	SaveState.data["campaign"]["chapters"]["ch1"]["stages"]["1-2"]["stars"] = 3
	SaveState.data["tower"]["highest_floor"] = 12
	SaveState.flush()
	SaveState.data = {}                       # 模拟进程重启后内存清空
	var r: Dictionary = SaveState.load_game()
	check(bool(r.get("ok", false)) and not bool(r.get("created", true)), "有档读回 ok 且非新档")
	check(SaveState.junzi() == 500, "军资往返一致")
	check(SaveState.fragments_of("zhaoyun") == 7, "定向碎片往返一致")
	check(int(SaveState.data["roster"]["guanyu"]["level"]) == 5, "养成等级往返一致")
	var stg: Dictionary = SaveState.data["campaign"]["chapters"]["ch1"]["stages"]["1-2"]
	check(bool(stg["cleared"]) and int(stg["stars"]) == 3, "评星/通关往返一致")
	check(int(SaveState.data["tower"]["highest_floor"]) == 12, "塔最高层往返一致")

## 幂等 flush(02 §12.2-1):数据不变时连续落盘,内容稳定
func _test_flush_idempotent() -> void:
	var s1 := _read_user_file(SaveState.save_file)
	SaveState.flush()
	var s2 := _read_user_file(SaveState.save_file)
	check(s1 != "" and s2 != "", "连续 flush 均落盘")
	var p1 = JSON.parse_string(s1)
	var p2 = JSON.parse_string(s2)
	check(p1 != null and p2 != null, "两次 flush 产物均可解析")
	if p1 != null and p2 != null:
		p1.erase("updated_at")
		p2.erase("updated_at")
		check(p1 == p2, "幂等 flush:内容一致(除 updated_at 时间戳)")

## 原子写(02 §3.1):无 .tmp 残留;.bak 单级回滚生效
func _test_atomic_and_bak() -> void:
	check(not FileAccess.file_exists(_upath(SaveState.save_file + ".tmp")), "原子写后无 .tmp 残留")
	check(FileAccess.file_exists(_upath(SaveState.save_file + ".bak")), ".bak 单级回滚已生成")
	# 主档损坏 → 回退 .bak
	_write_user_file(SaveState.save_file, "{corrupt!! not json")
	var r: Dictionary = SaveState.load_game()
	check(bool(r.get("ok", false)) and bool(r.get("warned", false)), "主档损坏 → 回退 .bak 并横幅告警")
	check(SaveState.junzi() == 500, ".bak 内容完整(军资 500)")
	check(not SaveState.last_note.is_empty(), "恢复提示写入 last_note(主城横幅源)")

## 主档 + 备份均不可解析 → 按新档处理(02 §3.1),不崩溃
func _test_corrupt_fallback() -> void:
	SaveState.delete_save()
	_write_user_file(SaveState.save_file, "totally not json")
	var r: Dictionary = SaveState.load_game()
	check(bool(r.get("ok", false)) and bool(r.get("created", false)) and bool(r.get("warned", false)),
		"主档损坏且无备份 → 新档 + 告警")
	check(SaveState.junzi() == 0 and int(SaveState.data["version"]) == 1, "重开新档默认值,不崩溃")

## 版本迁移骨架(02 §3.1)+ 结构修复
func _test_migrate_and_normalize() -> void:
	var d: Dictionary = SaveState.default_save()
	var out: Dictionary = SaveState.migrate(d)
	check(not out.is_empty() and int(out["version"]) == 1, "v1 migrate 直通")
	# 阶梯机制:注册 from=1 的临时步骤,证明梯子可注册、可推进、防死循环
	SaveState._steps[1] = _fake_step_v1_to_v2
	var d1: Dictionary = SaveState.default_save()
	d1["version"] = 1
	var up: Dictionary = SaveState.migrate(d1)
	check(not up.is_empty() and int(up["version"]) == 2 and bool(up.get("future_field", false)),
		"迁移阶梯:注册步骤 1→2 生效")
	SaveState._steps.erase(1)
	var dhigh: Dictionary = SaveState.default_save()
	dhigh["version"] = 99
	check(SaveState.migrate(dhigh).is_empty(), "过新版本拒绝迁移(不降级覆盖)")
	var dlow: Dictionary = SaveState.default_save()
	dlow["version"] = 0
	check(SaveState.migrate(dlow).is_empty(), "过旧/缺版本拒绝迁移")
	# normalize:缺失段落回填默认
	var d2: Dictionary = SaveState.default_save()
	d2.erase("wallet")
	d2.erase("tower")
	(d2["roster"] as Dictionary).erase("guanyu")
	var n: Dictionary = SaveState.normalize(d2)
	check(int(n["wallet"]["junzi"]) == 0, "normalize 回填缺失 wallet")
	check(int(n["tower"]["highest_floor"]) == 0, "normalize 回填缺失 tower")
	check(bool(n["roster"]["guanyu"]["owned"]), "normalize 回填缺失武将条目")

## 校验拦截(02 §3.2):id 合法性 / level-star 区间 / 军资非负 / 席位约束 / 评星区间
func _test_validation_rejects() -> void:
	check(SaveState.validate(SaveState.default_save()).is_empty(), "默认档通过校验")
	var e: Dictionary = SaveState.default_save()
	e["wallet"]["junzi"] = -5
	check(not SaveState.validate(e).is_empty(), "军资为负被拦截")
	e = SaveState.default_save()
	e["roster"]["guanyu"]["level"] = 31
	check(not SaveState.validate(e).is_empty(), "level 越出 [1,30] 被拦截")
	e = SaveState.default_save()
	e["roster"]["guanyu"]["star"] = 6
	check(not SaveState.validate(e).is_empty(), "star 越出 [1,5] 被拦截")
	e = SaveState.default_save()
	e["roster"]["zhaoyun"]["level"] = 3
	check(not SaveState.validate(e).is_empty(), "未拥有却有等级被拦截")
	e = SaveState.default_save()
	e["roster"]["mystery_hero"] = {"owned": true, "level": 1, "star": 1, "source": "recruit"}
	check(not SaveState.validate(e).is_empty(), "roster 非法武将 id 被拦截")
	e = SaveState.default_save()
	e["squad"]["slots"] = ["guanyu", "liubei"]
	check(not SaveState.validate(e).is_empty(), "slots[0] 非主公被拦截")
	e = SaveState.default_save()
	e["squad"]["slots"] = ["liubei", "guanyu", "guanyu"]
	check(not SaveState.validate(e).is_empty(), "席位重复被拦截")
	e = SaveState.default_save()
	e["squad"]["slots"] = ["liubei", "guanyu", "zhangfei", "zhaoyun"]
	check(not SaveState.validate(e).is_empty(), "上阵未拥有武将被拦截")
	e = SaveState.default_save()
	e["squad"]["slot_cap"] = 9
	check(not SaveState.validate(e).is_empty(), "slot_cap 越界被拦截")
	e = SaveState.default_save()
	e["campaign"]["chapters"]["ch1"]["stages"]["1-1"]["stars"] = 4
	check(not SaveState.validate(e).is_empty(), "评星越出 [0,3] 被拦截")
	e = SaveState.default_save()
	e["tower"]["highest_floor"] = -1
	check(not SaveState.validate(e).is_empty(), "最高层为负被拦截")
	e = SaveState.default_save()
	e["settings"]["master_volume"] = 2.0
	check(not SaveState.validate(e).is_empty(), "音量越出 [0,1] 被拦截")
	# 落盘坏档 → load_game 拒绝进主城,且坏档会话 flush 不覆盖原档
	SaveState.delete_save()
	var bad: Dictionary = SaveState.default_save()
	bad["wallet"]["junzi"] = -1
	_write_user_file(SaveState.save_file, JSON.stringify(bad))
	var r: Dictionary = SaveState.load_game()
	check(not bool(r.get("ok", true)), "校验失败 → 拒绝进主城(ok=false)")
	check(str(r.get("reason", "")).contains("校验失败"), "拒绝原因可读")
	var before := _read_user_file(SaveState.save_file)
	SaveState.data = SaveState.default_save()   # 模拟内存有值但会话未过校验
	SaveState.flush()
	check(_read_user_file(SaveState.save_file) == before, "坏档会话 flush 被拒(原档不被覆盖)")
	SaveState.data = {}

## 删档重开(验收 5):删档 → 新档 → 落盘 → 再删档干净
func _test_delete_and_reopen() -> void:
	SaveState.delete_save()
	check(not SaveState.has_save(), "delete_save 后无存档文件")
	check(SaveState.data.is_empty(), "delete_save 清空会话")
	var r: Dictionary = SaveState.load_game()
	check(bool(r.get("created", false)), "删档重开 → 新档")
	check(SaveState.junzi() == 0 and int(SaveState.data["version"]) == 1, "新档默认值,不崩溃")
	SaveState.add_junzi(88)
	SaveState.flush()
	check(SaveState.has_save(), "新档可正常落盘")
	SaveState.delete_save()
	check(not SaveState.has_save(), "再次删档干净")
	check(not FileAccess.file_exists(_upath(SaveState.save_file + ".bak")), ".bak 一并清理")
	check(not FileAccess.file_exists(_upath(SaveState.save_file + ".tmp")), ".tmp 一并清理")

## 局内军资不入库(01 §8.1 / 02 §8.4):RunState 与 SaveState 解耦
func _test_runstate_decoupled() -> void:
	SaveState.load_game()                     # 干净默认档
	RunState.reset(20261106)
	RunState.add_gold(123)
	check(SaveState.junzi() == 0, "局内军资不入库:RunState.gold 不影响 wallet")
	var dump: Dictionary = RunState.dump()
	check(not dump.has("wallet"), "dump 快照无 wallet 键")
	check(dump.has("mode") and dump.has("context"), "dump 快照带模式上下文(M7 增量)")

## SceneRouter 三层路由骨架(02 §7/§8.1):模式上下文注入走向明确
func _test_router_prepare() -> void:
	SceneRouter.prepare_campaign("1-1")
	check(str(RunState.mode) == "campaign", "路由:闯关模式注入 campaign")
	check(str(RunState.context.get("stage_id", "")) == "1-1", "路由:stage_id 注入")
	check(RunState.team.size() == 3 and RunState.gold == 0, "路由 prepare_campaign 已 reset(三人组/零军资)")
	SceneRouter.prepare_tower()
	check(str(RunState.mode) == "tower" and int(RunState.context.get("floor_start", 0)) == 1,
		"路由:塔模式注入 floor_start=1")
	# 坏档 → goto_city 拒绝进主城并横幅(不走场景切换,--script 模式安全)
	SaveState.delete_save()
	var bad: Dictionary = SaveState.default_save()
	bad["squad"]["slots"] = ["guanyu", "liubei"]
	_write_user_file(SaveState.save_file, JSON.stringify(bad))
	var fired := [false]
	var cb := func(_reason: String) -> void: fired[0] = true
	SceneRouter.city_enter_failed.connect(cb)
	SceneRouter.goto_city()
	check(fired[0], "goto_city:坏档 → city_enter_failed 横幅信号")
	SceneRouter.city_enter_failed.disconnect(cb)

## 主城场景冒烟(验收 2/4):五入口可见;TopBar 初始余额 0/0;主菜单脚本可实例化
func _test_city_and_menu_scene() -> void:
	SaveState.load_game()                     # 干净默认档(0/0)
	var city: Node = (load("res://scenes/city/main_city.tscn") as PackedScene).instantiate()
	_st.root.add_child(city)
	await _st.process_frame
	var entries := _st.get_nodes_in_group("hub_entry")
	check(entries.size() == 5, "主城五入口可见(实际 %d)" % entries.size())
	check(_find_label_text(city, "JunziLabel") == "0", "TopBar 军资初始 0(提案)")
	check(_find_label_text(city, "FragLabel") == "0", "TopBar 碎片初始 0(提案)")
	city.queue_free()
	await _st.process_frame
	var menu: Node = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	_st.root.add_child(menu)
	await _st.process_frame
	check(menu.get_child_count() > 0, "主菜单(进入主城版)可实例化无脚本错误")
	menu.queue_free()
	await _st.process_frame
