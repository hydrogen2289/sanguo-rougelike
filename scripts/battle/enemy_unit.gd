class_name EnemyUnit
extends UnitBase
## 敌兵(M1):melee 直线追击近身挥砍 / ranged 保持距离放箭(01 §6)。
## 西凉亲卫与华雄数据已入表;Boss 行为本卡不实现(M5 挂载点)。

const TARGET_ACQUIRE_DIST := 999.0

var ai := "melee"
var attack_range := 1.4
var keep_distance := 5.0
var arrow_speed := 8.0
var kb_resist := 0.0
var immune_stun := false
var wave_base_hp := 15.0
var wave_base_atk := 5.0
var gold_director: Node = null      # WaveDirector,负责军资掉落总额
var boss := false
var slow_mult := 1.0                # 移速乘区:1.0 正常,0.7 = 减速 30%(马超铁骑冲锋,03 §3.1)
var slow_left := 0.0                # 减速剩余时间(s)
# --- 03 第三批敌方控制三态(05 §1/§2):恐惧/嘲讽/倒戈,与眩晕互斥、后到覆盖先到 ---
# 计时口径与 slow_left 一致:_physics_process 每帧衰减,到期清零还原。
# 互斥规则:后到覆盖 —— 任一态生效即清空其余态(含眩晕),只保留最后施加的一种。
var fear_left := 0.0                # 恐惧剩余(s):远离恐惧源移动、不可攻击、不可索敌
var fear_source: Node3D = null      # 恐惧源(张辽),倒计时结束或失效即还原
var taunt_left := 0.0               # 嘲讽剩余(s):强制索敌嘲讽者(许褚)
var taunt_source: Node3D = null     # 嘲讽源
var defected_left := 0.0            # 倒戈剩余(s)(貂蝉闭月):攻击最近敌方单位
var defected_by: Node3D = null      # 施法者记录(受控增伤乘区判定用,非索敌目标)

func _ready() -> void:
	add_to_group("enemies")
	_setup_from_enemy_data()
	super()
	_apply_rig()

func _setup_from_enemy_data() -> void:
	var e := DataDB.enemy_by_id(unit_id)
	if e.is_empty():
		return
	display_name = str(e.get("name", unit_id))
	ai = str(e.get("ai", "melee"))
	boss = ai == "boss"
	move_speed = float(e.get("move_speed", 2.0))
	size_mult = float(e.get("size", 1.0))
	kb_resist = float(e.get("kb_resist", 0.0))
	immune_stun = bool(e.get("immune_stun", false))
	attack_range = float(e.get("attack_range", 1.4))
	keep_distance = float(e.get("keep_distance", 5.0))
	arrow_speed = float(e.get("arrow_speed", 8.0))
	atk_interval = float(e.get("atk_interval", 1.2))
	if boss:
		max_hp = float(e.get("hp", 1500))
		atk = float(e.get("atk_slash", 20))
	else:
		max_hp = wave_base_hp * float(e.get("hp_mult", 1.0))
		atk = float(e.get("atk_fixed", wave_base_atk * float(e.get("atk_mult", 1.0))))
	hp = max_hp

## 表现升级:程序化拼装 3D 小人(体格差异走 scale_mult 语义)
func _apply_rig() -> void:
	apply_visual(size_mult)

## 后到覆盖先到(05 §1/§2):新控制态生效时清空其余控制态(含眩晕)。
## Boss 三态时长减半由施加方按 boss_duration_mult 折算,这里不再折半(避免重复)。
func _overwrite_controls(fear := 0.0, taunt := 0.0, defect := 0.0) -> void:
	stun_left = 0.0
	slow_left = 0.0                     # 减速虽非控制态,一并覆盖保持状态字段互斥口径清晰
	slow_mult = 1.0
	fear_left = fear
	taunt_left = taunt
	defected_left = defect
	if fear <= 0.0:
		fear_source = null
	if taunt <= 0.0:
		taunt_source = null
	if defect <= 0.0:
		defected_by = null

## 当前是否处于任一受控态(恐惧/嘲讽/倒戈/眩晕)—— 止啼/连环「受控增伤 +15%」共用此乘区判定
func is_controlled() -> bool:
	return stun_left > 0.0 or fear_left > 0.0 or taunt_left > 0.0 or defected_left > 0.0

## 恐惧(张辽 威压,05 §2.1):远离施法者、不可攻击、不可索敌;与眩晕互斥(后到覆盖)
func apply_fear(dur: float, source: Node3D) -> void:
	if dead:
		return
	_overwrite_controls(dur, 0.0, 0.0)
	fear_source = source
	_spawn_float("惧", Color(0.45, 0.35, 0.55))

## 嘲讽(许褚 虎痴,05 §2.2):强制索敌嘲讽者;Boss 不豁免(时长减半由施加方折算)
func apply_taunt(dur: float, source: Node3D) -> void:
	if dead:
		return
	_overwrite_controls(0.0, dur, 0.0)
	taunt_source = source
	_spawn_float("嘲", Color(0.85, 0.6, 0.3))

## 倒戈(貂蝉 闭月,05 §2.5):攻击最近的敌方单位;结束恢复。Boss 只踌躇不倒戈
## —— Boss 由施加方改走眩晕折算路径,不进此函数。
func apply_defect(dur: float, caster: Node3D) -> void:
	if dead or boss:
		return
	_overwrite_controls(0.0, 0.0, dur)
	defected_by = caster
	_spawn_float("惑", Color(0.75, 0.4, 0.6))

## 计时衰减 + 状态到期还原(与 slow 的 left 计时同模式)
func _tick_states(delta: float) -> void:
	if fear_left > 0.0:
		fear_left -= delta
		if fear_left <= 0.0:
			fear_left = 0.0
			fear_source = null
	if taunt_left > 0.0:
		taunt_left -= delta
		if taunt_left <= 0.0:
			taunt_left = 0.0
			taunt_source = null
	if defected_left > 0.0:
		defected_left -= delta
		if defected_left <= 0.0:
			defected_left = 0.0
			defected_by = null

func _move(delta: float) -> void:
	_tick_states(delta)
	# 恐惧(05 §2.1):远离恐惧源移动,不可攻击、不可索敌(_tick 已拦)
	if fear_left > 0.0:
		var src := fear_source
		if src != null and is_instance_valid(src):
			var away: Vector3 = global_position - src.global_position
			away.y = 0.0
			if away.length_squared() > 0.0001:
				var sep_f := separation_push()
				velocity = away.normalized() * move_speed * slow_mult + sep_f
				facing = away.normalized()
			else:
				velocity = separation_push()
		else:
			velocity = separation_push()   # 恐惧源已亡:原地发怔(仍不可攻击)
		move_and_slide()
		_clamp_to_arena()
		return
	if stun_left > 0.0:
		velocity = Vector3.ZERO            # 眩晕:禁 AI 与普攻位移(01 §3)
		move_and_slide()
		return
	if slow_left > 0.0:
		slow_left -= delta
		if slow_left <= 0.0:
			slow_left = 0.0
			slow_mult = 1.0                # 减速到期还原移速乘区
	var sep := separation_push()
	var speed := move_speed * slow_mult
	if ai == "ranged":
		_move_ranged(sep, speed)
	else:
		_move_melee(sep, speed)
	move_and_slide()
	_clamp_to_arena()

func _move_melee(sep: Vector3, speed: float) -> void:
	if target == null or not is_instance_valid(target):
		velocity = sep
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	if to.length() > attack_range * 0.9:
		velocity = to.normalized() * speed + sep
		facing = to.normalized()
	else:
		velocity = sep

func _move_ranged(sep: Vector3, speed: float) -> void:
	# 保持 5m 距离放箭(01 §6)
	if target == null or not is_instance_valid(target):
		velocity = sep
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	facing = to.normalized()
	if d < keep_distance - 1.0:
		velocity = -to.normalized() * speed + sep
	elif d > keep_distance + 1.0:
		velocity = to.normalized() * speed + sep
	else:
		velocity = sep

## 减速(马超铁骑冲锋,03 §3.1):移速乘区 ratio(0.7 = -30%),持续 dur 秒。
## 占位取舍:03 §6 待拍板「减速 vs 短眩晕」—— 已按「enemy 移速乘区」实现;Boss 不豁免减速。
func apply_slow(ratio: float, dur: float) -> void:
	if dead:
		return
	slow_mult = minf(slow_mult, 1.0 - clampf(ratio, 0.0, 0.9))
	slow_left = maxf(slow_left, dur)

func _tick() -> void:
	# 恐惧/眩晕:不可攻击、不可索敌(05 §2.1 / 01 §3)
	if fear_left > 0.0 or stun_left > 0.0:
		return
	# 嘲讽(05 §2.2):目标强制改写为嘲讽者;嘲讽者失效(亡/ freed)即回正常索敌
	if taunt_left > 0.0:
		var ts := taunt_source
		if ts != null and is_instance_valid(ts) and not bool(ts.get("dead")):
			target = ts
		else:
			taunt_left = 0.0
			taunt_source = null
	# 倒戈(05 §2.5):目标强制改写为最近的「敌方单位」(excluding 自己)
	elif defected_left > 0.0:
		target = nearest_other_enemy()
	if target == null or not is_instance_valid(target) or target.dead:
		target = acquire_target("friendlies", TARGET_ACQUIRE_DIST)
	if target == null or not is_instance_valid(target):
		return
	face_towards(target.global_position)
	_try_attack()

## 倒戈索敌:最近的敌方单位(不含自己、不含已死者;找不到则原地发怔)
func nearest_other_enemy() -> Node:
	var best: Node = null
	var best_d := TARGET_ACQUIRE_DIST
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not is_instance_valid(e) or e.dead:
			continue
		var d := _flat_dist(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

## 击退抗性(01 §6):力士 50%,Boss 100%(免疫击退)
func knockback_resist() -> float:
	return kb_resist

## 眩晕免疫:Boss 免疫击退/眩晕/斩杀(01 §6)
func stun_immune() -> bool:
	return boss or immune_stun

func _try_attack() -> void:
	if stun_left > 0.0 or fear_left > 0.0:
		return
	if target == null or not is_instance_valid(target) or target.dead:
		return
	if _atk_cd > 0.0:
		return
	var d := _flat_dist(target.global_position)
	if d > attack_range + 0.4:
		return
	_atk_cd = atk_interval
	if ai == "ranged":
		_spawn_arrow()
	else:
		target.take_damage(UnitBase.compute_damage(atk, 1.0), self)

func _spawn_arrow() -> void:
	if battle == null:
		return
	var proj_scene: PackedScene = load("res://scenes/units/projectile.tscn")
	if proj_scene == null:
		return
	var proj := proj_scene.instantiate()
	var to: Vector3 = target.global_position - global_position
	var dir := Vector3(to.x, 0.0, to.z).normalized()
	proj.setup(dir, arrow_speed, UnitBase.compute_damage(atk, 1.0), false)
	battle.get_node("Projectiles").add_child(proj)
	proj.global_position = global_position + Vector3(0.0, 1.0, 0.0)

## 敌兵死亡:0.5s 淡出 + 军资掉落(02 §7.6/7.7)
func _die() -> void:
	super()
	remove_from_group("enemies")
	remove_from_group("units")
	collision_layer = 0
	set_physics_process(false)
	RunState.add_kill()
	Sfx.play("die", -6.0)                 # 敌兵死亡闷响(M6)
	EventBus.enemy_died.emit(self)
	if gold_director != null and is_instance_valid(gold_director):
		gold_director.notify_enemy_death(self)
	if is_inside_tree():
		var tw := rig_sink_out(0.5)          # 沉入地面 + 缩放淡出
		tw.tween_interval(0.0)
	else:
		queue_free.call_deferred()

## 计时结束仍在场的普通敌人自动退场,不给军资(01 §3/§6)
func retreat() -> void:
	if dead:
		return
	dead = true
	remove_from_group("enemies")
	remove_from_group("units")
	collision_layer = 0
	set_physics_process(false)
	if is_inside_tree():
		rig_sink_out(0.4)                    # 沉入地面 + 缩放淡出
	else:
		queue_free.call_deferred()
