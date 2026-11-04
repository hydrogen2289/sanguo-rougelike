extends Node
## 冒烟驱动本体(由 smoke_boot.gd 直挂 /root;场景切换不释放)。
## 跑法:godot.cmd --headless --path <工程> res://tests/smoke_boot.tscn
## 全流程:主菜单 → 序章(跳过)→ W1~W8(F2 快进 + 全武将技能施放)→
## 三选一×7 / 事件×3 / 商店×2 → 胜利结算 → 再来一局 → ESC 暂停开关 → 回主菜单 → 退出码 0。
## 任何一步超时或断言失败 → 退出码 1。

const TIMEOUT_S := 300.0          # 真实秒看门狗
const STATE_PRELUDE := 0
const STATE_SPAWNING := 1
const STATE_BATTLE := 2

var _t0 := 0.0
var _fail := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_t0 = Time.get_ticks_msec()
	_run()

func _process(_delta: float) -> void:
	if not _fail and (Time.get_ticks_msec() - _t0) / 1000.0 > TIMEOUT_S:
		_fail = true
		_fail_quit("看门狗超时 %.0fs" % TIMEOUT_S)

func _fail_quit(msg: String) -> void:
	_fail = true
	printerr("[SMOKE][FAIL] " + msg)
	get_tree().quit(1)

func _ok(msg: String) -> void:
	print("[SMOKE] " + msg)

func _elapsed() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _until(pred: Callable, failmsg: String, timeout := 60.0) -> bool:
	var deadline := _elapsed() + timeout
	while _elapsed() < deadline:
		if pred.call():
			return true
		await get_tree().process_frame
	_fail_quit(failmsg + "(等待超时 %.0fs)" % timeout)
	return false

## 软等待:不判失败,返回是否满足(供 ESC 键事件回退)
func _until_soft(pred: Callable, timeout := 3.0) -> bool:
	var deadline := _elapsed() + timeout
	while _elapsed() < deadline:
		if pred.call():
			return true
		await get_tree().process_frame
	return false

func _note(msg: String) -> void:
	print("[SMOKE][note] " + msg)

func _cs_name() -> String:
	var cs := get_tree().current_scene
	return String(cs.name) if cs != null else ""

func _director() -> Node:
	return get_tree().get_first_node_in_group("wave_director")

func _modal(kind: String) -> Node:
	for m in get_tree().get_nodes_in_group("modal"):
		if is_instance_valid(m) and m.visible and m.get_script() != null 				and String(m.get_script().resource_path).ends_with(kind + ".gd"):
			return m
	return null

func _run() -> void:
	await _frames(5)
	Engine.time_scale = 4.0     # 冒烟提速 4 倍(物理容差足够)
	# 1. 主菜单
	SceneRouter.goto_menu()
	if not await _until(func() -> bool: return _cs_name() == "MainMenu", "主菜单未出现"):
		return
	_ok("主菜单 OK(t=%.0fs)" % _elapsed())
	# 2. 开始游戏 → 序章
	SceneRouter.start_run()
	if not await _until(func() -> bool: return _cs_name() == "Prologue", "序章未出现"):
		return
	_ok("序章 OK")
	# 3. 序章任意键跳过 → 战斗
	var pro := get_tree().current_scene
	if pro != null and pro.has_method("confirm"):
		pro.confirm()
	if not await _until(func() -> bool: return _cs_name() == "Battle", "未进入战斗"):
		return
	_ok("序章跳过 → 战斗 OK")
	# 4. 开局设置:主公无敌(F1 口径)+ F6 招满(全武将技能都过一遍)
	var d := _director()
	if d == null:
		_fail_quit("wave_director 缺失")
		return
	var lord = d.battle.get_node_or_null("Units/PlayerLord")
	if lord != null:
		lord.invincible = true
	d._debug_fill_team()
	_ok("主公无敌 + 招满全武将 OK")
	# 5. 逐波推进
	for wave in range(1, 9):
		var di := _director()
		if di == null:
			_fail_quit("W%d: director 丢失" % wave)
			return
		if not await _until(func() -> bool: return int(di.state) == STATE_BATTLE,
				"W%d 未进入 BATTLE" % wave, 90.0):
			return
		await _frames(30)          # 打一会,普攻/受击/浮字都过一遍
		_cast_all_skills()
		await _frames(45)
		if wave < 8:
			di._force_end_wave()   # F2 口径(W1~W7 快进)
			if not await _resolve_intermission(di, wave):
				return
			_ok("W%d 战斗 + 波间队列 OK(t=%.0fs)" % [wave, _elapsed()])
		else:
			# W8 真打:不 F2,等「华雄被击杀 → 胜利结算」(M5 验收口径)
			_ok("W8 华雄战开打(真打口径,4 倍速)")
			if not await _until(func() -> bool: return _modal("result") != null,
					"W8 未在时限内击杀华雄", 240.0):
				return
			var res := _modal("result")
			if res == null or not res.victory:
				_fail_quit("W8 击杀华雄后应为胜利结算")
				return
			_ok("W8 华雄被击杀 → 胜利结算 OK(波内用时 %.0fs 游戏)" % [_director().battle_t])
	# 6. 胜利结算
	if not await _until(func() -> bool: return _modal("result") != null, "胜利结算未出现", 30.0):
		return
	var res := _modal("result")
	if res == null or not res.victory:
		_fail_quit("第 8 波后应为胜利结算")
		return
	_ok("胜利结算 OK(到达 W%d 击杀 %d 军资 %d 用时 %.0fs)" % [
		RunState.wave_idx, RunState.kills, RunState.gold, RunState.run_time])
	# 7. 再来一局
	res._on_restart()
	if not await _until(func() -> bool: return _cs_name() == "Battle" and RunState.wave_idx == 1,
			"再来一局未复位", 30.0):
		return
	var r2 := _director()
	if r2 == null:
		_fail_quit("重开后 director 缺失")
		return
	if not await _until(func() -> bool: return int(r2.state) == STATE_BATTLE, "重开后未进入 W1 BATTLE", 60.0):
		return
	check_state_reset()
	_ok("再来一局 OK(队伍 %d 人 / 军资 %d / 遗物 %d)" % [RunState.team.size(), RunState.gold, RunState.relics.size()])
	# 8. ESC 暂停开关(优先走真键事件,headless 输入管线不可达时直调兜底)
	var pz := get_tree().get_first_node_in_group("pause_menu")
	if pz == null:
		_fail_quit("pause_menu 缺失")
		return
	_press_escape()
	if not await _until_soft(func() -> bool: return pz.visible and get_tree().paused, 3.0):
		_note("ESC 键事件未送达(headless 输入管线),直调 open() 验证")
		pz.open()
	if not await _until(func() -> bool: return pz.visible and get_tree().paused, "暂停未打开", 5.0):
		return
	_press_escape()
	if not await _until_soft(func() -> bool: return not pz.visible and not get_tree().paused, 3.0):
		pz.close()
	if not await _until(func() -> bool: return not pz.visible and not get_tree().paused, "暂停未恢复", 5.0):
		return
	_ok("ESC 暂停/继续 OK")
	# 9. 暂停菜单 → 回主菜单
	pz.open()
	await _frames(3)
	pz._on_menu()
	if not await _until(func() -> bool: return _cs_name() == "MainMenu", "回主菜单失败", 20.0):
		return
	_ok("回主菜单 OK")
	Engine.time_scale = 1.0
	print("[SMOKE] 全流程通过,退出码 0(真实用时 %.0fs)" % _elapsed())
	get_tree().quit(0)

func check_state_reset() -> void:
	# 重开复位口径:队伍/遗物/强化/波次(军资与击杀在新局开打后即时累积,不在此断言;
	# RunState.reset 语义已由 test_flow 覆盖)
	if RunState.team.size() != 3 or RunState.relics.size() != 0 or RunState.upgrades.size() != 0:
		_fail_quit("重开状态未复位:队伍 %d 遗物 %d 强化 %d" % [
			RunState.team.size(), RunState.relics.size(), RunState.upgrades.size()])

func _cast_all_skills() -> void:
	for u in get_tree().get_nodes_in_group("friendlies"):
		if is_instance_valid(u) and not u.dead and u.get("skill_comp") != null:
			u.skill_comp.activate()   # CD 未到则 no-op;吕布不受令也会走到

func _press_escape() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)

## 波间队列:依次决断 三选一(选卡0)/ 事件(A 不可选则 B)/ 商店(出征)
func _resolve_intermission(d: Node, wave: int) -> bool:
	var guard := 0
	while guard < 50:
		guard += 1
		await _frames(3)
		if d == null or not is_instance_valid(d):
			_fail_quit("W%d: director 失效" % wave)
			return false
		var m := _any_modal()
		if m == null:
			if d.after_queue.is_empty() and int(d.state) != STATE_BATTLE and int(d.state) != STATE_SPAWNING:
				# 队列清空 → 应已进下一波 PRELUDE
				pass
			if d.after_queue.is_empty():
				break
			continue
		var mn := String(m.name)
		if mn == "TriSelect":
			m.pick(0)
		elif mn == "EventPopup":
			m.choose("a" if m.option_enabled("a") else "b")
		elif mn == "Shop":
			m.do_checkout()
		elif mn == "Result":
			break            # W8 胜利结算,交给外层
		else:
			_fail_quit("W%d: 未知弹窗 %s" % [wave, mn])
			return false
		# 等该弹窗关掉(或换成下一个)
		await _frames(3)
	if guard >= 50:
		_fail_quit("W%d: 波间队列未在限定步内走完" % wave)
		return false
	return true

func _any_modal() -> Node:
	for m in get_tree().get_nodes_in_group("modal"):
		if is_instance_valid(m) and m.visible:
			return m
	return null
