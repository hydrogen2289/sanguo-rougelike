extends Control
## 商店(M3,01 §7):6 格货架(遗物×2 + 强化×2 + 军医诊治常驻 + 随机×1)。
## 定价 普通25/稀有40/史诗60、强化 20~35;刷新 20/次;已购下架;余额不足置灰;
## 离店(出征)即开下一波,不可返回。

signal checkout

var _shelf: Array = []
var _slot_buttons: Array[Button] = []
var _gold_label: Label
var _built := false

func open(_shop_data: Dictionary) -> void:
	add_to_group("modal")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if _built:
		return
	_built = true
	var dim := UiTheme.dim_bg()
	add_child(dim)
	var panel := UiTheme.scroll_panel(Vector2(880, 560))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-440, -280)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var title := UiTheme.label("行 商 之 铺", 32, UiTheme.col("cinnabar", Color.RED))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_gold_label = UiTheme.label("军资 %d" % RunState.gold, 20, UiTheme.col("gold", Color(0.79, 0.66, 0.42)))
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_gold_label)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(grid)
	for i in 6:
		var b := _build_slot(i)
		grid.add_child(b)
		_slot_buttons.append(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	var refresh_btn := UiTheme.button("刷新货架(%d 军资)" % int(DataDB.shop.get("refresh_price", 20)), 18, Vector2(220, 46))
	refresh_btn.pressed.connect(refresh_shelf)
	row.add_child(refresh_btn)
	var go_btn := UiTheme.button("出 征", 22, Vector2(220, 46))
	go_btn.pressed.connect(do_checkout)
	row.add_child(go_btn)
	var hint := UiTheme.label("离店即开下一波,不可返回", 14, UiTheme.col("dark_brown", Color(0.4, 0.36, 0.3)))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	RunState.gold_changed.connect(_on_gold_changed)
	_roll()
	_render()

func _build_slot(i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(260, 150)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UiTheme.panel_style())
	var sb_h: StyleBox = UiTheme.panel_style().duplicate()
	sb_h.modulate_color = Color(1.08, 1.05, 0.98)
	b.add_theme_stylebox_override("hover", sb_h)
	var sb_d: StyleBox = UiTheme.panel_style().duplicate()
	sb_d.modulate_color = Color(0.7, 0.68, 0.62, 0.7)
	b.add_theme_stylebox_override("disabled", sb_d)
	b.pressed.connect(buy.bind(i))
	return b

func _roll() -> void:
	_shelf = ShopShelf.roll(RunState.rng, RunState.relics)

func _render() -> void:
	for i in _slot_buttons.size():
		var b := _slot_buttons[i]
		for c in b.get_children():
			c.queue_free()
		var item: Dictionary = _shelf[i] if i < _shelf.size() else {}
		if item.is_empty():
			b.disabled = true
			var sold := UiTheme.label("已 售", 22, UiTheme.col("dark_brown", Color(0.4, 0.36, 0.3)))
			sold.set_anchors_preset(Control.PRESET_CENTER)
			sold.position = Vector2(-30, -16)
			b.add_child(sold)
			continue
		b.disabled = RunState.gold < int(item.get("price", 0))   # 余额不足置灰(01 §7)
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 4)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(vb)
		var icon_path := str(item.get("icon", ""))
		if icon_path != "" and ResourceLoader.exists(icon_path):
			var tr := TextureRect.new()
			tr.texture = load(icon_path)
			tr.custom_minimum_size = Vector2(40, 40)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			vb.add_child(tr)
		var name_l := UiTheme.label("%s" % str(item.get("name", "?")), 18, UiTheme.col("dark_brown", Color.BLACK))
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(name_l)
		var price_l := UiTheme.label("%d 军资" % int(item.get("price", 0)), 16, UiTheme.col("gold", Color(0.79, 0.66, 0.42)))
		price_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(price_l)
		var desc := UiTheme.label(str(item.get("desc", "")), 12, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)), 2)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.custom_minimum_size = Vector2(220, 30)
		vb.add_child(desc)
		if _gold_label != null:
			_gold_label.text = "军资 %d" % RunState.gold

func _on_gold_changed(_gold: int) -> void:
	_render()

## 购买:即时生效 + 下架(01 §7)
func buy(index: int) -> void:
	if index < 0 or index >= _shelf.size():
		return
	var item: Dictionary = _shelf[index]
	var err := ShopShelf.buy(item)
	if err != "":
		if OS.is_debug_build():
			print("[Shop] 购买失败:%s" % err)
		EventBus.wave_banner.emit(err, 1.2)
		return
	if OS.is_debug_build():
		print("[Shop] 购入 %s(-%d)" % [str(item.get("name", "")), int(item.get("price", 0))])
	EventBus.wave_banner.emit("购入「%s」" % str(item.get("name", "")), 1.2)
	_shelf[index] = {}      # 已购下架(01 §7)
	_render()

## 刷新货架 20 军资/次(01 §7)
func refresh_shelf() -> void:
	var price := int(DataDB.shop.get("refresh_price", 20))
	if not RunState.try_spend(price):
		EventBus.wave_banner.emit("军资不足,无法刷新", 1.2)
		return
	_roll()
	_render()

## 出征:离店即开下一波(01 §7)
func do_checkout() -> void:
	visible = false
	checkout.emit()
