class_name Formation
extends RefCounted
## 队形与软分离工具(M1)。纯静态函数,便于 test_formulas 直接测(02 §7.1)。

const FORM_RADIUS := 1.5        # 以主公为圆心、半径 1.5m 的后方扇形(01 §5)
const RETURN_DIST := 5.0        # 与主公距离 > 5m 时 1.5 倍移速归队(01 §5)
const SEPARATION_RADIUS := 0.9  # 软分离邻域 0.9m(02 §3)
const FAN_DEG := 150.0          # 后方扇形张角

## 武将槽位 i / n:主公后方 150° 扇形均布
static func slot_offset(index: int, count: int, facing: Vector3) -> Vector3:
	var back := Vector3(-facing.x, 0.0, -facing.z)
	if back.length_squared() < 0.0001:
		back = Vector3(0.0, 0.0, 1.0)
	back = back.normalized()
	if count <= 1:
		return back * FORM_RADIUS
	var t := float(index) / float(count - 1)
	var ang := deg_to_rad(-FAN_DEG * 0.5 + FAN_DEG * t)
	return back.rotated(Vector3.UP, ang) * FORM_RADIUS

## 软分离:对 radius 内邻居叠加排斥位移(不做硬碰撞,02 §3)
static func separation(pos: Vector3, other_positions: Array, radius := SEPARATION_RADIUS) -> Vector3:
	var push := Vector3.ZERO
	for op in other_positions:
		var away := Vector3(pos.x - op.x, 0.0, pos.z - op.z)
		var d := away.length()
		if d > 0.0001 and d < radius:
			push += away * ((radius - d) / d)
		elif d <= 0.0001:
			# XZ 重叠时仅当 3D 距离也近乎重叠才散开(不同高度的单位不互斥)
			if pos.distance_to(op) < 0.5:
				push += Vector3(0.0, 0.0, 0.1)   # 完全重叠时的确定性散开
	return push
