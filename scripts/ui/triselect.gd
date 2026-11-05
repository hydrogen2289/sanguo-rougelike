extends Control
## 三选一(M3,01 §7;03 第三批换人 UI,05 §3):3 张竖版卷轴卡(武将/遗物/数值强化),
## 权重 50/30/20、保底 1 强化。点击或按 1/2/3,选定即生效,新武将即刻入场。
## 满员时武将卡为「替换卡」:选定后弹出 6 选 1(在场武将头像行),指定者离队入候选池。

signal card_chosen(index: int)

const KIND_TAG := {"hero": "武将", "relic": "遗物", "upgrade": "强化"}
const KIND_COLOR := {"hero": "cinnabar", "relic": "gold", "upgrade": "deep_green"}

var _cards: Array = []
var _built := false
var _pending_replace: Dictionary = {}   # 满员武将卡暂存:等待 6 选 1 指定离队者
var _replace_row: Control = null

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
## 05 §3 换人规则 1:满员替换卡 → 先弹 6 选 1 头像行,选定离队者后再真正生效
func pick(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	var card: Dictionary = _cards[index]
	if str(card.get("kind", "")) == "hero" and bool(card.get("replace", false)):
		_pending_replace = card
		_show_replace_row(card)
		return
	var result_text := TriSelectPool.apply_pick(card)
	_finish_pick(card, result_text)

## 完成选定:横幅 + 关弹窗 + 信号(替换卡在 6 选 1 后走到这里)
func _finish_pick(card: Dictionary, result_text: String) -> void:
	if OS.is_debug_build():
		print("[TriSelect] 选定 %s(%s) → %s" % [str(card.get("name", "")), str(card.get("kind", "")), result_text])
	EventBus.wave_banner.emit(result_text, 1.6)
	_cards = []
	_pending_replace = {}
	visible = false                   # 先隐去,避免同帧与新弹窗混淆(modal 组按名查找)
	card_chosen.emit(-1)

# ---------------------------------------------------------------- 替换卡 6 选 1(05 §3,最简可用)

## 在场武将头像行:点谁谁离队;离队者入候选池、可再抽回(不视为阵亡)
func _show_replace_row(new_card: Dictionary) -> void:
	if _replace_row != null and is_instance_valid(_replace_row):
		_replace_row.queue_free()
	_replace_row = Control.new()
	_replace_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_replace_row)
	var panel := UiTheme.scroll_panel(Vector2(760, 300))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-380, -150)
	_replace_row.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)
	var title := UiTheme.label("替换 · 指定一名武将离队(「%s」入场)" % str(new_card.get("name", "?")),
		24, UiTheme.col("cinnabar", Color.RED))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	for m in RunState.team:
		var hid := str(m.hero_id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(100, 120)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UiTheme.panel_style())
		var sb_h: StyleBox = UiTheme.panel_style().duplicate()
		sb_h.modulate_color = Color(1.08, 1.05, 0.98)
		b.add_theme_stylebox_override("hover", sb_h)
		var avb := VBoxContainer.new()
		avb.set_anchors_preset(Control.PRESET_FULL_RECT)
		avb.alignment = BoxContainer.ALIGNMENT_CENTER
		avb.add_theme_constant_override("separation", 6)
		avb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(avb)
		var icon_path := "res://assets/textures/units/%s.png" % hid
		if ResourceLoader.exists(icon_path):
			var tr := TextureRect.new()
			tr.texture = load(icon_path)
			tr.custom_minimum_size = Vector2(64, 64)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			avb.add_child(tr)
		var nm := UiTheme.label(str(m.get("name", hid)), 16, UiTheme.col("dark_brown", Color.BLACK))
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		avb.add_child(nm)
		b.pressed.connect(_confirm_replace.bind(hid))
		row.add_child(b)
	var hint := UiTheme.label("离队者回候选池,可再抽回(不视为阵亡)", 14, UiTheme.col("dark_brown", Color(0.4, 0.36, 0.3)))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)

## 6 选 1 确认:替换生效(离队者由 WaveDirector._sync_team_units 走 leave_team 回收)
func _confirm_replace(out_id: String) -> void:
	if _pending_replace.is_empty():
		return
	var result_text := TriSelectPool.apply_pick_with_replace(_pending_replace, out_id)
	if _replace_row != null and is_instance_valid(_replace_row):
		_replace_row.queue_free()
		_replace_row = null
	_finish_pick(_pending_replace, result_text)
