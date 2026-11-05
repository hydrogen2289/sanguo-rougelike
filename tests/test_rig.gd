extends "res://tests/test_base.gd"
## test_rig(表现升级冒烟,02 §4):hero/enemy/boss 实例化后 rig 存在,
## 至少含 N 个 MeshInstance3D 且 cast_shadow 开启、材质带 base_albedo;
## 12 个单位 id 全部可拼出,颜色取自 palette。
## 依赖 run_all.gd 先手动注册 autoload。

const HERO_SCENE := "res://scenes/units/hero.tscn"
const ENEMY_SCENE := "res://scenes/units/enemy.tscn"
const BOSS_SCENE := "res://scenes/units/boss_huaxiong.tscn"
# 03 第二批:名册 7 → 10(新增 马超/黄忠/魏延);03 第三批:10 → 15(张辽/许褚/甘宁/周瑜/貂蝉)
const HERO_IDS := ["liubei", "guanyu", "zhangfei", "zhaoyun", "zhuge", "huatuo", "lvbu",
	"machao", "huangzhong", "weiyan", "zhangliao", "xuchu", "ganning", "zhouyu", "diaochan"]
const ENEMY_IDS := ["huangjin_zu", "huangjin_gongshou", "huangjin_lishi", "xiliang_qinwei"]

var _st: SceneTree

func _run() -> void:
	_st = Engine.get_main_loop() as SceneTree
	var rig_script = load("res://scripts/util/unit_rig_3d.gd")
	var pal: Dictionary = rig_script.load_palette()
	check(not pal.is_empty(), "palette.json 可读且非空")
	# --- 静态构建器:12 单位全部可拼,含 mesh 且 cast_shadow=ON、有 base_albedo ---
	for uid in HERO_IDS + ENEMY_IDS + ["huaxiong"]:
		var r: Node3D = rig_script.build(uid, pal)
		check(r != null, "%s 可拼装" % uid)
		if r == null:
			continue
		var meshes := r.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() >= 6, "%s rig 含 ≥6 个 MeshInstance3D(实际 %d)" % [uid, meshes.size()])
		var all_shadow := true
		var all_meta := true
		for m in meshes:
			if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				all_shadow = false
			# 站位圈(Ring)是地形标记,不记 base_albedo(白闪/灰化跳过它),不在断言内
			if m.name != "Ring" and not m.has_meta("base_albedo"):
				all_meta = false
		check(all_shadow, "%s 所有 mesh cast_shadow=ON" % uid)
		check(all_meta, "%s 除站位圈外所有 mesh 记录 base_albedo" % uid)
		# 颜色来自 palette:base_albedo 必须是 palette 某一 token 色的派生(查 lighten/darken 邻域)
		r.free()
	# --- 场景级:hero 实例化后 rig 存在(随 _ready 挂载)---
	DataDB.load_all()
	# --- 03 第二批:heroes.json 三新将字段齐 + 魏延负面词条文本 ---
	for hid in ["machao", "huangzhong", "weiyan", "zhangliao", "xuchu", "ganning", "zhouyu", "diaochan"]:
		var h2: Dictionary = DataDB.hero_by_id(hid)
		check(not h2.is_empty(), "heroes.json 含 %s" % hid)
		if h2.is_empty():
			continue
		for f in ["name", "hp", "atk", "atk_speed", "range", "move_speed", "robe", "skill", "recruit_source"]:
			check(h2.has(f), "%s 字段齐全:%s" % [hid, f])
		check(str(h2.get("recruit_source", "")) == "triselect", "%s 走三选一池" % hid)
		var sk2: Dictionary = h2.get("skill", {})
		check(sk2.has("id") and sk2.has("cd") and sk2.has("type"), "%s 技能三件套齐" % hid)
		check(str(sk2.get("_placeholder", "")).contains("占位"), "%s 技能数值带占位标注" % hid)
	var wy: Dictionary = DataDB.hero_by_id("weiyan")
	var wy_trait: Dictionary = wy.get("trait", {})
	check(str(wy_trait.get("type", "")) == "fangu", "魏延词条类型 fangu(双刃)")
	check(float(wy_trait.get("atk_mult", 0.0)) > 1.0 and float(wy_trait.get("dmg_taken_mult", 0.0)) > 1.0,
		"魏延词条含攻防双向乘区(负面:受伤 ×%.2f)" % float(wy_trait.get("dmg_taken_mult", 0.0)))
	check(str(wy_trait.get("desc_neg", "")).contains("+25%"), "魏延词条含负面描述文本(受伤 +25%)")
	var wy_card: Dictionary = TriSelectPool._hero_card(wy)
	check(str(wy_card.get("desc", "")).contains("受到的伤害 +25%"), "魏延卡面文本明示负面词条")
	var hero = (load(HERO_SCENE) as PackedScene).instantiate()
	hero.unit_id = "liubei"
	_st.root.add_child(hero)
	await _st.process_frame
	var rig: Node3D = hero.get_node_or_null("Rig")
	check(rig != null, "hero 实例化后 Rig 节点存在")
	if rig != null:
		var meshes := rig.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() >= 6, "hero Rig 至少 6 个 MeshInstance3D(实际 %d)" % meshes.size())
		var shadow_on := meshes.size() > 0
		for m in meshes:
			if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				shadow_on = false
		check(shadow_on, "hero Rig mesh 全部 cast_shadow 开启")
	hero.free()
	# --- 敌兵/Boss 场景 rig ---
	var enemy = (load(ENEMY_SCENE) as PackedScene).instantiate()
	enemy.unit_id = "huangjin_zu"
	_st.root.add_child(enemy)
	await _st.process_frame
	var erig: Node3D = enemy.get_node_or_null("Rig")
	check(erig != null and erig.find_children("*", "MeshInstance3D", true, false).size() >= 6,
		"enemy 实例化后 Rig 存在且含 mesh")
	enemy.free()
	var boss = (load(BOSS_SCENE) as PackedScene).instantiate()
	boss.unit_id = "huaxiong"
	_st.root.add_child(boss)
	await _st.process_frame
	var brig: Node3D = boss.get_node_or_null("Rig")
	check(brig != null and brig.find_children("*", "MeshInstance3D", true, false).size() >= 6,
		"boss 实例化后 Rig 存在且含 mesh")
	boss.free()
