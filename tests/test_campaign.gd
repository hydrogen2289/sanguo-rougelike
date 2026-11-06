extends "res://tests/test_base.gd"
## test_campaign(M9,任务卡验收 1/2/3、02 §4.2/§4.3/§12.2):
## campaign.json 表加载与查询器(stage_by_id/chapter_list);
## _validate_campaign 坏表 fail-fast(结构/锚点/引用/波次契约);
## 评星三元(01 §3.3 提案默认)/ 首通重复奖励入库(走 SaveState 既有经济管道)/
## 推图解锁(01 §3.4)/ 评星宝箱(01 §8.2 占位);
## 选关→编队→开战真实链路(stage_select → squad_edit → SceneRouter 真路由 → battle)。
## 存档走测试专用文件 test_campaign_unit.json,套件结束清理并恢复默认,不碰玩家真实存档。

const BATTLE_SCENE := "res://scenes/battle.tscn"

var _st: SceneTree

func _run() -> void:
	_st = Engine.get_main_loop() as SceneTree
	DataDB.load_all()
	var old_file: String = SaveState.save_file
	SaveState.save_file = "test_campaign_unit.json"
	SaveState.delete_save()
	_test_table_and_queries()
	_test_validate_fail_fast()
	_test_stars_and_settle()
	_test_progression_and_boxes()
	await _test_select_chain()
	SaveState.delete_save()
	SaveState.save_file = old_file
	SaveState.data = {}

# ---------------------------------------------------------------- 工具

func _fresh_save() -> void:
	SaveState.delete_save()
	SaveState.load_game()

## 全 8 关按给定 outcome 通关入库
func _clear_all(outcome: Dictionary) -> void:
	for s in ["1-1", "1-2", "1-3", "1-4", "1-5", "1-6", "1-7", "1-8"]:
		var r: Dictionary = CampaignSave.settle_stage(s, outcome)
		if not bool(r.get("ok", false)):
			printerr("    [settle] %s 失败: %s" % [s, str(r.get("reason", ""))])

# ---------------------------------------------------------------- 1. 表加载与查询器

func _test_table_and_queries() -> void:
	check(not DataDB.campaign.is_empty(), "campaign.json 已加载")
	var chapters: Array = DataDB.chapter_list()
	check(chapters.size() == 1, "章节 1 章(桃园篇,M9 范围)")
	var ch1: Dictionary = chapters[0]
	check(str(ch1.get("id", "")) == "ch1" and str(ch1.get("name", "")) == "桃园篇", "ch1 桃园篇")
	check(int(ch1.get("order", 0)) == 1, "ch1 order=1")
	var stages: Array = ch1.get("stages", [])
	check(stages.size() == 8, "第一章 8 关(01 §3.5)")
	var ids := {}
	for st in stages:
		ids[str(st.get("id", ""))] = true
	for i in range(1, 9):
		check(ids.has("1-%d" % i), "关卡 1-%d 就位" % i)
	# 查询器(02 §4.2)
	var s1: Dictionary = DataDB.stage_by_id("1-1")
	check(not s1.is_empty(), "stage_by_id('1-1') 命中")
	check(str(s1.get("chapter_id", "")) == "ch1", "stage_by_id 带出 chapter_id")
	check((s1.get("waves", []) as Array).size() == 2, "1-1 共 2 波")
	var s8: Dictionary = DataDB.stage_by_id("1-8")
	check(bool(s8.get("boss_stage", false)), "1-8 为 Boss 关(01 §3.5)")
	check((s8.get("waves", []) as Array).size() == 2, "1-8 共 2 波")
	var w8: Dictionary = (s8.get("waves", []) as Array)[1]
	check((w8.get("composition", {}) as Dictionary).has("huaxiong"), "1-8 末波华雄在场(复用 boss_huaxiong 资产)")
	check(not (w8.get("reinforcement", {}) as Dictionary).is_empty(), "1-8 Boss 波增援配置(同塔 W8 口径)")
	check(DataDB.stage_by_id("9-9").is_empty(), "stage_by_id 坏 id 返回空")
	# 每关 1~3 波(01 §3.1)、after 恒空(02 §4.3)、奖励字段齐备、解锁链(01 §3.4)
	var prev_id := ""
	for st in stages:
		var sid := str(st.get("id", ""))
		var wv: Array = st.get("waves", [])
		check(wv.size() >= 1 and wv.size() <= 3, "%s 波次在 [1,3](短关卡)" % sid)
		var all_empty_after := true
		for w in wv:
			if not (w.get("after", []) as Array).is_empty():
				all_empty_after = false
		check(all_empty_after, "%s 闯关 after 队列恒为空" % sid)
		check(int(st.get("first_clear", {}).get("junzi", 0)) > 0, "%s 有首通奖励" % sid)
		check(int(st.get("repeat_clear", {}).get("junzi", 0)) > 0, "%s 有重复奖励" % sid)
		var ua = st.get("unlock_after")
		if sid == "1-1":
			check(ua == null, "1-1 为入门关(unlock_after=null)")
		else:
			check(str(ua) == prev_id, "%s unlock_after=%s(通关前一关解锁,01 §3.4)" % [sid, str(ua)])
		prev_id = sid

# ---------------------------------------------------------------- 2. 坏表 fail-fast

func _validate_probe(campaign) -> int:
	DataDB.campaign = campaign
	DataDB.last_errors = PackedStringArray()
	DataDB._validate_campaign()
	return DataDB.last_errors.size()

func _test_validate_fail_fast() -> void:
	DataDB.load_all()
	check(DataDB.last_errors.is_empty(), "现场表通过全量校验(campaign 合法)")
	var base: Dictionary = DataDB.campaign.duplicate(true)
	# 缺 chapters
	var bad: Dictionary = base.duplicate(true)
	bad.erase("chapters")
	check(_validate_probe(bad) > 0, "坏表:缺 chapters 被拦截")
	# 关卡无波次
	bad = base.duplicate(true)
	(bad["chapters"][0]["stages"][2] as Dictionary)["waves"] = []
	check(_validate_probe(bad) > 0, "坏表:关卡无波次被拦截")
	# 波次锚点越界(duration 90)
	bad = base.duplicate(true)
	(bad["chapters"][0]["stages"][0]["waves"][0] as Dictionary)["duration"] = 90
	check(_validate_probe(bad) > 0, "坏表:波次 duration 越锚点被拦截(同 waves 契约)")
	# composition 引用未知敌人
	bad = base.duplicate(true)
	(bad["chapters"][0]["stages"][0]["waves"][0] as Dictionary)["composition"] = {"mystery_zu": 3}
	check(_validate_probe(bad) > 0, "坏表:composition 引用未知敌人被拦截")
	# after 队列非空(闯关恒空,02 §4.3)
	bad = base.duplicate(true)
	(bad["chapters"][0]["stages"][0]["waves"][0] as Dictionary)["after"] = ["triselect"]
	check(_validate_probe(bad) > 0, "坏表:闯关 after 非空被拦截")
	# unlock_after 引用不存在的关卡
	bad = base.duplicate(true)
	(bad["chapters"][0]["stages"][3] as Dictionary)["unlock_after"] = "7-7"
	check(_validate_probe(bad) > 0, "坏表:unlock_after 引用未知关卡被拦截")
	# 首通绑定未知武将
	bad = base.duplicate(true)
	(bad["chapters"][0]["stages"][1]["first_clear"] as Dictionary)["fragments"] = {"mystery_hero": 5}
	check(_validate_probe(bad) > 0, "坏表:首通绑定未知武将被拦截")
	# 关卡 id 重复
	bad = base.duplicate(true)
	(bad["chapters"][0]["stages"][1] as Dictionary)["id"] = "1-1"
	check(_validate_probe(bad) > 0, "坏表:关卡 id 重复被拦截")
	# 无入门关(推图链无起点)
	bad = base.duplicate(true)
	(bad["chapters"][0]["stages"][0] as Dictionary)["unlock_after"] = "1-8"
	check(_validate_probe(bad) > 0, "坏表:推图链无起点(unlock_after 环)被拦截")
	# 恢复现场
	DataDB.load_all()
	check(DataDB.last_errors.is_empty(), "校验探测后现场表恢复干净")

# ---------------------------------------------------------------- 3. 评星 + 首通/重复奖励入库

func _test_stars_and_settle() -> void:
	_fresh_save()
	check(CampaignSave.is_unlocked("1-1"), "新档 1-1 解锁")
	check(not CampaignSave.is_unlocked("1-2"), "新档 1-2 锁定")
	check(not CampaignSave.is_unlocked("1-8"), "新档 1-8 锁定")
	# 评星三元(01 §3.3 提案默认);缺省事实按「无阵亡 + 满血」宽待(结算方恒传全量事实)
	check(CampaignSave.calc_stars({"no_casualty": false}) == 1, "评星:仅通关(有阵亡)→ ★1")
	check(CampaignSave.calc_stars({"no_casualty": true, "lord_hp_ratio": 0.3}) == 2, "评星:无阵亡且主公 <50% → ★2")
	check(CampaignSave.calc_stars({"no_casualty": true, "lord_hp_ratio": 0.5}) == 3, "评星:主公 HP 50% → ★3")
	check(CampaignSave.calc_stars({"no_casualty": true, "lord_hp_ratio": 0.49}) == 2, "评星:主公 HP 49% → ★2")
	check(CampaignSave.calc_stars({"no_casualty": false, "lord_hp_ratio": 0.9}) == 1, "评星:有阵亡 → ★1")
	check(CampaignSave.calc_stars({"victory": false}) == 0, "评星:失败 → 0 星")
	# 结算防御:未知关卡 / 存档未初始化
	check(not CampaignSave.settle_stage("9-9", {"victory": true}).get("ok", true), "结算未知关卡被拒")
	var saved_data: Dictionary = SaveState.data
	SaveState.data = {}
	check(not CampaignSave.settle_stage("1-1", {"victory": true}).get("ok", true), "存档未初始化时结算被拒")
	SaveState.data = saved_data
	# 首通 1-1(有阵亡 + 主公低血 → ★1):奖励按关卡表,入库走 SaveState 钱包
	var j0 := SaveState.junzi()
	var r1: Dictionary = CampaignSave.settle_stage("1-1", {"victory": true, "no_casualty": false, "lord_hp_ratio": 0.4})
	check(bool(r1.get("ok", false)) and bool(r1.get("first", false)), "1-1 首通结算 ok")
	check(int(r1.get("stars", 0)) == 1, "1-1 首通评星 ★1(有阵亡)")
	check(SaveState.junzi() == j0 + 125, "首通军资入库 +125(关卡表,01 §8.2 公式)")
	check(bool(CampaignSave.stage_state("1-1").get("cleared", false)), "1-1 通关标记入库")
	check(CampaignSave.stars_of("1-1") == 1, "1-1 评星入库")
	check(CampaignSave.is_unlocked("1-2"), "1-2 随 1-1 通关解锁(推图)")
	check(not CampaignSave.is_unlocked("1-3"), "1-3 仍锁定(1-2 未通)")
	# 重复 1-1(3 星战绩 → 评星取历史最高):发重复奖励,不发首通价
	var r2: Dictionary = CampaignSave.settle_stage("1-1", {"victory": true, "no_casualty": true, "lord_hp_ratio": 0.8})
	check(bool(r2.get("ok", false)) and not bool(r2.get("first", false)), "1-1 重复通关 first=false")
	check(SaveState.junzi() == j0 + 125 + 25, "重复奖励入库 +25(首通×0.2)")
	check(CampaignSave.stars_of("1-1") == 3, "评星取历史最高(1→3)")
	check(SaveState.fragments_total() == 0, "1-1 无绑定武将,重复不发碎片")
	# 首通/重复 1-2(绑定华佗碎片)
	var f0 := SaveState.fragments_of("huatuo")
	var r3: Dictionary = CampaignSave.settle_stage("1-2", {"victory": true, "no_casualty": true, "lord_hp_ratio": 0.9})
	check(int(r3.get("stars", 0)) == 3, "1-2 首通 ★3")
	check(SaveState.fragments_of("huatuo") == f0 + 5, "首通绑定华佗碎片 +5(01 §8.2)")
	check(SaveState.junzi() == j0 + 125 + 25 + 130, "1-2 首通军资 +130")
	var r4: Dictionary = CampaignSave.settle_stage("1-2", {"victory": true})
	check(SaveState.fragments_of("huatuo") == f0 + 5 + 1, "重复通关碎片 +1(绑定武将,占位)")
	check(SaveState.junzi() == j0 + 125 + 25 + 130 + 26, "1-2 重复军资 +26")
	check(CampaignSave.is_unlocked("1-3"), "1-3 随 1-2 通关解锁")
	# 失败不发奖励(01 §8.1)
	var j1 := SaveState.junzi()
	var r5: Dictionary = CampaignSave.settle_stage("1-3", {"victory": false})
	check(bool(r5.get("ok", false)) and int((r5.get("rewards", {}) as Dictionary).get("junzi", 0)) == 0
		and SaveState.junzi() == j1, "1-3 失败:ok 但零奖励、不入库")
	check(not bool(CampaignSave.stage_state("1-3").get("cleared", false)), "1-3 失败不记通关")

# ---------------------------------------------------------------- 4. 推图解锁 + 评星宝箱

func _test_progression_and_boxes() -> void:
	_fresh_save()
	var three_star := {"victory": true, "no_casualty": true, "lord_hp_ratio": 0.6}
	_clear_all(three_star)
	for i in range(1, 9):
		var st: Dictionary = CampaignSave.stage_state("1-%d" % i)
		check(bool(st.get("cleared", false)) and int(st.get("stars", 0)) == 3, "1-%d 通关 ★3" % i)
	check(CampaignSave.chapter_stars("ch1") == 24, "章节总星 24(8 关 × 3)")
	# 评星宝箱(01 §3.3/§8.2 占位:3/6/9 星各 1 箱)
	var box: Dictionary = CampaignSave.box_state("ch1")
	check(not bool(box.get(3, true)) and not bool(box.get(6, true)) and not bool(box.get(9, true)),
		"宝箱初始均未领取")
	var j0 := SaveState.junzi()
	var c1: Dictionary = CampaignSave.claim_box("ch1", 3)
	check(bool(c1.get("ok", false)) and int(c1.get("reward", 0)) == 200, "3 星宝箱领取 +200")
	check(SaveState.junzi() == j0 + 200, "宝箱军资入账(走 SaveState 管道)")
	check(not CampaignSave.claim_box("ch1", 3).get("ok", true), "重复领取被拒")
	check(CampaignSave.claim_box("ch1", 6).get("ok", false), "6 星宝箱可领")
	check(CampaignSave.claim_box("ch1", 9).get("ok", false), "9 星宝箱可领")
	check(not CampaignSave.claim_box("ch1", 12).get("ok", true), "非法档位被拒")
	check(SaveState.junzi() == j0 + 200 + 400 + 600, "宝箱合计 +1200")
	# 首通奖励合计(1190)+ 宝箱(1200)
	check(SaveState.junzi() == 1190 + 1200, "第一章全产出 2390(首通 1190 + 宝箱 1200)")
	check(CampaignSave.chapter_unlocked("ch1"), "ch1 解锁态保持(M9 仅 1 章,下一章解锁留 M10+)")
	check(CampaignSave.first_unlocked_stage() == "1-1", "first_unlocked_stage 兜底返回表序首关")

# ---------------------------------------------------------------- 5. 选关→编队→开战真实链路

## 只在传入的主城子树里找(不要全局 get_nodes_in_group:串行 run_all 时会抓到
## 前一套件没释放的旧 MainCity 按钮,点它等于点一个已 free 的节点)
func _find_hub_button(city: Node, label: String) -> Button:
	if not is_instance_valid(city):
		return null
	for b in city.find_children("*", "Button", true, false):
		if is_instance_valid(b) and not b.is_queued_for_deletion() and b.is_in_group("hub_entry") \
				and str(b.text).replace(" ", "") == label:
			return b
	return null

func _panel_of(city: Node, script_suffix: String) -> Node:
	var host := city.get_node_or_null("SubPanelHost")
	if host == null:
		return null
	for c in host.get_children():
		if is_instance_valid(c) and c.get_script() != null \
				and String(c.get_script().resource_path).ends_with(script_suffix):
			return c
	return null

## 同上:限定在主城子树里找关卡按钮,避免串行测试时抓到上一套件的残留节点
## (_rebuild 后旧按钮 queue_free 未及释放仍是子树成员,一并跳过)
func _stage_button(city: Node, stage_id: String) -> Button:
	if not is_instance_valid(city):
		return null
	for b in city.find_children("*", "Button", true, false):
		if is_instance_valid(b) and not b.is_queued_for_deletion() and b.is_in_group("stage_entry") \
				and str(b.get_meta("stage_id", "")) == stage_id:
			return b
	return null

func _test_select_chain() -> void:
	_fresh_save()
	var city: Node = (load("res://scenes/city/main_city.tscn") as PackedScene).instantiate()
	_st.root.add_child(city)
	await _st.process_frame
	# 战役入口 → 选关页
	var entry := _find_hub_button(city, "战役")
	check(entry != null, "主城战役入口在位")
	entry.pressed.emit()
	await _st.process_frame
	await _st.process_frame
	var sel := _panel_of(city, "stage_select.gd")
	check(sel != null, "战役入口打开选关页")
	# 锁定态渲染(01 §3.4):新档仅 1-1 可点
	var b1 := _stage_button(city, "1-1")
	var b2 := _stage_button(city, "1-2")
	var b8 := _stage_button(city, "1-8")
	check(_stage_button(city, "1-8") != null, "选关页 8 关节点齐备")
	check(b1 != null and not b1.disabled, "1-1 可点(已解锁)")
	check(b2 != null and b2.disabled, "1-2 锁定置灰")
	check(b8 != null and b8.disabled, "1-8 锁定置灰")
	# 通关 1-1、1-2(直调结算)后重开选关页:1-3 解锁
	CampaignSave.settle_stage("1-1", {"victory": true, "no_casualty": true, "lord_hp_ratio": 0.8})
	CampaignSave.settle_stage("1-2", {"victory": true, "no_casualty": true, "lord_hp_ratio": 0.8})
	sel._rebuild()
	await _st.process_frame
	var b3 := _stage_button(city, "1-3")
	check(b3 != null and not b3.disabled, "1-3 随 1-2 通关解锁(选关页同步)")
	# 选关 → 编队确认(squad_edit 复用)
	b3.pressed.emit()
	await _st.process_frame
	await _st.process_frame
	var squad := _panel_of(city, "squad_edit.gd")
	check(squad != null, "选关后进入编队确认面板")
	# 披挂出征 → SceneRouter 真路由 → battle(闯关模式上下文注入)
	var go_btn: Button = null
	for c in squad.find_children("*", "Button", true, false):
		if str(c.text).replace(" ", "") == "披挂出征":
			go_btn = c
	check(go_btn != null, "编队面板带「披挂出征」")
	go_btn.pressed.emit()
	await _st.process_frame
	await _st.process_frame
	var cs := _st.current_scene
	check(cs != null and cs.scene_file_path == BATTLE_SCENE, "出征后进入战斗场景(真路由)")
	check(str(RunState.mode) == "campaign", "闯关模式注入")
	check(str(RunState.context.get("stage_id", "")) == "1-3", "stage_id=1-3 注入")
	check(int(RunState.context.get("wave_total", 0)) == 2, "wave_total 由关卡表带出")
	var d = cs.get_node_or_null("WaveDirector")
	check(d != null and not d.wave_data.is_empty(), "battle 波次数据就绪")
	if d != null:
		check(str(d.wave_data.get("theme", "")) == "重锤压阵", "闯关波次脚本生效(1-3 W1 重锤压阵,非塔剧本)")
		check(int(d.wave_idx) == 1 and d._wave_total() == 2, "闯关波次总数按关卡表(2 波)")
	# 坏 id 拒绝:不切场景、上下文不变
	var nav_ok: bool = SceneRouter.goto_stage("9-9")
	check(not nav_ok, "坏 id goto_stage 被拒(返回 false)")
	check(_st.current_scene == cs and str(RunState.context.get("stage_id", "")) == "1-3",
		"坏 id 不切场景、上下文不变")
	# 清场:让位 current_scene 后释放战斗与主城,恢复未暂停态
	var dummy := Node.new()
	_st.root.add_child(dummy)
	_st.current_scene = dummy
	if is_instance_valid(cs):
		cs.free()
	city.free()
	_st.paused = false
	await _st.process_frame
