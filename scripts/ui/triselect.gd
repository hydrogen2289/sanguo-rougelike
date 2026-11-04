extends Control
## 三选一(M3,01 §7):3 张竖版卷轴卡(武将/遗物/数值强化),权重 50/30/20、保底 1 强化。
## 点击或按 1/2/3,选定即生效,新武将即刻入场(WaveDirector 响应 team_changed)。

signal card_chosen(index: int)

const KIND_TAG := {"hero": "武将", "relic": "遗物", "upgrade": "强化"}
const KIND_COLOR := {"hero": "cinnabar", "relic": "gold", "upgrade": "deep_green"}

var _cards: Array = []
var _built := false

func open(ctx: Dictionary) -> void:
	add_to_group("modal")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if _built:
		return
	_built = true
	var dim := UiTheme.dim_bg()
	add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-330, -280)
	box.size = Vector2(660, 560)
	box.add_theme_constant_override("separation", 20)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	var title := UiTheme.label("三选一 · 择一而行", 36, UiTheme.col("cinnabar", Color.RED))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint := UiTheme.label("点击卡片或按 1 / 2 / 3 选定", 16, UiTheme.col("dark_brown", Color.BLACK))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_cards = TriSelectPool.offer(RunState.rng, int(ctx.get("wave_idx", 1)))
	for i in _cards.size():
		row.add_child(_build_card(i))

func _build_card(i: int) -> Button:
	var card: Dictionary = _cards[i]
	var kind := str(card.get("kind", "upgrade"))
	var b := Button.new()
	b.custom_minimum_size = Vector2(200, 360)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UiTheme.panel_style())
	var sb_h: StyleBox = UiTheme.panel_style().duplicate()
	sb_h.modulate_color = Color(1.08, 1.05, 0.98)
	b.add_theme_stylebox_override("hover", sb_h)
	b.pressed.connect(pick.bind(i))
	# 卡面内容(竖版卷轴:类别签 + 图标/字牌 + 名称 + 效果)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 10)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	var tag := UiTheme.label(str(KIND_TAG.get(kind, "?")), 16, UiTheme.col(str(KIND_COLOR.get(kind, "dark_brown")), Color.BLACK))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tag)
	var icon_path := str(card.get("icon", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tr := TextureRect.new()
		tr.texture = load(icon_path)
		tr.custom_minimum_size = Vector2(96, 96)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(tr)
	else:
		var glyph := UiTheme.label("令", 56, UiTheme.col("spring_green", Color.GREEN))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(glyph)
	var name_l := UiTheme.label(str(card.get("name", "?")), 24, UiTheme.col("dark_brown", Color.BLACK))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(name_l)
	var desc := UiTheme.label(str(card.get("desc", "")), 15, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)), 2)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.custom_minimum_size = Vector2(170, 110)
	vb.add_child(desc)
	var key_hint := UiTheme.label("[%d]" % (i + 1), 16, UiTheme.col("dark_brown", Color.BLACK))
	key_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(key_hint)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_1:
				pick(0)
			KEY_2:
				pick(1)
			KEY_3:
				pick(2)

## 选定即生效(01 §7);应用后发信号,WaveDirector 关闭弹窗并推进波间队列
func pick(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	var card: Dictionary = _cards[index]
	var result_text := TriSelectPool.apply_pick(card)
	if OS.is_debug_build():
		print("[TriSelect] 选定 %d:%s(%s) → %s" % [index, str(card.get("name", "")), str(card.get("kind", "")), result_text])
	EventBus.wave_banner.emit(result_text, 1.6)
	_cards = []
	visible = false                   # 先隐去,避免同帧与新弹窗混淆(modal 组按名查找)
	card_chosen.emit(index)
