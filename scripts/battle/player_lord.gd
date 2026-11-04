class_name PlayerLord
extends HeroUnit
## 主公(玩家操控位)(M1)。
## 主公是唯一由玩家直接操控的单位,普攻全自动(01 §3)。

func _ready() -> void:
	is_lord = true
	super()

func _move(delta: float) -> void:
	_move_by_input(delta)
