extends Control
## CityBg —— 主城卷轴全景底图(M7,01 §11 主城表现占位:程序化卷轴全景,无 3D 场景)。
## 全部 draw_* 程序化绘制(色彩只引用 palette token),零外部素材;
## 02 §10 的 city_panorama.png 正式贴图落 gen_textures 管线后,本节点可换回 TextureRect 直挂。

func _ready() -> void:
	item_rect_changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var sz := size
	if sz.x <= 1.0 or sz.y <= 1.0:
		return
	var paper := UiTheme.col("paper", Color(0.95, 0.92, 0.83))
	var paper_dark := UiTheme.col("paper_dark", Color(0.91, 0.87, 0.77))
	var spring := UiTheme.col("spring_green", Color(0.56, 0.68, 0.55))
	var deep := UiTheme.col("deep_green", Color(0.31, 0.44, 0.32))
	var brown := UiTheme.col("dark_brown", Color(0.35, 0.27, 0.2))
	var cinnabar := UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23))
	var gold := UiTheme.col("gold", Color(0.79, 0.66, 0.42))
	var horizon := sz.y * 0.62
	# 天空 + 日 + 云
	draw_rect(Rect2(Vector2.ZERO, sz), paper)
	var sun := Vector2(sz.x * 0.82, sz.y * 0.14)
	draw_circle(sun, sz.y * 0.065, gold)
	draw_arc(sun, sz.y * 0.065, 0.0, TAU, 48, brown, 2.0)
	_cloud(Vector2(sz.x * 0.18, sz.y * 0.16), sz.x * 0.06, paper_dark)
	_cloud(Vector2(sz.x * 0.48, sz.y * 0.1), sz.x * 0.045, paper_dark)
	_cloud(Vector2(sz.x * 0.64, sz.y * 0.22), sz.x * 0.035, paper_dark)
	# 远山两层(春青,前深后淡)
	_mountains(horizon, sz.y * 0.2, 5, Color(spring.r, spring.g, spring.b, 0.55), sz.x * 0.03)
	_mountains(horizon, sz.y * 0.3, 4, Color(deep.r, deep.g, deep.b, 0.75), sz.x * 0.09)
	# 城墙横带 + 垛口
	var wall_y := horizon - sz.y * 0.06
	draw_rect(Rect2(0.0, wall_y, sz.x, sz.y * 0.06), brown)
	var merlon := sz.x * 0.012
	var mx := 0.0
	while mx < sz.x:
		draw_rect(Rect2(mx, wall_y - sz.y * 0.018, merlon, sz.y * 0.018), brown)
		mx += merlon * 2.0
	draw_rect(Rect2(0.0, wall_y, sz.x, sz.y * 0.008), cinnabar.darkened(0.2))
	# 城楼(中)与塔(两侧)
	_tower(Vector2(sz.x * 0.5, wall_y), sz.x * 0.13, sz.y * 0.16, cinnabar, gold)
	_tower(Vector2(sz.x * 0.22, wall_y), sz.x * 0.09, sz.y * 0.11, deep, gold)
	_tower(Vector2(sz.x * 0.78, wall_y), sz.x * 0.09, sz.y * 0.11, deep, gold)
	# 地面:暗纹地 + 春青窄带 + 树
	draw_rect(Rect2(0.0, horizon, sz.x, sz.y - horizon), paper_dark)
	draw_rect(Rect2(0.0, horizon, sz.x, sz.y * 0.015), spring)
	for i in 9:
		var tx := sz.x * (0.06 + 0.11 * float(i))
		var ty := horizon + sz.y * (0.05 + 0.06 * float(i % 3))
		draw_circle(Vector2(tx, ty - sz.y * 0.02), sz.y * 0.022, Color(deep.r, deep.g, deep.b, 0.85))
		draw_rect(Rect2(tx - sz.y * 0.004, ty - sz.y * 0.006, sz.y * 0.008, sz.y * 0.024), brown)

func _cloud(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r, col)
	draw_circle(c + Vector2(r * 0.9, r * 0.25), r * 0.75, col)
	draw_circle(c + Vector2(-r * 0.85, r * 0.3), r * 0.6, col)

## 折线山: peaks 座山峰,底边落在 horizon
func _mountains(horizon: float, peak_h: float, peaks: int, col: Color, jitter: float) -> void:
	var pts := PackedVector2Array()
	var n := peaks * 2 + 1
	for i in n:
		var t := float(i) / float(n - 1)
		var x := t * size.x * 1.04 - size.x * 0.02
		var y := horizon
		if i % 2 == 1:
			y = horizon - peak_h * (0.6 + 0.4 * absf(sin(float(i) * 2.7)))
			x += jitter * (0.5 - 0.5 * absf(sin(float(i) * 1.9)))
		pts.append(Vector2(x, y))
	pts.append(Vector2(size.x * 1.02, horizon + size.y * 0.02))
	pts.append(Vector2(-size.x * 0.02, horizon + size.y * 0.02))
	draw_polygon(pts, PackedColorArray([col]))   # 单色平涂(颜色数组须为 1 或点数长度)

## 城楼:台基 + 塔身 + 挑檐(弧)+ 宝顶 + 旗
func _tower(base: Vector2, w: float, h: float, body: Color, gold: Color) -> void:
	var brown := UiTheme.col("dark_brown", Color(0.35, 0.27, 0.2))
	var cinnabar := UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23))
	# 台基
	draw_rect(Rect2(base.x - w * 0.6, base.y - h * 0.18, w * 1.2, h * 0.18), brown)
	# 塔身
	draw_rect(Rect2(base.x - w * 0.5, base.y - h, w, h * 0.82), body)
	# 门洞
	draw_rect(Rect2(base.x - w * 0.09, base.y - h * 0.22, w * 0.18, h * 0.22), brown.darkened(0.25))
	# 挑檐:两段上扬弧
	var roof_y := base.y - h
	var seg := w * 0.78
	draw_arc(Vector2(base.x - seg * 0.5, roof_y), seg * 0.52, PI * 1.78, PI * 1.97, 16, brown, h * 0.09)
	draw_arc(Vector2(base.x + seg * 0.5, roof_y), seg * 0.52, PI * 1.03, PI * 1.22, 16, brown, h * 0.09)
	draw_rect(Rect2(base.x - seg * 0.52, roof_y - h * 0.05, seg * 1.04, h * 0.06), brown)
	# 宝顶 + 旗
	draw_circle(Vector2(base.x, roof_y - h * 0.14), h * 0.045, gold)
	var pole_top := roof_y - h * 0.3
	draw_line(Vector2(base.x, roof_y - h * 0.1), Vector2(base.x, pole_top), brown, 2.0)
	draw_polygon(
		PackedVector2Array([Vector2(base.x, pole_top), Vector2(base.x + w * 0.22, pole_top + h * 0.05), Vector2(base.x, pole_top + h * 0.11)]),
		PackedColorArray([cinnabar, cinnabar, cinnabar]))
