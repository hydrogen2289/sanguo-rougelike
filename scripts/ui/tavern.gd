extends Control
## 酒馆(M8,02 §7):未拥有的武将按稀有度分档列出,两种进门方式——
##   直购:花军资直接入伙(level 1 / star 1);
##   合成:攒够该将定向碎片即可招入。
## 另售「扩编令牌」:提升上阵席位数(3 → 7,价格见 economy.json item_price.slot_cap)。
## 全部判定在 HeroSave;本文件只管显示与点击;关闭时统一落盘。

signal closed

const PANEL_SIZE := Vector2(1320, 780)
const NAME_COLOR := Color(0.35, 0.27, 0.2)

var _list: VBoxContainer
var _toast: Label
var _dirty := false

func _ready() -> void:
	add_to_group("modal")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiTheme.dim_bg())
	var panel := UiTheme.scroll_panel(PANEL_SIZE)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -PANEL_SIZE * 0.5
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	# 标题
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	vb.add_child(head)
	head.add_child(UiTheme.label("酒 馆", 34, UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23)), 5))
	var tip := UiTheme.label("招贤纳士:军资直购,或集齐碎片合成", 18, UiTheme.col("dark_brown", NAME_COLOR), 3)
	tip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(tip)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UiTheme.button("收 起", 20, Vector2(140, 48))
	close.pressed.connect(_on_close)
	head.add_child(close)
	# 提示条
	_toast = UiTheme.label("", 17, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)), 3)
	vb.add_child(_toast)
	# 列表(纵向滚动)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_refresh()

func _on_close() -> void:
	if _dirty:
		SaveState.flush()
	closed.emit()
	queue_free()

# ---------------------------------------------------------------- 列表

func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	# 扩编令(席位)固定在最上
	_list.add_child(_slot_cap_row())
	var ids := HeroSave.unowned_ids()
	if ids.is_empty():
		var all := UiTheme.label("名册中的武将已全部入伙。", 22, NAME_COLOR, 3)
		_list.add_child(all)
		return
	var last_tier := ""
	for id in ids:
		var rar := DataDB.hero_rarity(str(id))
		if rar != last_tier:
			last_tier = rar
			var tier := UiTheme.label("—— %s ——" % HeroCard.RARITY_NAME.get(rar, rar), 20, UiTheme.col("gold", Color(0.79, 0.66, 0.42)), 3)
			_list.add_child(tier)
		_list.add_child(_hero_row(str(id)))

func _slot_cap_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var cur := HeroSave.slot_cap()
	var txt := "上阵席位 %d / %d" % [cur, SaveState.MAX_SLOT_CAP]
	row.add_child(UiTheme.label(txt, 22, UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23)), 3))
	var prices: Array = DataDB.economy.get("item_price", {}).get("slot_cap", [])
	var idx := cur - SaveState.INITIAL_SLOT_CAP
	if cur >= SaveState.MAX_SLOT_CAP:
		row.add_child(UiTheme.label("（已满编）", 18, NAME_COLOR, 3))
	elif idx >= 0 and idx < prices.size():
		var price := int(prices[idx])
		var b := UiTheme.button("扩编令牌 军资 %d" % price, 20, Vector2(340, 50))
		b.disabled = SaveState.junzi() < price
		b.pressed.connect(_on_buy_slot.bind())
		row.add_child(b)
	return row

func _hero_row(hero_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var card := HeroCard.card(hero_id, Vector2(150, 168), true)
	row.add_child(card)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 6)
	row.add_child(mid)
	var h := DataDB.hero_by_id(hero_id)
	var role := str(h.get("trait", {}).get("name", ""))
	mid.add_child(UiTheme.label("%s · %s" % [HeroCard.RARITY_NAME.get(DataDB.hero_rarity(hero_id), ""), role], 18, NAME_COLOR, 3))
	var frag := SaveState.fragments_of(hero_id)
	mid.add_child(UiTheme.label("持有碎片 %d" % frag, 16, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)), 3))
	# 两个按钮:直购 / 合成
	var price := HeroSave.buy_price(hero_id)
	var buy := UiTheme.button("军资直购 %d" % price, 19, Vector2(230, 50))
	buy.disabled = SaveState.junzi() < price
	buy.pressed.connect(_on_buy_hero.bind(hero_id))
	row.add_child(buy)
	var need := HeroSave.fuse_cost(hero_id)
	var fuse := UiTheme.button("碎片合成 %d" % need, 19, Vector2(230, 50))
	fuse.disabled = frag < need
	fuse.pressed.connect(_on_fuse_hero.bind(hero_id))
	row.add_child(fuse)
	return row

# ---------------------------------------------------------------- 操作

func _on_buy_hero(hero_id: String) -> void:
	var r := HeroSave.recruit_buy(hero_id)
	_say(r, "招入 %s" % _name(hero_id))

func _on_fuse_hero(hero_id: String) -> void:
	var r := HeroSave.recruit_fuse(hero_id)
	_say(r, "以碎片合成 %s" % _name(hero_id))

func _on_buy_slot() -> void:
	var r := HeroSave.buy_slot_cap()
	_say(r, "席位扩至 %d" % int(r.get("slot_cap", HeroSave.slot_cap())))

func _say(r: Dictionary, ok_msg: String) -> void:
	if bool(r.get("ok", false)):
		_dirty = true
		_toast.text = ok_msg
		Sfx.play("button", -6.0)
	else:
		_toast.text = str(r.get("reason", "无法进行该操作"))
	_refresh()

func _name(hero_id: String) -> String:
	return str(DataDB.hero_by_id(hero_id).get("name", hero_id))
