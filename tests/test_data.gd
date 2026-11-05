extends "res://tests/test_base.gd"
## test_data(M0):8 个 JSON 全表 schema 与锚点校验(01 数值锚点 / 02 §9)。

func _run() -> void:
	var db = load("res://scripts/autoload/data_db.gd").new()
	var ok: bool = db.load_all()
	for e in db.last_errors:
		printerr("    [schema] " + str(e))
	check(ok, "DataDB 8 表 schema 校验全绿")
	check(db.heroes.size() == 15, "heroes 15 条(主公+6 武将+03 第二批 3 将+03 第三批 5 将)")
	check(db.enemies.size() == 5, "enemies 5 条(3 敌兵+西凉亲卫+华雄)")
	check(db.waves.size() == 8, "waves 8 条")
	check(db.relics.size() == 8, "relics 8 条(必含 4 + 自拟 4)")
	check(db.upgrades.size() == 8, "upgrades 8 条")
	check(db.events.get("events", []).size() == 3, "events 3 条")
	check(not db.palette.is_empty(), "palette 非空(8 token)")
	# --- 锚点抽查(01 文档) ---
	var lord: Dictionary = db.hero_by_id("liubei")
	check(not lord.is_empty() and float(lord.hp) >= 100.0 and float(lord.hp) <= 120.0, "主公 HP 100~120")
	for hid in ["guanyu", "zhangfei", "zhaoyun", "zhuge", "huatuo", "lvbu"]:
		var h: Dictionary = db.hero_by_id(hid)
		check(not h.is_empty() and float(h.hp) >= 60.0 and float(h.hp) <= 90.0, "%s HP 60~90" % hid)
		check(not h.is_empty() and float(h.skill.cd) >= 6.0 and float(h.skill.cd) <= 15.0, "%s 技能 CD 6~15s" % hid)
	var boss: Dictionary = db.enemy_by_id("huaxiong")
	check(not boss.is_empty() and float(boss.hp) >= 1200.0 and float(boss.hp) <= 1800.0, "Boss HP 1200~1800")
	for i in range(1, 9):
		var w: Dictionary = db.wave(i)
		check(not w.is_empty(), "波 %d 存在" % i)
		check(not w.is_empty() and float(w.duration) >= 25.0 and float(w.duration) <= 45.0, "波 %d 时长 25~45s" % i)
		check(not w.is_empty() and int(w.gold_total) >= 15 and int(w.gold_total) <= 30, "波 %d 掉落 15~30" % i)
	# --- 商店单品价锚点 20~60(02 §9) ---
	for r in db.relics:
		check(float(r.price) >= 20.0 and float(r.price) <= 60.0, "遗物价 %s 在 20~60" % r.id)
	# --- 事件触发波 2/4/6 ---
	var ev_waves := {}
	for ev in db.events.events:
		ev_waves[int(ev.wave)] = true
	check(ev_waves.has(2) and ev_waves.has(4) and ev_waves.has(6), "事件触发波 2/4/6")
	# --- 拍板约束复核 ---
	check(str(db.hero_by_id("lvbu").get("recruit_source", "")) == "event", "吕布走事件招募(不入三选一)")
	for hid in ["zhaoyun", "huatuo", "zhuge", "machao", "huangzhong", "weiyan",
		"zhangliao", "ganning", "diaochan"]:
		check(int(db.hero_by_id(hid).get("recruit_min_wave", 99)) > 0, "%s 有三选一出现门槛" % hid)
	# --- 03 第二批:新技能/新词条类型 + 占位标注 + 魏延负面 ---
	for pair in [["machao", "charge"], ["huangzhong", "snipe"], ["weiyan", "frenzy"],
		["zhangliao", "fear"], ["xuchu", "taunt"], ["ganning", "dash_assassin"],
		["zhouyu", "fire_rain"], ["diaochan", "charm"]]:
		var sk: Dictionary = db.hero_by_id(pair[0]).get("skill", {})
		check(str(sk.get("type", "")) == pair[1], "%s 技能类型 %s" % [pair[0], pair[1]])
		check(str(sk.get("_placeholder", "")).contains("占位"), "%s 技能数值带占位标注" % pair[0])
	check(str(db.hero_by_id("weiyan").get("trait", {}).get("desc_neg", "")).contains("+25%"),
		"魏延词条含负面描述文本")
	# --- 03 第三批:五将口径(05 §2)---
	# 张辽:威压恐惧 2s、Boss 减半锚点;止啼受控增伤 +15%
	var zl: Dictionary = db.hero_by_id("zhangliao")
	check(absf(float(zl.get("skill", {}).get("fear_duration", 0.0)) - 2.0) < 0.001, "张辽恐惧 2s(05 §2.1)")
	check(float(zl.get("skill", {}).get("boss_duration_mult", 0.0)) == 0.5, "张辽 Boss 恐惧减半锚点(05 §2.1)")
	check(str(zl.get("trait", {}).get("type", "")) == "controlled_amp" and float(zl.get("trait", {}).get("dmg_amp", 0.0)) == 0.15,
		"张辽止啼 = 受控增伤 +15%")
	# 许褚:HP 150 全队最高;嘲讽 3s;裸衣减伤 30%
	var xc: Dictionary = db.hero_by_id("xuchu")
	check(absf(float(xc.get("hp", 0.0)) - 150.0) < 0.001, "许褚 HP 150(全队最高,05 §2.2)")
	check(absf(float(xc.get("skill", {}).get("taunt_duration", 0.0)) - 3.0) < 0.001, "许褚嘲讽 3s(05 §2.2)")
	check(absf(float(xc.get("size_mult", 1.0)) - 1.15) < 0.001, "许褚体型 ×1.15(05 §2.2)")
	check(str(xc.get("trait", {}).get("type", "")) == "lowhp_dr" and absf(float(xc.get("trait", {}).get("dr", 0.0)) - 0.30) < 0.001,
		"许褚裸衣 = HP<50% 减伤 30%")
	# 甘宁:攻速 1.3 全队最快、攻距 1.4 全队最短;背袭 ×2.5;锦帆 +20% 3s
	var gn: Dictionary = db.hero_by_id("ganning")
	check(absf(float(gn.get("atk_speed", 0.0)) - 1.3) < 0.001 and absf(float(gn.get("range", 0.0)) - 1.4) < 0.001,
		"甘宁攻速 1.3(全队最快)攻距 1.4(全队最短,05 §2.3)")
	check(absf(float(gn.get("skill", {}).get("backstab_mult", 0.0)) - 2.5) < 0.001, "甘宁背袭 ×2.5(05 §2.3)")
	check(str(gn.get("trait", {}).get("type", "")) == "kill_burst_move" and absf(float(gn.get("trait", {}).get("move_pct", 0.0)) - 0.20) < 0.001,
		"甘宁锦帆 = 击杀移速 +20%(05 §2.3)")
	# 周瑜:火雨 3 轮 0.8s 间隔 80% 伤害 + 点燃 3s;英物 CD -1
	var zy: Dictionary = db.hero_by_id("zhouyu")
	var zy_sk: Dictionary = zy.get("skill", {})
	check(int(zy_sk.get("rounds", 0)) == 3 and absf(float(zy_sk.get("interval", 0.0)) - 0.8) < 0.001,
		"周瑜火雨 3 轮 / 0.8s 间隔(05 §2.4)")
	check(absf(float(zy_sk.get("dmg_mult", 0.0)) - 0.8) < 0.001 and absf(float(zy_sk.get("burn_duration", 0.0)) - 3.0) < 0.001,
		"周瑜火雨每轮 80% + 点燃 3s(05 §2.4)")
	check(str(zy.get("trait", {}).get("type", "")) == "burn_kill_cd" and absf(float(zy.get("trait", {}).get("cd_reduce", 0.0)) - 1.0) < 0.001,
		"周瑜英物 = 点燃杀火雨 CD -1s")
	# 貂蝉:HP 65 全队最低;魅惑 4s / Boss 1.5s;连环受控增伤 +15%
	var dc: Dictionary = db.hero_by_id("diaochan")
	check(absf(float(dc.get("hp", 0.0)) - 65.0) < 0.001, "貂蝉 HP 65(全队最低,05 §2.5)")
	check(absf(float(dc.get("skill", {}).get("duration", 0.0)) - 4.0) < 0.001
		and absf(float(dc.get("skill", {}).get("boss_duration", 0.0)) - 1.5) < 0.001,
		"貂蝉魅惑 4s / Boss 踌躇 1.5s(05 §2.5)")
	check(str(dc.get("trait", {}).get("type", "")) == "controlled_amp" and float(dc.get("trait", {}).get("dmg_amp", 0.0)) == 0.15,
		"貂蝉连环 = 受控增伤 +15%(与止啼同构)")
	# 三批五将全走三选一池且 W2+ 门槛
	for hid in ["zhangliao", "xuchu", "ganning", "zhouyu", "diaochan"]:
		var h3: Dictionary = db.hero_by_id(hid)
		check(str(h3.get("recruit_source", "")) == "triselect", "%s 走三选一池" % hid)
		check(int(h3.get("recruit_min_wave", 99)) >= 2, "%s 有三选一出现门槛(W%d)" % [hid, int(h3.get("recruit_min_wave", 99))])
	check(_lord_count(db) == 1, "有且仅有 1 名主公(is_lord)")
	db.free()

func _lord_count(db) -> int:
	var n := 0
	for h in db.heroes:
		if bool(h.get("is_lord", false)):
			n += 1
	return n
