extends Node3D
## 斜俯视相机 rig(M2):俯角 55°、offset(0,13.1,9.2)、lerp 5.0/s 跟随主公(02 §4)。
## M6 震屏:监听 EventBus.screen_shake(Boss 出场/震地/华雄狂化),随机偏移幅度线性衰减。

const CAM_OFFSET := Vector3(0.0, 13.1, 9.2)   # 高 13.1 / tan55° ≈ 9.2
const LOOK_TARGET := Vector3(0.0, 0.6, 0.0)   # look_at 主公 + (0, 0.6, 0)
const FOLLOW_LERP := 5.0

@onready var cam: Camera3D = $Camera3D
var lord: Node3D = null

var _shake_amp := 0.0
var _shake_left := 0.0
var _shake_dur := 1.0

func _ready() -> void:
	cam.position = CAM_OFFSET
	cam.fov = 45.0
	cam.look_at_from_position(global_position + CAM_OFFSET, global_position + LOOK_TARGET)
	cam.current = true
	_find_lord.call_deferred()
	EventBus.screen_shake.connect(_on_screen_shake)

func _find_lord() -> void:
	var units := get_parent().get_node_or_null("Units")
	if units != null:
		lord = units.get_node_or_null("PlayerLord")

## 震屏:strength≈位移幅度(m),dur≈持续秒;取更强者,避免叠爆
func _on_screen_shake(strength: float, dur: float) -> void:
	if strength >= _shake_amp:
		_shake_amp = strength
		_shake_dur = maxf(0.1, dur)
		_shake_left = _shake_dur

func _process(delta: float) -> void:
	if lord == null or not is_instance_valid(lord):
		return
	var w := clampf(FOLLOW_LERP * delta, 0.0, 1.0)
	global_position = global_position.lerp(lord.global_position, w)
	if _shake_left > 0.0:
		_shake_left -= delta
		var k := clampf(_shake_left / _shake_dur, 0.0, 1.0)   # 线性衰减
		cam.position = CAM_OFFSET + Vector3(
			sin(Time.get_ticks_msec() * 0.09) * _shake_amp * k,
			0.0,
			cos(Time.get_ticks_msec() * 0.117) * _shake_amp * k * 0.6)
		if _shake_left <= 0.0:
			_shake_left = 0.0
			cam.position = CAM_OFFSET
	elif _shake_amp > 0.0:
		_shake_amp = 0.0
		cam.position = CAM_OFFSET
