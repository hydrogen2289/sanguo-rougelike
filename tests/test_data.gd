extends "res://tests/test_base.gd"
## test_data(M0):8 个 JSON 全表 schema 与锚点校验(01 数值锚点 / 02 §9)。

func _run() -> void:
	var db = load("res://scripts/autoload/data_db.gd").new()
	var ok: bool = db.load_all()
	for e in db.last_errors:
		printerr("    [schema] " + str(e))
	check(ok, "DataDB 8 表 schema 校验全绿")
	check(db.heroes.size() == 7, "heroes 7 条(主公+6 武将,已拍板约束 7)")
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
	for hid in ["zhaoyun", "huatuo", "zhuge"]:
		check(int(db.hero_by_id(hid).get("recruit_min_wave", 99)) > 0, "%s 有三选一出现门槛" % hid)
	check(_lord_count(db) == 1, "有且仅有 1 名主公(is_lord)")
	db.free()

func _lord_count(db) -> int:
	var n := 0
	for h in db.heroes:
		if bool(h.get("is_lord", false)):
			n += 1
	return n
