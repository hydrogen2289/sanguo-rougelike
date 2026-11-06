class_name HeroCard
extends RefCounted
## 武将卡片(M8):程序化头像 + 名/等级/星级/稀有度。武将府、酒馆、校场三处共用,
## 保证同一武将在任何界面里长相一致。头像为运行时像素绘制,不落盘(约束 4)。

const RARITY_COLOR := {
	"starting": Color(0.31, 0.44, 0.32),   # deep_green
	"normal":   Color(0.50, 0.46, 0.40),   # dark_brown
	"rare":     Color(0.35, 0.45, 0.62),
	"epic":     Color(0.71, 0.29, 0.23),   # cinnabar
}
const RARITY_NAME := {
	"starting": "初始", "normal": "普通", "rare": "稀有", "epic": "史诗",
}

## 袍色 token → 近似色。heroes.json 的 robe 并非全部在 palette 里(如 blue_robe/iron),
## 缺档时 UiTheme.col 会回退成同一个褐色,头像就全一样了,所以这里给一张映射表。
const ROBE_FALLBACK := {
	"iron": Color(0.42, 0.43, 0.45),
	"cloth": Color(0.62, 0.56, 0.45),
	"red_dress": Color(0.78, 0.30, 0.34),
	"white": Color(0.90, 0.88, 0.82),
	"dark_green": Color(0.22, 0.32, 0.24),
	"blue_robe": Color(0.28, 0.38, 0.56),
}

## 头像:袍色取自 heroes.json 的 robe token,再按稀有度叠一层边圈。
## 缺 robe/未拥有时用褐色剪影。
static func portrait(hero_id: String, size := 96, locked := false) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var robe := UiTheme.col("dark_brown", Color(0.35, 0.27, 0.2))
	var skin := Color(0.94, 0.85, 0.72)
	var hair := Color(0.18, 0.14, 0.12)
	var h := DataDB.hero_by_id(hero_id)
	if not h.is_empty():
		var token := str(h.get("robe", "dark_brown"))
		robe = UiTheme.col(token, ROBE_FALLBACK.get(token, robe))
	if locked:
		robe = robe.darkened(0.45)
		skin = skin.darkened(0.45)
		hair = hair.darkened(0.3)
	var c := size * 0.5
	# 底圈(稀有度)
	var ring: Color = RARITY_COLOR.get(DataDB.hero_rarity(hero_id), RARITY_COLOR["normal"])
	ProcIcon._fill_circle(img, c, c, size * 0.47, ring)
	ProcIcon._fill_circle(img, c, c, size * 0.43, UiTheme.col("paper", Color(0.95, 0.92, 0.83)))
	# 身体(袍)
	ProcIcon._fill_rect(img, size * 0.20, size * 0.62, size * 0.60, size * 0.30, robe)
	ProcIcon._fill_tri(img, Vector2(size * 0.20, size * 0.92), Vector2(size * 0.50, size * 0.58), Vector2(size * 0.36, size * 0.92), robe.lightened(0.12))
	ProcIcon._fill_tri(img, Vector2(size * 0.80, size * 0.92), Vector2(size * 0.50, size * 0.58), Vector2(size * 0.64, size * 0.92), robe.darkened(0.12))
	# 头
	ProcIcon._fill_circle(img, c, size * 0.44, size * 0.21, skin)
	# 发髻/冠
	ProcIcon._fill_circle(img, c, size * 0.25, size * 0.11, hair)
	ProcIcon._fill_rect(img, size * 0.28, size * 0.26, size * 0.44, size * 0.10, hair)
	return ImageTexture.create_from_image(img)

## 星级文字「★★☆」
static func star_text(star: int, cap := 5) -> String:
	var s := ""
	for i in cap:
		s += "★" if i < star else "☆"
	return s

## 一张完整卡片(纵向:头像 + 名字 + 明细);调用方自己接按钮
static func card(hero_id: String, size := Vector2(180, 220), locked := false) -> VBoxContainer:
	var h := DataDB.hero_by_id(hero_id)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = size
	vb.add_theme_constant_override("separation", 4)
	var rar := DataDB.hero_rarity(hero_id)
	var rar_col: Color = RARITY_COLOR.get(rar, Color.BLACK)
	var head := UiTheme.label(str(h.get("name", hero_id)), 22, rar_col, 4)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head)
	var pic := TextureRect.new()
	pic.texture = portrait(hero_id, 96, locked)
	pic.custom_minimum_size = Vector2(96, 96)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(pic)
	var detail := "未拥有"
	if not locked:
		detail = "Lv.%d  %s" % [HeroSave.level_of(hero_id), star_text(HeroSave.star_of(hero_id))]
	var dl := UiTheme.label(detail, 16, UiTheme.col("dark_brown", Color(0.4, 0.36, 0.3)), 3)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dl)
	return vb
