extends Control
## 事件弹窗(M3,01 §9):居中卷轴:标题 + 一句话剧情 + A/B 按钮;ESC 不可关闭(必须二选一)。
## 事件数据:data/events.json —— 鞭打督邮 W2 / 三让徐州 W4 / 虎牢关·飞将来投 W6。
## 吕布 = A 路「花 60 军资招募」(队伍未满且军资足够才可选,已拍板)。

signal chosen(option: String)   # "a" / "b"

var _event: Dictionary = {}
var _btn_a: Button
var _btn_b: Button
var _built := false

func open(event_data: Dictionary) -> void:
	add_to_group("modal")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_event = event_data
	if _built:
		return
	_built = true
	var dim := UiTheme.dim_bg()
	add_child(dim)
	var panel := UiTheme.scroll_panel(Vector2(760, 460))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-380, -230)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)
	var title := UiTheme.label("【%s】" % str(_event.get("name", "?")), 34, UiTheme.col("cinnabar", Color.RED))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var story := UiTheme.label(str(_event.get("story", "")), 20, UiTheme.col("dark_brown", Color.BLACK))
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story.custom_minimum_size = Vector2(600, 60)
	vb.add_child(story)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	_btn_a = _option_button("a", row)
	_btn_b = _option_button("b", row)
	var hint := UiTheme.label("必须二选一(ESC 不可关闭)", 14, UiTheme.col("dark_brown", Color(0.4, 0.36, 0.3)))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)

func _option_button(key: String, row: HBoxContainer) -> Button:
	var opt: Dictionary = _event.get(key if key == "a" else "b", {})
	var b := Button.new()
	b.custom_minimum_size = Vector2(280, 110)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UiTheme.panel_style())
	var sb_h: StyleBox = UiTheme.panel_style().duplicate()
	sb_h.modulate_color = Color(1.08, 1.05, 0.98)
	b.add_theme_stylebox_override("hover", sb_h)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	var lbl := UiTheme.label(str(opt.get("label", "?")), 20, UiTheme.col("dark_brown", Color.BLACK))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl)
	var desc := UiTheme.label(str(opt.get("desc", "")), 14, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)), 2)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(desc)
	b.pressed.connect(choose.bind(key))
	row.add_child(b)
	return b

## 选项是否可选(吕布招募:队伍未满 + 军资足够,01 §9;其余恒可选)
func option_enabled(option: String) -> bool:
	if _event.is_empty():
		return false
	if str(_event.get("id", "")) == "hulaoguan" and option == "a":
		if RunState.team.size() >= RunState.MAX_TEAM:
			return false
		var cost := int(_event.get("option_a", {}).get("effect", {}).get("cost_gold", 60))
		if RunState.gold < cost:
			return false
	return true

## 二选一结算:效果即时生效 → 发信号(WaveDirector 关闭弹窗推进队列)
func choose(option: String) -> void:
	if _event.is_empty() or not option_enabled(option):
		if OS.is_debug_build():
			print("[EventPopup] 选项 %s 不可选" % option)
		return
	var opt: Dictionary = _event.get("option_a" if option == "a" else "option_b", {})
	var result_text := EventEffects.apply(opt.get("effect", {}))
	if result_text == "":
		result_text = "「%s」" % str(opt.get("label", ""))
	if OS.is_debug_build():
		print("[Event] %s 选 %s → %s" % [str(_event.get("name", "")), option, result_text])
	EventBus.wave_banner.emit(result_text, 2.0)
	_event = {}
	_btn_a.disabled = true
	_btn_b.disabled = true
	visible = false                   # 先隐去,避免同帧与新弹窗混淆
	chosen.emit(option)
