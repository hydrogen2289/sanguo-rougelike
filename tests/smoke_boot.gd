extends Node
## 冒烟引导:把 SmokeRunner 直挂 /root(场景切换不释放),随后本场景可被安全替换。

func _ready() -> void:
	var runner := Node.new()
	runner.name = "SmokeRunner"
	runner.set_script(load("res://tests/smoke_runner.gd"))
	get_tree().root.add_child.call_deferred(runner)
