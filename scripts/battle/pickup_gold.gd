extends Node3D
## 军资掉落物(M1):自动磁吸,半径 2.5m 飞向主公(01 §3 / 02 §7.6)。

var value := 1
var _t := 0.0
var _lord: Node3D = null
var _speed := 0.0
const MAGNET_RADIUS := 2.5

func _ready() -> void:
	_t = RunState.rng.randf() * TAU
	var sp: Sprite3D = $Sprite
	if sp.texture == null:
		var path := "res://assets/textures/icons/coin.png"
		if ResourceLoader.exists(path):
			sp.texture = load(path)
	sp.pixel_size = 0.006
	sp.position.y = 0.0

func _process(delta: float) -> void:
	_t += delta
	var sp: Sprite3D = $Sprite
	sp.position.y = 0.35 + sin(_t * 3.0) * 0.08
	if _lord == null or not is_instance_valid(_lord):
		_lord = _find_lord()
		if _lord == null:
			return
	var d3 := _lord.global_position - global_position
	d3.y = 0.0
	var d := d3.length()
	if d < MAGNET_RADIUS:
		_speed = minf(_speed + 14.0 * delta, 9.0)
		global_position += d3.normalized() * _speed * delta
		if d < 0.45:
			RunState.add_gold(value)
			EventBus.gold_picked.emit(value)
			Sfx.play("coin")
			queue_free()
	else:
		_speed = 0.0

func _find_lord() -> Node3D:
	for u in get_tree().get_nodes_in_group("friendlies"):
		if u.is_lord and not u.dead:
			return u
	return null
