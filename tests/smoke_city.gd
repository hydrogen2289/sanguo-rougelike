extends Node
## 主城冒烟(M8;M9 扩战役链):进入主城 → 依次点开 酒馆 / 武将府 / 校场 → 做一次招募、
## 一次升级、一次编队改动 → 收起 → 回主菜单 → 重进验证存档 → 战役真实打通 1-1 并验证结算入库。
## 跑法:godot.cmd --headless --path <工程> res://tests/smoke_city.tscn
## 与 smoke_runner 同风格:任一步超时或断言失败即退出码 1。
## 用的是一份隔离存档(smoke_city_unit.json),结束删除,不碰玩家真实存档。
##
## 挂起修复(验收报告缺陷 1,2026-11-06):本驱动节点原为 tscn 根 = current_scene,
## SceneRouter.goto_city → change_scene_to_file 在下一帧把 current_scene(即本节点)释放,
## await 协程孤儿化、看门狗随节点死亡 → 永久挂起。
## 修复:启动时挂一个占位 Node 顶替 current_scene,本驱动退为 /root 普通子节点存活到收尾;
## 此后每次 change_scene 释放的都是占位/旧场景,驱动不受影响。

const TIMEOUT_S := 150.0
const BATTLE_KILL_DEADLINE_S := 100.0    # 战役冒烟清怪驱动时限(时间加速后实际远低于此)
const TIME_SCALE := 5.0                  # 战役段时钟加速(真实战斗管线,压缩等待)

var _t0 := 0.0
var _fail := false
var _tree: SceneTree = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_t0 = Time.get_ticks_msec()
	_tree = get_tree()
	_boot.call_deferred()

## 挂起修复核心:current_scene 指针让位给占位节点(见文件头注释)。
func _boot() -> void:
	var placeholder := Node.new()
	placeholder.name = "SmokeCityScene"
	_tree.root.add_child(placeholder)
	_tree.current_scene = placeholder
	_run()

func _process(_delta: float) -> void:
	if not _fail and _elapsed() > TIMEOUT_S:
		_fail_quit("看门狗超时 %.0fs" % TIMEOUT_S)

func _elapsed() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0

func _frames(n: int) -> void:
	for i in n:
		await _tree.process_frame

func _cs_name() -> String:
	var cs := _tree.current_scene
	return String(cs.name) if cs != null else ""

func _ok(msg: String) -> void:
	print("[CITY] " + msg)

func _fail_quit(msg: String) -> void:
	_fail = true
	printerr("[CITY][FAIL] " + msg)
	_tree.quit(1)

func _until(pred: Callable, failmsg: String, timeout := 20.0) -> bool:
	var deadline := _elapsed() + timeout
	while _elapsed() < deadline:
		if pred.call():
			return true
		await _tree.process_frame
	_fail_quit(failmsg)
	return false

func _panel() -> Node:
	var host := _tree.current_scene.get_node_or_null("SubPanelHost")
	if host == null:
		return null
	for c in host.get_children():
		if is_instance_valid(c):
			return c
	return null

func _hub_button(label: String) -> Button:
	var hub := _tree.current_scene.get_node_or_null("HubButtons")
	if hub == null:
		return null
	for c in hub.get_children():
		if c is Button and str(c.text).replace(" ", "") == label:
			return c
	return null

func _run() -> void:
	await _frames(5)
	# 隔离存档:先删掉可能残留的冒烟档
	SaveState.save_file = "smoke_city_unit.json"
	SaveState.delete_save()
	SaveState.load_game()
	SaveState.add_junzi(5000)          # 给足军资,验「有钱时按钮可用」
	SaveState.add_fragments("lvbu", 200)
	SaveState.mark_prologue_seen()     # 新档首次进主城会播 20s 序章;冒烟直接跳过
	SaveState.flush()
	# 进主城
	SceneRouter.goto_city()
	if not await _until(func() -> bool: return _cs_name() == "MainCity", "主城未出现"):
		return
	await _frames(3)
	_ok("主城 OK")
	# 五入口全部可点
	for lbl in ["战役", "试炼塔", "酒馆", "武将府", "校场"]:
		if _hub_button(lbl) == null:
			_fail_quit("主城缺少入口:" + lbl)
			return
	_ok("五入口齐备")
	# 酒馆:开 → 直购一名史诗将
	_hub_button("酒馆").pressed.emit()
	await _frames(3)
	var tw := _panel()
	if tw == null:
		_fail_quit("酒馆面板未挂载")
		return
	var before := SaveState.junzi()
	var r := HeroSave.recruit_buy("zhaoyun")
	if not bool(r.get("ok", false)):
		_fail_quit("酒馆直购失败:" + str(r.get("reason", "")))
		return
	if not HeroSave.owned("zhaoyun"):
		_fail_quit("直购后未入册")
		return
	_ok("酒馆直购 OK(军资 %d → %d)" % [before, SaveState.junzi()])
	tw._on_close()
	await _frames(3)
	# 武将府:开 → 升一级
	_hub_button("武将府").pressed.emit()
	await _frames(3)
	var hu := _panel()
	if hu == null:
		_fail_quit("武将府面板未挂载")
		return
	hu._picked = "zhaoyun"
	hu._on_upgrade()
	if HeroSave.level_of("zhaoyun") < 2:
		_fail_quit("武将府升级未生效")
		return
	_ok("武将府升级 OK(Lv.%d)" % HeroSave.level_of("zhaoyun"))
	hu._on_close()
	await _frames(3)
	# 校场:开 → 撤张飞腾席位 → 把赵云编入(初始 3 席满员,M8 席位规则:先撤后上)
	_hub_button("校场").pressed.emit()
	await _frames(3)
	var sq := _panel()
	if sq == null:
		_fail_quit("校场面板未挂载")
		return
	sq._on_toggle("zhangfei")
	sq._on_toggle("zhaoyun")
	if not (sq._slots as Array).has("zhaoyun"):
		_fail_quit("编队未写入(面板状态)")
		return
	_ok("校场选将 OK(%s)" % str(sq._slots))
	sq._on_close()                      # 关面板才落存档(编辑即存口径在 _persist)
	await _frames(3)
	if not HeroSave.slots().has("zhaoyun"):
		_fail_quit("编队未写入存档")
		return
	_ok("校场编队写入 OK(%s)" % str(HeroSave.slots()))
	# 落盘 → 重进主城,编队与等级仍在
	SceneRouter.goto_menu()
	if not await _until(func() -> bool: return _cs_name() == "MainMenu", "回主菜单失败"):
		return
	SaveState.data = {}
	SaveState.load_game()
	var slots: Array = SaveState.data.get("squad", {}).get("slots", [])
	if not slots.has("zhaoyun"):
		_fail_quit("重进后编队丢失")
		return
	if HeroSave.level_of("zhaoyun") < 2:
		_fail_quit("重进后等级丢失")
		return
	_ok("存档往返 OK")

	# ------------------------------------------------ M9 战役冒烟:真实打通 1-1 + 结算入库
	await _smoke_campaign()
	# 收尾:删隔离档,恢复默认档名
	SaveState.delete_save()
	SaveState.save_file = "save_v1.json"
	print("[CITY] 主城冒烟通过,退出码 0(用时 %.1fs)" % _elapsed())
	_tree.quit(0)

## 战役链路冒烟(M9 验收 5):SceneRouter 真路由进 1-1 → 闯关波次脚本真实生效 →
## 清怪驱动打完 → 胜利结算入库(通关/评星/首通奖励/推图解锁)。
func _smoke_campaign() -> void:
	var junzi_before := SaveState.junzi()
	var frag_before := int(SaveState.fragments_of("huatuo"))
	var fc: Dictionary = DataDB.stage_by_id("1-1").get("first_clear", {})
	if not SceneRouter.goto_stage("1-1"):
		_fail_quit("goto_stage('1-1') 被拒(路由/关卡表异常)")
		await _frames(1)
		return
	# 占位节点让位后,current_scene 依次为 MainMenu → Battle;驱动节点存活
	if not await _until(func() -> bool: return _cs_name() == "Battle", "战斗场景未出现"):
		return
	var battle := _tree.current_scene
	var d = battle.get_node_or_null("WaveDirector")
	if d == null:
		_fail_quit("battle 缺 WaveDirector")
		return
	if str(RunState.mode) != "campaign" or str(RunState.context.get("stage_id", "")) != "1-1":
		_fail_quit("模式上下文未注入:%s / %s" % [str(RunState.mode), str(RunState.context)])
		return
	if int(RunState.context.get("wave_total", 0)) != 2:
		_fail_quit("wave_total 未从关卡表带出(期望 2,实际 %d)" % int(RunState.context.get("wave_total", 0)))
		return
	# W1 波次数据应来自关卡脚本(非塔 8 波)
	if not await _until(func() -> bool: return not d.wave_data.is_empty(), "W1 波次数据未加载"):
		return
	if str(d.wave_data.get("theme", "")) != "桃园结义":
		_fail_quit("闯关波次脚本未生效:W1 主题=%s(期望 桃园结义)" % str(d.wave_data.get("theme", "")))
		return
	_ok("战役链路 OK:campaign 1-1,波次双源生效(W1 桃园结义)")
	# 时间加速 + 每帧清怪(真实战斗管线,压缩等待);波次自然推进直至结算 ENDED
	Engine.time_scale = TIME_SCALE
	var deadline := _elapsed() + BATTLE_KILL_DEADLINE_S
	while _elapsed() < deadline and is_instance_valid(battle) and is_instance_valid(d) \
			and int(d.state) != int(d.State.ENDED):
		for e in _tree.get_nodes_in_group("enemies"):
			if is_instance_valid(e) and not bool(e.get("dead")) and e.has_method("take_damage"):
				e.take_damage(999999.0, null)
		await _tree.process_frame
	Engine.time_scale = 1.0
	if not is_instance_valid(battle) or not is_instance_valid(d) or int(d.state) != int(d.State.ENDED):
		_fail_quit("%.0fs 内未打通 1-1(state=%s)" % [BATTLE_KILL_DEADLINE_S,
			str(d.state) if is_instance_valid(d) else "freed"])
		return
	await _frames(5)                   # 等结算弹窗挂载、结算入库 flush 完成
	# 结算入库断言(M9 验收 5):通关标记/评星/首通奖励/推图解锁
	var st: Dictionary = CampaignSave.stage_state("1-1")
	if not bool(st.get("cleared", false)):
		_fail_quit("1-1 通关标记未入库")
		return
	if int(st.get("stars", 0)) < 1:
		_fail_quit("1-1 评星未入库(期望 >=1)")
		return
	var gained := SaveState.junzi() - junzi_before
	if gained != int(fc.get("junzi", 0)):
		_fail_quit("首通奖励入库不符:+%d(期望 %d)" % [gained, int(fc.get("junzi", 0))])
		return
	if SaveState.fragments_of("huatuo") != frag_before:
		_fail_quit("1-1 无绑定武将却发了碎片")
		return
	if not CampaignSave.is_unlocked("1-2"):
		_fail_quit("1-2 未随 1-1 通关解锁")
		return
	if CampaignSave.is_unlocked("1-3"):
		_fail_quit("1-3 未通关 1-2 却已解锁(推图链失守)")
		return
	_ok("1-1 结算入库 OK:通关/★%d/军资+%d/1-2 解锁" % [int(st.get("stars", 0)), gained])
	# 清场:让位 current_scene 后释放战斗场景,恢复未暂停态
	var dummy := Node.new()
	dummy.name = "SmokeCityScene"
	_tree.root.add_child(dummy)
	_tree.current_scene = dummy
	battle.free()
	_tree.paused = false
	await _frames(2)
	_ok("战役冒烟 OK")
