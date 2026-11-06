class_name ProcIcon
extends RefCounted
## 程序化图标(M7):运行时像素绘制 → ImageTexture,零外部素材、零落盘
## (程序化素材原则;02 §10 的正式贴图增量落 gen_textures 管线后可无缝替换)。
## 色彩只引用 palette token(UiTheme.col)。

## 军资:方孔钱(金圆 + 方孔)
static func junzi(sz := 64) -> ImageTexture:
	var img := _img(sz)
	var gold := UiTheme.col("gold", Color(0.79, 0.66, 0.42))
	var brown := UiTheme.col("dark_brown", Color(0.35, 0.27, 0.2))
	var paper := UiTheme.col("paper", Color(0.95, 0.92, 0.83))
	var c := sz * 0.5
	var r := sz * 0.42
	_fill_circle(img, c, c, r, brown)
	_fill_circle(img, c, c, r - sz * 0.05, gold)
	_fill_circle(img, c - r * 0.25, c - r * 0.3, r * 0.35, gold.lightened(0.25))
	_fill_rect(img, c - sz * 0.11, c - sz * 0.11, sz * 0.22, sz * 0.22, brown)
	_fill_rect(img, c - sz * 0.08, c - sz * 0.08, sz * 0.16, sz * 0.16, paper)
	return _tex(img)

## 定向碎片:金绯石片(三片多面体)
static func fragment(sz := 64) -> ImageTexture:
	var img := _img(sz)
	var gold := UiTheme.col("gold", Color(0.79, 0.66, 0.42))
	var cinnabar := UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23))
	var brown := UiTheme.col("dark_brown", Color(0.35, 0.27, 0.2))
	_fill_tri(img, Vector2(sz * 0.5, sz * 0.08), Vector2(sz * 0.78, sz * 0.55), Vector2(sz * 0.5, sz * 0.68), gold)
	_fill_tri(img, Vector2(sz * 0.5, sz * 0.08), Vector2(sz * 0.5, sz * 0.68), Vector2(sz * 0.24, sz * 0.5), gold.lightened(0.2))
	_fill_tri(img, Vector2(sz * 0.24, sz * 0.5), Vector2(sz * 0.5, sz * 0.68), Vector2(sz * 0.4, sz * 0.92), cinnabar)
	_fill_tri(img, Vector2(sz * 0.5, sz * 0.68), Vector2(sz * 0.78, sz * 0.55), Vector2(sz * 0.62, sz * 0.9), cinnabar.lightened(0.15))
	_fill_tri(img, Vector2(sz * 0.4, sz * 0.92), Vector2(sz * 0.62, sz * 0.9), Vector2(sz * 0.5, sz * 0.68), brown)
	return _tex(img)

## 主城入口图标(02 §10 icons/build/*:campaign/tower/tavern/barracks/drill,96 级)
static func building(kind: String, sz := 96) -> ImageTexture:
	match kind:
		"tower":
			return _tower_icon(sz)
		"tavern":
			return _tavern_icon(sz)
		"barracks":
			return _barracks_icon(sz)
		"drill":
			return _drill_icon(sz)
		_:
			return _campaign_icon(sz)   # 默认战役旗帜

# ---------------------------------------------------------------- 各入口

static func _campaign_icon(sz: int) -> ImageTexture:
	var img := _img(sz)
	var brown := UiTheme.col("dark_brown", Color(0.35, 0.27, 0.2))
	var cinnabar := UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23))
	var gold := UiTheme.col("gold", Color(0.79, 0.66, 0.42))
	_fill_rect(img, sz * 0.3, sz * 0.08, sz * 0.08, sz * 0.84, brown)            # 旗杆
	_fill_circle(img, sz * 0.34, sz * 0.1, sz * 0.06, gold)                      # 杆顶
	_fill_tri(img, Vector2(sz * 0.38, sz * 0.16), Vector2(sz * 0.86, sz * 0.28), Vector2(sz * 0.38, sz * 0.46), cinnabar)
	return _tex(img)

static func _tower_icon(sz: int) -> ImageTexture:
	var img := _img(sz)
	var deep := UiTheme.col("deep_green", Color(0.31, 0.44, 0.32))
	var brown := UiTheme.col("dark_brown", Color(0.35, 0.27, 0.2))
	var gold := UiTheme.col("gold", Color(0.79, 0.66, 0.42))
	var w: Array[float] = [0.16, 0.28, 0.4]          # 三层塔身渐宽
	for i in 3:
		var y := sz * (0.62 - 0.2 * float(i))
		var bw: float = sz * w[i]
		_fill_rect(img, sz * 0.5 - bw * 0.5, y, bw, sz * 0.16, deep if i % 2 == 0 else brown)
		_fill_rect(img, sz * 0.5 - bw * 0.62, y - sz * 0.035, bw * 1.24, sz * 0.04, brown)   # 檐
	_fill_rect(img, sz * 0.5 - sz * 0.05, sz * 0.09, sz * 0.1, sz * 0.1, gold)               # 塔刹
	return _tex(img)

static func _tavern_icon(sz: int) -> ImageTexture:
	var img := _img(sz)
	var brown := UiTheme.col("dark_brown", Color(0.35, 0.27, 0.2))
	var green := UiTheme.col("spring_green", Color(0.56, 0.68, 0.55))
	var paper := UiTheme.col("paper", Color(0.95, 0.92, 0.83))
	_fill_circle(img, sz * 0.5, sz * 0.66, sz * 0.24, green)          # 壶腹
	_fill_rect(img, sz * 0.44, sz * 0.3, sz * 0.12, sz * 0.18, green) # 壶颈
	_fill_rect(img, sz * 0.4, sz * 0.24, sz * 0.2, sz * 0.07, brown)  # 壶盖
	_fill_rect(img, sz * 0.72, sz * 0.4, sz * 0.1, sz * 0.22, brown)  # 壶把
	_fill_rect(img, sz * 0.42, sz * 0.62, sz * 0.16, sz * 0.2, paper) # 酒字牌底
	return _tex(img)

static func _barracks_icon(sz: int) -> ImageTexture:
	var img := _img(sz)
	var cinnabar := UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23))
	var gold := UiTheme.col("gold", Color(0.79, 0.66, 0.42))
	var brown := UiTheme.col("dark_brown", Color(0.35, 0.27, 0.2))
	_fill_rect(img, sz * 0.42, sz * 0.12, sz * 0.16, sz * 0.12, brown)   # 印钮
	_fill_rect(img, sz * 0.22, sz * 0.28, sz * 0.56, sz * 0.52, brown)   # 印框
	_fill_rect(img, sz * 0.27, sz * 0.33, sz * 0.46, sz * 0.42, cinnabar)
	_fill_rect(img, sz * 0.36, sz * 0.44, sz * 0.28, sz * 0.06, gold)    # 印文横笔
	_fill_rect(img, sz * 0.47, sz * 0.4, sz * 0.06, sz * 0.28, gold)     # 印文竖笔
	return _tex(img)

static func _drill_icon(sz: int) -> ImageTexture:
	var img := _img(sz)
	var gold := UiTheme.col("gold", Color(0.79, 0.66, 0.42)).lightened(0.3)
	var brown := UiTheme.col("dark_brown", Color(0.35, 0.27, 0.2))
	_thick_line(img, sz * 0.2, sz * 0.2, sz * 0.78, sz * 0.76, sz * 0.07, gold)   # 交叉双剑
	_thick_line(img, sz * 0.8, sz * 0.2, sz * 0.22, sz * 0.76, sz * 0.07, gold)
	_fill_rect(img, sz * 0.14, sz * 0.72, sz * 0.2, sz * 0.07, brown)             # 剑格
	_fill_rect(img, sz * 0.66, sz * 0.72, sz * 0.2, sz * 0.07, brown)
	_fill_rect(img, sz * 0.46, sz * 0.8, sz * 0.08, sz * 0.14, brown)             # 中轴握柄
	return _tex(img)

# ---------------------------------------------------------------- 像素基元(局部自足,不依赖 gen_textures)

static func _img(sz: int) -> Image:
	return Image.create(sz, sz, false, Image.FORMAT_RGBA8)

static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)

static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if c.a >= 1.0:
		img.set_pixel(x, y, c)
		return
	var d := img.get_pixel(x, y)
	var a := c.a + d.a * (1.0 - c.a)
	if a <= 0.0:
		return
	img.set_pixel(x, y, Color(
		(c.r * c.a + d.r * d.a * (1.0 - c.a)) / a,
		(c.g * c.a + d.g * d.a * (1.0 - c.a)) / a,
		(c.b * c.a + d.b * d.a * (1.0 - c.a)) / a, a))

static func _fill_rect(img: Image, x0: float, y0: float, w: float, h: float, c: Color) -> void:
	for y in range(int(floor(y0)), int(ceil(y0 + h))):
		for x in range(int(floor(x0)), int(ceil(x0 + w))):
			_px(img, x, y, c)

static func _fill_circle(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	for y in range(int(floor(cy - r)) - 1, int(ceil(cy + r)) + 2):
		for x in range(int(floor(cx - r)) - 1, int(ceil(cx + r)) + 2):
			var d := Vector2(float(x) + 0.5 - cx, float(y) + 0.5 - cy).length()
			if d <= r:
				_px(img, x, y, c)

static func _thick_line(img: Image, ax: float, ay: float, bx: float, by: float, w: float, c: Color) -> void:
	var steps := int(ceil(sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)))) + 1
	for i in steps:
		var t := float(i) / maxf(1.0, float(steps - 1))
		_fill_circle(img, lerpf(ax, bx, t), lerpf(ay, by, t), w * 0.5, c)

## 三角形填充(扫描包围盒 + 重心坐标)
static func _fill_tri(img: Image, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)))
	var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)))
	var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(den) < 0.0001:
		return
	for y in range(int(floor(lo.y)), int(ceil(hi.y)) + 1):
		for x in range(int(floor(lo.x)), int(ceil(hi.x)) + 1):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var l1 := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / den
			var l2 := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / den
			var l3 := 1.0 - l1 - l2
			if l1 >= 0.0 and l2 >= 0.0 and l3 >= 0.0:
				_px(img, x, y, col)
