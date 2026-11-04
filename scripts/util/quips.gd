class_name Quips
extends RefCounted
## 台词浮字(01 §12):张飞狂化 / 吕布不受令 / 华佗治疗 / 关羽斩杀。
## 全局限频 1 次 / 5s 防刷屏(任务卡 M4)。

static var _last_ms: int = -100000

static func say(unit: Node, text: String, color := Color(0.35, 0.28, 0.2)) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_ms < 5000:
		return
	_last_ms = now
	if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree():
		return
	# 台词浮字统一挂 battle/VFX,绝不挂单位容器(Units/Heroes|Enemies):
	# WaveDirector 会遍历这些容器的子节点并读 .dead/.unit_id,混入 Label3D 会 SCRIPT ERROR。
	var b: Node = unit.get("battle")
	var parent: Node = null
	if b != null and is_instance_valid(b):
		parent = b.get_node_or_null("VFX")
	if parent == null:
		parent = unit.get_parent()
	if parent == null:
		return
	FloatText.spawn(parent, unit.global_position + Vector3(0.0, 2.4, 0.0), text, color, 64)
