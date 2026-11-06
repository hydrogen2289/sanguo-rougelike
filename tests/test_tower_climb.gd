extends "res://tests/test_base.gd"
## test_tower_climb(M10 端到端回归,02 §8.2/§8.4):
## 不是单测「生成器函数」,而是**真的把塔爬一遍**——真实 battle 场景 + 真实波间弹窗
## (三选一/事件/商店)+ 真实结算管道,验证 1~12 层连续推进、第 8 层 Boss、
## 9+ 层切到随机生成器、撤退结算入库、最高层只增不减。
##
## 来历:2026-11-06 收口探针发现「highest_floor 一直为 0」,追查后是探针未走真实
## 存档入口造成的假象;但这条链路本身此前只有函数级单测覆盖,没有端到端套件。
## 本套件补上,并固化「真实弹窗必须被逐个排掉才能推进」这一桩。
##
## 存档走测试专用文件 test_tower_climb_unit.json,套件结束清理并恢复默认,不碰玩家真实存档。

const BATTLE_SCENE := "res://scenes/battle.tscn"
const SAVE_NAME := "test_tower_climb_unit.json"
const CLIMB_TO := 12              # 实爬目标层(含 Boss 层 8 与生成器层 9+)

var _st: SceneTree

func _run() -> void:
	_st = Engine.get_main_loop() as SceneTree
	DataDB.load_all()
	var old_file: String = SaveState.save_file
	SaveState.save_file = SAVE_NAME
	SaveState.delete_save()
	SaveState.load_game()

	await _test_real_climb()

	SaveState.delete_save()
	SaveState.save_file = old_file
	SaveState.data = {}
	_st.paused = false

# ---------------------------------------------------------------- 实爬

func _test_real_climb() -> void:
	SceneRouter.prepare_tower()
	check(RunState.mode == &"tower", "塔入口 → mode=tower")
	check(bool(RunState.context.get("endless", false)), "塔入口 → context.endless=true")

	var battle = (load(BATTLE_SCENE) as PackedScene).instantiate()
	_st.root.add_child(battle)
	var d = battle.get_node("WaveDirector")
	await _frames(2)

	var floors: Array = []
	for want in range(1, CLIMB_TO + 1):
		if not await _wait_floor(d, want, 300):
			check(false, "第 %d 层未进入(停在第 %d 层,state=%s)" % [want, d.wave_idx, d.State.keys()[d.state]])
			break
		var wd: Dictionary = d.wave_data
		check(not wd.is_empty(), "第 %d 层波次数据非空" % want)
		var comp: Dictionary = wd.get("composition", {})
		var total := 0
		for k in comp:
			total += int(comp[k])
		floors.append({
			"floor": want, "count": total,
			"hp": float(wd.get("base_hp", 0.0)),
			"atk": float(wd.get("base_atk", 0.0)),
			"boss": d._is_boss_wave(),
		})
		if want < CLIMB_TO:
			d.state = d.State.BATTLE
			d._force_end_wave()        # F2 同语义:只用于推进,不评星
			await _drain_modals(d)

	check(floors.size() == CLIMB_TO, "连续爬到第 %d 层(实际 %d 层)" % [CLIMB_TO, floors.size()])

	# 1~8 层沿用 waves.json 剧本:第 8 层必须是 Boss 层
	var boss_floors: Array = []
	for f in floors:
		if f.boss:
			boss_floors.append(f.floor)
	check(boss_floors.has(8), "第 8 层是 Boss 层(实际 %s)" % str(boss_floors))
	check(boss_floors.size() == 1, "12 层内 Boss 层只有第 8 层(boss_every=8;实际 %s)" % str(boss_floors))

	# 9+ 层由 TowerWaveGen 生成:字段契约与手写剧本一致
	var f9: Dictionary = floors[8] if floors.size() > 8 else {}
	if not f9.is_empty():
		check(int(f9.count) > 0, "第 9 层(生成层)敌数 > 0(实际 %d)" % int(f9.count))
		var ref8: Dictionary = floors[7]
		check(float(f9.hp) > 0.0 and float(f9.atk) > 0.0, "第 9 层 hp/atk 为正")

	# 层数递进:难度单调不减(生成层按 f0×growth^(f-9),不允许回落)
	var mono := true
	var mono_msg := ""
	for i in range(1, floors.size()):
		if float(floors[i].hp) < float(floors[i - 1].hp) or float(floors[i].atk) < float(floors[i - 1].atk):
			mono = false
			mono_msg = "第 %d 层 hp %.0f/atk %.0f < 上一层 hp %.0f/atk %.0f" % [
				floors[i].floor, floors[i].hp, floors[i].atk, floors[i - 1].hp, floors[i - 1].atk]
	check(mono, "层数递进 hp/atk 单调不减" + ("" if mono_msg == "" else "(" + mono_msg + ")"))

	# 撤退结算入库:已通过 11 层 → highest_floor 应为 11(当前正在打第 12 层,未通过)
	var before: int = TowerSave.highest_floor()
	d.retreat()
	await _frames(3)
	var after: int = TowerSave.highest_floor()
	check(after > before, "撤退结算后 highest_floor 前进(%d → %d)" % [before, after])
	check(after == CLIMB_TO - 1, "highest_floor = 已通过层数 %d(实际 %d)" % [CLIMB_TO - 1, after])
	check(TowerSave.highest_floor() <= TowerSave.floor_cap(), "highest_floor 不越层数上限")

	# 只增不减:再结算一次更低的层数不倒退
	var r: Dictionary = TowerSave.record_floor(3)
	check(bool(r.get("ok", false)) and not bool(r.get("changed", true)), "record_floor(更低层) 不改变最高层")
	check(TowerSave.highest_floor() == after, "最高层不倒退(仍为 %d)" % after)
	var rneg: Dictionary = TowerSave.record_floor(-1)
	check(not bool(rneg.get("ok", true)), "record_floor(负数) 拒绝")

	battle.free()
	_st.paused = false

# ---------------------------------------------------------------- 工具

func _frames(n: int) -> void:
	for i in n:
		await _st.process_frame

func _wait_floor(d, want: int, max_frames: int) -> bool:
	for i in max_frames:
		if int(d.wave_idx) == want:
			return true
		await _st.process_frame
	return false

## 波间弹窗必须被真实排掉才推进:三选一选第 1 张 / 事件选可选的第一项 / 商店直接出征。
## 这条绕过会掩盖「弹窗卡死」类缺陷,所以按真实 UI 接口调用,不直接改 after_queue。
func _drain_modals(d) -> void:
	for i in 40:
		if d.modal == null:
			await _frames(2)
			if d.modal == null:
				return
			continue
		var m = d.modal
		if not is_instance_valid(m):
			await _st.process_frame
			continue
		var path := String(m.get_script().resource_path) if m.get_script() != null else ""
		if path.ends_with("shop.gd") and m.has_method("do_checkout"):
			m.do_checkout()
		elif path.ends_with("triselect.gd") and m.has_method("pick"):
			m.pick(0)
		elif path.ends_with("event_popup.gd") and m.has_method("choose"):
			if m.option_enabled("b"):
				m.choose("b")
			elif m.option_enabled("a"):
				m.choose("a")
			else:
				return
		else:
			var btns: Array = m.find_children("*", "Button", true, false)
			if btns.is_empty():
				await _st.process_frame
				continue
			(btns[0] as Button).pressed.emit()
		await _frames(2)
