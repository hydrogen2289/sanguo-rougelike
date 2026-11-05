extends SceneTree
## gen_textures.gd —— 程序化贴图生成(M0)。
## 全部视觉素材由本脚本绘制生成 PNG,固定 seed 可复现(02 §5);
## 色彩只引用 data/palette.json 的 token(派生色由 token 混合而来,不写死新色值)。
## 运行:godot.cmd --headless --path <工程> --script res://tools/gen_textures.gd

const TEX_ROOT := "res://assets/textures/"
const GLOBAL_SEED := 20261103

var PAL := {}
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	if not _load_palette():
		quit(1)
		return
	var made: Array = []
	_gen_ground(made)
	_gen_units(made)
	_gen_fx(made)
	_gen_icons(made)
	_gen_ui(made)
	_gen_icon_png(made)
	_write_manifest(made)
	print("[gen_textures] 完成:共 %d 张 + manifest.json(seed=%d)" % [made.size(), GLOBAL_SEED])
	quit(0)

# ---------------------------------------------------------------- 基础设施

func _load_palette() -> bool:
	var path := "res://data/palette.json"
	if not FileAccess.file_exists(path):
		printerr("[gen_textures] 缺少 data/palette.json")
		return false
	PAL = JSON.parse_string(FileAccess.get_file_as_string(path))
	if PAL == null or (PAL as Dictionary).is_empty():
		printerr("[gen_textures] palette.json 解析失败")
		return false
	return true

func C(token: String) -> Color:
	return Color(str(PAL.get(token, "#FF00FF")))

func lighten(c: Color, t: float) -> Color:
	return c.lerp(Color.WHITE, t)

func darken(c: Color, t: float) -> Color:
	return c.lerp(Color.BLACK, t)

func mixc(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, t)

func seed_for(rel: String) -> int:
	return GLOBAL_SEED + hash(rel) % 100000

func new_img(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

## alpha 混合写像素
func bpx(img: Image, x: int, y: int, c: Color) -> void:
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
		(c.b * c.a + d.b * d.a * (1.0 - c.a)) / a,
		a))

func fill_rect(img: Image, x0: float, y0: float, w: float, h: float, c: Color) -> void:
	for y in range(int(floor(y0)), int(ceil(y0 + h))):
		for x in range(int(floor(x0)), int(ceil(x0 + w))):
			bpx(img, x, y, c)

func fill_ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(int(floor(cy - ry)) - 1, int(ceil(cy + ry)) + 2):
		for x in range(int(floor(cx - rx)) - 1, int(ceil(cx + rx)) + 2):
			var dx := (float(x) + 0.5 - cx) / (rx + 0.001)
			var dy := (float(y) + 0.5 - cy) / (ry + 0.001)
			if dx * dx + dy * dy <= 1.0:
				bpx(img, x, y, c)

func fill_circle(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	fill_ellipse(img, cx, cy, r, r, c)

## 圆形:深褐描边(先画大圈再填内圈,01 §11「2px 深褐描边」)
func disc(img: Image, cx: float, cy: float, r: float, fill: Color, outline: Color, ow := 2.0) -> void:
	fill_circle(img, cx, cy, r + ow, outline)
	fill_circle(img, cx, cy, r, fill)

func oval(img: Image, cx: float, cy: float, rx: float, ry: float, fill: Color, outline: Color, ow := 2.0) -> void:
	fill_ellipse(img, cx, cy, rx + ow, ry + ow, outline)
	fill_ellipse(img, cx, cy, rx, ry, fill)

func thick_line(img: Image, ax: float, ay: float, bx: float, by: float, w: float, c: Color) -> void:
	var steps := int(ceil(sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)))) + 1
	for i in steps:
		var t := float(i) / maxf(1.0, float(steps - 1))
		fill_circle(img, lerpf(ax, bx, t), lerpf(ay, by, t), w * 0.5, c)

func arc(img: Image, cx: float, cy: float, r: float, a0: float, a1: float, w: float, c: Color) -> void:
	var n := int(absf(a1 - a0) * r) + 3
	for i in n:
		var a := lerpf(a0, a1, float(i) / maxf(1, n - 1))
		fill_circle(img, cx + cos(a) * r, cy + sin(a) * r, w * 0.5, c)

func save(img: Image, rel: String, list: Array) -> void:
	var path := TEX_ROOT + rel
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err := img.save_png(abs_path)
	if err != OK:
		printerr("[gen_textures] 保存失败 %s (err=%d)" % [rel, err])
		quit(1)
		return
	list.append({"path": rel, "w": img.get_width(), "h": img.get_height(), "seed": seed_for(rel)})
	print("  [gen] " + rel)

# ---------------------------------------------------------------- 地面

func _gen_ground(list: Array) -> void:
	rng.seed = seed_for("ground/ground_paper.png")
	var img := new_img(512, 512)
	var paper := C("paper")
	var paper_dark := C("paper_dark")
	var green := C("spring_green")
	var brown := C("dark_brown")
	img.fill(paper)
	# 米纸暗纹大块
	for i in 14:
		var c := Color(paper_dark.r, paper_dark.g, paper_dark.b, rng.randf_range(0.10, 0.22))
		fill_ellipse(img, rng.randf_range(0, 511), rng.randf_range(0, 511), rng.randf_range(30, 90), rng.randf_range(20, 60), c)
	# 淡青草渍圆斑 ×30
	for i in 30:
		var c := Color(green.r, green.g, green.b, rng.randf_range(0.05, 0.16))
		fill_ellipse(img, rng.randf_range(0, 511), rng.randf_range(0, 511), rng.randf_range(6, 26), rng.randf_range(4, 18), c)
	# 淡墨路痕曲线 ×2(二次贝塞尔采样)
	for i in 2:
		var p0 := Vector2(rng.randf_range(0, 512), rng.randf_range(0, 512))
		var p1 := Vector2(rng.randf_range(0, 512), rng.randf_range(0, 512))
		var p2 := Vector2(rng.randf_range(0, 512), rng.randf_range(0, 512))
		var ink := Color(brown.r, brown.g, brown.b, 0.10)
		for k in 130:
			var t := float(k) / 129.0
			var q := p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
			fill_circle(img, q.x, q.y, rng.randf_range(2.5, 4.5), ink)
	# 纸纤维噪点
	var dot := Color(brown.r, brown.g, brown.b, 0.04)
	for i in 900:
		bpx(img, rng.randi_range(0, 511), rng.randi_range(0, 511), dot)
	save(img, "ground/ground_paper.png", list)

# ---------------------------------------------------------------- 角色
# 卡通立牌模板:4× 超采样消锯齿 + 100 空间坐标 + 分件绘制
# (落地影/腿靴/袍身/手臂/大头/发/头饰/五官/须髯/兵器)。
# 角色差异只写在 _unit_specs() 的字典里:袍色、肤色、眼形、眉形、口型、须发、头饰、兵器。

const SS := 4                                  # 超采样倍数
const OW := 1.75                               # 描边宽度(100 空间单位)



func e_ell(img: Image, k: float, x: float, y: float, rx: float, ry: float, col: Color, out := true) -> void:
	if out:
		oval(img, x * k, y * k, rx * k, ry * k, col, C("dark_brown"), OW * k)
	else:
		fill_ellipse(img, x * k, y * k, rx * k, ry * k, col)

func e_cir(img: Image, k: float, x: float, y: float, r: float, col: Color, out := true) -> void:
	e_ell(img, k, x, y, r, r, col, out)

## 等宽胶囊(四肢/杆):先描边再本色
func e_limb(img: Image, k: float, ax: float, ay: float, bx: float, by: float, w: float, col: Color) -> void:
	thick_line(img, ax * k, ay * k, bx * k, by * k, (w + OW * 2.0) * k, C("dark_brown"))
	thick_line(img, ax * k, ay * k, bx * k, by * k, w * k, col)

func e_line(img: Image, k: float, ax: float, ay: float, bx: float, by: float, w: float, col: Color) -> void:
	thick_line(img, ax * k, ay * k, bx * k, by * k, w * k, col)

func e_arc(img: Image, k: float, x: float, y: float, r: float, a0: float, a1: float, w: float, col: Color) -> void:
	arc(img, x * k, y * k, r * k, a0, a1, w * k, col)

func e_rect(img: Image, k: float, x: float, y: float, w: float, h: float, col: Color) -> void:
	fill_rect(img, x * k, y * k, w * k, h * k, col)

## 锥形弧(飘带/缨穗)
func e_arc_taper(img: Image, k: float, x: float, y: float, r: float, a0: float, a1: float, w0: float, w1: float, col: Color) -> void:
	_arc_taper(img, k, x, y, r, a0, a1, w0 + OW * 2.0, w1 + OW * 1.4, C("dark_brown"))
	_arc_taper(img, k, x, y, r, a0, a1, w0, w1, col)

func _arc_taper(img: Image, k: float, x: float, y: float, r: float, a0: float, a1: float, w0: float, w1: float, col: Color) -> void:
	var n := int(absf(a1 - a0) * r * k) + 3
	for i in n:
		var t := float(i) / float(n - 1)
		var a := lerpf(a0, a1, t)
		fill_circle(img, (x + cos(a) * r) * k, (y + sin(a) * r) * k, maxf(0.3, lerpf(w0, w1, t) * 0.5) * k, col)

## 锥形二次贝塞尔(雉鸡翎/衣带)
func e_bezier(img: Image, k: float, ax: float, ay: float, cx: float, cy: float, bx: float, by: float, w0: float, w1: float, col: Color) -> void:
	_bezier(img, k, ax, ay, cx, cy, bx, by, w0 + OW * 2.0, w1 + OW * 1.4, C("dark_brown"))
	_bezier(img, k, ax, ay, cx, cy, bx, by, w0, w1, col)

func _bezier(img: Image, k: float, ax: float, ay: float, cx: float, cy: float, bx: float, by: float, w0: float, w1: float, col: Color) -> void:
	var n := int(sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)) * k * 1.4) + 4
	for i in n:
		var t := float(i) / float(n - 1)
		var q := Vector2(ax, ay).lerp(Vector2(cx, cy), t).lerp(Vector2(cx, cy).lerp(Vector2(bx, by), t), t)
		fill_circle(img, q.x * k, q.y * k, maxf(0.3, lerpf(w0, w1, t) * 0.5) * k, col)

## 多边形件(刃/甲/扇):沿轮廓描边后扫描线填充
func e_poly(img: Image, p: Dictionary, pts: Array, col: Color) -> void:
	var k := float(p["k"])
	var ink: Color = p["ink"]
	var ring: Array = []
	for pt in pts:
		ring.append(Vector2(pt.x * k, pt.y * k))
	for i in ring.size():
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		thick_line(img, a.x, a.y, b.x, b.y, OW * 2.0 * k + 1.0, ink)
	_fill_poly(img, ring, col)

func _fill_poly(img: Image, pts: Array, col: Color) -> void:
	var y0 := int(floor(minf(_poly_min_y(pts), 0.0)))
	var y1 := int(ceil(_poly_max_y(pts)))
	for y in range(y0, y1 + 1):
		var xs: Array = []
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			if (a.y <= float(y) and b.y > float(y)) or (b.y <= float(y) and a.y > float(y)):
				xs.append(a.x + float(y - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var j := 0
		while j + 1 < xs.size():
			for x in range(int(ceil(xs[j])), int(floor(xs[j + 1])) + 1):
				bpx(img, x, y, col)
			j += 2

func _poly_min_y(pts: Array) -> float:
	var m := INF
	for pt in pts:
		m = minf(m, pt.y)
	return m

func _poly_max_y(pts: Array) -> float:
	var m := -INF
	for pt in pts:
		m = maxf(m, pt.y)
	return m

# ---- 100 空间几何件

func _nrm(ax: float, ay: float, bx: float, by: float) -> Vector2:
	var d := Vector2(bx - ax, by - ay).normalized()
	return Vector2(-d.y, d.x)

## 月牙刃:外弧 + 内弧围合
func g_crescent(cx: float, cy: float, r_out: float, r_in: float, a0: float, a1: float) -> Array:
	var pts: Array = []
	for i in 13:
		var a := lerpf(a0, a1, float(i) / 12.0)
		pts.append(Vector2(cx + cos(a) * r_out, cy + sin(a) * r_out))
	for i in 13:
		var a := lerpf(a1, a0, float(i) / 12.0)
		pts.append(Vector2(cx + cos(a) * r_in, cy + sin(a) * r_in))
	return pts

## 弯月渐收刃:根部厚、末端收尖(偃月刀/蛇矛)
func g_crescent_taper(cx: float, cy: float, r_out: float, r_in0: float, r_in1: float, a0: float, a1: float) -> Array:
	var pts: Array = []
	for i in 13:
		var a := lerpf(a0, a1, float(i) / 12.0)
		pts.append(Vector2(cx + cos(a) * r_out, cy + sin(a) * r_out))
	for i in 13:
		var t := float(i) / 12.0
		var a := lerpf(a1, a0, t)
		var r_in := lerpf(r_in1, r_in0, t)
		pts.append(Vector2(cx + cos(a) * r_in, cy + sin(a) * r_in))
	return pts

## 弯月透镜刃:两端收尖、中段宽 w(戟耳/斧刃)
func g_crescent_lens(cx: float, cy: float, r_out: float, w: float, a0: float, a1: float) -> Array:
	var pts: Array = []
	for i in 13:
		var a := lerpf(a0, a1, float(i) / 12.0)
		pts.append(Vector2(cx + cos(a) * r_out, cy + sin(a) * r_out))
	for i in 13:
		var t := float(i) / 12.0
		var a := lerpf(a1, a0, t)
		var r_in := r_out - w * sin(PI * t)
		pts.append(Vector2(cx + cos(a) * r_in, cy + sin(a) * r_in))
	return pts

## 柳叶刃:两端收尖、中段宽 w
func g_leaf(ax: float, ay: float, bx: float, by: float, w: float) -> Array:
	var nrm := _nrm(ax, ay, bx, by)
	var pts: Array = []
	for i in 10:
		var t := float(i) / 9.0
		var c := Vector2(lerpf(ax, bx, t), lerpf(ay, by, t))
		pts.append(c + nrm * (sin(PI * t) * w * 0.5))
	for i in range(9, -1, -1):
		var t := float(i) / 9.0
		var c := Vector2(lerpf(ax, bx, t), lerpf(ay, by, t))
		pts.append(c - nrm * (sin(PI * t) * w * 0.5))
	return pts

## 刀身:尾宽 w0、尖宽 w1 的四边形
func g_wedge(ax: float, ay: float, bx: float, by: float, w0: float, w1: float) -> Array:
	var nrm := _nrm(ax, ay, bx, by)
	return [
		Vector2(ax, ay) + nrm * (w0 * 0.5), Vector2(bx, by) + nrm * (w1 * 0.5),
		Vector2(bx, by) - nrm * (w1 * 0.5), Vector2(ax, ay) - nrm * (w0 * 0.5)
	]

## 扇形(羽扇/甲片)
func g_pie(cx: float, cy: float, r: float, a0: float, a1: float) -> Array:
	var pts: Array = [Vector2(cx, cy)]
	for i in 15:
		var a := lerpf(a0, a1, float(i) / 14.0)
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	return pts

## 平涂 + 单层阴影 + 高光(01 §11 淡彩三层,纸雕味)
func e_shade_ell(img: Image, k: float, x: float, y: float, rx: float, ry: float, base: Color) -> void:
	oval(img, x * k, y * k, rx * k, ry * k, base, C("dark_brown"), OW * k)
	fill_ellipse(img, x * k, (y + ry * 0.20) * k, rx * 0.90 * k, ry * 0.74 * k, darken(base, 0.20))
	fill_ellipse(img, (x - rx * 0.12) * k, (y - ry * 0.26) * k, rx * 0.66 * k, ry * 0.50 * k, lighten(base, 0.18))

## 横带(腰带/下摆缘/札甲条/胸甲)
func g_band(top: float, bot: float, w_top: float, w_bot: float, dip: float) -> Array:
	return [
		Vector2(50 - w_top * 0.5, top), Vector2(50 + w_top * 0.5, top),
		Vector2(50 + w_bot * 0.5, bot), Vector2(50 + w_bot * 0.22, bot + dip),
		Vector2(50 - w_bot * 0.22, bot + dip), Vector2(50 - w_bot * 0.5, bot)
	]

## 大袖:沿轴向外张开的管状件
func g_sleeve(sx: float, sy: float, ex: float, ey: float, w0: float, w1: float) -> Array:
	var pts: Array = []
	var n := 7
	for i in n:
		var t := float(i) / float(n - 1)
		pts.append(Vector2(lerpf(sx, ex, t) - lerpf(w0, w1, t) * 0.5, lerpf(sy, ey, t)))
	for i in range(n - 1, -1, -1):
		var t := float(i) / float(n - 1)
		pts.append(Vector2(lerpf(sx, ex, t) + lerpf(w0, w1, t) * 0.5, lerpf(sy, ey, t)))
	return pts

## 无描边填充
func f_poly(img: Image, p: Dictionary, pts: Array, col: Color) -> void:
	var k := float(p["k"])
	var ring: Array = []
	for pt in pts:
		ring.append(Vector2(pt.x * k, pt.y * k))
	_fill_poly(img, ring, col)

## 渐变多边形:上浅下深,补足淡彩的层次(百炼英雄式体积感)
func gp_poly(img: Image, p: Dictionary, pts: Array, c_top: Color, c_bot: Color) -> void:
	var k := float(p["k"])
	var ink: Color = p["ink"]
	var ring: Array = []
	for pt in pts:
		ring.append(Vector2(pt.x * k, pt.y * k))
	for i in ring.size():
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		thick_line(img, a.x, a.y, b.x, b.y, OW * 2.0 * k + 1.0, ink)
	_fill_grad(img, ring, c_top * 1.0, c_bot * 1.0)

func _fill_grad(img: Image, pts: Array, c_top: Color, c_bot: Color) -> void:
	var ymin := INF
	var ymax := -INF
	for pt in pts:
		ymin = minf(ymin, pt.y)
		ymax = maxf(ymax, pt.y)
	if ymax <= ymin + 0.5:
		_fill_poly(img, pts, c_bot)
		return
	for y in range(int(floor(ymin)), int(ceil(ymax)) + 1):
		var xs: Array = []
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			if (a.y <= float(y) and b.y > float(y)) or (b.y <= float(y) and a.y > float(y)):
				xs.append(a.x + float(y - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var t := clampf((float(y) - ymin) / (ymax - ymin), 0.0, 1.0)
		var col := c_top.lerp(c_bot, t)
		var j := 0
		while j + 1 < xs.size():
			for x in range(int(ceil(xs[j])), int(floor(xs[j + 1])) + 1):
				bpx(img, x, y, col)
			j += 2

## 渐变椭圆(头/拳/肩吞:顶部受光、底部压暗)
func g_ell_grad(img: Image, k: float, x: float, y: float, rx: float, ry: float, base: Color, out := true) -> void:
	if out:
		oval(img, x * k, y * k, rx * k, ry * k, base, C("dark_brown"), OW * k)
	var top := lighten(base, 0.34)
	var bot := darken(base, 0.16)
	for i in int(ry * k * 2.0) + 1:
		var t := float(i) / float(int(ry * k * 2.0))
		var yy := (y - ry) * k + t * ry * 2.0 * k
		var w := sqrt(maxf(0.0, 1.0 - pow(t * 2.0 - 1.0, 2.0))) * rx * k
		if w < 0.5:
			continue
		var col := top.lerp(bot, t)
		for xx in range(int(x * k - w), int(x * k + w) + 1):
			bpx(img, xx, int(yy), col)

## 尖刺团:外沿锯齿(炸发/虬髯/披风破边)
func g_spiky(cx: float, cy: float, r_in: float, r_out: float, a0: float, a1: float, n: int, jag := 0.35) -> Array:
	var pts: Array = []
	for i in n + 1:
		var t := float(i) / float(n)
		var a := lerpf(a0, a1, t)
		var r := r_out if i % 2 == 1 else lerpf(r_in, r_out, jag)
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	for i in range(n, -1, -1):
		var t := float(i) / float(n)
		var a := lerpf(a0, a1, t)
		pts.append(Vector2(cx + cos(a) * r_in, cy + sin(a) * r_in))
	return pts

## 折线刃(蛇矛/破枪):沿轴向摆动的宽窄带
func g_serrated(ax: float, ay: float, bx: float, by: float, w: float, waves: float, amp: float) -> Array:
	var nrm := _nrm(ax, ay, bx, by)
	var pts: Array = []
	var n := 9
	for i in n:
		var t := float(i) / float(n - 1)
		var c := Vector2(lerpf(ax, bx, t), lerpf(ay, by, t))
		var off := sin(t * PI * waves) * amp
		pts.append(c + nrm * (w * 0.5 + off))
	for i in range(n - 1, -1, -1):
		var t := float(i) / float(n - 1)
		var c := Vector2(lerpf(ax, bx, t), lerpf(ay, by, t))
		var off := sin(t * PI * waves) * amp
		pts.append(c - nrm * (w * 0.5 - off * 0.35))
	return pts

# ---- 规格表:三头身 + 冲镜姿势 + 主色/脸谱/头饰/兵器

func _robe_color(name: String) -> Color:
	match name:
		"green": return C("spring_green")
		"deep_green": return C("deep_green")
		"white": return mixc(C("paper"), Color.WHITE, 0.70)
		"gold": return C("gold")
		"cream": return mixc(C("paper"), C("gold"), 0.40)
		"red": return C("cinnabar")
		"dark_red": return darken(C("cinnabar"), 0.26)
		"iron": return mixc(C("dark_brown"), C("deep_green"), 0.42)
		"black": return mixc(C("dark_brown"), C("deep_green"), 0.68)
		"cloth": return mixc(C("huangjin"), C("dark_brown"), 0.42)
		"sand": return mixc(C("huangjin"), C("paper"), 0.26)
		"jade": return mixc(C("spring_green"), C("paper"), 0.22)
		"paper": return mixc(C("paper"), C("paper_dark"), 0.42)
		"dark_brown": return darken(C("dark_brown"), 0.18)   # 魏延深褐战甲(03 §3.3)
		"blue_robe": return mixc(C("spring_green"), mixc(C("dark_brown"), C("deep_green"), 0.42), 0.5)
			# 张辽蓝袍(05 §4):spring_green lerp iron,palette 派生不新增 hex
		"red_dress": return darken(C("cinnabar"), 0.10)
			# 貂蝉红裙(05 §4):cinnabar 略沉,与吕布正朱砂拉开
		"": return C("paper")
		_: return C("spring_green")

func _skin(name: String) -> Color:
	var base := mixc(C("gold"), Color.WHITE, 0.66)
	match name:
		"pale": return mixc(base, C("paper"), 0.14)
		"tan": return base
		"red": return mixc(base, C("cinnabar"), 0.52)
		"dark": return mixc(base, C("dark_brown"), 0.50)
		"yellow": return mixc(base, C("huangjin"), 0.34)
		"iron": return mixc(base, C("deep_green"), 0.26)
		"old": return mixc(base, C("paper"), 0.16)
		_: return base

func _hair_color(name: String) -> Color:
	match name:
		"white": return mixc(C("paper"), Color.WHITE, 0.50)
		"grey": return mixc(C("paper"), C("dark_brown"), 0.30)
		"rust": return mixc(C("cinnabar"), C("dark_brown"), 0.42)
		_: return darken(C("dark_brown"), 0.22)

func _metal(name: String) -> Color:
	match name:
		"silver": return mixc(C("paper"), Color.WHITE, 0.55)
		"gold": return mixc(C("gold"), C("cinnabar"), 0.12)
		"iron": return mixc(C("dark_brown"), C("paper"), 0.24)
		"dark": return mixc(C("dark_brown"), C("deep_green"), 0.52)
		_: return mixc(C("paper"), Color.WHITE, 0.55)

func _unit_specs() -> Array:
	return [
		{"id": "liubei", "size": 320, "garment": "pao", "robe": "gold", "trim": "deep_green",
			"skin": "pale", "hair": "black", "hat": "renwang_guan", "eyes": "fierce2",
			"brows": "angry", "mouth": "roar", "beard": "none", "weapon": "twin_swords"},
		{"id": "guanyu", "size": 320, "garment": "pao", "robe": "green", "cape": "deep_green",
			"trim": "gold", "skin": "red", "hair": "black", "hat": "green_towel",
			"eyes": "phoenix", "brows": "slant", "mouth": "grit", "beard": "long",
			"weapon": "guandao"},
		{"id": "zhangfei", "size": 320, "garment": "armor", "robe": "black", "metal": "iron",
			"trim": "gold", "skin": "dark", "hair": "rust", "hat": "black_jin",
			"eyes": "ring", "brows": "thick", "mouth": "roar", "beard": "bushy",
			"weapon": "serpent_spear"},
		{"id": "zhaoyun", "size": 320, "garment": "armor", "robe": "white", "metal": "silver",
			"cape": "white", "trim": "cinnabar", "skin": "pale", "hair": "black",
			"hat": "silver_helmet", "eyes": "fierce2", "brows": "straight", "mouth": "tight",
			"beard": "none", "weapon": "tiger_spear"},
		{"id": "zhuge", "size": 320, "garment": "chang", "robe": "jade", "trim": "gold",
			"skin": "pale", "hair": "black", "hat": "guan_jin", "eyes": "calm",
			"brows": "thin", "mouth": "smile", "beard": "goatee", "weapon": "feather_fan"},
		{"id": "huatuo", "size": 320, "garment": "chang", "robe": "paper", "trim": "green",
			"skin": "old", "hair": "white", "hat": "old_cap", "eyes": "happy",
			"brows": "white_bushy", "mouth": "open_smile", "beard": "white_long",
			"weapon": "gourd"},
		{"id": "lvbu", "size": 320, "garment": "armor", "robe": "red", "metal": "gold",
			"cape": "dark_red", "trim": "gold", "skin": "pale", "hair": "black",
			"hat": "gold_crown", "eyes": "fierce", "brows": "angry", "mouth": "smirk",
			"beard": "none", "weapon": "halberd"},
		{"id": "huangjin_zu", "size": 256, "garment": "duan", "robe": "cloth", "trim": "huangjin",
			"skin": "yellow", "hair": "black", "hat": "yellow_turban", "eyes": "fierce2",
			"brows": "angry", "mouth": "shout", "beard": "none", "weapon": "cleaver",
			"foe": true},
		{"id": "huangjin_gongshou", "size": 256, "garment": "duan", "robe": "sand",
			"trim": "huangjin", "skin": "yellow", "hair": "black", "hat": "yellow_turban",
			"eyes": "squint", "brows": "angry", "mouth": "flat", "beard": "none",
			"weapon": "bow", "foe": true},
		{"id": "huangjin_lishi", "size": 256, "garment": "bare", "robe": "cloth",
			"trim": "huangjin", "skin": "tan", "hair": "black", "hat": "topknot",
			"eyes": "fierce2", "brows": "angry", "mouth": "grit", "beard": "stubble",
			"weapon": "hammer", "foe": true, "hefty": true},
		{"id": "xiliang_qinwei", "size": 256, "garment": "armor", "robe": "sand",
			"metal": "iron", "trim": "cinnabar", "skin": "tan", "hair": "black",
			"hat": "leather_helm", "eyes": "narrow", "brows": "angry", "mouth": "flat",
			"beard": "short", "weapon": "spear_shield", "foe": true},
		{"id": "huaxiong", "size": 448, "garment": "armor", "robe": "black", "metal": "dark",
			"cape": "black", "trim": "cinnabar", "skin": "iron", "hair": "black",
			"hat": "iron_helm", "eyes": "glow", "brows": "none", "mouth": "hidden",
			"beard": "mask", "weapon": "great_axe", "foe": true, "hefty": true},
		{"id": "machao", "size": 320, "garment": "armor", "robe": "white", "metal": "silver",
			"trim": "cinnabar", "skin": "pale", "hair": "black",
			"hat": "lion_helm", "eyes": "fierce2", "brows": "straight", "mouth": "tight",
			"beard": "none", "weapon": "wide_spear"},
		{"id": "huangzhong", "size": 320, "garment": "armor", "robe": "iron", "metal": "dark",
			"trim": "gold", "skin": "old", "hair": "white", "hat": "iron_helm",
			"eyes": "narrow", "brows": "white_bushy", "mouth": "grit", "beard": "goat",
			"weapon": "great_bow"},
		{"id": "weiyan", "size": 320, "garment": "armor", "robe": "dark_brown", "metal": "dark",
			"trim": "gold", "skin": "red", "hair": "black", "hat": "topknot_gold",
			"eyes": "fierce", "brows": "slant", "mouth": "smirk", "beard": "stubble",
			"weapon": "straight_blade"},
		# --- 03 第三批(05 §4)---
		{"id": "zhangliao", "size": 320, "garment": "armor", "robe": "blue_robe",
			"metal": "gold", "trim": "gold", "skin": "pale", "hair": "black",
			"hat": "none", "eyes": "fierce2", "brows": "straight", "mouth": "tight",
			"beard": "short", "weapon": "hook_halberd"},
		{"id": "xuchu", "size": 320, "garment": "bare", "robe": "iron", "metal": "iron",
			"trim": "gold", "skin": "dark", "hair": "black", "hat": "tiger_helm",
			"eyes": "ring", "brows": "thick", "mouth": "roar", "beard": "bushy",
			"weapon": "broad_blade", "hefty": true},
		{"id": "ganning", "size": 320, "garment": "duan", "robe": "cloth", "trim": "cinnabar",
			"skin": "tan", "hair": "black", "hat": "red_headwrap", "eyes": "fierce2",
			"brows": "straight", "mouth": "smirk", "beard": "none",
			"weapon": "twin_daggers"},
		{"id": "zhouyu", "size": 320, "garment": "chang", "robe": "paper", "trim": "gold",
			"skin": "pale", "hair": "black", "hat": "white_lunjin", "eyes": "calm",
			"brows": "thin", "mouth": "smile", "beard": "none", "weapon": "slim_sword"},
		{"id": "diaochan", "size": 320, "garment": "chang", "robe": "red_dress",
			"trim": "gold", "skin": "pale", "hair": "black", "hat": "twin_buns",
			"eyes": "calm", "brows": "soft", "mouth": "smile", "beard": "none",
			"weapon": "round_fan"}
	]

# ---- 身形件(三头身:头大、身短、腿跨步)

## 躯干:上窄下宽 + 底摆波浪,可整体横移 tilt 制造扭转
func g_torso(top: float, bot: float, tw: float, bw: float, dip: float, cx := 50.0) -> Array:
	var pts: Array = []
	var n := 9
	for i in n:
		var t := float(i) / float(n - 1)
		var y := lerpf(top, bot, t)
		var w := lerpf(tw, bw, t * t * 0.5 + t * 0.5) * 0.5
		var sway := sin(t * PI * 0.9) * 2.2
		pts.append(Vector2(cx - w + sway, y))
	for i in range(1, n):
		var t := float(i) / float(n - 1)
		var w := bw * 0.5
		pts.append(Vector2(cx - w + lerpf(0, w * 2, t) + sin(t * PI) * 1.6, bot + sin(PI * t) * dip))
	for i in range(n - 1, -1, -1):
		var t := float(i) / float(n - 1)
		var y := lerpf(top, bot, t)
		var w := lerpf(tw, bw, t * t * 0.5 + t * 0.5) * 0.5
		var sway := sin(t * PI * 0.9) * 2.2
		pts.append(Vector2(cx + w + sway, y))
	return pts

## 拳/掌(冲镜的透视夸张:半径比手臂大)
func g_fist(cx: float, cy: float, r: float) -> Array:
	var pts: Array = []
	for i in 13:
		var a := float(i) / 12.0 * TAU
		var rr := r * (1.0 + 0.10 * sin(a * 3.0))
		pts.append(Vector2(cx + cos(a) * rr, cy + sin(a) * rr))
	return pts

## 肩吞(兽面):圆 + 两侧獠牙
func gPauldron(cx: float, cy: float, r: float) -> Array:
	var pts: Array = []
	for i in 9:
		var a := PI + float(i) / 8.0 * PI
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r * 0.9))
	pts.append(Vector2(cx + r * 1.25, cy + r * 0.35))
	pts.append(Vector2(cx + r * 0.7, cy + r * 0.95))
	pts.append(Vector2(cx - r * 0.7, cy + r * 0.95))
	pts.append(Vector2(cx - r * 1.25, cy + r * 0.35))
	return pts

# ---- 生成入口

func _gen_units(list: Array) -> void:
	for sp in _unit_specs():
		_gen_stand(list, sp)

func _gen_stand(list: Array, sp: Dictionary) -> void:
	var size := int(sp.get("size", 320))
	var k := float(size) / 100.0 * float(SS)
	var id := str(sp.get("id", ""))
	rng.seed = seed_for("units/%s.png" % id)
	var img := new_img(size * SS, size * SS)
	var ink := C("dark_brown")
	var gold := C("gold")
	var cin := C("cinnabar")
	var paper := C("paper")
	var robe := _robe_color(str(sp.get("robe", "green")))
	var p := {"k": k, "ink": ink, "gold": gold, "cin": cin, "paper": paper,
		"steel": mixc(gold, paper, 0.45), "robe": robe, "robe_dark": darken(robe, 0.36),
		"skin": _skin(str(sp.get("skin", "tan"))),
		"hair": _hair_color(str(sp.get("hair", "black"))),
		"metal": _metal(str(sp.get("metal", "silver"))),
		"cape": _robe_color(str(sp.get("cape", ""))),
		"hefty": bool(sp.get("hefty", false))}
	# 地面投影
	fill_ellipse(img, 50 * k, 96 * k, 20 * k, 3.4 * k, Color(ink.r, ink.g, ink.b, 0.22))
	if str(sp.get("cape", "")) != "":
		_cape(img, p)
	_weapon_back(img, p, str(sp.get("weapon", "")))
	_legs(img, p, sp)
	_garment(img, p, sp)
	_arms(img, p, sp)
	# 头 + 颈
	var cx := 47.0
	var hr := 22.0 if bool(sp.get("hefty", false)) else 21.0
	e_line(img, k, cx, 44, cx, 52, 9.0, darken(p["skin"], 0.18))
	var hatted := str(sp.get("hat", "")) in ["silver_helmet", "leather_helm", "iron_helm"]
	if not hatted:
		g_ell_grad(img, k, cx - hr + 1.0, 30, 3.4, 4.0, p["skin"])
		g_ell_grad(img, k, cx + hr - 1.0, 30, 3.4, 4.0, p["skin"])
	g_ell_grad(img, k, cx, 26, hr, hr * 1.02, p["skin"])
	_hair(img, p, str(sp.get("hat", "")), cx)
	_hat(img, p, str(sp.get("hat", "")), cx)
	_face(img, p, str(sp.get("eyes", "fierce2")), str(sp.get("brows", "angry")),
		str(sp.get("mouth", "shout")), bool(sp.get("foe", false)), cx)
	_beard(img, p, str(sp.get("beard", "none")), cx)
	_weapon_front(img, p, str(sp.get("weapon", "")))
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	save(img, "units/%s.png" % id, list)

# ---- 披风(破边 + 张角)

func _cape(img: Image, p: Dictionary) -> void:
	var col: Color = p["cape"]
	var pts: Array = [Vector2(33, 46), Vector2(63, 44)]
	for i in 6:
		var t := float(i) / 5.0
		pts.append(Vector2(lerpf(76, 20, t), 88.0 + (3.4 if i % 2 == 1 else 0.0)))
	pts.append(Vector2(20, 88))
	gp_poly(img, p, pts, lighten(col, 0.10), darken(col, 0.34))

# ---- 腿(跨步:前腿直立承重,后腿后蹬)

func _legs(img: Image, p: Dictionary, sp: Dictionary) -> void:
	var k := float(p["k"])
	var ink: Color = p["ink"]
	var paper: Color = p["paper"]
	var leg: Color = p["robe_dark"]
	var w := 9.5 if bool(sp.get("hefty", false)) else 8.2
	e_limb(img, k, 52, 76, 56, 90, w, leg)
	e_limb(img, k, 44, 76, 36, 89, w * 0.92, darken(leg, 0.12))
	e_poly(img, p, g_wedge(56, 88, 66, 93, 7.0, 9.0), mixc(ink, paper, 0.10))
	e_poly(img, p, g_wedge(36, 87, 28, 92, 6.4, 8.4), mixc(ink, paper, 0.06))

# ---- 衣身

func _garment(img: Image, p: Dictionary, sp: Dictionary) -> void:
	match str(sp.get("garment", "pao")):
		"armor":
			_armor(img, p, sp)
		"chang":
			_chang(img, p, sp)
		"duan":
			_duan(img, p, sp)
		"bare":
			_bare(img, p, sp)
		_:
			_pao(img, p, sp)

func _pao(img: Image, p: Dictionary, sp: Dictionary) -> void:
	var k := float(p["k"])
	var robe: Color = p["robe"]
	var trim := _robe_color(str(sp.get("trim", "gold")))
	var top := 46.0
	var bot := 82.0
	var tw := 34.0
	var bw := 48.0
	gp_poly(img, p, g_torso(top, bot, tw, bw, 3.0), lighten(robe, 0.14), darken(robe, 0.34))
	e_line(img, k, 40, 46, 48, 60, 3.6, lighten(robe, 0.26))
	e_line(img, k, 56, 45, 48, 60, 3.6, trim)
	e_poly(img, p, g_band(63.0, 68.0, 36.0, 40.0, 0.0), darken(robe, 0.48))
	e_cir(img, k, 48, 65.5, 2.8, trim)
	e_poly(img, p, g_band(bot - 4.0, bot + 2.4, 44.0, bw, 2.0), trim)

func _armor(img: Image, p: Dictionary, sp: Dictionary) -> void:
	var k := float(p["k"])
	var ink: Color = p["ink"]
	var robe: Color = p["robe"]
	var metal: Color = p["metal"]
	var trim: Color = p["cin"] if str(sp.get("trim", "gold")) == "cinnabar" else p["gold"]
	var top := 46.0
	var bot := 84.0
	var tw := 36.0
	var bw := 46.0
	gp_poly(img, p, g_torso(top, bot, tw, bw, 2.4), darken(robe, 0.05), darken(robe, 0.42))
	# 甲裙札条
	for i in 4:
		var y := 66.0 + float(i) * 4.4
		var w := lerpf(tw, bw, ((y - top) / (bot - top)) * 0.9) + 2.0
		f_poly(img, p, g_band(y, y + 4.0, w, w + 1.6, 1.2), mixc(metal, ink, 0.34))
	# 胸甲
	gp_poly(img, p, g_band(46.0, 66.0, 33.0, 40.0, 0.0), lighten(metal, 0.24), darken(metal, 0.30))
	e_cir(img, k, 48, 56, 6.4, lighten(metal, 0.34))
	e_cir(img, k, 48, 56, 2.6, trim)
	e_poly(img, p, g_band(62.0, 67.0, 38.0, 41.0, 0.0), mixc(ink, robe, 0.30))
	e_cir(img, k, 48, 64.5, 2.8, trim)
	# 兽面肩吞
	e_poly(img, p, gPauldron(30, 48, 9.5), mixc(metal, ink, 0.10))
	e_poly(img, p, gPauldron(66, 46, 9.5), mixc(metal, ink, 0.10))
	e_cir(img, k, 27.4, 47.0, 1.5, ink, false)
	e_cir(img, k, 32.6, 47.0, 1.5, ink, false)
	e_cir(img, k, 63.4, 45.0, 1.5, ink, false)
	e_cir(img, k, 68.6, 45.0, 1.5, ink, false)
	e_poly(img, p, g_leaf(24, 52, 20, 58, 3.0), lighten(metal, 0.20))
	e_poly(img, p, g_leaf(72, 50, 76, 56, 3.0), lighten(metal, 0.20))

func _chang(img: Image, p: Dictionary, sp: Dictionary) -> void:
	var k := float(p["k"])
	var robe: Color = p["robe"]
	var trim := _robe_color(str(sp.get("trim", "gold")))
	var top := 46.0
	var bot := 86.0
	var tw := 34.0
	var bw := 54.0
	gp_poly(img, p, g_torso(top, bot, tw, bw, 3.2), lighten(robe, 0.12), darken(robe, 0.30))
	e_poly(img, p, g_band(47.0, bot + 1.6, 8.0, 11.0, 2.0), trim)
	e_line(img, k, 44.5, 47, 44.5, 84, 1.3, darken(trim, 0.28))
	e_line(img, k, 51.5, 47, 51.5, 84, 1.3, darken(trim, 0.28))
	e_cir(img, k, 48, 55, 2.4, trim)
	e_bezier(img, k, 48, 57, 45, 66, 46, 76, 2.0, 0.8, trim)

func _duan(img: Image, p: Dictionary, sp: Dictionary) -> void:
	var k := float(p["k"])
	var ink: Color = p["ink"]
	var robe: Color = p["robe"]
	var trim := _robe_color(str(sp.get("trim", "huangjin")))
	var top := 46.0
	var bot := 72.0
	var tw := 34.0
	var bw := 40.0
	gp_poly(img, p, g_torso(top, bot, tw, bw, 1.6), lighten(robe, 0.10), darken(robe, 0.32))
	e_line(img, k, 41, 46, 49, 58, 3.0, lighten(robe, 0.20))
	e_poly(img, p, g_band(60.0, 65.0, 36.0, 39.0, 0.0), trim)
	e_cir(img, k, 48, 62.5, 2.2, darken(trim, 0.32))
	f_poly(img, p, g_band(67.0, 71.0, 11.0, 12.0, 0.6), darken(robe, 0.28))
	e_line(img, k, 52, 80, 52, 88, 1.8, trim)
	e_line(img, k, 40, 80, 36, 87, 1.8, trim)

func _bare(img: Image, p: Dictionary, sp: Dictionary) -> void:
	var k := float(p["k"])
	var ink: Color = p["ink"]
	var skin: Color = p["skin"]
	var trim := _robe_color(str(sp.get("trim", "huangjin")))
	var top := 46.0
	var bot := 74.0
	var tw := 38.0
	var bw := 42.0
	gp_poly(img, p, g_torso(top, bot, tw, bw, 1.4), lighten(skin, 0.16), darken(skin, 0.26))
	e_arc(img, k, 41, 56, 6.0, PI + 0.3, TAU - 0.3, 1.6, darken(skin, 0.32))
	e_arc(img, k, 55, 56, 6.0, PI + 0.3, TAU - 0.3, 1.6, darken(skin, 0.32))
	e_line(img, k, 48, 58, 48, 72, 1.6, darken(skin, 0.24))
	e_poly(img, p, g_band(62.0, 67.0, 38.0, 40.0, 0.0), trim)
	var w := lerpf(tw, bw, 0.95)
	e_poly(img, p, g_band(72.0, 78.0, w * 0.9, 36.0, 1.0), mixc(trim, ink, 0.25))

# ---- 手臂:一手前伸握兵器(透视放大),一手后摆握拳

func _arms(img: Image, p: Dictionary, sp: Dictionary) -> void:
	var k := float(p["k"])
	var robe: Color = p["robe"]
	var metal: Color = p["metal"]
	var skin: Color = p["skin"]
	var g := str(sp.get("garment", "pao"))
	var arm_col := metal if g == "armor" else (robe if g != "bare" else skin)
	# 后摆臂(画面左)
	e_limb(img, k, 33, 50, 24, 62, 8.0, arm_col)
	e_poly(img, p, g_fist(22, 66, 6.2), skin)
	# 前伸臂(画面右,冲镜)
	e_limb(img, k, 62, 49, 74, 58, 9.2, arm_col)
	if g == "chang":
		e_poly(img, p, g_sleeve(60, 46, 76, 58, 14.0, 18.0), robe)
		e_ell(img, k, 76, 58.5, 8.6, 3.0, lighten(robe, 0.20))
	elif g != "bare":
		e_ell(img, k, 68, 54, 6.0, 3.0, lighten(arm_col, 0.20), false)
	e_poly(img, p, g_fist(78, 62, 8.4), skin)
	e_line(img, k, 74.5, 60, 74.5, 66, 1.4, darken(skin, 0.30))
	e_line(img, k, 78, 59.5, 78, 66, 1.4, darken(skin, 0.30))
	e_line(img, k, 81.5, 60, 81.5, 66, 1.4, darken(skin, 0.30))

# ---- 头发(尖刺炸开)

func _hair(img: Image, p: Dictionary, hat: String, cx: float) -> void:
	var k := float(p["k"])
	var hair: Color = p["hair"]
	if hat in ["silver_helmet", "leather_helm", "iron_helm", "lion_helm", "tiger_helm"]:
		return
	if hat == "old_cap" or hat == "guan_jin" or hat == "white_lunjin":
		e_poly(img, p, g_spiky(cx, 22, 17.0, 22.0, PI * 1.08, PI * 1.92, 5, 0.55), hair)
	elif hat == "topknot_gold":
		# 魏延狂髻:束起不炸开(贴头皮窄弧,03 §3.3)
		e_poly(img, p, g_spiky(cx, 21, 16.5, 20.0, PI * 1.10, PI * 1.90, 4, 0.30), hair)
	else:
		e_poly(img, p, g_spiky(cx, 20, 16.0, 25.5, PI * 1.02, PI * 1.98, 7, 0.42), hair)
	if hat == "topknot":
		e_cir(img, k, cx, 1.5, 5.2, hair)

# ---- 头饰

func _hat(img: Image, p: Dictionary, hat: String, cx: float) -> void:
	var k := float(p["k"])
	var ink: Color = p["ink"]
	var gold: Color = p["gold"]
	var cin: Color = p["cin"]
	var paper: Color = p["paper"]
	var hair: Color = p["hair"]
	var metal: Color = p["metal"]
	var deep := C("deep_green")
	match hat:
		"renwang_guan":
			# 刘备:帻冠 + 金箍 + 双垂带
			e_ell(img, k, cx, 5, 13.0, 8.0, mixc(ink, deep, 0.45))
			e_rect(img, k, cx - 14, 10, 28, 3.4, gold)
			e_bezier(img, k, cx - 14, 13, cx - 21, 20, cx - 20, 29, 2.6, 1.0, mixc(ink, deep, 0.45))
			e_bezier(img, k, cx + 14, 13, cx + 21, 20, cx + 20, 29, 2.6, 1.0, mixc(ink, deep, 0.45))
		"green_towel":
			# 关羽:绿绢巾 + 金边 + 前结 + 双飘带
			e_ell(img, k, cx, 9, 21.0, 9.5, deep)
			e_rect(img, k, cx - 20, 13, 40, 3.0, gold)
			e_cir(img, k, cx + 19, 11, 4.2, deep)
			e_cir(img, k, cx + 19, 11, 1.8, gold, false)
			e_bezier(img, k, cx + 22, 14, cx + 30, 22, cx + 27, 35, 3.0, 1.0, deep)
			e_bezier(img, k, cx + 17, 15, cx + 23, 25, cx + 20, 36, 2.4, 0.9, mixc(deep, paper, 0.3))
		"black_jin":
			# 张飞:黑扎巾 + 额前白月牙 + 炸巾带
			e_ell(img, k, cx, 8, 21.0, 9.5, ink)
			e_cir(img, k, cx, 1.0, 4.0, ink)
			e_poly(img, p, g_crescent(cx, 19, 6.6, 3.4, PI * 0.15, PI * 0.85), lighten(paper, 0.30))
			e_bezier(img, k, cx - 20, 12, cx - 28, 17, cx - 30, 26, 3.0, 1.0, ink)
			e_bezier(img, k, cx + 20, 12, cx + 28, 17, cx + 30, 26, 3.0, 1.0, ink)
		"silver_helmet":
			# 赵云:银盔 + 红缨 + 护额
			g_ell_grad(img, k, cx, 10, 22.5, 12.0, metal)
			e_rect(img, k, cx - 23, 17, 46, 4.0, mixc(ink, metal, 0.28))
			e_ell(img, k, cx, 6, 10.0, 4.5, lighten(metal, 0.30), false)
			e_cir(img, k, cx, -2.5, 5.2, cin)
			for i in 4:
				e_line(img, k, cx, 0.0, cx - 9 + float(i) * 6, -5.0, 2.4, cin)
			e_poly(img, p, g_wedge(cx - 20, 21, cx - 21, 40, 7.0, 5.0), mixc(ink, metal, 0.30))
			e_poly(img, p, g_wedge(cx + 20, 21, cx + 21, 40, 7.0, 5.0), mixc(ink, metal, 0.30))
		"guan_jin":
			# 诸葛亮:高方山纶巾 + 金玉带 + 后垂巾
			e_rect(img, k, cx - 13, -6, 26, 20, deep)
			e_ell(img, k, cx, -6, 13.0, 3.6, deep)
			e_rect(img, k, cx - 13, 10, 26, 3.4, gold)
			e_bezier(img, k, cx + 11, 14, cx + 21, 21, cx + 18, 32, 3.2, 1.4, deep)
			e_bezier(img, k, cx - 11, 14, cx - 21, 21, cx - 18, 32, 3.2, 1.4, deep)
		"old_cap":
			# 华佗:软巾 + 垂鬓白发
			e_ell(img, k, cx, 6, 19.0, 9.5, mixc(paper, C("spring_green"), 0.42))
			e_rect(img, k, cx - 19, 12, 38, 3.0, C("spring_green"))
			e_ell(img, k, cx - 18, 20, 5.0, 4.0, hair, false)
			e_ell(img, k, cx + 18, 20, 5.0, 4.0, hair, false)
			e_bezier(img, k, cx + 17, 15, cx + 24, 22, cx + 21, 31, 2.6, 1.0, C("spring_green"))
		"gold_crown":
			# 吕布:束发金冠 + 双雉鸡翎高挑
			e_ell(img, k, cx, 6, 14.0, 8.5, gold)
			e_rect(img, k, cx - 14, 11, 28, 3.4, cin)
			e_cir(img, k, cx, 0.5, 3.6, cin)
			e_cir(img, k, cx, 0.5, 1.6, gold, false)
			e_bezier(img, k, cx - 12, 4, cx - 24, -4, cx - 34, 3, 3.4, 0.9, cin)
			e_bezier(img, k, cx + 12, 4, cx + 24, -4, cx + 34, 3, 3.4, 0.9, cin)
			e_bezier(img, k, cx - 12, 5, cx - 23, -1, cx - 31, 4, 1.4, 0.4, mixc(cin, paper, 0.5))
			e_bezier(img, k, cx + 12, 5, cx + 23, -1, cx + 31, 4, 1.4, 0.4, mixc(cin, paper, 0.5))
		"yellow_turban":
			# 黄巾:额巾 + 结 + 双垂带
			e_ell(img, k, cx, 9, 21.0, 9.0, C("huangjin"))
			e_rect(img, k, cx - 20, 13, 40, 3.0, darken(C("huangjin"), 0.24))
			e_cir(img, k, cx + 19, 10, 3.8, C("huangjin"))
			e_bezier(img, k, cx + 22, 12, cx + 29, 20, cx + 26, 31, 2.8, 1.0, C("huangjin"))
			e_bezier(img, k, cx + 17, 13, cx + 23, 22, cx + 21, 32, 2.2, 0.9, darken(C("huangjin"), 0.22))
		"topknot":
			# 力士:发髻 + 黄额带
			e_rect(img, k, cx - 21, 12, 42, 3.4, C("huangjin"))
		"leather_helm":
			# 西凉:皮盔 + 红缨 + 护颊
			g_ell_grad(img, k, cx, 11, 23.0, 13.5, mixc(C("huangjin"), ink, 0.38))
			e_rect(img, k, cx - 23, 17, 46, 3.2, ink)
			e_cir(img, k, cx, -1.0, 4.4, cin)
			e_line(img, k, cx, 1, cx - 6, -4, 2.2, cin)
			e_line(img, k, cx, 1, cx + 6, -4, 2.2, cin)
			e_poly(img, p, g_crescent(cx - 21, 24, 8.5, 3.2, PI * 0.12, PI * 0.95), mixc(C("huangjin"), ink, 0.38))
			e_poly(img, p, g_crescent(cx + 21, 24, 8.5, 3.2, PI * 0.05, PI * 0.88), mixc(C("huangjin"), ink, 0.38))
		"iron_helm":
			# 华雄:黑兜鍪 + 红缨 + 尖角
			g_ell_grad(img, k, cx, 10, 24.5, 14.5, metal)
			e_rect(img, k, cx - 25, 17, 50, 3.4, ink)
			e_cir(img, k, cx, -2.0, 5.0, cin)
			for i in 3:
				e_line(img, k, cx, 0, cx - 10 + float(i) * 10, -5, 2.4, cin)
			e_poly(img, p, g_leaf(cx - 20, 8, cx - 30, -2, 5.0), metal)
			e_poly(img, p, g_leaf(cx + 20, 8, cx + 30, -2, 5.0), metal)
			e_poly(img, p, g_crescent(cx - 22, 24, 10.0, 3.6, PI * 0.10, PI * 0.95), metal)
			e_poly(img, p, g_crescent(cx + 22, 24, 10.0, 3.6, PI * 0.05, PI * 0.90), metal)
		"lion_helm":
			# 马超狮盔(03 §3.1):银盔压扁 + 盔顶金珠(兽首圆珠意象),护颊窄垂片
			g_ell_grad(img, k, cx, 10, 23.0, 13.0, metal)
			e_rect(img, k, cx - 23, 17, 46, 3.6, mixc(ink, metal, 0.28))
			e_cir(img, k, cx, -1.5, 4.6, gold)
			e_cir(img, k, cx, -1.5, 1.8, cin, false)
			e_poly(img, p, g_wedge(cx - 21, 21, cx - 22, 38, 6.0, 4.0), mixc(ink, metal, 0.30))
			e_poly(img, p, g_wedge(cx + 21, 21, cx + 22, 38, 6.0, 4.0), mixc(ink, metal, 0.30))
		"topknot_gold":
			# 魏延狂髻(03 §3.3):头顶黑小球束发 + 束发金箍细环 + 额带
			e_cir(img, k, cx, 1.0, 5.4, ink)
			e_arc(img, k, cx, 6.5, 6.0, PI * 1.05, PI * 1.95, 2.6, gold)
			e_rect(img, k, cx - 20, 13, 40, 3.0, ink)
		"red_headwrap":
			# 甘宁红巾(05 §4):朱砂包头巾 + 右侧结 + 垂带(与黄巾金黄区分)
			e_ell(img, k, cx, 9, 21.0, 9.0, cin)
			e_rect(img, k, cx - 20, 13, 40, 3.0, darken(cin, 0.22))
			e_cir(img, k, cx + 19, 10, 3.8, darken(cin, 0.15))
			e_bezier(img, k, cx + 22, 12, cx + 29, 20, cx + 26, 31, 2.8, 1.0, darken(cin, 0.12))
		"white_lunjin":
			# 周瑜白纶巾(05 §4):paper 色方巾 + 金箍 + 双垂带(与诸葛深绿巾区分)
			e_rect(img, k, cx - 13, -6, 26, 20, mixc(paper, Color.WHITE, 0.30))
			e_ell(img, k, cx, -6, 13.0, 3.6, mixc(paper, Color.WHITE, 0.30))
			e_rect(img, k, cx - 13, 10, 26, 3.4, gold)
			e_bezier(img, k, cx + 11, 14, cx + 21, 21, cx + 18, 32, 3.2, 1.4, mixc(paper, C("paper_dark"), 0.5))
			e_bezier(img, k, cx - 11, 14, cx - 21, 21, cx - 18, 32, 3.2, 1.4, mixc(paper, C("paper_dark"), 0.5))
		"twin_buns":
			# 貂蝉双髻(05 §4):顶置两颗黑发小球 + 金饰各一粒
			e_cir(img, k, cx - 10, 2.0, 7.0, ink)
			e_cir(img, k, cx + 10, 2.0, 7.0, ink)
			e_cir(img, k, cx - 10, -2.0, 1.8, gold, false)
			e_cir(img, k, cx + 10, -2.0, 1.8, gold, false)
		"tiger_helm":
			# 许褚虎头盔(05 §4):铁灰半球盔 + 顶部双耳片 + 金额箍
			g_ell_grad(img, k, cx, 10, 24.0, 14.0, metal)
			e_rect(img, k, cx - 24, 17, 48, 3.4, mixc(ink, metal, 0.28))
			for sgn in [-1.0, 1.0]:
				var s := float(sgn)
				e_poly(img, p, g_wedge(cx + 11.0 * s, 2.0, cx + 15.0 * s, -8.0, 5.0, 3.0), darken(metal, 0.12))
			e_rect(img, k, cx - 20, 13, 40, 3.0, gold)
		_:
			pass

# ---- 五官

func _face(img: Image, p: Dictionary, eyes: String, brows: String, mouth: String, foe: bool, cx: float) -> void:
	var k := float(p["k"])
	var ink: Color = p["ink"]
	var paper: Color = p["paper"]
	var cin: Color = p["cin"]
	_eyes(img, p, eyes, cx)
	_brows(img, p, brows, cx)
	_mouth(img, p, mouth, cx)
	var cheek := Color(cin.r, cin.g, cin.b, 0.16 if foe else 0.24)
	fill_ellipse(img, (cx - 12.5) * k, 34.0 * k, 4.6 * k, 3.0 * k, cheek)
	fill_ellipse(img, (cx + 12.5) * k, 34.0 * k, 4.6 * k, 3.0 * k, cheek)
	if eyes != "glow":
		e_arc(img, k, cx, 34, 1.8, 0.6, PI - 0.6, 1.2, ink)

func _eyes(img: Image, p: Dictionary, style: String, cx: float) -> void:
	var k := float(p["k"])
	var ink: Color = p["ink"]
	var gold: Color = p["gold"]
	var paper: Color = p["paper"]
	var y := 29.0
	var dx := 9.0
	match style:
		"fierce2":
			# 大圆眼 + 高光 + 上睑(百炼式英气眼)
			for ex in [cx - dx, cx + dx]:
				e_ell(img, k, ex, y, 4.0, 4.6, lighten(paper, 0.4))
				e_ell(img, k, ex + 0.3, y + 0.5, 2.6, 3.0, ink)
				e_cir(img, k, ex - 1.0, y - 1.2, 1.1, paper, false)
				e_arc(img, k, ex, y - 1.0, 4.4, PI + 0.35, TAU - 0.35, 1.8, ink)
		"phoenix":
			for ex in [cx - dx, cx + dx]:
				var sgn := -1.0 if ex < cx else 1.0
				e_limb(img, k, ex - 3.6 * sgn, y + 1.2, ex + 3.6 * sgn, y - 1.8, 3.0, ink)
				e_cir(img, k, ex + 1.6 * sgn, y - 0.8, 0.8, paper, false)
				e_arc(img, k, ex, y + 1.6, 4.4, PI + 0.5, TAU - 0.5, 1.4, ink)
		"ring":
			for ex in [cx - dx, cx + dx]:
				e_cir(img, k, ex, y, 5.2, lighten(paper, 0.40))
				e_cir(img, k, ex + 0.4, y + 0.3, 3.0, ink)
				e_cir(img, k, ex - 1.1, y - 1.2, 1.0, paper, false)
		"calm":
			for ex in [cx - dx, cx + dx]:
				e_ell(img, k, ex, y + 0.4, 3.2, 1.9, ink)
				e_limb(img, k, ex - 3.8, y - 1.6, ex + 3.8, y - 0.6, 1.8, ink)
		"happy":
			for ex in [cx - dx, cx + dx]:
				e_arc(img, k, ex, y + 2.0, 3.8, PI + 0.45, TAU - 0.45, 2.6, ink)
		"fierce":
			for ex in [cx - dx, cx + dx]:
				var sgn := -1.0 if ex < cx else 1.0
				e_limb(img, k, ex - 3.4 * sgn, y + 1.8, ex + 3.6 * sgn, y - 2.0, 3.4, ink)
				e_cir(img, k, ex + 1.6 * sgn, y - 1.2, 1.1, gold, false)
		"squint":
			e_limb(img, k, cx - 13.0, y, cx - 5.0, y - 1.0, 2.4, ink)
			e_ell(img, k, cx + 9.0, y, 3.4, 3.8, ink)
			e_cir(img, k, cx + 8.0, y - 1.2, 1.0, paper, false)
		"narrow":
			for ex in [cx - dx, cx + dx]:
				e_limb(img, k, ex - 3.4, y + 0.8, ex + 3.4, y - 1.2, 2.6, ink)
		"glow":
			for ex in [cx - dx, cx + dx]:
				e_limb(img, k, ex - 3.6, y + 1.0, ex + 3.6, y - 1.4, 3.2, darken(gold, 0.45))
				e_limb(img, k, ex - 2.6, y + 0.5, ex + 2.6, y - 1.0, 1.6, lighten(gold, 0.50))
		_:
			for ex in [cx - dx, cx + dx]:
				e_cir(img, k, ex, y, 2.8, ink)
				e_cir(img, k, ex - 0.9, y - 1.1, 1.0, paper, false)

func _brows(img: Image, p: Dictionary, style: String, cx: float) -> void:
	var k := float(p["k"])
	var ink: Color = p["ink"]
	var hair: Color = p["hair"]
	var dx := 9.0
	match style:
		"soft":
			for ex in [cx - dx, cx + dx]:
				e_arc(img, k, ex, 23.0, 4.4, PI + 0.5, TAU - 0.5, 1.8, ink)
		"thin":
			for ex in [cx - dx, cx + dx]:
				e_limb(img, k, ex - 4.4, 22.4, ex + 4.4, 21.2, 1.6, ink)
		"straight":
			for ex in [cx - dx, cx + dx]:
				e_limb(img, k, ex - 4.2, 22.0, ex + 4.2, 21.2, 2.4, ink)
		"slant":
			for ex in [cx - dx, cx + dx]:
				var sgn := -1.0 if ex < cx else 1.0
				e_bezier(img, k, ex - 4.4 * sgn, 25.0, ex, 21.6, ex + 5.6 * sgn, 17.5, 2.8, 0.9, ink)
		"angry":
			for ex in [cx - dx, cx + dx]:
				var sgn := -1.0 if ex < cx else 1.0
				e_limb(img, k, ex - 4.2 * sgn, 24.6, ex + 3.8 * sgn, 19.4, 2.8, ink)
		"thick":
			for ex in [cx - dx, cx + dx]:
				var sgn := -1.0 if ex < cx else 1.0
				e_poly(img, p, g_wedge(ex - 5.2 * sgn, 25.0, ex + 5.0 * sgn, 18.0, 5.0, 2.0), ink)
		"white_bushy":
			for ex in [cx - dx, cx + dx]:
				var sgn := -1.0 if ex < cx else 1.0
				e_limb(img, k, ex - 5.0 * sgn, 23.6, ex + 5.2 * sgn, 20.4, 3.4, hair)
		_:
			pass

func _mouth(img: Image, p: Dictionary, style: String, cx: float) -> void:
	var k := float(p["k"])
	var ink: Color = p["ink"]
	var paper: Color = p["paper"]
	var cin: Color = p["cin"]
	match style:
		"shout":
			# 大喝:张口 + 上排牙
			e_ell(img, k, cx, 38.5, 5.4, 4.6, mixc(ink, cin, 0.45))
			e_rect(img, k, cx - 4.4, 35.2, 8.8, 2.2, lighten(paper, 0.3))
		"roar":
			e_ell(img, k, cx, 38.0, 6.6, 5.6, mixc(ink, cin, 0.50))
			e_rect(img, k, cx - 5.4, 34.4, 10.8, 2.4, lighten(paper, 0.3))
			e_poly(img, p, g_wedge(cx - 3.0, 41.6, cx + 3.0, 41.6, 2.4, 2.4), lighten(paper, 0.3))
		"smile":
			e_arc(img, k, cx, 36.0, 5.2, 0.45, PI - 0.45, 2.0, ink)
		"smirk":
			e_arc(img, k, cx + 1.5, 36.0, 4.8, 0.30, PI - 1.0, 2.0, ink)
		"tight":
			e_limb(img, k, cx - 4.4, 37.6, cx + 4.4, 37.0, 2.0, ink)
		"flat":
			e_limb(img, k, cx - 5.0, 37.6, cx + 5.0, 37.6, 2.0, ink)
		"grit":
			e_ell(img, k, cx, 37.5, 6.2, 3.0, mixc(ink, cin, 0.35))
			e_line(img, k, cx - 5.6, 37.5, cx + 5.6, 37.5, 1.3, lighten(paper, 0.28))
			for i in 3:
				e_line(img, k, cx - 3.4 + float(i) * 3.4, 35.4, cx - 3.4 + float(i) * 3.4, 39.6, 1.0, lighten(paper, 0.2))
		"open_smile":
			e_ell(img, k, cx, 37.5, 5.0, 3.6, mixc(ink, cin, 0.38))
			e_arc(img, k, cx, 34.0, 5.4, PI + 0.4, TAU - 0.4, 1.8, paper)
		_:
			pass

# ---- 须髯 / 面甲

func _beard(img: Image, p: Dictionary, style: String, cx: float) -> void:
	var k := float(p["k"])
	var ink: Color = p["ink"]
	var hair: Color = p["hair"]
	var metal: Color = p["metal"]
	var skin: Color = p["skin"]
	match style:
		"long":
			# 关羽美髯:三绺长须飘至腹
			e_poly(img, p, g_leaf(cx, 42, cx - 1, 78, 8.0), hair)
			e_poly(img, p, g_leaf(cx - 6.5, 41, cx - 13, 70, 3.6), hair)
			e_poly(img, p, g_leaf(cx + 6.5, 41, cx + 13, 70, 3.6), hair)
			e_line(img, k, cx - 6, 34, cx - 12, 39, 2.0, hair)
			e_line(img, k, cx + 6, 34, cx + 12, 39, 2.0, hair)
			e_line(img, k, cx, 50, cx - 1, 76, 1.3, lighten(hair, 0.28))
		"bushy":
			# 张飞虬髯:炸开一片尖刺
			e_poly(img, p, g_spiky(cx, 40, 13.0, 21.0, PI * 0.08, PI * 0.92, 9, 0.30), hair)
			e_poly(img, p, g_leaf(cx - 8, 34, cx - 16, 36, 3.6), hair)
			e_poly(img, p, g_leaf(cx + 8, 34, cx + 16, 36, 3.6), hair)
		"goatee":
			e_poly(img, p, g_leaf(cx, 42, cx, 62, 6.4), hair)
			e_poly(img, p, g_leaf(cx - 4.5, 41, cx - 6, 56, 2.8), hair)
			e_poly(img, p, g_leaf(cx + 4.5, 41, cx + 6, 56, 2.8), hair)
		"white_long":
			e_poly(img, p, g_leaf(cx, 42, cx, 74, 9.0), hair)
			e_poly(img, p, g_leaf(cx - 6, 41, cx - 10, 62, 3.4), hair)
			e_poly(img, p, g_leaf(cx + 6, 41, cx + 10, 62, 3.4), hair)
		"short":
			e_poly(img, p, g_leaf(cx - 3, 35.5, cx - 11, 38.5, 2.8), hair)
			e_poly(img, p, g_leaf(cx + 3, 35.5, cx + 11, 38.5, 2.8), hair)
			e_ell(img, k, cx, 43.5, 2.8, 2.0, hair)
		"stubble":
			# 力士:上唇两撇 + 颏下一撮
			e_poly(img, p, g_leaf(cx - 3, 36, cx - 10, 38, 3.0), hair)
			e_poly(img, p, g_leaf(cx + 3, 36, cx + 10, 38, 3.0), hair)
			e_ell(img, k, cx, 45.5, 3.4, 2.4, hair)
		"goat":
			# 黄忠:八字两撇 + 山羊一绺(与华佗 white_long 三绺垂胸区分,03 §3.2)
			e_poly(img, p, g_leaf(cx - 3, 36, cx - 11, 39, 3.2), hair)
			e_poly(img, p, g_leaf(cx + 3, 36, cx + 11, 39, 3.2), hair)
			e_poly(img, p, g_leaf(cx, 42, cx + 1, 60, 4.2), hair)
		"mask":
			# 华雄:铁面甲 + 鼻脊 + 铆钉 + 排气缝
			e_poly(img, p, g_crescent(cx, 28, 20.0, 11.0, PI * 0.16, PI * 0.84), metal)
			e_line(img, k, cx, 28, cx, 46, 2.4, darken(metal, 0.38))
			e_cir(img, k, cx - 10, 37, 1.5, ink, false)
			e_cir(img, k, cx + 10, 37, 1.5, ink, false)
			e_cir(img, k, cx - 5, 43, 1.5, ink, false)
			e_cir(img, k, cx + 5, 43, 1.5, ink, false)
			e_line(img, k, cx - 7, 40, cx - 2, 40, 1.4, darken(metal, 0.45))
			e_line(img, k, cx + 2, 40, cx + 7, 40, 1.4, darken(metal, 0.45))
		_:
			pass

# ---- 兵器(斜贯画面的长杆,后层)

func _weapon_back(img: Image, p: Dictionary, wp: String) -> void:
	var k := float(p["k"])
	var ink: Color = p["ink"]
	var gold: Color = p["gold"]
	var wood := mixc(ink, gold, 0.30)
	match wp:
		"guandao":
			e_limb(img, k, 14, 92, 84, 10, 3.2, wood)
		"serpent_spear":
			e_limb(img, k, 16, 90, 86, 14, 3.0, wood)
		"tiger_spear":
			e_limb(img, k, 18, 90, 86, 16, 3.0, wood)
		"halberd":
			e_limb(img, k, 16, 92, 88, 18, 3.4, wood)
		"spear_shield":
			e_limb(img, k, 20, 90, 88, 20, 2.8, wood)
		"great_axe":
			e_limb(img, k, 14, 94, 86, 26, 4.2, wood)
		"hammer":
			e_limb(img, k, 22, 88, 82, 30, 3.8, wood)
		"wide_spear":
			# 马超长枪(03 §3.1):杆金褐,与赵云虎头枪区分
			e_limb(img, k, 18, 90, 86, 16, 3.0, mixc(gold, C("paper"), 0.20))
		"great_bow":
			# 黄忠大弓斜背 + 箭囊 3 箭羽(03 §3.2)
			e_poly(img, p, g_wedge(56, 60, 70, 34, 8.4, 7.0), mixc(C("cinnabar"), gold, 0.4))
			for i in 3:
				e_line(img, k, 40 + float(i) * 3, 34, 44 + float(i) * 3, 22, 1.5, ink)
		"straight_blade":
			# 魏延大刀:宽直刃(与偃月弯刃区分,03 §3.3)
			e_limb(img, k, 16, 92, 84, 20, 3.4, wood)
		# --- 03 第三批(05 §4)---
		"hook_halberd":
			# 张辽钩镰戟(05 §4):长杆
			e_limb(img, k, 16, 92, 86, 16, 3.2, wood)
		"broad_blade":
			# 许褚大刀(05 §4):长杆,宽刃前层
			e_limb(img, k, 16, 92, 84, 22, 3.6, wood)
		"twin_daggers":
			# 甘宁双匕(05 §4):两短杆
			e_limb(img, k, 24, 80, 62, 44, 2.6, wood)
			e_limb(img, k, 78, 74, 92, 58, 2.6, wood)
		"slim_sword":
			# 周瑜细剑(05 §4):单杆
			e_limb(img, k, 20, 88, 84, 22, 2.6, wood)
		"round_fan":
			# 貂蝉团扇(05 §4):无背杆
			pass
		"bow":
			e_poly(img, p, g_wedge(56, 60, 70, 34, 8.4, 7.0), mixc(ink, gold, 0.25))
			for i in 3:
				e_line(img, k, 62 + float(i) * 1.8, 40, 60 + float(i) * 2.6, 28, 1.5, ink)
		_:
			pass

# ---- 兵器头 / 手持物(前层)

func _weapon_front(img: Image, p: Dictionary, wp: String) -> void:
	var k := float(p["k"])
	var ink: Color = p["ink"]
	var gold: Color = p["gold"]
	var cin: Color = p["cin"]
	var paper: Color = p["paper"]
	var steel: Color = p["steel"]
	match wp:
		"twin_swords":
			for sgn in [-1.0, 1.0]:
				var s := float(sgn)
				var hx := 47.0 + 25.0 * s
				e_poly(img, p, g_leaf(hx, 68, hx + 16 * s, 24, 7.4), steel)
				e_rect(img, k, hx - 4.4, 64.5, 8.8, 3.0, gold)
				e_cir(img, k, hx - 1 * s, 70, 2.4, mixc(ink, gold, 0.5), false)
		"guandao":
			# 青龙偃月刀:大刃沿杆轴斜出 + 背齿 + 红缨 + 吞口
			e_poly(img, p, g_crescent_taper(80, 18, 19.0, 9.5, 19.0, -1.15, 1.05), steel)
			e_poly(img, p, g_leaf(85, 12, 92, 3, 4.4), steel)
			e_poly(img, p, g_leaf(74, 16, 66, 10, 3.6), steel)
			e_cir(img, k, 82, 24, 4.0, gold)
			e_cir(img, k, 82, 24, 1.8, cin, false)
			for i in 3:
				e_bezier(img, k, 82, 28, 78 + float(i) * 3, 36, 76 + float(i) * 4, 46, 2.2, 0.6, cin)
		"serpent_spear":
			# 丈八蛇矛:波浪矛头
			e_poly(img, p, g_serrated(80, 24, 92, 2, 7.0, 2.4, 2.4), steel)
			e_cir(img, k, 80, 27, 3.4, cin)
			e_bezier(img, k, 80, 30, 75, 38, 74, 48, 2.2, 0.6, cin)
		"tiger_spear":
			# 赵云虎头枪:柳叶尖 + 虎头吞口 + 双缨
			e_poly(img, p, g_leaf(84, 20, 94, 2, 7.4), steel)
			e_cir(img, k, 82, 24, 5.2, gold)
			e_cir(img, k, 80.2, 23.0, 1.2, ink, false)
			e_cir(img, k, 83.8, 23.0, 1.2, ink, false)
			e_arc(img, k, 82, 25.5, 2.6, 0.4, PI - 0.4, 1.3, ink)
			e_bezier(img, k, 82, 29, 77, 36, 75, 46, 2.4, 0.7, cin)
			e_bezier(img, k, 82, 29, 87, 36, 89, 46, 2.4, 0.7, cin)
		"halberd":
			# 方天画戟:中尖 + 双月牙耳 + 金珠 + 缨
			e_poly(img, p, g_leaf(86, 24, 96, 4, 6.4), steel)
			e_poly(img, p, g_crescent_lens(86, 22, 12.5, 5.4, -0.85, 0.85), steel)
			e_poly(img, p, g_crescent_lens(86, 22, 12.5, 5.4, PI - 0.85, PI + 0.85), steel)
			e_cir(img, k, 86, 28, 2.8, gold)
			e_bezier(img, k, 86, 31, 81, 38, 80, 48, 2.2, 0.6, cin)
		"feather_fan":
			e_poly(img, p, g_pie(74, 58, 20.0, -PI * 1.02, -PI * 0.02), lighten(paper, 0.35))
			for i in 6:
				var a := -PI * 1.02 + float(i) * (PI * 1.0 / 5.0)
				e_line(img, k, 74, 58, 74 + cos(a) * 19, 58 + sin(a) * 19, 1.3, darken(C("spring_green"), 0.12))
			e_limb(img, k, 76, 64, 78, 54, 2.8, mixc(ink, gold, 0.3))
		"gourd":
			e_line(img, k, 24, 68, 24, 62, 1.8, ink)
			e_cir(img, k, 25, 60, 3.4, mixc(gold, cin, 0.32))
			e_cir(img, k, 25, 67, 5.2, mixc(gold, cin, 0.32))
			e_rect(img, k, 23, 55, 4.0, 2.2, ink)
			e_poly(img, p, g_wedge(62, 70, 78, 62, 5.4, 5.4), mixc(paper, gold, 0.4))
			e_line(img, k, 63, 68, 77, 63, 1.1, darken(paper, 0.4))
		"cleaver":
			e_poly(img, p, g_wedge(76, 62, 94, 34, 7.0, 2.0), steel)
			e_line(img, k, 74, 66, 79, 60, 3.0, mixc(ink, gold, 0.35))
			e_cir(img, k, 73, 68, 2.2, gold, false)
		"bow":
			e_arc(img, k, 66, 56, 17.0, -PI * 0.42, PI * 0.42, 3.4, mixc(ink, gold, 0.25))
			e_line(img, k, 66 + cos(-PI * 0.42) * 17, 56 + sin(-PI * 0.42) * 17, 66 + cos(PI * 0.42) * 17, 56 + sin(PI * 0.42) * 17, 1.4, paper)
			e_poly(img, p, g_wedge(52, 56, 84, 56, 2.2, 1.2), mixc(ink, gold, 0.4))
			e_poly(img, p, g_leaf(84, 56, 90, 56, 3.4), steel)
		"hammer":
			e_rect(img, k, 72, 18, 22, 17, mixc(ink, gold, 0.38))
			e_rect(img, k, 72, 22, 22, 2.4, darken(ink, 0.25))
			e_rect(img, k, 72, 29, 22, 2.4, darken(ink, 0.25))
			e_poly(img, p, g_leaf(94, 22, 98, 12, 5.0), steel)
		"spear_shield":
			e_poly(img, p, g_leaf(86, 22, 96, 2, 6.6), steel)
			e_cir(img, k, 86, 25, 3.0, cin)
			e_cir(img, k, 22, 62, 13.5, mixc(C("dark_brown"), C("gold"), 0.34))
			e_arc(img, k, 22, 62, 10.8, 0, TAU, 2.2, mixc(C("huangjin"), C("dark_brown"), 0.35))
			e_cir(img, k, 22, 62, 4.4, gold)
			e_cir(img, k, 22, 62, 1.8, cin, false)
			for i in 4:
				var a := PI * 0.25 + float(i) * PI * 0.5
				e_cir(img, k, 22 + cos(a) * 8.2, 62 + sin(a) * 8.2, 1.3, ink, false)
		"great_axe":
			# 华雄双刃大斧:杆顶双月牙 + 上尖 + 红缨
			e_poly(img, p, g_leaf(84, 26, 92, 8, 6.4), steel)
			e_poly(img, p, g_crescent_lens(84, 32, 15.5, 8.0, -0.9, 0.9), steel)
			e_poly(img, p, g_crescent_lens(84, 32, 15.5, 8.0, PI - 0.9, PI + 0.9), steel)
			e_cir(img, k, 84, 32, 4.0, cin)
			e_bezier(img, k, 84, 36, 79, 44, 78, 54, 2.4, 0.8, cin)
		"wide_spear":
			# 马超长枪:加宽锥头 + 金箍 + 红缨(枪头比赵云宽,03 §3.1)
			e_poly(img, p, g_leaf(82, 22, 94, 2, 9.0), steel)
			e_cir(img, k, 80, 26, 4.4, gold)
			e_bezier(img, k, 81, 30, 77, 38, 75, 47, 2.4, 0.7, cin)
		"great_bow":
			# 黄忠大弓:大弧 + 弦 + 搭箭(前层),赤铜弓身(03 §3.2)
			e_arc(img, k, 66, 56, 19.0, -PI * 0.46, PI * 0.46, 3.8, mixc(C("cinnabar"), gold, 0.4))
			e_line(img, k, 66 + cos(-PI * 0.46) * 19, 56 + sin(-PI * 0.46) * 19, 66 + cos(PI * 0.46) * 19, 56 + sin(PI * 0.46) * 19, 1.4, paper)
			e_poly(img, p, g_wedge(52, 56, 86, 56, 2.4, 1.2), mixc(ink, gold, 0.4))
			e_poly(img, p, g_leaf(86, 56, 93, 56, 3.6), steel)
		"straight_blade":
			# 魏延大刀:宽直刃 box 意象(无弯,与偃月区分)+ 金格 + 红缨(03 §3.3)
			e_poly(img, p, g_wedge(80, 28, 92, 8, 9.5, 7.0), steel)
			e_rect(img, k, 76, 30, 8.0, 3.4, gold)
			e_bezier(img, k, 78, 34, 74, 42, 72, 52, 2.4, 0.8, cin)
		# --- 03 第三批(05 §4)---
		"hook_halberd":
			# 张辽钩镰戟(05 §4):单侧弯钩(下勾镰)+ 戟锋 + 红缨
			e_poly(img, p, g_crescent_lens(84, 24, 13.0, 5.0, -0.75, 0.85), steel)
			e_poly(img, p, g_leaf(84, 24, 93, 8, 4.6), steel)
			e_cir(img, k, 84, 28, 3.0, gold)
			e_bezier(img, k, 84, 31, 80, 38, 78, 47, 2.2, 0.6, cin)
		"broad_blade":
			# 许褚大刀(05 §4):超宽直刃(比魏延 9.5 更宽)+ 金格
			e_poly(img, p, g_wedge(80, 28, 94, 6, 12.0, 8.0), steel)
			e_rect(img, k, 75, 30, 9.0, 3.6, gold)
			e_bezier(img, k, 78, 34, 74, 42, 72, 52, 2.4, 0.8, cin)
		"twin_daggers":
			# 甘宁双匕(05 §4):双手各一短宽刃 + 红柄缨
			for pair in [[24.0, 80.0, 44.0, 62.0], [78.0, 74.0, 62.0, 92.0]]:
				e_poly(img, p, g_wedge(pair[0], pair[1], pair[2], pair[3], 5.0, 1.6), steel)
				e_line(img, k, pair[2], pair[3], (pair[0] + pair[2]) * 0.5, (pair[1] + pair[3]) * 0.5, 2.2, darken(C("dark_brown"), 0.2))
				e_cir(img, k, pair[0], pair[1], 2.2, cin)
		"slim_sword":
			# 周瑜细剑(05 §4):细长直刃 + 金格
			e_poly(img, p, g_wedge(80, 26, 94, 4, 4.6, 1.2), steel)
			e_rect(img, k, 76, 30, 7.0, 3.0, gold)
			e_cir(img, k, 79, 32, 2.0, mixc(ink, gold, 0.4), false)
		"round_fan":
			# 貂蝉团扇(05 §4):圆扁片 paper 色 + 扇柄 + 金缘
			e_cir(img, k, 26, 62, 13.0, mixc(paper, Color.WHITE, 0.30))
			e_arc(img, k, 26, 62, 12.0, 0, TAU, 1.6, gold)
			e_line(img, k, 34, 74, 40, 84, 2.4, mixc(C("dark_brown"), C("gold"), 0.4))
			e_bezier(img, k, 30, 50, 26, 58, 22, 66, 1.2, 0.5, C("spring_green"))
		_:
			pass

# ---------------------------------------------------------------- 特效

func _gen_fx(list: Array) -> void:
	var brown := C("dark_brown")
	var gold := C("gold")
	var green := C("spring_green")
	var deep := C("deep_green")
	var paper := C("paper")
	# slash 128:扇形渐隐斩击
	var img := new_img(128, 128)
	var white := Color(paper.r, paper.g, paper.b, 0.95)
	arc(img, 18, 110, 52, -1.35, -0.25, 9, white)
	var mid := Color(paper.r, paper.g, paper.b, 0.55)
	arc(img, 18, 110, 63, -1.3, -0.3, 7, mid)
	var faint := Color(paper.r, paper.g, paper.b, 0.30)
	arc(img, 18, 110, 74, -1.25, -0.35, 5, faint)
	save(img, "fx/slash.png", list)
	# ring 128:圆环冲击(金)
	img = new_img(128, 128)
	arc(img, 64, 64, 50, 0, TAU, 8, Color(gold.r, gold.g, gold.b, 0.9))
	arc(img, 64, 64, 40, 0, TAU, 5, Color(gold.r, gold.g, gold.b, 0.4))
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		fill_circle(img, 64 + cos(a) * 57, 64 + sin(a) * 57, 4, Color(gold.r, gold.g, gold.b, 0.8))
	save(img, "fx/ring.png", list)
	# heal 128:青绿叶片
	img = new_img(128, 128)
	oval(img, 64, 42, 13, 24, green, deep)
	oval(img, 42, 76, 13, 24, green, deep)
	oval(img, 86, 76, 13, 24, green, deep)
	thick_line(img, 64, 96, 64, 112, 4, deep)
	save(img, "fx/heal.png", list)
	# arrow 64:箭形(向上)
	img = new_img(64, 64)
	thick_line(img, 32, 54, 32, 22, 4, brown)
	thick_line(img, 32, 8, 20, 24, 5, brown)
	thick_line(img, 32, 8, 44, 24, 5, brown)
	thick_line(img, 32, 54, 22, 44, 4, brown)
	thick_line(img, 32, 54, 42, 44, 4, brown)
	fill_circle(img, 32, 10, 4, gold)
	save(img, "fx/arrow.png", list)

# ---------------------------------------------------------------- 图标

func _gen_icons(list: Array) -> void:
	var brown := C("dark_brown")
	var gold := C("gold")
	var blade := lighten(C("gold"), 0.35)
	var green := C("spring_green")
	var deep := C("deep_green")
	var cinnabar := C("cinnabar")
	var paper := C("paper")
	# 遗物图标 ×8(128)
	var img := new_img(128, 128)
	# 青釭剑
	img = new_img(128, 128)
	thick_line(img, 64, 20, 64, 90, 7, blade)
	fill_circle(img, 64, 18, 6, blade)
	fill_rect(img, 46, 90, 36, 9, gold)
	thick_line(img, 64, 99, 64, 112, 6, brown)
	fill_circle(img, 64, 114, 5, gold)
	save(img, "icons/relics/qinggang_sword.png", list)
	# 赤兔马
	img = new_img(128, 128)
	oval(img, 62, 72, 30, 18, cinnabar, brown)
	thick_line(img, 84, 66, 100, 44, 9, cinnabar)
	disc(img, 102, 42, 10, cinnabar, brown)
	for i in 4:
		var lx := 44.0 + 13.0 * float(i)
		thick_line(img, lx, 86, lx + (2.0 if i % 2 == 0 else -2.0), 112, 5, darken(cinnabar, 0.2))
	arc(img, 36, 66, 14, PI * 0.5, PI * 1.4, 5, darken(cinnabar, 0.2))
	save(img, "icons/relics/chitu_horse.png", list)
	# 太平要术(卷轴)
	img = new_img(128, 128)
	fill_rect(img, 32, 34, 12, 60, deep)
	fill_rect(img, 84, 34, 12, 60, deep)
	fill_rect(img, 44, 40, 40, 48, paper)
	for i in 3:
		thick_line(img, 50, 50.0 + 12.0 * float(i), 78, 50.0 + 12.0 * float(i), 3, brown)
	save(img, "icons/relics/taiping_yaoshu.png", list)
	# 玉玺
	img = new_img(128, 128)
	oval(img, 64, 38, 16, 11, cinnabar, brown)
	fill_rect(img, 40, 48, 48, 44, cinnabar)
	fill_rect(img, 40, 48, 48, 6, brown)
	fill_rect(img, 40, 86, 48, 6, brown)
	fill_rect(img, 40, 48, 6, 44, brown)
	fill_rect(img, 82, 48, 6, 44, brown)
	save(img, "icons/relics/yuxi.png", list)
	# 孙子兵法(书)
	img = new_img(128, 128)
	fill_rect(img, 34, 38, 60, 52, green)
	fill_rect(img, 34, 38, 60, 6, deep)
	fill_rect(img, 34, 84, 60, 6, deep)
	fill_rect(img, 34, 38, 6, 52, deep)
	fill_rect(img, 88, 38, 6, 52, deep)
	for i in 3:
		thick_line(img, 48, 52.0 + 12.0 * float(i), 80, 52.0 + 12.0 * float(i), 3, paper)
	save(img, "icons/relics/sunzi_bingfa.png", list)
	# 连弩图(弩)
	img = new_img(128, 128)
	arc(img, 64, 58, 36, -0.35, PI + 0.35, 6, brown)
	thick_line(img, 64, 34, 64, 108, 7, brown)
	thick_line(img, 30, 58, 98, 58, 3, brown)
	thick_line(img, 64, 58, 64, 26, 4, blade)
	fill_circle(img, 64, 24, 5, blade)
	save(img, "icons/relics/liannu_tu.png", list)
	# 双股剑
	img = new_img(128, 128)
	thick_line(img, 36, 34, 92, 94, 6, blade)
	thick_line(img, 92, 34, 36, 94, 6, blade)
	fill_circle(img, 52, 50, 5, gold)
	fill_circle(img, 76, 50, 5, gold)
	save(img, "icons/relics/shuanggu_jian.png", list)
	# 青囊书(药囊)
	img = new_img(128, 128)
	disc(img, 64, 44, 10, gold, brown)
	oval(img, 64, 82, 32, 26, green, brown)
	thick_line(img, 52, 60, 52, 72, 4, paper)
	thick_line(img, 76, 60, 76, 72, 4, paper)
	fill_circle(img, 64, 78, 6, paper)
	save(img, "icons/relics/qingnang_shu.png", list)
	# 技能图标 ×7(96)
	# 仁德之泽:盾
	img = new_img(96, 96)
	oval(img, 48, 42, 24, 28, green, deep)
	thick_line(img, 48, 22, 48, 62, 5, paper)
	thick_line(img, 32, 40, 64, 40, 5, paper)
	arc(img, 48, 84, 16, PI + 0.3, TAU - 0.3, 5, deep)
	save(img, "icons/skills/rende_ze.png", list)
	# 青龙偃月·扫:新月
	img = new_img(96, 96)
	arc(img, 40, 48, 30, -2.3, 0.7, 9, blade)
	thick_line(img, 58, 24, 74, 76, 5, brown)
	save(img, "icons/skills/qinglong_sweep.png", list)
	# 当阳桥吼:声波
	img = new_img(96, 96)
	disc(img, 34, 48, 13, cinnabar, brown)
	arc(img, 34, 48, 24, -0.8, 0.8, 5, cinnabar)
	arc(img, 34, 48, 36, -0.8, 0.8, 5, cinnabar)
	arc(img, 34, 48, 48, -0.8, 0.8, 4, cinnabar)
	save(img, "icons/skills/dangyang_roar.png", list)
	# 七进七出:穿阵
	img = new_img(96, 96)
	for i in 3:
		disc(img, 28.0 + 20.0 * float(i), 68.0 - 20.0 * float(i), 9, paper, deep)
	thick_line(img, 18, 78, 74, 22, 5, cinnabar)
	fill_circle(img, 76, 20, 6, cinnabar)
	save(img, "icons/skills/qijin_qichu.png", list)
	# 借东风:风旋
	img = new_img(96, 96)
	arc(img, 42, 44, 24, -2.6, 0.9, 6, green)
	arc(img, 60, 58, 17, -2.6, 0.9, 5, deep)
	fill_circle(img, 62, 26, 5, deep)
	fill_circle(img, 44, 74, 4, green)
	save(img, "icons/skills/jie_dongfeng.png", list)
	# 妙手回春:十字
	img = new_img(96, 96)
	disc(img, 48, 48, 30, paper, deep)
	thick_line(img, 48, 30, 48, 66, 11, green)
	thick_line(img, 30, 48, 66, 48, 11, green)
	save(img, "icons/skills/miaoshou.png", list)
	# 方天乱舞:戟
	img = new_img(96, 96)
	thick_line(img, 48, 18, 48, 80, 6, gold)
	arc(img, 48, 26, 16, PI * 0.2, PI * 0.8, 5, blade)
	arc(img, 48, 26, 16, -PI * 0.8, -PI * 0.2, 5, blade)
	fill_circle(img, 48, 14, 5, blade)
	save(img, "icons/skills/fangtian_wu.png", list)
	# 军资铜钱(64)
	img = new_img(64, 64)
	disc(img, 32, 32, 26, gold, darken(gold, 0.35))
	arc(img, 32, 32, 18, 0, TAU, 3, darken(gold, 0.3))
	fill_rect(img, 25, 25, 14, 14, darken(gold, 0.5))
	fill_rect(img, 25, 25, 14, 3, brown)
	fill_rect(img, 25, 36, 14, 3, brown)
	fill_rect(img, 25, 25, 3, 14, brown)
	fill_rect(img, 36, 25, 3, 14, brown)
	save(img, "icons/coin.png", list)

# ---------------------------------------------------------------- UI

func _gen_ui(list: Array) -> void:
	var paper := C("paper")
	var paper_dark := C("paper_dark")
	var brown := C("dark_brown")
	var deep := C("deep_green")
	var gold := C("gold")
	var cinnabar := C("cinnabar")
	# panel_paper 128:九宫格宣纸面板
	var img := new_img(128, 128)
	img.fill(paper)
	fill_rect(img, 0, 0, 128, 4, brown)
	fill_rect(img, 0, 124, 128, 4, brown)
	fill_rect(img, 0, 0, 4, 128, brown)
	fill_rect(img, 124, 0, 4, 128, brown)
	for i in 8:
		fill_circle(img, 8 + 16 * i, 6, 2, paper)
	fill_rect(img, 10, 10, 108, 3, paper_dark)
	fill_rect(img, 10, 115, 108, 3, paper_dark)
	save(img, "ui/panel_paper.png", list)
	# scroll_bg 1024×256:卷轴展开底(两端轴头)
	img = new_img(1024, 256)
	img.fill(paper)
	rng.seed = seed_for("ui/scroll_bg.png")
	for i in 26:
		var ly := rng.randf_range(24, 232)
		fill_rect(img, 30, ly, 964, rng.randf_range(1.5, 3.5), Color(paper_dark.r, paper_dark.g, paper_dark.b, 0.5))
	# 左右轴杆 + 轴头
	for rx in [14, 1010]:
		fill_rect(img, rx - 12, 18, 24, 220, deep)
		fill_rect(img, rx - 12, 18, 24, 6, brown)
		fill_rect(img, rx - 12, 232, 24, 6, brown)
		fill_rect(img, rx - 6, 14, 12, 8, gold)
		fill_rect(img, rx - 6, 234, 12, 8, gold)
	save(img, "ui/scroll_bg.png", list)
	# btn_seal 96:朱印按钮
	img = new_img(96, 96)
	var seal := Color(cinnabar.r, cinnabar.g, cinnabar.b, 0.92)
	fill_ellipse(img, 20, 20, 12, 12, seal)
	fill_ellipse(img, 76, 20, 12, 12, seal)
	fill_ellipse(img, 20, 76, 12, 12, seal)
	fill_ellipse(img, 76, 76, 12, 12, seal)
	fill_rect(img, 20, 8, 56, 80, seal)
	fill_rect(img, 8, 20, 80, 56, seal)
	fill_rect(img, 16, 16, 64, 4, Color(paper.r, paper.g, paper.b, 0.65))
	fill_rect(img, 16, 76, 64, 4, Color(paper.r, paper.g, paper.b, 0.65))
	fill_rect(img, 16, 16, 4, 64, Color(paper.r, paper.g, paper.b, 0.65))
	fill_rect(img, 76, 16, 4, 64, Color(paper.r, paper.g, paper.b, 0.65))
	save(img, "ui/btn_seal.png", list)
	# vignette 512:边缘渐晕(深褐向外)
	img = new_img(512, 512)
	for y in 512:
		for x in 512:
			var d := Vector2(x - 255.5, y - 255.5).length() / 256.0
			var t := clampf((d - 0.55) / 0.45, 0.0, 1.0)
			var a := pow(t, 1.6) * 0.5
			if a > 0.003:
				img.set_pixel(x, y, Color(brown.r, brown.g, brown.b, a))
	save(img, "ui/vignette.png", list)

# ---------------------------------------------------------------- 工程图标

func _gen_icon_png(list: Array) -> void:
	rng.seed = seed_for("icon.png")
	var img := new_img(256, 256)
	var brown := C("dark_brown")
	var paper := C("paper")
	disc(img, 128, 128, 108, paper, brown, 6)
	var peach := mixc(C("cinnabar"), Color.WHITE, 0.25)
	disc(img, 108, 140, 42, peach, brown)
	disc(img, 148, 140, 42, peach, brown)
	fill_ellipse(img, 128, 96, 34, 26, peach)
	fill_ellipse(img, 128, 64, 13, 24, C("spring_green"))
	thick_line(img, 128, 52, 128, 36, 5, brown)
	var abs_path := ProjectSettings.globalize_path("res://icon.png")
	var err := img.save_png(abs_path)
	if err == OK:
		print("  [gen] icon.png(根目录,不入 manifest)")
	else:
		printerr("[gen_textures] icon.png 保存失败 err=%d" % err)

# ---------------------------------------------------------------- manifest

func _write_manifest(list: Array) -> void:
	var manifest := {
		"generator": "tools/gen_textures.gd",
		"seed": GLOBAL_SEED,
		"count": list.size(),
		"icon": "res://icon.png",
		"files": list,
	}
	var abs_path := ProjectSettings.globalize_path(TEX_ROOT + "manifest.json")
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
