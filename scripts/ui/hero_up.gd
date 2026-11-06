extends Control
## 武将府(M8,02 §7):左侧已拥有武将名册,右侧选中武将的养成面板。
## 升级花军资(曲线见 HeroSave.level_cost),升星花该将定向碎片。
## 每次操作成功即时刷新并把改动标记为脏;关闭面板时统一落盘(SceneRouter.goto_menu 也会落)。
## 所有算术与校验都在 HeroSave;本文件只管显示与点击。

signal closed

const PANEL_SIZE := Vector2(1320, 760)
const NAME_COLOR := Color(0.35, 0.27, 0.2)

var _picked := "liubei"
var _roster_box: HBoxContainer
var _detail: VBoxContainer
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
	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 12)
	panel.add_child(root_vb)
	# 标题行
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	root_vb.add_child(head)
	var title := UiTheme.label("武 将 府", 34, UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23)), 5)
	head.add_child(title)
	var tip := UiTheme.label("升级耗军资 · 升星耗该将碎片", 18, UiTheme.col("dark_brown", NAME_COLOR), 3)
	tip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(tip)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UiTheme.button("收 起", 20, Vector2(140, 48))
	close.pressed.connect(_on_close)
	head.add_child(close)
	# 名册(横向可滚)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vb.add_child(scroll)
	_roster_box = HBoxContainer.new()
	_roster_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_roster_box)
	# 详情区
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 14)
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vb.add_child(_detail)
	_refresh()

func _on_close() -> void:
	if _dirty:
		SaveState.flush()
	closed.emit()
	queue_free()

# ---------------------------------------------------------------- 名册

func _refresh() -> void:
	for c in _roster_box.get_children():
		c.queue_free()
	for id in HeroSave.owned_ids():
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 168)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UiTheme.panel_style())
		b.add_theme_stylebox_override("hover", UiTheme.panel_style())
		b.add_theme_stylebox_override("pressed", UiTheme.panel_style())
		if str(id) == _picked:
			b.modulate = Color(1.15, 1.08, 0.92)
		b.pressed.connect(_on_pick.bind(str(id)))
		var card := HeroCard.card(str(id), Vector2(150, 168))
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(card)
		_roster_box.add_child(b)
	_refresh_detail()

# ---------------------------------------------------------------- 详情

func _refresh_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if not HeroSave.owned(_picked):
		_picked = "liubei"
	var h := DataDB.hero_by_id(_picked)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	_detail.add_child(row)
	# 左:大头像 + 基础值
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	var pic := TextureRect.new()
	pic.texture = HeroCard.portrait(_picked, 160)
	pic.custom_minimum_size = Vector2(160, 160)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	left.add_child(pic)
	var lv := HeroSave.level_of(_picked)
	var st := HeroSave.star_of(_picked)
	var f := HeroSave.factors(_picked)
	var hp := float(h.get("hp", 0)) * f
	var atk := float(h.get("atk", 0)) * f
	left.add_child(_line("Lv.%d / %d   %s" % [lv, HeroSave.level_cap(), HeroCard.star_text(st)], 22,
		UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23))))
	left.add_child(_line("生命 %.0f   攻击 %.1f" % [hp, atk], 18, NAME_COLOR))
	left.add_child(_line("养成加成 ×%.2f" % f, 16, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32))))
	# 右:两条养成操作
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	right.add_child(_line("兵 法(等级)", 24, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32))))
	if lv >= HeroSave.level_cap():
		right.add_child(_line("已达等级上限", 18, NAME_COLOR))
	else:
		var cost := HeroSave.level_cost(lv)
		var can := SaveState.junzi() >= cost
		var btn := UiTheme.button("升级 → Lv.%d   军资 %d" % [lv + 1, cost], 20, Vector2(460, 52))
		btn.disabled = not can
		btn.tooltip_text = "" if can else "军资不足"
		btn.pressed.connect(_on_upgrade)
		right.add_child(btn)
	var rule := ColorRect.new()
	rule.color = UiTheme.col("gold", Color(0.79, 0.66, 0.42))
	rule.custom_minimum_size = Vector2(0, 2)
	right.add_child(rule)
	right.add_child(_line("星 阶(星级)", 24, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32))))
	if st >= HeroSave.star_cap():
		right.add_child(_line("已达星级上限", 18, NAME_COLOR))
	else:
		var scost := HeroSave.star_cost(st)
		var have := SaveState.fragments_of(_picked)
		var can2 := have >= scost
		var btn2 := UiTheme.button("升星 → %d 星   碎片 %d/%d" % [st + 1, have, scost], 20, Vector2(460, 52))
		btn2.disabled = not can2
		btn2.tooltip_text = "" if can2 else "该将碎片不足(出征/塔结算获取)"
		btn2.pressed.connect(_on_star_up)
		right.add_child(btn2)
	var note := _line("升星是全属性乘区,适用于出征与试炼塔的全部队伍。", 15, Color(0.42, 0.38, 0.32))
	right.add_child(note)

func _line(text: String, size: int, color: Color) -> Label:
	var l := UiTheme.label(text, size, color, 3)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# ---------------------------------------------------------------- 操作

func _on_pick(hero_id: String) -> void:
	_picked = hero_id
	_refresh()

func _on_upgrade() -> void:
	var r := HeroSave.upgrade_level(_picked)
	if bool(r.get("ok", false)):
		_dirty = true
		Sfx.play("button", -6.0)
	_refresh()

func _on_star_up() -> void:
	var r := HeroSave.star_up(_picked)
	if bool(r.get("ok", false)):
		_dirty = true
		Sfx.play("button", -6.0)
	_refresh()
