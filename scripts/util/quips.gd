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
	var parent := unit.get_parent()
	if parent == null:
		return
	FloatText.spawn(parent, unit.global_position + Vector3(0.0, 2.4, 0.0), text, color, 64)
