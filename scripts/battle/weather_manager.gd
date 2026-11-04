extends Node
## 天气管理(M1 落位;M4 借东风技能经 EventBus.eastwind_started 接入,01 §4 / 02 §7.8)。
## 东风期间:fire_mult = 1 + fire_dmg_pct、全体普攻附加灼烧、全屏 12% 春青色罩 + 风线。

var eastwind := false
var fire_mult := 1.0
# 灼烧参数读自诸葛亮技能表(01 §4 借东风):每 0.5s 2 点、持续 3s、火伤 +30%
var burn_tick_dmg := 2.0
var burn_interval := 0.5
var burn_duration := 3.0
var fire_dmg_pct := 0.30
var _overlay: ColorRect
var _timer: Timer

func _ready() -> void:
	add_to_group("weather_manager")
	var zhuge: Dictionary = DataDB.hero_by_id("zhuge")
	if not zhuge.is_empty():
		var sk: Dictionary = zhuge.get("skill", {})
		burn_tick_dmg = float(sk.get("burn_tick_dmg", 2.0))
		burn_interval = float(sk.get("burn_tick", 0.5))
		burn_duration = float(sk.get("burn_duration", 3.0))
		fire_dmg_pct = float(sk.get("fire_dmg_pct", 0.30))
	_overlay = ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/eastwind_tint.gdshader")
	mat.set_shader_parameter("strength", 1.0)
	_overlay.material = mat
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.modulate.a = 0.0
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	layer.add_child(_overlay)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_clear_eastwind)
	add_child(_timer)
	EventBus.eastwind_started.connect(set_eastwind)

func set_eastwind(duration: float) -> void:
	eastwind = true
	fire_mult = 1.0 + fire_dmg_pct
	_timer.start(duration)
	Sfx.play("eastwind")
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 1.0, 0.6)

## 普攻命中回调(M4):东风期间为命中目标附加灼烧(独立结算,01 §3/§4)
func try_apply_burn(target: Node) -> void:
	if not eastwind or target == null or not is_instance_valid(target):
		return
	if target.has_method("apply_burn") and not target.dead:
		target.apply_burn(burn_tick_dmg * fire_mult, burn_interval, burn_duration)

func _clear_eastwind() -> void:
	eastwind = false
	fire_mult = 1.0
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 0.0, 1.0)
	EventBus.eastwind_ended.emit()
