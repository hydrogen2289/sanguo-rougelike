class_name ObjectPool
extends RefCounted
## 通用对象池(02 §7.10)。M6 已接线:浮字(FloatText)与技能 VFX(Sprite3D)复用。
## acquire 归还前经 reset_cb 复位;release 侧由调用方保证先脱离场景树。

var _factory: Callable
var _reset_cb: Callable
var _items: Array = []

func _init(factory: Callable, reset_cb := Callable()) -> void:
	_factory = factory
	_reset_cb = reset_cb

func acquire():
	while not _items.is_empty():
		var it = _items.pop_back()
		if it != null and is_instance_valid(it):
			if _reset_cb.is_valid():
				_reset_cb.call(it)
			return it
		# 池中对象已被外部释放(场景树拆除等)→ 丢弃继续取
	return _factory.call()

func release(item) -> void:
	_items.append(item)

func size() -> int:
	return _items.size()
