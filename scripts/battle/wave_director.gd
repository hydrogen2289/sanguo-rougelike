extends Node
## 波次状态机(M1 立骨架;M3 补全波间队列与胜负结算;M5 补全第 8 波 Boss 规则):
## PRELUDE → SPAWNING → BATTLE → INTERMISSION(按 waves.json after 依次弹 三选一/事件/商店)→ 下一波。
## 第 8 波:出场演出(红字「华雄 · 都督之威」+ 震屏)→ 每 10s 增援黄巾卒 →
## 击杀华雄才结束;计时到 Boss 未死 → 普通敌退场、战斗继续(01 §3/§6/§10)。
## 主公阵亡 → 全屏褪色 1s → 失败结算(01 §12,M6 演出)。

enum State { PRELUDE, SPAWNING, BATTLE, INTERMISSION, ENDED }

const PRELUDE_SECS := 3.0          # 每波开始前 3s 静场横幅(01 §6)
const INTERMISSION_SECS := 2.5
const SPAWN_WINDOW := 0.5          # 波时长前 50% 均匀刷完(M5 平衡调整:0.6→0.5,缓解走位真空期)
const ELITE_IDS := ["huangjin_lishi"]   # 精英在波次中点之后出现(01 §6)

const TRISELECT_SCENE := "res://scenes/ui/triselect.tscn"
const SHOP_SCENE := "res://scenes/ui/shop.tscn"
const EVENT_SCENE := "res://scenes/ui/event_popup.tscn"
const RESULT_SCENE := "res://scenes/ui/result.tscn"
const PAUSE_SCENE := "res://scenes/ui/pause.tscn"

var state: State = State.PRELUDE
var wave_idx := 1
var wave_data: Dictionary = {}
var spawn_queue: Array = []        # [{t: float, id: String}]
var spawn_t := 0.0
var battle_t := 0.0
var state_t := 0.0
var gold_pool := 0                 # 本波军资掉落余额,总额对齐波表
var spawner: Spawner
var reinforce_t := 0.0             # W8 增援计时(每 10s 黄巾卒×4,01 §6)

# --- M3 波间队列与模态 ---
var after_queue: Array = []        # 剩余波间项(triselect / event_* / shop / victory)
var modal: Control = null          # 当前打开的波间弹窗
var modal_layer: CanvasLayer = null
var pause_ui: Control = null
var _ui_built := false
var _w8_timeup_done := false
var _hero_slots: Dictionary = {}   # hero_id -> formation_index(0~5):存活武将全局槽位表(P1-2,01 §10)

@onready var battle: Node3D = get_parent()

func _ready() -> void:
	add_to_group("wave_director")
	spawner = Spawner.new()
	spawner.battle = battle
	spawner.director = self
	EventBus.lord_died.connect(_on_lord_died)
	EventBus.enemy_died.connect(_on_enemy_died)
	RunState.team_changed.connect(_on_team_changed)
	RunState.heal_all_requested.connect(_on_heal_all)
	Sfx.play_bgm()
	# UI 层不在 _ready 建(battle 尚在子节点装配期,add_child 会报 busy),
	# 首帧 _process 或首个弹窗/结算前懒构建(_ensure_ui)。
	if RunState.wave_idx >= 1:
		wave_idx = RunState.wave_idx
	_sync_team_units()
	CsvLogger.ensure_header()
	_enter_state(State.PRELUDE)

func _ensure_ui() -> void:
	if _ui_built or battle == null or not is_instance_valid(battle):
		return
	_ui_built = true
	_build_ui_layers()

func _build_ui_layers() -> void:
	modal_layer = CanvasLayer.new()
	modal_layer.layer = 10
	battle.add_child(modal_layer)
	pause_ui = _instantiate_ui(PAUSE_SCENE)
	if pause_ui != null:
		var pl := CanvasLayer.new()
		pl.layer = 20
		battle.add_child(pl)
		pl.add_child(pause_ui)

func _instantiate_ui(path: String) -> Control:
	if not ResourceLoader.exists(path):
		return null
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	return ps.instantiate()

## 保证队伍里每个存活成员都有场上单位(开局 / 三选一新武将 / 事件招募 / F6 招满共用)
func _sync_team_units() -> void:
	var lord := battle.get_node_or_null("Units/PlayerLord")
	if lord != null:
		lord.battle = battle
	_alloc_hero_slots()
	for m in RunState.team:
		if not bool(m.alive):
			continue
		if str(m.hero_id) == "liubei":
			continue
		if _unit_of(str(m.hero_id)) != null:
			continue
		# 槽位取全局槽位表(新招募取最小空闲槽;阵亡释放),保证 formation_index 全场互异(P1-2)
		spawner.spawn_hero(str(m.hero_id), int(_hero_slots.get(str(m.hero_id), 0)))
	_bind_hud_skills()

## 存活武将槽位表维护(01 §10「槽位序号=快捷键 1~6」):
## 阵亡/离队成员释放其槽;存活而未入表者按最小空闲槽分配;场上武将槽位永不冲突。
## 表挂在 WaveDirector 上,重开(新战斗场景)自然复位。
func _alloc_hero_slots() -> void:
	for hid in _hero_slots.keys():
		var m: Dictionary = RunState.member(str(hid))
		if m.is_empty() or not bool(m.get("alive", false)):
			_hero_slots.erase(str(hid))
	for m in RunState.team:
		if not bool(m.alive) or str(m.hero_id) == "liubei":
			continue
		var hid := str(m.hero_id)
		if _hero_slots.has(hid):
			continue
		for s in RunState.MAX_TEAM - 1:      # 非主公武将上限 6 → 槽 0~5
			if not _hero_slots.values().has(s):
				_hero_slots[hid] = s
				break

## 新武将即刻入场(01 §7):三选一/事件招募/F6 共用
func _on_team_changed() -> void:
	_sync_team_units()

## 军医诊治 / 军医草药:全队回复 30% HP(01 §5/§7)
func _on_heal_all(ratio: float) -> void:
	for f in get_tree().get_nodes_in_group("friendlies"):
		if is_instance_valid(f) and not f.dead:
			f.heal(f.max_hp * ratio)

func _unit_of(hero_id: String) -> Node:
	var heroes_root := battle.get_node_or_null("Units/Heroes")
	if heroes_root == null:
		return null
	for u in heroes_root.get_children():
		# 跳过误挂进来的浮字/VFX 等非单位节点(否则读 .unit_id 会 SCRIPT ERROR)
		if not is_instance_valid(u) or not (u is UnitBase):
			continue
		if str(u.unit_id) == hero_id:
			return u
	return null

func _process(delta: float) -> void:
	_ensure_ui()
	state_t += delta
	_heartbeat(delta)
	match state:
		State.PRELUDE:
			if state_t >= PRELUDE_SECS:
				_enter_state(State.SPAWNING)
		State.SPAWNING:
			spawn_t += delta
			while not spawn_queue.is_empty() and float(spawn_queue[0]["t"]) <= spawn_t:
				var item: Dictionary = spawn_queue.pop_front()
				var arc: Array = item.get("arc", [])
				spawner.spawn_enemy(str(item["id"]), float(wave_data["base_hp"]), float(wave_data["base_atk"]), arc)
			if spawn_queue.is_empty():
				_enter_state(State.BATTLE)
		State.BATTLE:
			battle_t += delta
			if wave_idx >= DataDB.waves.size() and _boss_alive():
				_tick_reinforce(delta)   # W8:每 10s 增援黄巾卒×4(01 §6)
			if _alive_enemies() == 0:
				_finish_wave(true)
			elif battle_t >= float(wave_data["duration"]):
				_time_up()
		State.INTERMISSION:
			pass               # 波间推进由弹窗回调驱动(_modal_done → _advance_after_queue)
		State.ENDED:
			pass

## 调试心跳(仅 debug 构建):每 5 游戏秒打印时间/帧/状态/敌数
var _hb_t := 0.0
func _heartbeat(delta: float) -> void:
	if not OS.is_debug_build():
		return
	_hb_t += delta
	if _hb_t >= 5.0:
		_hb_t = 0.0
		print("[HB] t=%.1f state=%s wave=%d enemies=%d fps=%d frames=%d" % [
			RunState.run_time, State.keys()[state], wave_idx,
			_alive_enemies(), Engine.get_frames_per_second(), Engine.get_process_frames()])

func _enter_state(s: State) -> void:
	state = s
	state_t = 0.0
	match s:
		State.PRELUDE:
			wave_data = DataDB.wave(wave_idx)
			gold_pool = int(wave_data.get("gold_total", 0))
			reinforce_t = 0.0
			RunState.wave_idx = wave_idx
			_w8_timeup_done = false
			if wave_idx >= DataDB.waves.size():
				# W8 出场演出:红字「华雄 · 都督之威」+ 震屏(01 §10),代替普通波次横幅
				EventBus.banner_styled.emit("华雄 · 都督之威", PRELUDE_SECS,
					UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23)), 56)
				EventBus.screen_shake.emit(0.55, 0.9)
			else:
				var title := "第 %d 波" % wave_idx
				var theme := str(wave_data.get("theme", ""))
				if theme != "":
					title += " · " + theme
				EventBus.wave_banner.emit(title, PRELUDE_SECS)
			Sfx.play("horn", -6.0)
			_build_spawn_queue()
		State.SPAWNING:
			spawn_t = 0.0
			# 关卡目标提示(docs/03 §2);W8 保留 Boss 出场演出,不覆盖横幅
			var obj: Dictionary = wave_data.get("objective", {})
			if wave_idx < DataDB.waves.size() and not obj.is_empty():
				EventBus.wave_banner.emit("目标 · " + str(obj.get("label", "")), 1.8)
		State.BATTLE:
			battle_t = 0.0
		State.INTERMISSION:
			EventBus.wave_banner.emit("第 %d 波结束" % wave_idx, 1.5)
			_begin_after_queue()
		State.ENDED:
			pass
	if OS.is_debug_build():
		print("[WaveDirector] state=%s wave=%d run_time=%.1f" % [State.keys()[s], wave_idx, RunState.run_time])
	EventBus.wave_state_changed.emit(State.keys()[s], wave_idx)

# ---------------------------------------------------------------- M3 波间队列

## 按 wave_data.after 建队列(01 §6 波次表):triselect → event_* → shop(第 4/6 波后)
func _begin_after_queue() -> void:
	after_queue = (wave_data.get("after", []) as Array).duplicate()
	_advance_after_queue()

func _advance_after_queue() -> void:
	if state != State.INTERMISSION or modal != null:
		return
	if after_queue.is_empty():
		if wave_idx >= DataDB.waves.size():
			_show_result(true)     # 兜底(波 8 after 应含 victory)
		else:
			_next_wave()
		return
	var item := str(after_queue.pop_front())
	if item == "triselect":
		_open_triselect()
	elif item == "shop":
		_open_shop()
	elif item == "victory":
		_show_result(true)
	elif item.begins_with("event_"):
		_open_event(item.substr(6))
	else:
		_advance_after_queue()     # 未知项跳过

func _open_triselect() -> void:
	_ensure_ui()
	var ui := _instantiate_ui(TRISELECT_SCENE)
	if ui == null:
		_advance_after_queue()
		return
	modal = ui
	modal_layer.add_child(ui)
	get_tree().paused = true          # 弹窗期间冻结战斗(01 §10)
	ui.card_chosen.connect(func(_i: int) -> void: _modal_done(), CONNECT_ONE_SHOT)
	ui.open({"wave_idx": wave_idx})

func _open_event(event_id: String) -> void:
	_ensure_ui()
	var ev: Dictionary = DataDB.event_by_id(event_id)
	if ev.is_empty():
		_advance_after_queue()
		return
	var ui := _instantiate_ui(EVENT_SCENE)
	if ui == null:
		_advance_after_queue()
		return
	modal = ui
	modal_layer.add_child(ui)
	get_tree().paused = true          # 弹窗期间冻结战斗(01 §10)
	ui.chosen.connect(func(_opt: String) -> void: _modal_done(), CONNECT_ONE_SHOT)
	ui.open(ev)

func _open_shop() -> void:
	_ensure_ui()
	var ui := _instantiate_ui(SHOP_SCENE)
	if ui == null:
		_advance_after_queue()
		return
	modal = ui
	modal_layer.add_child(ui)
	get_tree().paused = true          # 弹窗期间冻结战斗(01 §10)
	ui.checkout.connect(func() -> void: _modal_done(), CONNECT_ONE_SHOT)
	ui.open({})

## 弹窗决断完成 → 关闭、解除暂停、推进队列
func _modal_done() -> void:
	if modal != null and is_instance_valid(modal):
		modal.queue_free()
	modal = null
	get_tree().paused = false
	_advance_after_queue()

# ---------------------------------------------------------------- 胜负结算(M3)

## 胜利「桃园功成」/ 失败「大意失荆州」;数据走 RunState.dump()(01 §10)
func _show_result(victory: bool) -> void:
	_ensure_ui()
	state = State.ENDED
	if modal != null and is_instance_valid(modal):
		modal.queue_free()
	modal = null
	var ui := _instantiate_ui(RESULT_SCENE)
	get_tree().paused = true
	if ui == null:
		printerr("[WaveDirector] result 场景缺失,仅暂停")
		return
	modal = ui
	modal_layer.add_child(ui)
	ui.open(victory, RunState.dump())
	if OS.is_debug_build():
		print("[WaveDirector] 结算:%s 波=%d 击杀=%d 军资=%d 用时=%.0fs" % [
			"胜利" if victory else "失败", wave_idx, RunState.kills, RunState.gold, RunState.run_time])

## 主公阵亡 → 全屏褪色 1s → 失败结算(01 §12 关键演出)
func _on_lord_died() -> void:
	if state == State.ENDED:
		return
	if OS.is_debug_build():
		print("[WaveDirector] 主公阵亡 → 失败结算")
	state = State.ENDED
	_death_fade()
	Sfx.play("lose", -2.0)
	EventBus.wave_banner.emit("主公阵亡 —— 大意失荆州", 2.0)
	get_tree().paused = true
	var wr: WeakRef = weakref(self)
	var tm := get_tree().create_timer(1.2, true)   # 暂停中也计时
	tm.timeout.connect(func() -> void:
		var d = wr.get_ref()
		if d != null and is_instance_valid(d):
			d._show_defeat_result_if_ended())

## 全屏褪色演出:深褐罩 1s 淡入至 0.88,停在结算页后(01 §12;M6)
func _death_fade() -> void:
	if battle == null or not is_instance_valid(battle):
		return
	var layer := CanvasLayer.new()
	layer.layer = 8               # 结算弹窗(layer 10)之下,褪色垫底
	battle.add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(0.08, 0.06, 0.05, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var tw := rect.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)   # 暂停中继续淡入
	tw.tween_property(rect, "color:a", 0.88, 1.0)

## 延迟到期后的失败结算入口(状态仍 ENDED 且无结算弹窗时才弹;测试直调同一入口)
func _show_defeat_result_if_ended() -> void:
	if state != State.ENDED:
		return
	if modal != null and is_instance_valid(modal):
		return
	_show_result(false)

# ---------------------------------------------------------------- 波次流程

## 关卡剧本(docs/03 §2):优先按 spawn_plan 分批 + 扇区投放;
## 无剧本的旧数据回退「均匀刷新,普通敌在前、精英压后」(向后兼容)。
## 两种口径都保证队列按 t 升序,且在 duration*SPAWN_WINDOW 内投完(平衡模拟对齐)。
func _build_spawn_queue() -> void:
	spawn_queue = []
	var plan: Dictionary = wave_data.get("spawn_plan", {})
	var batches: Array = plan.get("batches", [])
	if not batches.is_empty():
		var default_arc: Array = plan.get("arc", [])
		for b in batches:
			var t := float(b.get("t", 0.0))
			var arc: Array = b.get("arc", default_arc)
			var spawn: Dictionary = b.get("spawn", {})
			for id in spawn:
				for i in int(spawn[id]):
					spawn_queue.append({"t": t, "id": str(id), "arc": arc})
		spawn_queue.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
		return
	var comp: Dictionary = wave_data.get("composition", {})
	var total := 0
	for id in comp:
		total += int(comp[id])
	if total == 0:
		return
	var interval := float(wave_data["duration"]) * SPAWN_WINDOW / float(total)
	var t := 0.0
	var ordered: Array = []
	for id in ["huangjin_zu", "huangjin_gongshou"]:
		for i in int(comp.get(id, 0)):
			ordered.append(str(id))
	for id in comp:
		if not ELITE_IDS.has(str(id)) and str(id) != "huangjin_zu" and str(id) != "huangjin_gongshou":
			for i in int(comp[id]):
				ordered.append(str(id))
	for id in ordered:
		spawn_queue.append({"t": t, "id": id})
		t += interval

func _alive_enemies() -> int:
	return get_tree().get_nodes_in_group("enemies").size()

func _time_up() -> void:
	# 幂等守卫:仅 BATTLE 态结算一次;BATTLE 每帧重复触发的二次调用一律 no-op(P1-1 回归)
	if state != State.BATTLE:
		return
	# 第 8 波「杀华雄才结束」:Boss 在场时计时到绝不退场/结算,唯一出口是击杀华雄(01 §3)。
	# 重复触发只做一次「普通敌退场 + 横幅」,之后每帧静默 return(修复前一帧后即落穿假胜利)
	if wave_idx >= DataDB.waves.size() and _boss_alive():
		if not _w8_timeup_done:
			_w8_timeup_done = true
			for e in get_tree().get_nodes_in_group("enemies"):
				if is_instance_valid(e) and not e.get("boss") and e.has_method("retreat"):
					e.retreat()
			EventBus.wave_banner.emit("斩华雄,方可结束!", 2.0)
		return
	# 计时结束:普通敌自动退场,不给军资(01 §3/§6)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("retreat"):
			e.retreat()
	_finish_wave(false)

func _boss_alive() -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead and bool(e.get("boss")):
			return true
	return false

## W8 增援:按 waves.json reinforcement(黄巾卒×4 / 10s),Boss 在场才增援(01 §6)
func _tick_reinforce(delta: float) -> void:
	var rf: Dictionary = wave_data.get("reinforcement", {})
	if rf.is_empty():
		return
	reinforce_t += delta
	if reinforce_t < float(rf.get("interval", 10.0)):
		return
	reinforce_t -= float(rf.get("interval", 10.0))
	var count := int(rf.get("count", 4))
	var arc: Array = rf.get("arc", [])
	for i in count:
		spawner.spawn_enemy(str(rf.get("enemy", "huangjin_zu")), float(wave_data["base_hp"]), float(wave_data["base_atk"]), arc)

## 敌兵死亡回调:第 8 波 Boss 阵亡 → 立即胜利(增援/召唤物在场也算,01 §3 杀华雄才结束)
func _on_enemy_died(unit: Node) -> void:
	if state != State.BATTLE and state != State.SPAWNING:
		return
	if wave_idx < DataDB.waves.size():
		return
	if is_instance_valid(unit) and bool(unit.get("boss")):
		if OS.is_debug_build():
			print("[WaveDirector] 华雄阵亡 → 胜利(用时 %.1fs)" % battle_t)
		_finish_wave(true)

func _finish_wave(cleared: bool) -> void:
	if OS.is_debug_build():
		print("[WaveDirector] wave %d 结束(cleared=%s) 敌余=%d" % [wave_idx, str(cleared), _alive_enemies()])
	CsvLogger.append_row([
		wave_idx, snappedf(battle_t, 0.1), _alive_enemies(),
		_team_hp_snapshot(), "cleared" if cleared else "time_up",
	])
	_enter_state(State.INTERMISSION)

## 敌兵死亡回调:军资掉落,总额对齐波表(02 §7.6)
func notify_enemy_death(enemy: Node) -> void:
	var v := Spawner.roll_drop(RunState.rng, gold_pool)
	if v > 0:
		gold_pool -= v
		spawner.spawn_gold(v, enemy.global_position)

func _next_wave() -> void:
	if wave_idx >= DataDB.waves.size():
		_show_result(true)         # 第 8 波结束 → 「桃园功成」(M3)
		return
	wave_idx += 1
	_enter_state(State.PRELUDE)

func _team_hp_snapshot() -> String:
	var parts: Array = []
	for m in RunState.team:
		parts.append("%s:%d/%d%s" % [m.hero_id, roundi(float(m.hp)), roundi(float(m.max_hp)), "" if bool(m.alive) else "(阵亡)"])
	return ";".join(PackedStringArray(parts))

# ---------------------------------------------------------------- HUD 技能槽绑定(M4)

## 将场上武将技能组件绑到 HUD 槽位(1~6 = 非主公武将,01 §10)
func _bind_hud_skills() -> void:
	var hud := battle.get_node_or_null("HUDLayer/HUD")
	if hud == null or not hud.has_method("bind_skill_slot"):
		return
	var heroes_root := battle.get_node_or_null("Units/Heroes")
	if heroes_root == null:
		return
	for u in heroes_root.get_children():
		# 跳过误挂进来的浮字/Label3D 等非单位节点(否则读 .dead 会 SCRIPT ERROR)
		if not is_instance_valid(u) or not (u is UnitBase) or u.dead:
			continue
		if u.get("skill_comp") == null:
			continue
		hud.bind_skill_slot(u.formation_index + 1, u.skill_comp)

# ---------------------------------------------------------------- 调试热键(仅 debug 构建,02 §9)

func _debug_fill_team() -> void:
	for id in ["zhaoyun", "huatuo", "zhuge", "lvbu"]:
		RunState.add_team_member(id)
	_sync_team_units()
	EventBus.wave_banner.emit("已招满全武将", 1.5)

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F1:
			var lord := battle.get_node_or_null("Units/PlayerLord")
			if lord != null:
				lord.invincible = not lord.invincible
				EventBus.wave_banner.emit("主公无敌: %s" % str(lord.invincible), 1.0)
		KEY_F2, KEY_F4:
			_force_end_wave()
		KEY_F3:
			RunState.add_gold(100)
			EventBus.wave_banner.emit("+100 军资", 1.0)
		KEY_F5:
			_jump_wave(8)
		KEY_F6:
			_debug_fill_team()
		KEY_F9:
			_regen_textures()

func _force_end_wave() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("retreat"):
			e.retreat()
	if state == State.SPAWNING or state == State.BATTLE:
		_finish_wave(false)

func _jump_wave(n: int) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("retreat"):
			e.retreat()
	get_tree().paused = false
	wave_idx = clampi(n, 1, DataDB.waves.size())
	_enter_state(State.PRELUDE)

func _regen_textures() -> void:
	OS.create_process(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/gen_textures.gd",
	])
