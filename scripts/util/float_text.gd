class_name FloatText
extends Label3D
## 浮字(M1 最简版;M4 加字号参数;M6 对象池化,02 §7.10):
## 0.7s 上浮 + 0.45s 淡出,结束后脱离场景树归还池,spawn 时取出复用。

const POOL_CAP := 64

static var _pool: ObjectPool = null

static func spawn(parent: Node, pos: Vector3, text: String, color: Color, font_size := 48) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var l: FloatText = _acquire()
	if l.get_parent() != null:
		l.get_parent().remove_child(l)
	parent.add_child(l)
	l.text = text
	l.modulate = Color(color.r, color.g, color.b, 1.0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.01
	l.font = UiTheme.font(font_size)   # 内嵌中文字体(Label3D 默认字体无汉字,Linux 上会变方块)
	l.font_size = font_size
	l.outline_size = int(font_size * 0.2)
	l.no_depth_test = true
	l.global_position = pos
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", pos + Vector3(0.0, 1.0, 0.0), 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.25)
	tw.chain().tween_callback(func() -> void: FloatText._release(l))

static func _acquire() -> FloatText:
	if _pool == null:
		_pool = ObjectPool.new(
			func() -> Variant: return FloatText.new(),
			func(l: Label3D) -> void:
				l.text = ""
				l.modulate = Color.WHITE)
	return _pool.acquire() as FloatText

static func _release(l: FloatText) -> void:
	if l == null or not is_instance_valid(l):
		return
	if l.get_parent() != null:
		l.get_parent().remove_child(l)
	if _pool != null and _pool.size() < POOL_CAP:
		_pool.release(l)
	else:
		l.free()
