class_name UiTheme
extends RefCounted
## UI 主题工具(M3):米纸/卷轴质感,全部引用 palette token + SystemFont(01 §11,已拍板不下载素材)。

const FONT_STACK := ["Microsoft YaHei", "SimHei", "Noto Sans CJK SC"]

static var _fonts := {}   # 字号 -> SystemFont 缓存

static func col(token: String, fallback: Color) -> Color:
	var c = DataDB.palette.get(token, "")
	if str(c).begins_with("#"):
		return Color(str(c))
	return fallback

static func font(size: int) -> SystemFont:
	if not _fonts.has(size):
		var f := SystemFont.new()
		f.font_names = FONT_STACK
		_fonts[size] = f
	return _fonts[size]

static func label(text: String, font_size: int, color: Color, outline := 4) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(font_size))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", col("paper", Color.WHITE))
	l.add_theme_constant_override("outline_size", outline)
	return l

static func panel_style(alpha := 1.0) -> StyleBoxTexture:
	# 宣纸九宫格面板(panel_paper.png 128×128,02 §5)
	var sb := StyleBoxTexture.new()
	var path := "res://assets/textures/ui/panel_paper.png"
	if ResourceLoader.exists(path):
		sb.texture = load(path)
		sb.texture_margin_left = 24
		sb.texture_margin_right = 24
		sb.texture_margin_top = 24
		sb.texture_margin_bottom = 24
	sb.modulate_color = Color(1.0, 1.0, 1.0, alpha)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	return sb

static func button(text: String, font_size := 20, min_size := Vector2(180, 46)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: Sfx.play("button", -8.0))   # 按钮音(M6)
	b.add_theme_font_override("font", font(font_size))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", col("dark_brown", Color(0.35, 0.27, 0.2)))
	b.add_theme_color_override("font_hover_color", col("paper", Color.WHITE))
	b.add_theme_color_override("font_pressed_color", col("paper", Color.WHITE))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.52, 0.46))
	var path := "res://assets/textures/ui/btn_seal.png"
	if ResourceLoader.exists(path):
		var sb := StyleBoxTexture.new()
		sb.texture = load(path)
		sb.texture_margin_left = 16
		sb.texture_margin_right = 16
		sb.texture_margin_top = 16
		sb.texture_margin_bottom = 16
		b.add_theme_stylebox_override("normal", sb)
		var sb_h := sb.duplicate()
		sb_h.modulate_color = Color(1.12, 1.05, 0.95)
		b.add_theme_stylebox_override("hover", sb_h)
		var sb_p := sb.duplicate()
		sb_p.modulate_color = Color(0.85, 0.8, 0.72)
		b.add_theme_stylebox_override("pressed", sb_p)
		b.add_theme_stylebox_override("disabled", sb.duplicate())
	else:
		var sbf := StyleBoxFlat.new()
		sbf.bg_color = col("spring_green", Color(0.56, 0.68, 0.55))
		b.add_theme_stylebox_override("normal", sbf)
	return b

## 全屏暗化底(模态弹窗用)
static func dim_bg() -> ColorRect:
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.1, 0.08, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	return dim

## 卷轴面板(带 scroll_bg 底)
static func scroll_panel(size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = size
	p.add_theme_stylebox_override("panel", panel_style())
	var path := "res://assets/textures/ui/scroll_bg.png"
	if ResourceLoader.exists(path):
		var sb := StyleBoxTexture.new()
		sb.texture = load(path)
		sb.texture_margin_left = 48
		sb.texture_margin_right = 48
		sb.texture_margin_top = 32
		sb.texture_margin_bottom = 32
		sb.content_margin_left = 56
		sb.content_margin_right = 56
		sb.content_margin_top = 36
		sb.content_margin_bottom = 36
		p.add_theme_stylebox_override("panel", sb)
	return p

## CD 扫罩用程序化圆盘(64×64 白色实心圆,运行时生成,不落盘)
static func disc_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var c := Vector2(32.0, 32.0)
	for y in 64:
		for x in 64:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= 31.0:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)
