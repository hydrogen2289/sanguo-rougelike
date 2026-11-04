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

func _ready() -> void:
	add_to_group("enemies")
	_setup_from_enemy_data()
	super()

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

func _apply_sprite() -> void:
	var path := "res://assets/textures/units/%s.png" % unit_id
	if ResourceLoader.exists(path):
		apply_visual(load(path), 0.005, size_mult)

func _move(delta: float) -> void:
	if stun_left > 0.0:
		velocity = Vector3.ZERO            # 眩晕:禁 AI 与普攻位移(01 §3)
		move_and_slide()
		return
	var sep := separation_push()
	if ai == "ranged":
		_move_ranged(sep)
	else:
		_move_melee(sep)
	move_and_slide()
	_clamp_to_arena()

func _move_melee(sep: Vector3) -> void:
	if target == null or not is_instance_valid(target):
		velocity = sep
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	if to.length() > attack_range * 0.9:
		velocity = to.normalized() * move_speed + sep
		facing = to.normalized()
	else:
		velocity = sep

func _move_ranged(sep: Vector3) -> void:
	# 保持 5m 距离放箭(01 §6)
	if target == null or not is_instance_valid(target):
		velocity = sep
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	facing = to.normalized()
	if d < keep_distance - 1.0:
		velocity = -to.normalized() * move_speed + sep
	elif d > keep_distance + 1.0:
		velocity = to.normalized() * move_speed + sep
	else:
		velocity = sep

func _tick() -> void:
	if stun_left > 0.0:
		return                             # 眩晕:跳过索敌与攻击
	if target == null or not is_instance_valid(target) or target.dead:
		target = acquire_target("friendlies", TARGET_ACQUIRE_DIST)
	if target == null or not is_instance_valid(target):
		return
	face_towards(target.global_position)
	_try_attack()

## 击退抗性(01 §6):力士 50%,Boss 100%(免疫击退)
func knockback_resist() -> float:
	return kb_resist

## 眩晕免疫:Boss 免疫击退/眩晕/斩杀(01 §6)
func stun_immune() -> bool:
	return boss or immune_stun

func _try_attack() -> void:
	if stun_left > 0.0:
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
		var tw := create_tween()
		tw.tween_property(sprite, "modulate:a", 0.0, 0.5)
		tw.tween_callback(queue_free)
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
		var tw := create_tween()
		tw.tween_property(sprite, "modulate:a", 0.0, 0.4)
		tw.tween_callback(queue_free)
	else:
		queue_free.call_deferred()
