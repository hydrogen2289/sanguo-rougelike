class_name UnitRig3D
extends RefCounted
## 程序化拼装 Q 版 3D 低模小人(表现升级,02 §4):
## 只用 Godot 内置几何体(SphereMesh/CapsuleMesh/BoxMesh/CylinderMesh/TorusMesh)
## + StandardMaterial3D 拼装,不下载外部素材、不引新依赖(已拍板约束)。
## 颜色只引用 data/palette.json 的 token(派生色由 token 混合,同 tools/gen_textures.gd 口径)。
## 约定:build() 返回的 Node3D 脚底在原点、面朝本地 +Z;
## 朝向由调用方转 rotation.y = atan2(dir.x, dir.z)(此时 +Z 恰指向 dir)。
## 每个 MeshInstance3D 记 meta "base_albedo",供 UnitBase 白闪/灰化取样。

static var _pal_cache: Dictionary = {}

## 读取并缓存调色板(失败返回空字典,调用方自查)
static func load_palette() -> Dictionary:
	if not _pal_cache.is_empty():
		return _pal_cache
	var path := "res://data/palette.json"
	if FileAccess.file_exists(path):
		var p = JSON.parse_string(FileAccess.get_file_as_string(path))
		if p is Dictionary:
			_pal_cache = p
	return _pal_cache

# ---------------------------------------------------------------- 对外入口

## 大球头的球心与半径:五官和头饰都相对它定位
const HEAD_R := 0.42
const HEAD_Y := 1.18

## 按单位 id 拼装小人:两段式(基础身体 + 单位识别物)
static func build(unit_id: String, pal: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Rig"
	root.set_meta("unit_id", unit_id)
	var s := _spec(unit_id, pal)
	_build_body(root, s)
	_build_feature(root, unit_id, s)
	_ring(root, unit_id, pal)   # 脚下站位圈:角色与地面分离
	return root

# ---------------------------------------------------------------- 调色与规格

static func C(pal: Dictionary, token: String) -> Color:
	return Color(str(pal.get(token, "#FF00FF")))

## 袍色映射(沿用 gen_textures.gd _robe_color 语义 + 敌兵 cloth/iron)
static func _robe(pal: Dictionary, tok: String) -> Color:
	match tok:
		"deep_green": return C(pal, "deep_green")
		"dark_green": return C(pal, "deep_green").darkened(0.30)
		"spring_green": return C(pal, "spring_green")
		"white": return C(pal, "paper").lerp(Color.WHITE, 0.70)   # 赵云白袍要白净,0.55 偏米色
		"brocade": return C(pal, "paper").lerp(Color.WHITE, 0.45).lerp(C(pal, "gold"), 0.30)
			# 锦马超:白袍织金,和赵云的素白拉开(同 token 会整场撞色)
		"paper": return C(pal, "paper").lerp(C(pal, "paper_dark"), 0.6)
		"cinnabar": return C(pal, "cinnabar")
		"cloth": return C(pal, "spring_green").darkened(0.12)
		"iron": return C(pal, "deep_green").darkened(0.42)
		"dark_brown": return C(pal, "dark_brown")   # 魏延深褐战甲(03 §3.3 新 robe 映射)
		"blue_robe": return C(pal, "spring_green").lerp(C(pal, "deep_green").darkened(0.42), 0.5)
			# 张辽蓝袍(05 §4):spring_green lerp iron,palette 派生不新增 hex
		"red_dress": return C(pal, "cinnabar").lerp(C(pal, "dark_brown"), 0.18)
			# 貂蝉红裙(05 §4):cinnabar 略沉,与吕布正朱砂拉开
		_: return C(pal, "spring_green")

## 单位身份表(移植自 tools/gen_textures.gd v8 立牌的五把钥匙:
## 脸谱主色 / 眉目 / 须髯 / 体型 / 头饰+兵器)。前四把在这里,后一把仍由 _build_feature 出。
## skin/hair 是配方名,由 _spec 统一解析成 palette token 派生色。
const LOOKS := {
	"liubei": {"skin": "warm", "hair": "jet", "beard": "short", "ears": true,
		"eye": {"r": 0.050, "gap": 0.15, "y": 1.24, "flat": 1.0},
		"brow": {"len": 0.16, "w": 0.030, "lift": 0.07, "tilt": 0.0},
		"body": {"torso_r": 0.29, "wide": 1.0, "deep": 0.82, "leg_r": 0.09}},
	"guanyu": {"skin": "ruddy", "hair": "jet", "beard": "long", "ears": false,
		"eye": {"r": 0.042, "gap": 0.15, "y": 1.23, "flat": 0.55},
		"brow": {"len": 0.19, "w": 0.034, "lift": 0.10, "tilt": -0.30},
		"body": {"torso_r": 0.30, "wide": 1.02, "deep": 0.82, "leg_r": 0.09}},
	"zhangfei": {"skin": "dark", "hair": "jet", "beard": "tuft", "ears": false,
		"eye": {"r": 0.072, "gap": 0.16, "y": 1.25, "flat": 1.0},
		"brow": {"len": 0.15, "w": 0.052, "lift": 0.13, "tilt": 0.42},
		"body": {"torso_r": 0.34, "wide": 1.12, "deep": 0.90, "leg_r": 0.10}},
	"zhaoyun": {"skin": "pale", "hair": "jet", "beard": "none", "ears": false,
		"eye": {"r": 0.064, "gap": 0.15, "y": 1.24, "flat": 1.0},
		"brow": {"len": 0.15, "w": 0.030, "lift": 0.11, "tilt": 0.18},
		"body": {"torso_r": 0.29, "wide": 1.02, "deep": 0.80, "leg_r": 0.09}},
	"zhuge": {"skin": "pale", "hair": "jet", "beard": "three", "ears": false,
		"eye": {"r": 0.040, "gap": 0.14, "y": 1.23, "flat": 0.5},
		"brow": {"len": 0.18, "w": 0.028, "lift": 0.09, "tilt": -0.12},
		"body": {"torso_r": 0.27, "wide": 0.94, "deep": 0.76, "leg_r": 0.08}},
	"huatuo": {"skin": "warm", "hair": "white", "beard": "white_long", "ears": false,
		"eye": {"r": 0.054, "gap": 0.14, "y": 1.22, "flat": 0.85},
		"brow": {"len": 0.17, "w": 0.026, "lift": 0.10, "tilt": 0.12},
		"body": {"torso_r": 0.27, "wide": 0.96, "deep": 0.78, "leg_r": 0.08}},
	"lvbu": {"skin": "pale", "hair": "jet", "beard": "none", "ears": false,
		"eye": {"r": 0.058, "gap": 0.15, "y": 1.24, "flat": 0.9},
		"brow": {"len": 0.17, "w": 0.030, "lift": 0.11, "tilt": 0.34},
		"body": {"torso_r": 0.29, "wide": 1.04, "deep": 0.80, "leg_r": 0.09}},
	"huangjin_zu": {"skin": "yellow", "hair": "brown", "beard": "none", "ears": false,
		"eye": {"r": 0.046, "gap": 0.14, "y": 1.23, "flat": 1.0},
		"brow": {"len": 0.13, "w": 0.026, "lift": 0.07, "tilt": 0.10},
		"body": {"torso_r": 0.26, "wide": 0.92, "deep": 0.76, "leg_r": 0.08}},
	"huangjin_gongshou": {"skin": "yellow", "hair": "brown", "beard": "none", "ears": false,
		"eye": {"r": 0.044, "gap": 0.15, "y": 1.23, "flat": 0.6},
		"brow": {"len": 0.13, "w": 0.026, "lift": 0.08, "tilt": -0.06},
		"body": {"torso_r": 0.25, "wide": 0.90, "deep": 0.74, "leg_r": 0.08}},
	"huangjin_lishi": {"skin": "dark", "hair": "brown", "beard": "mustache", "ears": false,
		"eye": {"r": 0.062, "gap": 0.15, "y": 1.24, "flat": 1.0},
		"brow": {"len": 0.15, "w": 0.048, "lift": 0.12, "tilt": 0.30},
		"body": {"torso_r": 0.36, "wide": 1.16, "deep": 0.94, "leg_r": 0.11}},
	"xiliang_qinwei": {"skin": "bronze", "hair": "brown", "beard": "mustache", "ears": false,
		"eye": {"r": 0.050, "gap": 0.15, "y": 1.23, "flat": 0.8},
		"brow": {"len": 0.16, "w": 0.044, "lift": 0.11, "tilt": 0.24},
		"body": {"torso_r": 0.32, "wide": 1.08, "deep": 0.88, "leg_r": 0.10}},
	"huaxiong": {"skin": "iron", "hair": "jet", "beard": "tuft", "ears": false,
		"eye": {"r": 0.056, "gap": 0.15, "y": 1.24, "flat": 0.8},
		"brow": {"len": 0.18, "w": 0.056, "lift": 0.14, "tilt": 0.36},
		"body": {"torso_r": 0.38, "wide": 1.20, "deep": 0.96, "leg_r": 0.11}},
	"machao": {"skin": "pale", "hair": "jet", "beard": "none", "ears": false,
		"eye": {"r": 0.050, "gap": 0.15, "y": 1.24, "flat": 0.70},
		"brow": {"len": 0.18, "w": 0.046, "lift": 0.13, "tilt": 0.48},
		"body": {"torso_r": 0.29, "wide": 1.04, "deep": 0.82, "leg_r": 0.09}},
	"huangzhong": {"skin": "wan", "hair": "white", "beard": "goat", "ears": false,
		"eye": {"r": 0.040, "gap": 0.14, "y": 1.22, "flat": 0.45},
		"brow": {"len": 0.23, "w": 0.034, "lift": 0.07, "tilt": -0.32},
		"body": {"torso_r": 0.28, "wide": 0.98, "deep": 0.80, "leg_r": 0.085}},
	"weiyan": {"skin": "ruddy", "hair": "jet", "beard": "short", "ears": false,
		"eye": {"r": 0.056, "gap": 0.15, "y": 1.24, "flat": 0.7},
		"brow": {"len": 0.18, "w": 0.038, "lift": 0.12, "tilt": 0.34},
		"body": {"torso_r": 0.30, "wide": 1.04, "deep": 0.82, "leg_r": 0.09}},
	# --- 03 第三批(05 §4)---
	"zhangliao": {"skin": "purple_jade", "hair": "jet", "beard": "short", "ears": false,
		"eye": {"r": 0.052, "gap": 0.15, "y": 1.24, "flat": 0.8},
		"brow": {"len": 0.17, "w": 0.034, "lift": 0.11, "tilt": 0.28},
		"body": {"torso_r": 0.30, "wide": 1.04, "deep": 0.82, "leg_r": 0.09}},
	"xuchu": {"skin": "dark", "hair": "jet", "beard": "tuft", "ears": false,
		"eye": {"r": 0.062, "gap": 0.16, "y": 1.24, "flat": 0.9},
		"brow": {"len": 0.17, "w": 0.050, "lift": 0.13, "tilt": 0.36},
		"body": {"torso_r": 0.35, "wide": 1.14, "deep": 0.92, "leg_r": 0.105}},
	"ganning": {"skin": "bronze", "hair": "jet", "beard": "none", "ears": false,
		"eye": {"r": 0.058, "gap": 0.15, "y": 1.24, "flat": 0.9},
		"brow": {"len": 0.16, "w": 0.036, "lift": 0.10, "tilt": 0.26},
		"body": {"torso_r": 0.28, "wide": 1.00, "deep": 0.80, "leg_r": 0.09}},
	"zhouyu": {"skin": "pale", "hair": "jet", "beard": "none", "ears": false,
		"eye": {"r": 0.048, "gap": 0.14, "y": 1.23, "flat": 0.6},
		"brow": {"len": 0.17, "w": 0.028, "lift": 0.09, "tilt": -0.08},
		"body": {"torso_r": 0.27, "wide": 0.96, "deep": 0.78, "leg_r": 0.08}},
	"diaochan": {"skin": "pale", "hair": "jet", "beard": "none", "ears": false,
		"eye": {"r": 0.050, "gap": 0.14, "y": 1.23, "flat": 0.5},
		"brow": {"len": 0.15, "w": 0.024, "lift": 0.07, "tilt": -0.10},
		"body": {"torso_r": 0.26, "wide": 0.94, "deep": 0.76, "leg_r": 0.075}},
	"_default": {"skin": "yellow", "hair": "brown", "beard": "none", "ears": false,
		"eye": {"r": 0.046, "gap": 0.14, "y": 1.23, "flat": 1.0},
		"brow": {"len": 0.13, "w": 0.026, "lift": 0.07, "tilt": 0.10},
		"body": {"torso_r": 0.26, "wide": 0.92, "deep": 0.76, "leg_r": 0.08}},
}

## 单位基础配色 + 身份(全部由 palette token 派生)
static func _spec(unit_id: String, pal: Dictionary) -> Dictionary:
	var brown := C(pal, "dark_brown")
	var skin0 := C(pal, "gold").lerp(Color.WHITE, 0.55)
	var s := {
		"pal": pal,                         # 原始调色板(识别物偶尔要再取 token)
		"robe": C(pal, "spring_green"),
		"robe_dark": C(pal, "spring_green").darkened(0.30),
		"skin": skin0,
		"steel": C(pal, "gold").lerp(Color.WHITE, 0.35),
		"gold": C(pal, "gold"),
		"cinnabar": C(pal, "cinnabar"),
		"huangjin": C(pal, "huangjin"),
		"pole": brown,                      # 兵器长杆深褐
		"brown": brown,
		"eye": brown.darkened(0.25),
		"hair": brown,
		"iron": C(pal, "deep_green").darkened(0.42),
	}
	var robe_tok := "spring_green"
	match unit_id:
		"liubei": robe_tok = "deep_green"
		"guanyu": robe_tok = "spring_green"
		"zhangfei": robe_tok = "dark_green"
		"zhaoyun": robe_tok = "white"
		"zhuge": robe_tok = "paper"
		"huatuo": robe_tok = "spring_green"
		"lvbu": robe_tok = "cinnabar"
		"huangjin_zu", "huangjin_gongshou", "huangjin_lishi": robe_tok = "cloth"
		"xiliang_qinwei": robe_tok = "deep_green"
		"huaxiong": robe_tok = "iron"
		"machao": robe_tok = "brocade"        # 白袍织金(03 §3.1),不再复用赵云 white
		"huangzhong": robe_tok = "iron"       # 老将铁甲(03 §3.2)
		"weiyan": robe_tok = "dark_brown"     # 深褐战甲(03 §3.3)
		"zhangliao": robe_tok = "blue_robe"   # 蓝袍金甲(05 §4;派生自 spring_green.lerp(iron))
		"xuchu": robe_tok = "iron"            # 虎痴裸衣甲(05 §4;iron 底 + 裸臂)
		"ganning": robe_tok = "cloth"         # 锦帆贼粗布短打(05 §4;spring_green 偏暗)
		"zhouyu": robe_tok = "paper"          # 儒袍 paper 色(05 §4;与诸葛同袍色,纶巾区分)
		"diaochan": robe_tok = "red_dress"    # 红裙(05 §4;cinnabar 派生)
	s.robe = _robe(pal, robe_tok)
	s.robe_dark = (s.robe as Color).darkened(0.30)
	var look: Dictionary = LOOKS.get(unit_id, LOOKS["_default"])
	s.look = look
	match str(look.skin):
		"ruddy": s.skin = C(pal, "cinnabar").lerp(skin0, 0.44)      # 关羽 面如重枣
		"dark": s.skin = brown.lerp(C(pal, "cinnabar"), 0.24).lerp(skin0, 0.24)   # 张飞/力士 豹头乌面:黑里透红,0.46 会洗成灰绿
		"pale": s.skin = skin0.lerp(Color.WHITE, 0.42)              # 赵云/诸葛/吕布 白净
		"wan": s.skin = skin0.lerp(C(pal, "paper_dark"), 0.50)      # 华佗 苍白
		"yellow": s.skin = skin0.lerp(C(pal, "huangjin"), 0.40)     # 黄巾 菜色
		"bronze": s.skin = brown.lerp(skin0, 0.32)                  # 西凉/甘宁 古铜
		"iron": s.skin = C(pal, "deep_green").lerp(brown, 0.55)     # 华雄 铁青
		"purple_jade": s.skin = C(pal, "paper").lerp(brown, 0.35)   # 张辽 面如紫玉(05 §4;paper.lerp(dark_brown) 系)
	match str(look.hair):
		"white": s.hair = C(pal, "paper").lerp(Color.WHITE, 0.30)   # 华佗 白发白眉
		"jet": s.hair = brown.darkened(0.45)
	s.eye_white = C(pal, "paper").lerp(Color.WHITE, 0.80)
	s.blush = C(pal, "cinnabar").lerp(s.skin, 0.62)
	return s

# ---------------------------------------------------------------- 拼装助手

static func _mat(color: Color, metal := 0.0, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

## 通用挂件:每 MeshInstance3D cast_shadow = ON(软阴影落地是本次核心收益)
## 并记 meta base_albedo(白闪/灰化取样);no_meta=true 的例外是站位圈等地形标记
static func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3,
		metal := 0.0, rough := 0.8, scl := Vector3.ONE, no_meta := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color, metal, rough)
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if not no_meta:
		mi.set_meta("base_albedo", color)
	parent.add_child(mi)
	return mi

static func _sphere(parent: Node3D, s: Dictionary, r: float, color: Color, pos: Vector3,
		metal := 0.0, rough := 0.8, scl := Vector3.ONE) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return _mesh(parent, m, color, pos, metal, rough, scl)

static func _box(parent: Node3D, s: Dictionary, size: Vector3, color: Color, pos: Vector3,
		metal := 0.0, rough := 0.8) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mesh(parent, m, color, pos, metal, rough)

static func _capsule(parent: Node3D, s: Dictionary, r: float, h: float, color: Color, pos: Vector3,
		scl := Vector3.ONE) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return _mesh(parent, m, color, pos, 0.0, 0.8, scl)

static func _cylinder(parent: Node3D, r_top: float, r_bot: float, h: float, color: Color,
		pos: Vector3, metal := 0.0, rough := 0.8, with_meta := true) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	return _mesh(parent, m, color, pos, metal, rough, Vector3.ONE, not with_meta)

## 弯月刃(青龙偃月刀/画戟侧刃):3 段扁盒沿弧排布(弧形近似),刃面默认朝 +Z
## 段尺寸 ×1.4、弧半径 ×1.25:上一版刃太小,武器识别度不足(打磨遗留 ④)
static func _crescent_z(parent: Node3D, s: Dictionary, center: Vector3, r: float, flip := 1.0) -> void:
	for a in [-0.5, 0.0, 0.5]:
		var mi := _box(parent, s, Vector3(0.045, 0.28, 0.06), s.steel,
			center + Vector3(0.0, cos(a) * r * 1.25 * flip, sin(a) * r * 1.25), 0.8, 0.3)
		mi.rotation.x = -a * flip

## 弯月刃(大斧双刃):弧在 X-Y 平面(向两侧展开)
static func _crescent_x(parent: Node3D, s: Dictionary, center: Vector3, r: float) -> void:
	for a in [-0.5, 0.0, 0.5]:
		var mi := _box(parent, s, Vector3(0.28, 0.30, 0.06), s.steel,
			center + Vector3(sin(a) * r * 1.25, cos(a) * r * 1.25, 0.0), 0.8, 0.3)
		mi.rotation.z = -a

## 束发金冠:细环贴头顶(刘备);珠/垂带可选
static func _gold_crown(parent: Node3D, s: Dictionary) -> void:
	_cylinder(parent, 0.19, 0.21, 0.09, s.gold, Vector3(0.0, HEAD_Y + HEAD_R - 0.02, -0.02), 0.6, 0.4)

## 站位圈:贴地扁圆柱,把角色从地面里「垫」出来(打磨遗留 ⑤)。
## 不记 base_albedo meta(经 _mesh 的 no_meta 参数跳过)——白闪/灰化会跳过它:
## 站位圈是地形标记不是角色本体,灰化后圈子保持原色反而更醒目地标记尸体位置,可接受。
static func _ring(parent: Node3D, unit_id: String, pal: Dictionary) -> void:
	var ground := C(pal, "paper")
	var c: Color
	if unit_id == "huaxiong":
		c = C(pal, "cinnabar").lerp(ground, 0.5)          # Boss 朱砂圈
	elif unit_id in ["huangjin_zu", "huangjin_gongshou", "huangjin_lishi", "xiliang_qinwei"]:
		c = C(pal, "huangjin").lerp(ground, 0.5)          # 敌兵 黄巾圈
	else:
		c = C(pal, "gold").lerp(ground, 0.5)              # 武将 缃金圈
	_cylinder(parent, 0.42, 0.42, 0.02, c, Vector3(0.0, 0.01, 0.0), 0.0, 1.0, false).name = "Ring"

## 斜挎披帛/背带:细长扁盒从左肩到右腰(刘备金披帛/华佗药囊背带)
static func _sash(parent: Node3D, s: Dictionary, color: Color) -> void:
	var mi := _box(parent, s, Vector3(0.05, 0.98, 0.05), color, Vector3(-0.12, 0.78, 0.30))
	mi.rotation.z = -0.42

## 张飞黑色罗帽:深色小帽尖 + 顶部小揪(抓髻)
static func _luo_hat(parent: Node3D, s: Dictionary) -> void:
	var jet := (s.hair as Color).darkened(0.5)
	_cylinder(parent, 0.10, 0.26, 0.18, jet, Vector3(0.0, HEAD_Y + HEAD_R + 0.02, -0.03))
	_sphere(parent, s, 0.05, jet, Vector3(0.0, HEAD_Y + HEAD_R + 0.14, -0.03))

## 关羽绿色包耳幞头:软质圆筒帽 + 两侧包耳 + 前帽沿。
## 帽体下沿压在 1.37 —— 关羽的卧蚕眉在 1.33,再低一寸就把招牌五官埋进布里
## (上一版用压扁半球,赤道面正好糊在眉高上,特写里只剩一道深色带子)。
static func _putou_hat(parent: Node3D, s: Dictionary) -> void:
	var green := C(s.pal, "spring_green").darkened(0.30)
	_cylinder(parent, 0.22, 0.40, 0.26, green, Vector3(0.0, 1.50, -0.03))
	# 两侧包耳垂片
	for side in [-1.0, 1.0]:
		_box(parent, s, Vector3(0.05, 0.20, 0.24), green,
			Vector3(side * (HEAD_R + 0.02), HEAD_Y + 0.24, -0.04))
	# 前帽沿(眉上一点点,给额头留出一条缝)
	_box(parent, s, Vector3(0.60, 0.05, 0.10), green.darkened(0.2),
		Vector3(0.0, 1.385, _face_z(0.0, 0.205) - 0.01))

## 黄巾头巾:扁圆柱罩在头顶 + 右侧结
static func _turban(parent: Node3D, s: Dictionary) -> void:
	_cylinder(parent, 0.36, 0.38, 0.14, s.huangjin, Vector3(0.0, 1.44, -0.02))
	_sphere(parent, s, 0.06, s.huangjin, Vector3(0.30, 1.40, 0.08))

## 狮盔(马超,03 §3.1):锥形盔体 + 两侧兽耳 + 额前金箍 + 脑后白绒球。
## 盔体下沿必须高于眉线(≈1.34),否则会把眉毛吞进盔里 —— 用圆筒锥而不是压扁半球,
## 半球盔的赤道面正好压在眉高上(赵云那顶能露眉是因为他眉位更低,不能照抄)。
static func _lion_helm(parent: Node3D, s: Dictionary) -> void:
	_cylinder(parent, 0.15, 0.40, 0.26, s.steel, Vector3(0.0, 1.49, -0.02), 0.7, 0.35)
	_sphere(parent, s, 0.06, s.gold, Vector3(0.0, 1.66, -0.02), 0.6, 0.4)
	# 狮耳:盔两侧竖起的扁球
	for side in [-1.0, 1.0]:
		_sphere(parent, s, 0.10, s.steel, Vector3(side * 0.38, 1.48, -0.04), 0.7, 0.35,
			Vector3(0.45, 1.05, 0.80))
	# 额前金箍(压住盔沿,是「锦马超」最响的一块)
	_cylinder(parent, 0.405, 0.405, 0.055, s.gold, Vector3(0.0, 1.385, -0.02), 0.6, 0.4)
	# 脑后白绒球
	_sphere(parent, s, 0.095, C(s.pal, "paper").lerp(Color.WHITE, 0.35), Vector3(0.0, 1.46, -0.34))

## 头顶狂髻(魏延,03 §3.3):黑发小球束在头顶 + 束发金箍细环
static func _topknot_gold(parent: Node3D, s: Dictionary) -> void:
	_cylinder(parent, 0.19, 0.21, 0.05, s.gold, Vector3(0.0, HEAD_Y + HEAD_R - 0.06, -0.02), 0.6, 0.4)
	# 髻球要压进发帽里:球心只高出头顶 0.05、半径 0.13,否则头顶光秃秃地顶着一颗悬空的蛋
	_sphere(parent, s, 0.13, (s.hair as Color).darkened(0.35), Vector3(0.0, HEAD_Y + HEAD_R + 0.05, -0.02))

## 莲冠(华佗):头顶小方柱冠 + 横簪。白发老人再戴软巾会和黄忠同形,
## 硬质小冠 + 一根簪才是「道门医者」的剪影。
static func _dao_crown(parent: Node3D, s: Dictionary) -> void:
	var jade := C(s.pal, "deep_green").lerp(C(s.pal, "dark_brown"), 0.45)
	_cylinder(parent, 0.13, 0.16, 0.20, jade, Vector3(0.0, 1.60, -0.04), 0.4, 0.6)
	_sphere(parent, s, 0.055, s.gold, Vector3(0.0, 1.72, -0.04), 0.6, 0.4)
	# 横簪:一根细杆穿过冠,两头出头
	var pin := _cylinder(parent, 0.016, 0.016, 0.40, s.gold, Vector3(0.0, 1.58, -0.04), 0.6, 0.4)
	pin.rotation.z = PI * 0.5

## 黄巾额带(弓手):只缠额头的一条 + 脑后两条垂布。
## 卒戴包头巾、弓手露半个脑门,远距离才分得出谁是射手。
static func _band_turban(parent: Node3D, s: Dictionary) -> void:
	_cylinder(parent, 0.40, 0.41, 0.11, s.huangjin, Vector3(0.0, 1.40, -0.02))
	for i in [-1, 1]:
		var tail := _box(parent, s, Vector3(0.05, 0.26, 0.025), s.huangjin.darkened(0.15),
			Vector3(float(i) * 0.09, 1.30, -0.38))
		tail.rotation.x = -0.22

## 红巾头束(甘宁,05 §4):朱砂扁圆柱头巾 + 侧结(与黄巾的金黄区分)
static func _red_headwrap(parent: Node3D, s: Dictionary) -> void:
	_cylinder(parent, 0.38, 0.40, 0.13, s.cinnabar, Vector3(0.0, 1.43, -0.02))
	_sphere(parent, s, 0.06, s.cinnabar.darkened(0.15), Vector3(0.29, 1.39, 0.08))

## 白纶巾(周瑜,05 §4):paper 色软质圆筒巾 + 前额垂带(与诸葛深绿巾区分)
static func _white_lunjin(parent: Node3D, s: Dictionary) -> void:
	var paper := C(s.pal, "paper").lerp(Color.WHITE, 0.25)
	_cylinder(parent, 0.17, 0.36, 0.26, paper, Vector3(0.0, 1.50, -0.03))
	_cylinder(parent, 0.375, 0.375, 0.05, s.gold, Vector3(0.0, 1.385, -0.03), 0.6, 0.4)
	for side in [-1.0, 1.0]:
		var rb := _box(parent, s, Vector3(0.035, 0.26, 0.03), paper,
			Vector3(side * 0.20, 1.40, -0.06))
		rb.rotation.z = side * 0.12

## 双髻(貂蝉,05 §4):hair 色两颗小球顶置
static func _twin_buns(parent: Node3D, s: Dictionary) -> void:
	for side in [-1.0, 1.0]:
		_sphere(parent, s, 0.115, (s.hair as Color).darkened(0.35),
			Vector3(side * 0.17, HEAD_Y + HEAD_R + 0.06, -0.02))
	# 髻上小金饰:左右各一粒
	for side in [-1.0, 1.0]:
		_sphere(parent, s, 0.032, s.gold, Vector3(side * 0.17, HEAD_Y + HEAD_R + 0.15, 0.03), 0.6, 0.4)

## 虎头盔(许褚,05 §4):iron 半球盔 + 顶部双小耳片
static func _tiger_helm(parent: Node3D, s: Dictionary) -> void:
	_sphere(parent, s, 0.42, s.iron, Vector3(0.0, 1.36, -0.02), 0.7, 0.4,
		Vector3(1.05, 0.62, 1.05))
	# 双耳片:盔顶两侧竖起的窄扁盒(虎耳意象)
	for side in [-1.0, 1.0]:
		var ear := _box(parent, s, Vector3(0.05, 0.16, 0.10), s.iron.darkened(0.15),
			Vector3(side * 0.22, 1.70, -0.04))
		ear.rotation.z = -side * 0.35
	_cylinder(parent, 0.405, 0.405, 0.05, s.gold, Vector3(0.0, 1.385, -0.02), 0.6, 0.4)

# ---------------------------------------------------------------- 基础身体(Q 版两头身)

static func _build_body(root: Node3D, s: Dictionary) -> void:
	var b: Dictionary = s.look.body
	var tr := float(b.torso_r)
	var wide := float(b.wide)
	var deep := float(b.deep)
	var leg_r := float(b.leg_r)
	# 短腿(深袍色),间距跟腰宽走;脚上补一双皮靴往前探,人才真正「站」在站位圈上
	# (只有圆腿时下半身没有落脚处,全身像浮在底盘上的球)
	var leather: Color = s.brown.darkened(0.25)
	for side in [-1.0, 1.0]:
		var lx: float = side * tr * 0.44
		_capsule(root, s, leg_r, 0.34, s.robe_dark, Vector3(lx, 0.17, 0.0))
		var boot := _capsule(root, s, leg_r * 1.15, 0.20, leather, Vector3(lx, 0.10, 0.07))
		boot.rotation.x = PI * 0.5
	# 椭球小身:半径与 x/z 压扁全部由身份表(力士/华雄宽、弓手/诸葛瘦)
	var body := CapsuleMesh.new()
	body.radius = tr
	body.height = 0.64
	_mesh(root, body, s.robe, Vector3(0.0, 0.60, 0.0), 0.0, 0.8, Vector3(wide, 0.95, deep))
	# 腰带 + 金扣
	var belt := CylinderMesh.new()
	belt.top_radius = tr * 1.05
	belt.bottom_radius = tr * 1.05
	belt.height = 0.07
	_mesh(root, belt, s.robe_dark, Vector3(0.0, 0.52, 0.0), 0.0, 0.8, Vector3(wide, 1.0, deep))
	_sphere(root, s, 0.05, s.gold, Vector3(0.0, 0.52, tr * deep + 0.02), 0.6, 0.4)
	# 手臂(小胶囊斜向外)+ 球手
	var sh := tr * wide + 0.04
	var arm_l := _capsule(root, s, leg_r * 0.78, 0.30, s.robe_dark, Vector3(-sh, 0.70, 0.0))
	arm_l.rotation.z = 0.35
	var arm_r := _capsule(root, s, leg_r * 0.78, 0.30, s.robe_dark, Vector3(sh, 0.70, 0.0))
	arm_r.rotation.z = -0.35
	_sphere(root, s, 0.10, s.skin, Vector3(-sh - 0.08, 0.60, 0.03))
	_sphere(root, s, 0.10, s.skin, Vector3(sh + 0.08, 0.60, 0.03))
	# 大球头(约占身高一半)
	_sphere(root, s, HEAD_R, s.skin, Vector3(0.0, HEAD_Y, 0.0))
	# 发帽打底(华佗白发,其余深褐):贴头皮压扁 + 球心上移前移,露出额头(打磨遗留 ①蘑菇头)
	_sphere(root, s, HEAD_R + 0.01, s.hair, Vector3(0.0, HEAD_Y + 0.22, -0.05), 0.0, 0.8,
		Vector3(1.00, 0.40, 1.00))
	_build_face(root, s)

# ---------------------------------------------------------------- 五官(立牌 v8「脸谱」的 3D 落点)

## 球面上某点(相对球心偏移 dx/dy)的深度:五官贴这个 z 才不会被球头吞掉
static func _face_z(dx: float, dy: float) -> float:
	return sqrt(maxf(HEAD_R * HEAD_R - dx * dx - dy * dy, 0.0))

static func _build_face(root: Node3D, s: Dictionary) -> void:
	var look: Dictionary = s.look
	var e: Dictionary = look.eye
	var br: Dictionary = look.brow
	var beard := str(look.beard)
	# 眼:先白珠后瞳仁,两颗都压 flat —— 只有黑点时整张脸是「死」的,这是卡通感的关键一步
	var gap := float(e.gap)
	var ey := float(e.y)
	var er := float(e.r)
	for side in [-1.0, 1.0]:
		var ez := _face_z(gap, ey - HEAD_Y)
		var scl := Vector3(1.0, float(e.flat), 1.0)
		_sphere(root, s, er * 1.6, s.eye_white, Vector3(side * gap, ey, ez + er * 0.35), 0.0, 0.7, scl)
		_sphere(root, s, er, s.eye, Vector3(side * gap, ey, ez + er * 1.15), 0.0, 0.6, scl)
	# 腮红:立牌 v8 同款,贴在球面上
	var cy := ey - 0.11
	for side in [-1.0, 1.0]:
		_sphere(root, s, 0.075, s.blush, Vector3(side * 0.27, cy, _face_z(0.27, cy - HEAD_Y) + 0.005),
			0.0, 0.85, Vector3(1.0, 0.72, 0.35))
	# 眉:tilt 正=剑眉上挑,负=卧蚕眉下压(关羽)
	var bl := float(br.len)
	var by := ey + float(br.lift)
	for side in [-1.0, 1.0]:
		var bx := gap + bl * 0.18
		var bm := _box(root, s, Vector3(bl, float(br.w), 0.06), s.hair,
			Vector3(side * bx, by, _face_z(bx, by - HEAD_Y) + 0.01))
		bm.rotation.z = side * float(br.tilt)
	# 刘备双耳垂肩:耳廓偏后贴头,下面再坠一颗耳垂。
	# 上一版只有一颗又薄又高的扁球,读成两片鱼鳍而不是「两耳垂肩」。
	if bool(look.ears):
		var ear_c: Color = (s.skin as Color).lerp(s.brown, 0.16)
		for side in [-1.0, 1.0]:
			_sphere(root, s, 0.10, ear_c, Vector3(side * 0.42, HEAD_Y - 0.02, -0.04),
				0.0, 0.8, Vector3(0.55, 1.05, 0.80))
			var lobe := _capsule(root, s, 0.045, 0.17, ear_c,
				Vector3(side * 0.40, HEAD_Y - 0.20, -0.02))
			lobe.rotation.z = side * 0.18
	# 须髯锚在下颌线(球头底沿)之下,贴在脸上会读成一张嘴
	var chin := HEAD_Y - HEAD_R * 0.80
	match beard:
		"long":
			# 美髯垂胸:下颌一坨 + 三绺加长垂到胸口(外两绺外撇,否则糊成一块黑帘)
			_sphere(root, s, 0.11, s.hair, Vector3(0.0, chin + 0.03, 0.25), 0.0, 0.8, Vector3(1.1, 0.72, 0.6))
			for x in [-0.13, 0.0, 0.13]:
				var st := _capsule(root, s, 0.028, 0.74, s.hair, Vector3(x, chin - 0.42, 0.27))
				st.rotation.z = signf(float(x)) * 0.16
		"white_long":
			_sphere(root, s, 0.09, s.hair, Vector3(0.0, chin + 0.02, 0.25), 0.0, 0.8, Vector3(1.0, 0.7, 0.6))
			for x in [-0.06, 0.0, 0.06]:
				_capsule(root, s, 0.022, 0.30, s.hair, Vector3(x, chin - 0.17, 0.26))
		"three":
			_sphere(root, s, 0.085, s.hair, Vector3(0.0, chin + 0.02, 0.24), 0.0, 0.8, Vector3(1.0, 0.65, 0.6))
			for x in [-0.055, 0.0, 0.055]:
				_capsule(root, s, 0.026, 0.30, s.hair, Vector3(x, chin - 0.16, 0.27))
		"tuft":
			# 虬髯:下颌一大坨 + 腮边三簇逐级外炸 + 两根横出的硬髯刺。
			# 上一版只有两簇且贴在腮上,特写里读不出「络腮胡子炸开」。
			_sphere(root, s, 0.13, s.hair, Vector3(0.0, chin + 0.04, 0.22), 0.0, 0.8,
				Vector3(1.35, 0.85, 0.75))
			for side in [-1.0, 1.0]:
				for i in 3:
					var fy := chin + 0.20 - float(i) * 0.13
					_sphere(root, s, 0.085 - float(i) * 0.008, s.hair,
						Vector3(side * (0.24 + float(i) * 0.05), fy, 0.16 - float(i) * 0.03))
				var spike := _capsule(root, s, 0.022, 0.24, s.hair,
					Vector3(side * 0.36, chin + 0.08, 0.08))
				spike.rotation.z = -side * 0.90
		"mustache":
			# 两片在鼻下相接成一条八字胡;分得太开会读成两道疤
			for side in [-1.0, 1.0]:
				var mx := 0.072
				var my := HEAD_Y - 0.10
				var mu := _box(root, s, Vector3(0.15, 0.036, 0.05), s.hair,
					Vector3(side * mx, my, _face_z(mx, -0.10) + 0.015))
				mu.rotation.z = -side * 0.58
		"short":
			_sphere(root, s, 0.075, s.hair, Vector3(0.0, chin + 0.03, 0.23), 0.0, 0.8, Vector3(1.1, 0.55, 0.6))
		"goat":
			# 八字 + 山羊髯(黄忠,03 §3.2;与华佗 white_long 垂胸长髯区分):
			# 上唇两撇扁盒(形同 mustache 但走 hair 白色)+ 下颌一绺 capsule
			for side in [-1.0, 1.0]:
				var mx := 0.072
				var my := HEAD_Y - 0.10
				var mu := _box(root, s, Vector3(0.15, 0.036, 0.05), s.hair,
					Vector3(side * mx, my, _face_z(mx, -0.10) + 0.015))
				mu.rotation.z = -side * 0.58
			_capsule(root, s, 0.030, 0.34, s.hair, Vector3(0.0, chin - 0.12, 0.24))

# ---------------------------------------------------------------- 单位识别物(沿用立牌语义)

static func _build_feature(root: Node3D, unit_id: String, s: Dictionary) -> void:
	match unit_id:
		"liubei":
			# 束发金冠 + 金披帛(织席贩履出身,经典戏服绿蟒袍金纹的斜挎金带)
			_gold_crown(root, s)
			_sash(root, s, s.gold)
			# 双股剑:双手各一柄细剑(钢刃加宽到 0.06 + 金格 + 褐柄),斜向外上举
			for side in [-1.0, 1.0]:
				var blade := _box(root, s, Vector3(0.060, 0.52, 0.014), s.steel,
					Vector3(side * 0.46, 1.02, 0.05), 0.8, 0.3)
				blade.rotation.z = -side * 0.5
				_box(root, s, Vector3(0.12, 0.03, 0.05), s.gold,
					Vector3(side * 0.41, 0.80, 0.03), 0.6, 0.4)
				var grip := _cylinder(root, 0.02, 0.02, 0.16, s.pole,
					Vector3(side * 0.39, 0.70, 0.02))
				grip.rotation.z = -side * 0.5
		"guanyu":
			# 绿锦袍 + 红内衬:领口/袖口朱砂撞色(绿袍红脸是他的招牌);绿包耳幞头
			# 青龙偃月刀:长杆 + 杆顶弯月刃 + 红缨(长髯走身份表 _build_face)
			_putou_hat(root, s)
			_box(root, s, Vector3(0.34, 0.07, 0.06), s.cinnabar, Vector3(0.0, 0.93, 0.17))   # 红领缘
			var sh_g := 0.30 * 1.02 + 0.04
			for side in [-1.0, 1.0]:
				_cylinder(root, 0.105, 0.105, 0.05, s.cinnabar,
					Vector3(side * (sh_g + 0.08), 0.62, 0.03))                               # 红袖口
			var pole := _cylinder(root, 0.026, 0.03, 1.70, s.pole, Vector3(0.42, 0.98, -0.02))
			pole.rotation.z = -0.05
			_crescent_z(root, s, Vector3(0.40, 1.86, 0.05), 0.15)
			_sphere(root, s, 0.05, s.cinnabar, Vector3(0.42, 1.68, 0.02))
		"zhangfei":
			# 黑罗帽(帽尖 + 顶揪)+ 躯干豹斑 + 黑护腕;丈八蛇矛:长杆 + 波浪矛头
			_luo_hat(root, s)
			var jet := (s.hair as Color).darkened(0.5)
			for p in [Vector3(-0.14, 0.70, 0.28), Vector3(0.15, 0.64, 0.29), Vector3(0.0, 0.50, 0.30)]:
				_sphere(root, s, 0.05, jet, p, 0.0, 0.85, Vector3(1.0, 0.7, 0.35))           # 豹纹暗示
			for side in [-1.0, 1.0]:
				_cylinder(root, 0.11, 0.11, 0.06, jet,
					Vector3(side * (0.34 * 1.12 + 0.12), 0.62, 0.03))                        # 黑护腕
			var pole := _cylinder(root, 0.026, 0.03, 1.70, s.pole, Vector3(0.42, 0.98, -0.02))
			pole.rotation.z = -0.05
			_cylinder(root, 0.0, 0.085, 0.30, s.steel, Vector3(0.44, 1.91, -0.02), 0.8, 0.3)
			_sphere(root, s, 0.045, s.steel, Vector3(0.43, 1.82, 0.03), 0.8, 0.3)
			_sphere(root, s, 0.04, s.steel, Vector3(0.45, 1.75, -0.04), 0.8, 0.3)
		"zhaoyun":
			# 白袍银枪:银盔(半球)+ 红缨;亮银枪(锥头 + 红缨)
			_sphere(root, s, 0.42, s.steel, Vector3(0.0, 1.36, -0.02), 0.7, 0.35, Vector3(1.04, 0.6, 1.04))
			_sphere(root, s, 0.06, s.cinnabar, Vector3(0.0, 1.64, -0.02))
			var pole := _cylinder(root, 0.026, 0.03, 1.70, s.pole, Vector3(0.42, 0.98, -0.02))
			pole.rotation.z = -0.05
			_cylinder(root, 0.0, 0.085, 0.30, s.steel, Vector3(0.44, 1.92, -0.02), 0.8, 0.3)
			_sphere(root, s, 0.05, s.cinnabar, Vector3(0.43, 1.74, -0.02))
		"zhuge":
			# 纶巾:软质圆筒巾(不是方盒 —— 上一版 _box 在头顶读成一块灰砖)
			# + 金额箍压沿 + 左右垂带到肩 + 脑后两条巾角
			_cylinder(root, 0.17, 0.36, 0.26, (s.robe as Color).darkened(0.35),
				Vector3(0.0, 1.50, -0.03))
			_cylinder(root, 0.375, 0.375, 0.05, s.gold, Vector3(0.0, 1.385, -0.03), 0.6, 0.4)
			for side in [-1.0, 1.0]:
				var rb := _box(root, s, Vector3(0.035, 0.26, 0.03),
					C((s["pal"] as Dictionary), "paper"), Vector3(side * 0.20, 1.40, -0.06))
				rb.rotation.z = side * 0.12
			for side in [-1.0, 1.0]:
				var horn := _box(root, s, Vector3(0.05, 0.22, 0.03),
					(s.robe as Color).darkened(0.35), Vector3(side * 0.10, 1.44, -0.36))
				horn.rotation.x = -0.35
			# 羽扇:扇面放大(r0.14→0.19)+ 扇骨折线(细扁盒呈放射状)
			var fan := _sphere(root, s, 0.19, C((s["pal"] as Dictionary), "paper").lerp(Color.WHITE, 0.25),
				Vector3(-0.50, 0.90, 0.10), 0.0, 0.8, Vector3(0.35, 1.0, 1.0))
			for i in [-1, 0, 1]:
				var rib := _box(root, s, Vector3(0.012, 0.34, 0.02),
					C((s["pal"] as Dictionary), "paper_dark").darkened(0.2),
					fan.position + Vector3(0.0, float(i) * 0.045, 0.05), 0.0, 0.8)
				rib.rotation.x = float(i) * 0.28
			_cylinder(root, 0.018, 0.018, 0.18, s.pole, Vector3(-0.46, 0.68, 0.08))
		"huatuo":
			# 莲冠 + 横簪(与黄忠的白发软巾拉开:硬冠才是道门医者的剪影)
			# 药葫芦:腰侧两小球叠(金褐)+ 暗纹药囊背带(朱砂偏金斜挎)
			_dao_crown(root, s)
			_sphere(root, s, 0.09, s.gold.lerp(s.cinnabar, 0.35), Vector3(0.44, 0.72, 0.06))
			_sphere(root, s, 0.12, s.gold.lerp(s.cinnabar, 0.35), Vector3(0.44, 0.55, 0.06))
			_cylinder(root, 0.02, 0.02, 0.06, s.pole, Vector3(0.44, 0.82, 0.06))
			_sash(root, s, s.cinnabar.lerp(s.gold, 0.4))
		"lvbu":
			# 束发金冠 + 冠顶珠 + 两侧红缨垂带到肩;双雉鸡翎加长后仰再前挑(演义标志性)
			_cylinder(root, 0.16, 0.18, 0.10, s.gold, Vector3(0.0, 1.63, -0.02), 0.6, 0.4)
			_sphere(root, s, 0.045, s.cinnabar, Vector3(0.0, 1.72, -0.02), 0.6, 0.4)   # 冠顶珠
			for side in [-1.0, 1.0]:
				var tassel := _capsule(root, s, 0.018, 0.30, s.cinnabar,
					Vector3(side * 0.19, 1.44, -0.12))
				tassel.rotation.z = side * 0.18                                        # 冠侧红缨垂带
				# 雉翎:杆加长到 ~1.0,后仰(rotation.x)再前挑,末端金缨球
				var plume := _cylinder(root, 0.012, 0.022, 1.00, s.cinnabar.darkened(0.15),
					Vector3(side * 0.40, 2.02, -0.34))
				plume.rotation.z = -side * 0.50
				plume.rotation.x = -0.55
				_sphere(root, s, 0.055, s.gold, Vector3(side * 0.62, 2.16, -0.72), 0.6, 0.4)
			var pole := _cylinder(root, 0.028, 0.032, 1.75, s.pole, Vector3(0.42, 0.99, -0.02))
			pole.rotation.z = -0.05
			_cylinder(root, 0.0, 0.08, 0.28, s.steel, Vector3(0.44, 1.95, -0.02), 0.8, 0.3)
			_crescent_x(root, s, Vector3(0.44, 1.82, -0.02), 0.14)
			_sphere(root, s, 0.045, s.gold, Vector3(0.44, 1.70, -0.02), 0.6, 0.4)
		"huangjin_zu":
			# 黄巾卒:黄头巾 + 腰前布结(粗布短打差异)+ 环首刀(宽背短刃 + 环首)
			_turban(root, s)
			_box(root, s, Vector3(0.08, 0.06, 0.05), s.robe_dark,
				Vector3(0.0, 0.52, 0.30 * 0.76 + 0.04))
			var blade := _box(root, s, Vector3(0.035, 0.24, 0.20), s.steel,
				Vector3(0.50, 0.94, 0.10), 0.8, 0.3)
			blade.rotation.x = -0.5
			_cylinder(root, 0.02, 0.02, 0.16, s.pole, Vector3(0.44, 0.72, 0.03))
			_sphere(root, s, 0.035, s.gold, Vector3(0.44, 0.64, 0.0), 0.6, 0.4)
		"huangjin_gongshou":
			# 黄巾弓手:额带 + 脑后垂布(卒是包头巾,露半个脑门才分得出发射的)
			# + 左手弓(细环)+ 搭箭
			_band_turban(root, s)
			var bow := TorusMesh.new()
			bow.inner_radius = 0.30
			bow.outer_radius = 0.33
			var bmi := _mesh(root, bow, s.pole.lerp(s.gold, 0.3), Vector3(-0.46, 0.86, 0.12), 0.0, 0.8,
				Vector3(1.0, 1.0, 0.25))
			bmi.rotation.y = PI * 0.5
			_cylinder(root, 0.012, 0.012, 0.42, C((s["pal"] as Dictionary), "paper_dark"), Vector3(-0.46, 0.86, 0.12))
		"huangjin_lishi":
			# 黄巾力士:黄头巾 + 大锤(方头铁箍;体格 ×1.4 由 size_mult 缩放)
			_turban(root, s)
			_cylinder(root, 0.024, 0.026, 0.90, s.pole, Vector3(0.50, 1.05, -0.02))
			_box(root, s, Vector3(0.24, 0.18, 0.18), s.steel, Vector3(0.50, 1.56, -0.02), 0.8, 0.3)
			_box(root, s, Vector3(0.26, 0.03, 0.20), s.pole.darkened(0.2), Vector3(0.50, 1.50, -0.02))
		"xiliang_qinwei":
			# 西凉亲卫:铁盔(半球)+ 红缨;长枪 + 左臂圆盾
			_sphere(root, s, 0.42, s.iron.lerp(s.brown, 0.3), Vector3(0.0, 1.36, -0.02), 0.7, 0.4,
				Vector3(1.04, 0.62, 1.04))
			_sphere(root, s, 0.05, s.cinnabar, Vector3(0.0, 1.64, -0.02))
			var pole := _cylinder(root, 0.024, 0.028, 1.60, s.pole, Vector3(0.44, 0.94, -0.02))
			pole.rotation.z = -0.05
			_cylinder(root, 0.0, 0.05, 0.20, s.steel, Vector3(0.46, 1.80, -0.02), 0.8, 0.3)
			var shield := _cylinder(root, 0.24, 0.24, 0.035,
				C((s["pal"] as Dictionary), "paper").lerp(C((s["pal"] as Dictionary), "spring_green"), 0.35),
				Vector3(-0.48, 0.68, 0.10), 0.3, 0.6)
			shield.rotation.x = PI * 0.5
			_sphere(root, s, 0.05, s.gold, Vector3(-0.48, 0.68, 0.13), 0.6, 0.4)
		"huaxiong":
			# Boss 华雄:铁盔 + 盔顶朱缨 + 头盔前檐护鼻面甲(贴盔球面,替换悬空纸盒);
			# 大斧(长杆 + 双月刃 + 朱缨)
			_sphere(root, s, 0.44, s.iron, Vector3(0.0, 1.36, -0.02), 0.7, 0.4, Vector3(1.05, 0.6, 1.05))
			_sphere(root, s, 0.07, s.cinnabar, Vector3(0.0, 1.70, -0.10), 0.6, 0.4)   # 盔顶朱缨球
			# 前檐:3 段扁盒贴盔面下半(y≈1.28~1.30 / z≈0.43 恰凸出盔球面),成一道眉檐
			for i in [-1, 0, 1]:
				var seg := _box(root, s, Vector3(0.20, 0.09, 0.07), s.iron.darkened(0.25),
					Vector3(float(i) * 0.22, 1.30 - absf(float(i)) * 0.015, 0.43 - absf(float(i)) * 0.02))
				seg.rotation.y = float(i) * 0.32
			# 护鼻:窄盒从檐中央垂到鼻梁
			_box(root, s, Vector3(0.07, 0.18, 0.06), s.iron.darkened(0.25),
				Vector3(0.0, 1.14, 0.41))
			# 两颗金眼珠嵌在檐下眼瞳位置(白眼球上的金瞳,是「檐下阴影里的金眼」)
			_sphere(root, s, 0.05, s.gold, Vector3(-0.15, 1.24, 0.46), 0.6, 0.3)
			_sphere(root, s, 0.05, s.gold, Vector3(0.15, 1.24, 0.46), 0.6, 0.3)
			var pole := _cylinder(root, 0.034, 0.038, 1.85, s.pole, Vector3(0.50, 1.02, -0.02))
			pole.rotation.z = -0.05
			_crescent_x(root, s, Vector3(0.52, 1.98, -0.02), 0.20)
			_cylinder(root, 0.0, 0.05, 0.16, s.steel, Vector3(0.52, 1.84, -0.02), 0.8, 0.3)
			_sphere(root, s, 0.06, s.cinnabar, Vector3(0.52, 1.68, -0.02))
		"machao":
			# 锦马超(03 §3.1):狮盔(钢灰半球+金珠)+ 白袍银铠 —— 双肩 steel 扁球甲;
			# 长枪与赵云区分:枪杆 gold.lerp(steel, 0.4)、枪头锥加宽(r0.085→0.10)
			_lion_helm(root, s)
			var sh_m := 0.30 * 1.04 + 0.04
			for side in [-1.0, 1.0]:
				_sphere(root, s, 0.12, s.steel, Vector3(side * (sh_m + 0.05), 0.80, 0.0),
					0.5, 0.5, Vector3(1.0, 0.55, 1.0))                                   # 银甲肩吞
			var pole_m := _cylinder(root, 0.026, 0.03, 1.70,
				(s.gold as Color).lerp(s.steel, 0.4), Vector3(0.42, 0.98, -0.02))
			pole_m.rotation.z = -0.05
			_cylinder(root, 0.0, 0.10, 0.30, s.steel, Vector3(0.44, 1.92, -0.02), 0.8, 0.3)   # 加宽枪头锥
			_sphere(root, s, 0.05, s.cinnabar, Vector3(0.43, 1.74, -0.02))                # 红缨(缨下宽锥)
		"huangzhong":
			# 老黄忠(03 §3.2):白发白髯走身份表;铁灰抹额 + 额心金护(不换盔,
			# 白发才是他的招牌,戴盔就和华佗的硬冠一样没了年龄感);
			# 铁灰护肩(iron 扁球×2);赤铜大弓 TorusMesh 压扁挂左手 + 背后箭囊 3 根细 cylinder 斜插
			_cylinder(root, 0.40, 0.415, 0.10, s.iron, Vector3(0.0, 1.385, -0.02), 0.5, 0.5)
			_sphere(root, s, 0.055, s.gold, Vector3(0.0, 1.40, 0.355), 0.6, 0.4)          # 额心金护
			var sh_h := 0.29 * 0.98 + 0.04
			for side in [-1.0, 1.0]:
				_sphere(root, s, 0.12, s.iron, Vector3(side * (sh_h + 0.05), 0.80, 0.0),
					0.4, 0.5, Vector3(1.0, 0.55, 1.0))                                   # 铁灰护肩
			var bow := TorusMesh.new()
			bow.inner_radius = 0.30
			bow.outer_radius = 0.34
			var bmi := _mesh(root, bow, (s.cinnabar as Color).lerp(s.gold, 0.4),
				Vector3(-0.46, 0.86, 0.12), 0.3, 0.5, Vector3(1.0, 1.0, 0.25))           # 赤铜大弓
			bmi.rotation.y = PI * 0.5
			_cylinder(root, 0.012, 0.012, 0.42, C((s["pal"] as Dictionary), "paper_dark"),
				Vector3(-0.46, 0.86, 0.12))                                              # 弓弦
			# 背后箭囊:斜插细 cylinder ×3(负 z 在背后,微微散开)
			for i in 3:
				var qx := -0.10 + float(i) * 0.09
				var qi := _cylinder(root, 0.018, 0.018, 0.52, s.pole, Vector3(qx, 1.02, -0.30))
				qi.rotation.x = 0.45
				qi.rotation.z = (float(i) - 1.0) * 0.12
		"weiyan":
			# 魏延(03 §3.3):褐甲黑护腕 + 头顶黑狂髻(金箍);大刀宽直刃 box(0.09 宽、无弯)
			# —— 与关羽偃月弯刃(_crescent_z)区分;剑眉/短须/面如重枣走身份表
			_topknot_gold(root, s)
			var sh_w := 0.30 * 1.04 + 0.04
			for side in [-1.0, 1.0]:
				_cylinder(root, 0.11, 0.11, 0.06,
					(s.hair as Color).darkened(0.5), Vector3(side * (sh_w + 0.10), 0.62, 0.03))   # 黑护腕
			var pole_w := _cylinder(root, 0.028, 0.032, 1.70, s.pole, Vector3(0.42, 0.98, -0.02))
			pole_w.rotation.z = -0.05
			_box(root, s, Vector3(0.09, 0.42, 0.035), s.steel, Vector3(0.46, 1.92, -0.02), 0.8, 0.3)  # 宽直刃
			_cylinder(root, 0.05, 0.05, 0.06, s.gold, Vector3(0.45, 1.70, -0.02), 0.6, 0.4)           # 刀格金箍
		"zhangliao":
			# 张辽(05 §4):蓝袍金甲 —— 双肩 gold 扁球甲吞 + 腰束金带;
			# 钩镰戟:长杆 + 单侧弯钩小盒(与偃月弯弧/画戟双耳区分,钩向前下勾)
			var sh_zl := 0.30 * 1.04 + 0.04
			for side in [-1.0, 1.0]:
				_sphere(root, s, 0.12, s.gold, Vector3(side * (sh_zl + 0.05), 0.80, 0.0),
					0.5, 0.5, Vector3(1.0, 0.55, 1.0))                                   # 金甲肩吞
			_cylinder(root, 0.315, 0.315, 0.07, s.gold, Vector3(0.0, 0.52, 0.0), 0.6, 0.4)   # 金腰箍
			var pole_zl := _cylinder(root, 0.026, 0.03, 1.72, s.pole, Vector3(0.42, 0.98, -0.02))
			pole_zl.rotation.z = -0.05
			# 单侧弯钩:三段小盒沿弧排布,朝前下勾(戟钩意象)
			for a in [-0.55, 0.0, 0.5]:
				var hook := _box(root, s, Vector3(0.045, 0.20, 0.055), s.steel,
					Vector3(0.44, 1.86 + cos(a) * 0.18, 0.02 + sin(a) * 0.16), 0.8, 0.3)
				hook.rotation.x = -a
			_cylinder(root, 0.0, 0.06, 0.16, s.steel, Vector3(0.44, 1.74, -0.02), 0.8, 0.3)   # 戟锋锥
		"xuchu":
			# 许褚(05 §4):虎头盔(iron 半球 + 双耳片)+ 裸臂(skin 色手臂替代袍袖)
			# + 大刀宽刃(比魏延更宽,0.12);体格 ×1.15 由调用方 size_mult/hero size 表达
			_tiger_helm(root, s)
			var sh_xc := 0.35 * 1.14 + 0.04
			for side in [-1.0, 1.0]:
				_capsule(root, s, 0.085, 0.30, s.skin, Vector3(side * (sh_xc + 0.02), 0.70, 0.0))   # 裸臂
			_sphere(root, s, 0.10, s.skin, Vector3(-sh_xc - 0.10, 0.60, 0.03))
			_sphere(root, s, 0.10, s.skin, Vector3(sh_xc + 0.10, 0.60, 0.03))
			var pole_xc := _cylinder(root, 0.030, 0.034, 1.70, s.pole, Vector3(0.48, 0.98, -0.02))
			pole_xc.rotation.z = -0.05
			_box(root, s, Vector3(0.12, 0.46, 0.04), s.steel, Vector3(0.52, 1.94, -0.02), 0.8, 0.3)  # 大刀宽刃
			_cylinder(root, 0.06, 0.06, 0.06, s.gold, Vector3(0.51, 1.70, -0.02), 0.6, 0.4)          # 刀格金箍
		"ganning":
			# 甘宁(05 §4):头束红巾(cinnabar,区别黄巾金黄)+ 腰挂金铃(gold 小球×2)
			# + 双匕(双手各一短刃 box,与刘备双剑的细长区分:短而宽)
			_red_headwrap(root, s)
			for i in 2:
				_sphere(root, s, 0.055, s.gold, Vector3(0.30 + float(i) * 0.10, 0.50, 0.24), 0.6, 0.4)  # 腰铃
			for side in [-1.0, 1.0]:
				var dg := _box(root, s, Vector3(0.055, 0.26, 0.03), s.steel,
					Vector3(side * 0.40, 0.86, 0.06), 0.8, 0.3)
				dg.rotation.z = -side * 0.42
				_cylinder(root, 0.022, 0.022, 0.12, s.pole, Vector3(side * 0.33, 0.74, 0.03))
				_sphere(root, s, 0.03, s.cinnabar, Vector3(side * 0.31, 0.70, 0.03))               # 匕柄红缨
		"zhouyu":
			# 周瑜(05 §4):白纶巾(paper 色,与诸葛深绿巾区分)+ 儒袍 + 执剑(右手细剑)
			_white_lunjin(root, s)
			var blade_zy := _box(root, s, Vector3(0.05, 0.48, 0.015), s.steel,
				Vector3(0.44, 1.00, 0.05), 0.8, 0.3)
			blade_zy.rotation.z = -0.45
			_box(root, s, Vector3(0.11, 0.03, 0.05), s.gold, Vector3(0.39, 0.78, 0.03), 0.6, 0.4)  # 剑格
			var grip_zy := _cylinder(root, 0.02, 0.02, 0.16, s.pole, Vector3(0.37, 0.68, 0.02))
			grip_zy.rotation.z = -0.45
		"diaochan":
			# 貂蝉(05 §4):双髻(hair 两小球顶置)+ 红裙走 robe;团扇(左手圆扁片 paper 色)
			_twin_buns(root, s)
			_sphere(root, s, 0.17, C((s["pal"] as Dictionary), "paper").lerp(Color.WHITE, 0.25),
				Vector3(-0.46, 0.88, 0.10), 0.0, 0.8, Vector3(0.14, 1.0, 1.0))                 # 团扇
			_cylinder(root, 0.016, 0.016, 0.20, s.pole, Vector3(-0.46, 0.72, 0.08))            # 扇柄
		_:
			# 兜底:敌兵皆戴黄巾(未知 id 不至于裸头)
			_turban(root, s)

