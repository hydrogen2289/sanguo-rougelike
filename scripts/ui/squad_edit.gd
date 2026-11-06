extends Control
## 校场 · 编队(M8,02 §5.3/§7):主公固定居首,其余席位从已拥有武将里点选。
## 编队即出征名单:RunState.reset 从 SaveState.data.squad.slots 取人(02 §5.3)。
## 出征前(M9 关卡确认)与本面板共用同一份存档字段,不另存一份。
## 面板关闭时若有过改动则落盘。

signal closed
## 确认出征时带出新名单,供调用方(未来 M9 关卡确认页)接手
signal confirmed(slots: Array)

const PANEL_SIZE := Vector2(1280, 700)
const NAME_COLOR := Color(0.35, 0.27, 0.2)

var _slots: Array = []
var _slot_box: HBoxContainer
var _pool: HBoxContainer
var _cap_label: Label
var _hint: Label
var _dirty := false
var _with_confirm := false

func setup(confirm_button: bool) -> void:
	_with_confirm = confirm_button

func _ready() -> void:
	add_to_group("modal")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_slots = HeroSave.slots()
	add_child(UiTheme.dim_bg())
	var panel := UiTheme.scroll_panel(PANEL_SIZE)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -PANEL_SIZE * 0.5
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	vb.add_child(head)
	head.add_child(UiTheme.label("校 场 · 编 队", 32, UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23)), 5))
	_cap_label = UiTheme.label("", 20, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)), 3)
	_cap_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_cap_label)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var auto := UiTheme.button("按战力补满", 19, Vector2(170, 46))
	auto.pressed.connect(_on_auto)
	head.add_child(auto)
	var close := UiTheme.button("收 起", 19, Vector2(120, 46))
	close.pressed.connect(_on_close)
	head.add_child(close)
	# 上阵槽位
	vb.add_child(UiTheme.label("上 阵", 20, NAME_COLOR, 3))
	var slot_scroll := ScrollContainer.new()
	slot_scroll.custom_minimum_size = Vector2(0, 150)
	slot_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(slot_scroll)
	_slot_box = HBoxContainer.new()
	_slot_box.add_theme_constant_override("separation", 10)
	slot_scroll.add_child(_slot_box)
	# 候选池
	vb.add_child(UiTheme.label("候 选(点选上阵 / 再点撤下)", 20, NAME_COLOR, 3))
	var pool_scroll := ScrollContainer.new()
	pool_scroll.custom_minimum_size = Vector2(0, 200)
	pool_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(pool_scroll)
	_pool = HBoxContainer.new()
	_pool.add_theme_constant_override("separation", 10)
	pool_scroll.add_child(_pool)
	# 底栏
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	vb.add_child(foot)
	_hint = UiTheme.label("主公刘备固定居首;阵亡的武将在本次出征内不会复活。", 16, Color(0.42, 0.38, 0.32), 3)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_hint)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp2)
	if _with_confirm:
		var ok := UiTheme.button("披挂出征", 22, Vector2(220, 54))
		ok.pressed.connect(_on_confirm)
		foot.add_child(ok)
	_refresh()

func _on_close() -> void:
	_persist()
	closed.emit()
	queue_free()

## 确认:先落盘再喊人(调用方通常立刻切场景,这里不自行销毁)
func _on_confirm() -> void:
	if _persist():
		confirmed.emit(_slots.duplicate())

## 写回存档(校验失败时不写并提示;成功则记脏,由关闭/出征统一落盘)
func _persist() -> bool:
	var r := HeroSave.set_squad(_slots)
	if not bool(r.get("ok", false)):
		_hint.text = str(r.get("reason", "编队不合法"))
		_hint.add_theme_color_override("font_color", UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23)))
		return false
	if _dirty:
		SaveState.flush()
		_dirty = false
	return true

# ---------------------------------------------------------------- 渲染

func _refresh() -> void:
	_cap_label.text = "席位 %d / %d" % [HeroSave.slot_cap(), SaveState.MAX_SLOT_CAP]
	for c in _slot_box.get_children():
		c.queue_free()
	var cap := HeroSave.slot_cap()
	for i in cap:
		_slot_box.add_child(_slot_tile(i))
	for c in _pool.get_children():
		c.queue_free()
	for id in HeroSave.owned_ids():
		_pool.add_child(_pool_tile(str(id)))

func _slot_tile(i: int) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiTheme.panel_style())
	box.custom_minimum_size = Vector2(150, 148)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	box.add_child(vb)
	if i < _slots.size():
		var id := str(_slots[i])
		var card := HeroCard.card(id, Vector2(140, 140))
		vb.add_child(card)
		if i > 0:
			var off := UiTheme.button("撤下", 15, Vector2(100, 26))
			off.pressed.connect(_on_remove.bind(id))
			vb.add_child(off)
	else:
		vb.add_child(UiTheme.label("空位", 18, Color(0.55, 0.50, 0.44), 3))
		vb.add_child(UiTheme.label("从下方点选", 13, Color(0.55, 0.50, 0.44), 2))
	return box

func _pool_tile(hero_id: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 168)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UiTheme.panel_style())
	b.add_theme_stylebox_override("hover", UiTheme.panel_style())
	b.add_theme_stylebox_override("pressed", UiTheme.panel_style())
	var on := _slots.has(hero_id)
	b.modulate = Color(1.12, 1.06, 0.90) if on else Color(1, 1, 1, 0.86)
	b.pressed.connect(_on_toggle.bind(hero_id))
	var card := HeroCard.card(hero_id, Vector2(150, 168))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(card)
	return b

# ---------------------------------------------------------------- 操作

func _on_toggle(hero_id: String) -> void:
	if _slots.has(hero_id):
		_on_remove(hero_id)
		return
	if str(_slots[0]) == "liubei" and hero_id == "liubei":
		return
	if _slots.size() >= HeroSave.slot_cap():
		_hint.text = "席位已满:先撤下一名,或去酒馆买扩编令牌。"
		return
	_slots.append(hero_id)
	_dirty = true
	_refresh()

func _on_remove(hero_id: String) -> void:
	var idx := _slots.find(hero_id)
	if idx <= 0:
		return                         # 主公不可撤(index 0)
	_slots.remove_at(idx)
	_dirty = true
	_refresh()

func _on_auto() -> void:
	HeroSave.auto_fill()
	_slots = HeroSave.slots()
	_dirty = true
	_refresh()
