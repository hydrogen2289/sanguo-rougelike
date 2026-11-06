extends PanelContainer
## TopBar —— 主城顶部常驻栏(M7,02 §6.2/§13.2-M7)。
## 军资 + 定向碎片余额(提案:货币仅此两种,01 §13-2)、主公头像、存档提示、返回主菜单。
## 余额订阅 SaveState.wallet_changed 即时刷新;落盘后闪现「已存档」。

var _junzi_label: Label
var _frag_label: Label
var _hint: Label
var _tw: Tween

func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel_style())
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	add_child(hb)
	# --- 货币区(军资 / 定向碎片) ---
	hb.add_child(_icon(ProcIcon.junzi(40), "军资(跨局货币,局内军资不入库)"))
	_junzi_label = UiTheme.label("0", 26, UiTheme.col("dark_brown", Color(0.35, 0.27, 0.2)))
	_junzi_label.name = "JunziLabel"
	_junzi_label.tooltip_text = "军资余额"
	hb.add_child(_junzi_label)
	hb.add_child(_icon(ProcIcon.fragment(40), "定向武将碎片"))
	_frag_label = UiTheme.label("0", 26, UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23)))
	_frag_label.name = "FragLabel"
	_frag_label.tooltip_text = "碎片总余额(按武将定向记账)"
	hb.add_child(_frag_label)
	# --- 弹性空档 ---
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	# --- 主公头像(现有程序化立牌裁显示) ---
	var avatar := _icon(load("res://assets/textures/units/liubei.png") if ResourceLoader.exists("res://assets/textures/units/liubei.png") else ProcIcon.junzi(40), "主公 · 刘备")
	avatar.custom_minimum_size = Vector2(44, 44)
	hb.add_child(avatar)
	var lord := UiTheme.label("主公 · 刘备", 20, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)))
	hb.add_child(lord)
	# --- 存档提示(落盘后短暂显示) ---
	_hint = UiTheme.label("已存档", 18, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)))
	_hint.visible = false
	hb.add_child(_hint)
	# --- 返回主菜单(主城可出,02 §7) ---
	var back := UiTheme.button("返回主菜单", 20, Vector2(176, 44))
	back.pressed.connect(func() -> void: SceneRouter.goto_menu())   # goto_menu 内含 flush 落盘
	hb.add_child(back)
	SaveState.wallet_changed.connect(_refresh)
	SaveState.save_flushed.connect(_flash_saved)
	_refresh()

func _icon(tex: Texture2D, tip: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(36, 36)
	tr.tooltip_text = tip
	return tr

func _refresh() -> void:
	# 会话未初始化(直接实例化主城的测试/异常路径)按 0 显示,不触碰存档
	var has := not SaveState.data.is_empty()
	_junzi_label.text = str(SaveState.junzi()) if has else "0"
	_frag_label.text = str(SaveState.fragments_total()) if has else "0"

func _flash_saved() -> void:
	_hint.visible = true
	_hint.modulate.a = 1.0
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_interval(1.2)
	_tw.tween_property(_hint, "modulate:a", 0.0, 0.8)
	_tw.tween_callback(func() -> void: _hint.visible = false)
