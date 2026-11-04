class_name HeroUnit
extends UnitBase
## 武将(主公与跟随武将共用)(M1;M4 加个性机制/refresh_stats/普攻命中回调)。
## 跟随 AI:formation 后方扇形 + 软分离 0.9m + 归队加速(02 §7.1);
## 索敌普攻:0.2s 节拍取 8m 内最近敌人,近战直伤 / 远程走 projectile(01 §3)。

const TARGET_ACQUIRE_DIST := 8.0   # 自动索敌 8m 内最近敌人(01 §3)
const RANGED_THRESHOLD := 2.5      # 攻距超过此值走弹道

var formation_index := 0
var lord: Node3D = null
var hero_data: Dictionary = {}
var skill_comp: Node = null

# --- M4 个性机制状态(01 §4) ---
var _trait_data: Dictionary = {}
var _enraged := false
var _roar_t := 0.0
var _aura_t := 0.0
var _base_atk_interval := 1.0
var _base_atk_range := 1.5

func _ready() -> void:
	add_to_group("friendlies")
	hero_data = DataDB.hero_by_id(unit_id)
	_trait_data = hero_data.get("trait", {})
	setup_from_data(hero_data)
	refresh_stats()                    # 应用 RunState 修饰符 + 个体加成
	super()                            # UnitBase._ready(group/MeleeRange)
	skill_comp = get_node_or_null("Skill")
	if skill_comp != null:
		skill_comp.setup(self)
	_apply_sprite()
	# 遗物/强化/事件修饰符变动 → 存量单位即时刷新(01 §8/§9)
	RunState.mods_changed.connect(refresh_stats)

func _apply_sprite() -> void:
	var path := "res://assets/textures/units/%s.png" % unit_id
	if ResourceLoader.exists(path):
		apply_visual(load(path), 0.005, 1.0)

func bind_lord(l: Node3D) -> void:
	lord = l

## 重新计算属性(RunState 修饰符变动:遗物/强化/事件,01 §8/§9)。
## max_hp 增加时同步加到当前 HP;不整活满血。
func refresh_stats() -> void:
	if hero_data.is_empty():
		return
	var d := hero_data
	var old_max := max_hp
	max_hp = RunState.stat(float(d.get("hp", 100)), "maxhp")
	if is_lord:
		max_hp += RunState.lord_maxhp_bonus()
	atk = RunState.stat(float(d.get("atk", 5)), "atk") * RunState.hero_atk_mult(unit_id)
	atk_interval = 1.0 / maxf(0.1, float(d.get("atk_speed", 1.0)))
	atk_range = float(d.get("range", 1.5))
	move_speed = RunState.stat(float(d.get("move_speed", 4.0)), "move")
	if is_lord:
		move_speed *= RunState.lord_move_mult()
	_base_atk_interval = atk_interval
	_base_atk_range = atk_range
	_apply_enrage_multipliers()
	if old_max > 0.0 and max_hp > old_max:
		hp += max_hp - old_max
	hp = minf(hp, max_hp)
	_sync_run_state_hp()

func _sync_run_state_hp() -> void:
	for m in RunState.team:
		if str(m.hero_id) == unit_id:
			m["max_hp"] = max_hp
			m["hp"] = hp

func _apply_enrage_multipliers() -> void:
	if not _enraged:
		return
	atk_interval = _base_atk_interval / maxf(1.0, float(_trait_data.get("atk_speed_mult", 1.4)))
	atk_range = _base_atk_range * maxf(1.0, float(_trait_data.get("range_mult", 1.3)))

func _move(delta: float) -> void:
	if is_lord:
		_move_by_input(delta)          # 保底:主公移动走输入
	else:
		_move_follow(delta)

## 主公输入移动( PlayerLord 覆写后的公共实现)
func _move_by_input(delta: float) -> void:
	var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3(iv.x, 0.0, iv.y)
	var sep := separation_push()
	if dir.length_squared() > 0.001:
		velocity = dir.normalized() * move_speed + sep
		facing = dir.normalized()
		sprite.flip_h = facing.x < 0.0
	else:
		velocity = sep
	move_and_slide()
	_clamp_to_arena()

## 跟随 AI:队形槽位 + 归队加速 + 软分离(02 §7.1)
func _move_follow(delta: float) -> void:
	if lord == null or not is_instance_valid(lord):
		velocity = separation_push()
		move_and_slide()
		return
	var followers := 0
	for h in get_tree().get_nodes_in_group("friendlies"):
		if not h.is_lord and not h.dead:
			followers += 1
	var tp: Vector3 = lord.global_position + Formation.slot_offset(formation_index, followers, lord.facing)
	var to_tp := tp - global_position
	to_tp.y = 0.0
	var lord_dist := _flat_dist(lord.global_position)
	var sp := move_speed * (1.5 if lord_dist > Formation.RETURN_DIST else 1.0)
	var sep := separation_push()
	if to_tp.length() > 0.25:
		velocity = to_tp.normalized() * sp + sep
		facing = to_tp.normalized()
	else:
		velocity = sep
	move_and_slide()
	_clamp_to_arena()

func _tick() -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		target = acquire_target("enemies", TARGET_ACQUIRE_DIST)
	_tick_trait()
	_try_attack()

## 个性机制 0.2s 节拍:光环(仁政/青囊)与燕人狂怒(01 §4)
func _tick_trait() -> void:
	if dead:
		return
	var ttype := str(_trait_data.get("type", ""))
	if ttype == "aura":
		_aura_t += DECISION_TICK
		if _aura_t >= 1.0:
			var amt := float(_trait_data.get("heal_per_sec", 0.8)) * _aura_t
			var radius := float(_trait_data.get("radius", 3.0))
			_aura_t -= 1.0
			for f in get_tree().get_nodes_in_group("friendlies"):
				if is_instance_valid(f) and not f.dead and _flat_dist(f.global_position) <= radius:
					f.heal(amt)    # heal() 内部 × 青囊书 heal_mult
	elif ttype == "enrage":
		_tick_enrage()

## 燕人狂怒:HP<35% 狂化(攻速+40% 攻距+30%,每 5s 吼退 2m 内敌 2m);HP≥50% 解除(01 §4)
func _tick_enrage() -> void:
	var ratio := hp / maxf(1.0, max_hp)
	var enter := float(_trait_data.get("enter_ratio", 0.35))
	var exit := float(_trait_data.get("exit_ratio", 0.50))
	if not _enraged and ratio < enter:
		_enraged = true
		_roar_t = 0.0
		_apply_enrage_multipliers()
		_spawn_float("狂", Color(0.71, 0.29, 0.23))
		Quips.say(self, "燕人张飞在此!")
	elif _enraged and ratio >= exit:
		_enraged = false
		_roar_t = 0.0
		apply_enrage_off()
	if _enraged:
		_roar_t += DECISION_TICK
		if _roar_t >= float(_trait_data.get("roar_interval", 5.0)):
			_roar_t -= float(_trait_data.get("roar_interval", 5.0))
			_roar()

func apply_enrage_off() -> void:
	_enraged = false
	atk_interval = _base_atk_interval
	atk_range = _base_atk_range

## 狂化吼退:2m 内敌兵击退 2m(01 §4)
func _roar() -> void:
	var radius := float(_trait_data.get("roar_radius", 2.0))
	var dist := float(_trait_data.get("roar_knockback", 2.0))
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead and _flat_dist(e.global_position) <= radius:
			e.apply_knockback(e.global_position - global_position, dist)

## 拖刀计可否斩杀(静态便于 test_formulas):普通敌兵当前 HP ≤ 最大 15%,Boss 免疫(01 §4)
static func can_execute_target(target_hp: float, target_max_hp: float, target_boss: bool, threshold := 0.15) -> bool:
	if target_boss or target_hp <= 0.0:
		return false
	return target_hp <= target_max_hp * threshold

static func enrage_should_enter(hp_ratio: float, enter := 0.35) -> bool:
	return hp_ratio < enter

static func enrage_should_exit(hp_ratio: float, exit := 0.50) -> bool:
	return hp_ratio >= exit

func _try_attack() -> void:
	if stun_left > 0.0:
		return
	if target == null or not is_instance_valid(target) or target.dead:
		return
	if _atk_cd > 0.0:
		return
	var d := _flat_dist(target.global_position)
	if d > atk_range + 0.4:
		return
	_atk_cd = atk_interval
	face_towards(target.global_position)
	if atk_range > RANGED_THRESHOLD:
		# 远程:命中效果(灼烧/斩杀)移到弹道真正命中时经 shooter 回调结算(P2-②);
		# 出手只生成弹道,不再直调命中回调(原实现会挂空 + 与弹道侧双重附加)
		_spawn_projectile()
	else:
		target.take_damage(UnitBase.compute_damage(atk, 1.0), self)
		Sfx.play("slash", -10.0)      # 挥砍(M6;Sfx 内限频防刷)
		_attack_anim()
		_post_attack_hit(target)      # 近战直伤命中即回调,行为不变

## 普攻命中回调(02 §7.4):拖刀计斩杀 + 东风灼烧附加(01 §4)。
## 近战在 _try_attack 直伤后调用;远程由 projectile 真正命中时回调(_on_body_entered)。
func _post_attack_hit(target: Node) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		return
	var ttype := str(_trait_data.get("type", ""))
	if ttype == "execution":
		var thr := float(_trait_data.get("threshold_ratio", 0.15))
		if HeroUnit.can_execute_target(float(target.hp), float(target.max_hp), bool(target.get("boss")), thr):
			target.executed_by(self)
			EventBus.executed_kill.emit()   # 全屏「斩!」白闪(01 §12,M6)
			Quips.say(self, "鼠辈,安敢挡我")
			return
	# 借东风:天气为全体普攻附加灼烧(已拍板;01 §4 说明 2)
	var wm := get_tree().get_first_node_in_group("weather_manager")
	if wm != null:
		wm.try_apply_burn(target)

func _spawn_projectile() -> void:
	if battle == null:
		return
	var proj_scene: PackedScene = load("res://scenes/units/projectile.tscn")
	if proj_scene == null:
		return
	var proj := proj_scene.instantiate()
	var to: Vector3 = target.global_position - global_position
	var dir := Vector3(to.x, 0.0, to.z).normalized()
	proj.setup(dir, 10.0, UnitBase.compute_damage(atk, 1.0), true, self)   # 携带射手:命中回调用
	battle.get_node("Projectiles").add_child(proj)
	proj.global_position = global_position + Vector3(0.0, 1.0, 0.0)

func _attack_anim() -> void:
	if not is_inside_tree() or target == null or not is_instance_valid(target):
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	var dir: Vector3 = to.normalized() * 0.15 if to.length_squared() > 0.001 else Vector3.ZERO
	var base_y := sprite.position.y
	var tw := create_tween()
	tw.tween_property(sprite, "position", Vector3(dir.x, base_y, dir.z), 0.06)
	tw.tween_property(sprite, "position", Vector3(0.0, base_y, 0.0), 0.10)

## 死亡:武将灰化倒地 2s 后移除,本局退场不可复活(01 §5 / 02 §7.7)
func _die() -> void:
	super()
	if OS.is_debug_build():
		print("[Hero] %s 阵亡" % display_name)
	remove_from_group("friendlies")
	remove_from_group("units")
	collision_layer = 0
	set_physics_process(false)
	RunState.mark_casualty(unit_id)
	EventBus.hero_died.emit(unit_id)
	if is_lord:
		# 主公阵亡事件 → 失败结算(WaveDirector 挂 M3)
		EventBus.lord_died.emit()
	if is_inside_tree():
		sprite.modulate = Color(0.45, 0.45, 0.45, 1.0)   # 灰化
		var tw := create_tween()
		tw.tween_property(sprite, "scale", Vector3(1.3, 0.15, 1.0), 0.4)   # 倒地
		tw.tween_interval(1.4)
		tw.tween_property(sprite, "modulate:a", 0.0, 0.4)
		tw.tween_callback(queue_free)
	else:
		queue_free.call_deferred()
