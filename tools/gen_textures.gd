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

func _robe_color(name: String) -> Color:
	match name:
		"deep_green": return C("deep_green")
		"dark_green": return darken(C("deep_green"), 0.30)
		"spring_green": return C("spring_green")
		"white": return lighten(C("paper"), 0.55)
		"paper": return mixc(C("paper"), C("paper_dark"), 0.6)
		"cinnabar": return C("cinnabar")
		_: return C("spring_green")

func _gen_units(list: Array) -> void:
	# 7 武将 320×320(01 §11:识别物两两区分)
	_gen_hero_stand(list, "liubei", "deep_green", "twin_swords")
	_gen_hero_stand(list, "guanyu", "spring_green", "guandao")
	_gen_hero_stand(list, "zhangfei", "dark_green", "spear_zhang")
	_gen_hero_stand(list, "zhaoyun", "white", "silver_spear")
	_gen_hero_stand(list, "zhuge", "paper", "fan")
	_gen_hero_stand(list, "huatuo", "spring_green", "gourd")
	_gen_hero_stand(list, "lvbu", "cinnabar", "halberd")
	# 敌兵 256×256(黄巾头巾区分,力士体格 ×1.4)
	_gen_enemy_stand(list, "huangjin_zu", "knife", false, false)
	_gen_enemy_stand(list, "huangjin_gongshou", "bow", false, false)
	_gen_enemy_stand(list, "huangjin_lishi", "hammer", true, false)
	_gen_enemy_stand(list, "xiliang_qinwei", "spear_x", false, true)
	# Boss 448×448(面甲 + 大斧,体格 ×1.5)
	_gen_boss(list)

## Q 版两头身武将立牌(大圆头约身高 1/2 + 小椭圆身 + 简笔四肢 + 识别物 + 2px 描边)
func _gen_hero_stand(list: Array, id: String, robe_tok: String, item: String) -> void:
	rng.seed = seed_for("units/%s.png" % id)
	var img := new_img(320, 320)
	var brown := C("dark_brown")
	var skin := mixc(C("gold"), Color.WHITE, 0.55)
	var robe := _robe_color(robe_tok)
	var robe_dark := darken(robe, 0.30)
	var blade := lighten(C("gold"), 0.35)
	var green := C("spring_green")
	# 兵器长杆(画在身体后层)
	if item in ["guandao", "spear_zhang", "silver_spear", "halberd"]:
		thick_line(img, 244, 44, 260, 302, 7 if item == "halberd" else 5, brown)
	# 腿脚
	fill_rect(img, 143, 266, 13, 34, robe_dark)
	fill_rect(img, 164, 266, 13, 34, robe_dark)
	fill_ellipse(img, 149, 302, 12, 6, brown)
	fill_ellipse(img, 171, 302, 12, 6, brown)
	# 身体(椭圆袍)+ 描边
	oval(img, 160, 212, 54, 62, robe, brown)
	# 腰带
	fill_rect(img, 112, 236, 96, 10, robe_dark)
	fill_circle(img, 160, 241, 6, C("gold"))
	# 手臂 + 手
	oval(img, 108, 206, 15, 32, robe_dark, brown)
	oval(img, 212, 206, 15, 32, robe_dark, brown)
	disc(img, 104, 240, 9, skin, brown)
	disc(img, 216, 240, 9, skin, brown)
	# 识别物(手持层)
	_gen_item(img, item, blade, brown, skin)
	# 头(大圆,约占身高一半)
	disc(img, 160, 106, 70, skin, brown)
	# 发顶
	fill_ellipse(img, 160, 56, 58, 24, brown)
	if item == "fan":
		# 诸葛纶巾:平顶巾
		fill_ellipse(img, 160, 52, 44, 20, C("deep_green"))
		fill_rect(img, 138, 26, 44, 26, C("deep_green"))
		fill_rect(img, 138, 46, 44, 5, C("gold"))
	# 吕布雉鸡翎
	if item == "halberd":
		thick_line(img, 132, 44, 96, 6, 6, C("cinnabar"))
		thick_line(img, 188, 44, 224, 6, 6, C("cinnabar"))
		fill_circle(img, 96, 6, 5, C("gold"))
		fill_circle(img, 224, 6, 5, C("gold"))
	# 脸:眼/眉/嘴/腮
	fill_circle(img, 136, 112, 5, brown)
	fill_circle(img, 184, 112, 5, brown)
	thick_line(img, 126, 98, 144, 96, 3, brown)
	thick_line(img, 176, 96, 194, 98, 3, brown)
	arc(img, 160, 126, 16, 0.4, PI - 0.4, 3, brown)
	var blush := Color(C("cinnabar").r, C("cinnabar").g, C("cinnabar").b, 0.18)
	fill_circle(img, 120, 130, 8, blush)
	fill_circle(img, 200, 130, 8, blush)
	# 脖领围巾
	fill_rect(img, 138, 172, 44, 12, green)
	# 长髯(关羽)/虬髯(张飞)
	if item == "guandao":
		oval(img, 160, 182, 26, 40, brown, brown, 0)
		fill_ellipse(img, 160, 214, 18, 26, brown)
	elif item == "spear_zhang":
		fill_circle(img, 138, 172, 16, brown)
		fill_circle(img, 182, 172, 16, brown)
		fill_circle(img, 160, 186, 18, brown)
		fill_ellipse(img, 160, 212, 16, 22, brown)
	# 青龙偃月刀刃 / 蛇矛头 / 方天戟刃(上层)
	_gen_item_top(img, item, blade, brown)
	save(img, "units/%s.png" % id, list)

func _gen_item(img: Image, item: String, blade: Color, brown: Color, skin: Color) -> void:
	var gold := C("gold")
	match item:
		"twin_swords":
			# 刘备双股剑:双手各持一柄
			thick_line(img, 104, 238, 62, 156, 6, blade)
			thick_line(img, 216, 238, 258, 156, 6, blade)
			fill_circle(img, 92, 208, 6, gold)
			fill_circle(img, 228, 208, 6, gold)
			thick_line(img, 104, 238, 92, 208, 5, brown)
			thick_line(img, 216, 238, 228, 208, 5, brown)
		"fan":
			# 诸葛亮羽扇
			oval(img, 96, 186, 22, 36, C("spring_green"), brown)
			for i in 5:
				var t := -0.8 + 0.4 * float(i)
				thick_line(img, 96, 218, 96 + sin(t) * 34, 186 - cos(t) * 32, 2, C("paper_dark"))
			thick_line(img, 104, 240, 96, 220, 4, brown)
		"gourd":
			# 华佗药葫芦(腰间)
			disc(img, 218, 246, 11, mixc(C("gold"), C("cinnabar"), 0.35), brown)
			disc(img, 218, 228, 14, mixc(C("gold"), C("cinnabar"), 0.35), brown)
			thick_line(img, 212, 214, 224, 214, 3, brown)
		_:
			pass

func _gen_item_top(img: Image, item: String, blade: Color, brown: Color) -> void:
	var gold := C("gold")
	match item:
		"guandao":
			# 青龙偃月:杆顶新月刃
			arc(img, 244, 54, 26, -2.6, 0.2, 8, blade)
			fill_circle(img, 244, 44, 6, blade)
			thick_line(img, 234, 66, 244, 54, 5, blade)
		"spear_zhang":
			# 丈八蛇矛:波浪矛头
			fill_circle(img, 252, 46, 6, blade)
			fill_circle(img, 245, 34, 6, blade)
			fill_circle(img, 253, 22, 6, blade)
			thick_line(img, 248, 52, 252, 44, 5, blade)
		"silver_spear":
			fill_circle(img, 250, 36, 7, blade)
			thick_line(img, 242, 48, 250, 38, 4, blade)
			thick_line(img, 258, 48, 250, 38, 4, blade)
		"halberd":
			# 方天画戟:两侧新月
			arc(img, 252, 52, 22, PI * 0.15, PI * 0.95, 6, blade)
			arc(img, 252, 52, 22, -PI * 0.95, -PI * 0.15, 6, blade)
			fill_circle(img, 252, 36, 6, gold)
		_:
			pass

## 敌兵 256×256:黄巾头巾 + 兵器差异
func _gen_enemy_stand(list: Array, id: String, weapon: String, big: bool, elite: bool) -> void:
	rng.seed = seed_for("units/%s.png" % id)
	var img := new_img(256, 256)
	var brown := C("dark_brown")
	var skin := mixc(C("gold"), Color.WHITE, 0.55)
	var cloth := darken(C("spring_green"), 0.15)
	var cloth_dark := darken(cloth, 0.30)
	var band := C("cinnabar") if elite else C("huangjin")
	var head_r := 54.0 if big else 46.0
	var head_y := 84.0 if big else 88.0
	var body_rx := 48.0 if big else 38.0
	var body_ry := 52.0 if big else 44.0
	var body_y := 168.0 if big else 164.0
	# 腿
	fill_rect(img, 113, 212, 12, 28, cloth_dark)
	fill_rect(img, 131, 212, 12, 28, cloth_dark)
	fill_ellipse(img, 119, 242, 10, 5, brown)
	fill_ellipse(img, 137, 242, 10, 5, brown)
	# 身体
	oval(img, 128, body_y, body_rx, body_ry, cloth, brown)
	# 手臂
	oval(img, 128 - body_rx + 2, body_y - 6, 12, 26, cloth_dark, brown)
	oval(img, 128 + body_rx - 2, body_y - 6, 12, 26, cloth_dark, brown)
	disc(img, 128 - body_rx - 2, body_y + 22, 8, skin, brown)
	disc(img, 128 + body_rx + 2, body_y + 22, 8, skin, brown)
	# 头
	disc(img, 128, head_y, head_r, skin, brown)
	# 黄巾/朱巾头巾 + 结
	fill_rect(img, 128 - head_r, head_y - head_r * 0.55, head_r * 2.0, head_r * 0.42, band)
	fill_circle(img, 128 + head_r - 4, head_y - head_r * 0.35, 8, band)
	fill_rect(img, 128 + head_r - 8, head_y - head_r * 0.2, 6, 18, band)
	# 脸
	fill_circle(img, 128 - 18, head_y + 8, 4, brown)
	fill_circle(img, 128 + 18, head_y + 8, 4, brown)
	arc(img, 128, head_y + 22, 10, 0.5, PI - 0.5, 3, brown)
	# 兵器
	var blade := lighten(C("gold"), 0.3)
	match weapon:
		"knife":
			thick_line(img, 168, 190, 200, 150, 5, blade)
			fill_circle(img, 172, 186, 5, brown)
		"bow":
			arc(img, 78, 158, 38, -1.1, 1.1, 5, brown)
			thick_line(img, 84, 122, 84, 194, 2, C("paper_dark"))
			thick_line(img, 84, 158, 108, 158, 3, C("paper_dark"))
		"hammer":
			thick_line(img, 168, 196, 196, 120, 6, brown)
			fill_rect(img, 182, 84, 40, 34, mixc(brown, C("gold"), 0.4))
			fill_rect(img, 182, 84, 40, 6, brown)
		"spear_x":
			thick_line(img, 170, 220, 182, 60, 5, brown)
			fill_circle(img, 182, 54, 7, blade)
			# 小圆盾
			oval(img, 84, 172, 18, 24, mixc(C("paper"), Color.WHITE, 0.3), brown)
	if big:
		# 力士胸带
		thick_line(img, 104, 150, 152, 196, 6, brown)
		thick_line(img, 152, 150, 104, 196, 6, brown)
	save(img, "units/%s.png" % id, list)

## 华雄 448×448:面甲 + 大斧,体格 ×1.5
func _gen_boss(list: Array) -> void:
	var id := "huaxiong"
	rng.seed = seed_for("units/%s.png" % id)
	var img := new_img(448, 448)
	var brown := C("dark_brown")
	var skin := mixc(C("gold"), Color.WHITE, 0.55)
	var armor := darken(C("deep_green"), 0.35)
	var armor_dark := darken(armor, 0.3)
	var blade := lighten(C("gold"), 0.3)
	# 大斧长杆(后层)
	thick_line(img, 356, 56, 382, 424, 12, brown)
	# 腿
	fill_rect(img, 196, 380, 22, 52, armor_dark)
	fill_rect(img, 232, 380, 22, 52, armor_dark)
	fill_ellipse(img, 207, 434, 18, 9, brown)
	fill_ellipse(img, 243, 434, 18, 9, brown)
	# 身体甲
	oval(img, 224, 306, 78, 92, armor, brown)
	# 肩甲
	oval(img, 146, 276, 26, 30, armor_dark, brown)
	oval(img, 302, 276, 26, 30, armor_dark, brown)
	fill_rect(img, 158, 296, 132, 14, C("cinnabar"))
	# 手臂
	oval(img, 130, 296, 18, 40, armor_dark, brown)
	oval(img, 318, 296, 18, 40, armor_dark, brown)
	disc(img, 126, 340, 12, skin, brown)
	disc(img, 322, 340, 12, skin, brown)
	# 大斧刃(新月大弧)
	arc(img, 366, 76, 56, -2.9, 0.3, 16, blade)
	fill_circle(img, 360, 52, 10, blade)
	# 头
	disc(img, 224, 148, 92, skin, brown)
	# 盔
	fill_ellipse(img, 224, 84, 82, 34, armor)
	arc(img, 224, 70, 60, PI + 0.5, TAU - 0.5, 8, C("cinnabar"))
	# 面甲:遮上半脸,留金色眼孔
	fill_rect(img, 150, 116, 148, 52, darken(armor, 0.4))
	fill_rect(img, 150, 116, 148, 8, brown)
	fill_circle(img, 190, 142, 9, C("gold"))
	fill_circle(img, 258, 142, 9, C("gold"))
	# 短髯
	fill_ellipse(img, 224, 226, 34, 24, brown)
	# 嘴甲
	fill_rect(img, 200, 180, 48, 14, darken(armor, 0.4))
	save(img, "units/%s.png" % id, list)

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
