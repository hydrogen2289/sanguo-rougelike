class_name Spawner
extends RefCounted
## 生成器(M1):敌人 / 武将 / 军资,由 WaveDirector 驱动。
## 场景懒加载(避免 --script 测试模式下强依赖导入缓存)。

var battle: Node = null
var director: Node = null

func spawn_hero(hero_id: String, formation_index: int) -> Node:
	var scene: PackedScene = load("res://scenes/units/hero.tscn")
	if scene == null or battle == null:
		return null
	var u := scene.instantiate()
	u.unit_id = hero_id
	u.is_lord = false
	u.formation_index = formation_index
	u.battle = battle
	battle.get_node("Units/Heroes").add_child(u)
	u.bind_lord(battle.get_node("Units/PlayerLord"))
	return u

func spawn_enemy(enemy_id: String, base_hp: float, base_atk: float) -> Node:
	# Boss 走专属场景(boss_huaxiong.tscn,02 §2 目录树);其余敌兵走 enemy.tscn
	var scene_path := "res://scenes/units/enemy.tscn"
	var ed: Dictionary = DataDB.enemy_by_id(enemy_id)
	if str(ed.get("ai", "")) == "boss" and ResourceLoader.exists("res://scenes/units/boss_huaxiong.tscn"):
		scene_path = "res://scenes/units/boss_huaxiong.tscn"
	var scene: PackedScene = load(scene_path)
	if scene == null or battle == null:
		return null
	var u := scene.instantiate()
	u.unit_id = enemy_id
	u.wave_base_hp = base_hp
	u.wave_base_atk = base_atk
	u.battle = battle
	u.gold_director = director
	battle.get_node("Units/Enemies").add_child(u)
	u.global_position = ring_position()
	return u

func spawn_gold(value: int, pos: Vector3) -> Node:
	var scene: PackedScene = load("res://scenes/units/pickup_gold.tscn")
	if scene == null or battle == null:
		return null
	var g := scene.instantiate()
	g.value = value
	battle.get_node("Pickups").add_child(g)
	g.global_position = pos + Vector3(
		RunState.rng.randf_range(-0.4, 0.4), 0.0, RunState.rng.randf_range(-0.4, 0.4))
	return g

## 敌人环形刷在相机视野外约 2m(01 §6):以主公为心,半径 12~15m,夹回战场内
func ring_position() -> Vector3:
	var lord: Node3D = battle.get_node("Units/PlayerLord")
	var ang := RunState.rng.randf() * TAU
	var r := RunState.rng.randf_range(12.0, 15.0)
	var p := lord.global_position + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	p.x = clampf(p.x, -19.0, 19.0)
	p.z = clampf(p.z, -19.0, 19.0)
	return p

## 军资掉落:单枚 1~3,每波总额对齐 waves.json 的 15~30(02 §7.6)。
## 纯静态便于 test_formulas 直接测。
static func roll_drop(rng: RandomNumberGenerator, pool_left: int) -> int:
	if pool_left <= 0:
		return 0
	return mini(pool_left, rng.randi_range(1, 3))
