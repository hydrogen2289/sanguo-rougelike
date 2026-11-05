extends Node
## DataDB —— 数据层 autoload(M0)。
## 启动时一次性加载 data/ 下 8 个 JSON 并做 schema 校验;
## 缺字段 / 数值越出 01 文档锚点区间即 fail fast(打印表名+行号,退出码 1)。
## 调平衡只改 JSON,不动代码(02 §6)。

const DATA_DIR := "res://data/"

var palette: Dictionary = {}
var heroes: Array = []
var enemies: Array = []
var waves: Array = []
var relics: Array = []
var upgrades: Array = []
var events: Dictionary = {}
var shop: Dictionary = {}

var last_errors: PackedStringArray = PackedStringArray()

func _ready() -> void:
	if not load_all():
		for e in last_errors:
			printerr("[DataDB] " + e)
		# --script 模式(工具/测试)由调用方决定退出码;游戏模式 fail fast
		if OS.get_cmdline_args().has("--script"):
			return
		printerr("[DataDB] 数据 schema 校验失败,fail fast 退出。")
		get_tree().quit(1)
	else:
		print("[DataDB] 8 表加载 + schema 校验通过。")

# ---------------------------------------------------------------- 加载

func load_all() -> bool:
	last_errors = PackedStringArray()
	palette = _load_dict("palette")
	heroes = _load_array("heroes", "heroes")
	enemies = _load_array("enemies", "enemies")
	waves = _load_array("waves", "waves")
	relics = _load_array("relics", "relics")
	upgrades = _load_array("upgrades", "upgrades")
	events = _load_dict("events")
	shop = _load_dict("shop")
	if last_errors.is_empty():
		_validate_all()
	return last_errors.is_empty()

func _read_json(table: String):
	var path := DATA_DIR + table + ".json"
	if not FileAccess.file_exists(path):
		_err(table, -1, "-", "文件缺失: " + path)
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		_err(table, -1, "-", "JSON 解析失败")
		return null
	return parsed

func _load_dict(table: String) -> Dictionary:
	var parsed = _read_json(table)
	if parsed is Dictionary:
		return parsed
	return {}

func _load_array(table: String, key: String) -> Array:
	var parsed = _read_json(table)
	if parsed == null:
		return []
	if parsed is Dictionary and parsed.has(key) and parsed[key] is Array:
		return parsed[key]
	_err(table, -1, "-", "根对象缺少数组字段 '%s'" % key)
	return []

# ---------------------------------------------------------------- 查询

func hero_by_id(id: String) -> Dictionary:
	for h in heroes:
		if str(h.get("id", "")) == id:
			return h
	return {}

func enemy_by_id(id: String) -> Dictionary:
	for e in enemies:
		if str(e.get("id", "")) == id:
			return e
	return {}

func wave(idx: int) -> Dictionary:
	for w in waves:
		if int(w.get("idx", -1)) == idx:
			return w
	return {}

func relic_by_id(id: String) -> Dictionary:
	for r in relics:
		if str(r.get("id", "")) == id:
			return r
	return {}

func upgrade_by_id(id: String) -> Dictionary:
	for u in upgrades:
		if str(u.get("id", "")) == id:
			return u
	return {}

func event_by_id(id: String) -> Dictionary:
	for ev in events.get("events", []):
		if str(ev.get("id", "")) == id:
			return ev
	return {}

func event_for_wave(idx: int) -> Dictionary:
	for ev in events.get("events", []):
		if int(ev.get("wave", -1)) == idx:
			return ev
	return {}

# ---------------------------------------------------------------- 校验

func _err(table: String, row: int, id: String, msg: String) -> void:
	last_errors.append("表[%s] 行[%d] (%s): %s" % [table, row, id, msg])

func _need(d: Dictionary, keys: Array, table: String, row: int) -> bool:
	var ok := true
	for k in keys:
		if not d.has(k):
			_err(table, row, str(d.get("id", "?")), "缺字段 '%s'" % k)
			ok = false
	return ok

func _range(table: String, row: int, d: Dictionary, key: String, lo: float, hi: float) -> void:
	if not d.has(key):
		return
	var v := float(d[key])
	if v < lo or v > hi:
		_err(table, row, str(d.get("id", "?")), "%s=%.2f 越出锚点区间 [%.2f, %.2f]" % [key, v, lo, hi])

func _unique_ids(arr: Array, table: String) -> void:
	var seen := {}
	for i in arr.size():
		var id := str(arr[i].get("id", ""))
		if id == "":
			_err(table, i, "-", "缺 id")
		elif seen.has(id):
			_err(table, i, id, "id 重复")
		seen[id] = true

func _validate_all() -> void:
	_validate_palette()
	_validate_heroes()
	_validate_enemies()
	_validate_waves()
	_validate_relics()
	_validate_upgrades()
	_validate_events()
	_validate_shop()

func _validate_palette() -> void:
	var tokens := ["paper", "paper_dark", "spring_green", "deep_green", "dark_brown", "cinnabar", "gold", "huangjin"]
	for t in tokens:
		if not palette.has(t):
			_err("palette", -1, t, "缺色 token")
		elif not str(palette[t]).begins_with("#"):
			_err("palette", -1, t, "色值格式应为 #RRGGBB")

func _validate_heroes() -> void:
	if heroes.is_empty():
		return
	_unique_ids(heroes, "heroes")
	var lord_count := 0
	for i in heroes.size():
		var h: Dictionary = heroes[i]
		_need(h, ["id", "name", "is_lord", "hp", "atk", "atk_speed", "range", "move_speed", "skill", "recruit_min_wave"], "heroes", i)
		var is_lord: bool = bool(h.get("is_lord", false))
		if is_lord:
			lord_count += 1
			_range("heroes", i, h, "hp", 100, 120)      # 主公 HP 锚点(02 §9)
		elif str(h.get("id", "")) == "xuchu" or str(h.get("id", "")) == "zhangliao":
			_range("heroes", i, h, "hp", 60, 160)
			# 03 第三批:许褚 HP 150(全队最高,05 §2.2)/ 张辽 HP 95(05 §2.1,90 锚点之上)放宽
		else:
			_range("heroes", i, h, "hp", 60, 90)        # 武将 HP 锚点(01 §4)
		_range("heroes", i, h, "atk", 1, 35)
		# 03 第三批:甘宁攻速 1.3(全队最快,05 §2.3)锚点放宽到 1.5
		_range("heroes", i, h, "atk_speed", 0.5, 1.5)
		_range("heroes", i, h, "range", 1, 8)     # 03 第二批:黄忠 6.5m(全队最远),锚点放宽到 8
		_range("heroes", i, h, "move_speed", 3.5, 6.0)   # 03 第二批:马超 5.6(全队最快),锚点放宽到 6
		_range("heroes", i, h, "recruit_min_wave", 0, 8)
		var skill: Dictionary = h.get("skill", {})
		_need(skill, ["id", "name", "cd", "type"], "heroes", i)
		_range("heroes", i, skill, "cd", 6, 18)         # 技能 CD 锚点;03 第三批貂蝉闭月 16s(05 §2.5),放宽到 18
		# 03 第二批追加:charge(马超铁骑冲锋)/ snipe(黄忠百步穿杨)/ frenzy(魏延狂骨)
		# 03 第三批追加:fear(张辽威压)/ taunt(许褚虎痴)/ dash_assassin(甘宁百翎直袭)/
		#               fire_rain(周瑜火雨)/ charm(貂蝉闭月)
		var known_types := ["shield", "cone", "nova", "dash", "weather", "heal_all", "triple_nova",
			"charge", "snipe", "frenzy", "fear", "taunt", "dash_assassin", "fire_rain", "charm"]
		if skill.has("type") and not known_types.has(str(skill["type"])):
			_err("heroes", i, str(h.get("id", "?")), "未知技能类型 %s" % str(skill["type"]))
		if h.has("trait"):
			var tr: Dictionary = h["trait"]
			_need(tr, ["id", "name", "type"], "heroes", i)
			# 03 第二批追加:fangu(魏延反骨,双刃词条);auraless = 无被动占位标记
			# 03 第三批追加:controlled_amp(止啼/连环 受控增伤)/ lowhp_dr(裸衣 低血减伤)/
			#               kill_burst_move(锦帆 击杀移速)/ burn_kill_cd(英物 点燃杀减 CD)
			var known_traits := ["aura", "execution", "enrage", "disobey", "fangu", "auraless",
				"controlled_amp", "lowhp_dr", "kill_burst_move", "burn_kill_cd"]
			if tr.has("type") and not known_traits.has(str(tr["type"])):
				_err("heroes", i, str(h.get("id", "?")), "未知个性机制 %s" % str(tr["type"]))
	if lord_count != 1:
		_err("heroes", -1, "-", "有且仅有 1 名主公(is_lord),实际 %d" % lord_count)

func _validate_enemies() -> void:
	if enemies.is_empty():
		return
	_unique_ids(enemies, "enemies")
	var known_ai := ["melee", "ranged", "boss"]
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		_need(e, ["id", "name", "ai", "move_speed", "size", "atk_interval"], "enemies", i)
		var ai := str(e.get("ai", ""))
		if not known_ai.has(ai):
			_err("enemies", i, str(e.get("id", "?")), "未知 ai 类型 %s" % ai)
		if ai == "boss":
			_range("enemies", i, e, "hp", 1200, 1800)   # Boss HP 锚点(02 §9)
			_need(e, ["atk_slash", "atk_slam", "atk_charge", "phase2_hp_ratio"], "enemies", i)
		else:
			_range("enemies", i, e, "hp_mult", 0.5, 3.0)
			_range("enemies", i, e, "atk_mult", 0.3, 3.0)
		_range("enemies", i, e, "atk_interval", 0.5, 3.0)
		_range("enemies", i, e, "move_speed", 1.5, 3.0)
		_range("enemies", i, e, "size", 0.5, 2.0)
		_range("enemies", i, e, "kb_resist", 0.0, 1.0)
		if ai == "ranged":
			_need(e, ["attack_range", "keep_distance", "arrow_speed"], "enemies", i)

func _validate_waves() -> void:
	if waves.is_empty():
		return
	var enemy_ids := {}
	for e in enemies:
		enemy_ids[str(e.get("id", ""))] = true
	for i in waves.size():
		var w: Dictionary = waves[i]
		var wid := str(w.get("idx", "?"))
		_need(w, ["idx", "duration", "base_hp", "base_atk", "composition", "gold_total"], "waves", i)
		if int(w.get("idx", -1)) != i + 1:
			_err("waves", i, wid, "idx 应为 %d(顺序排列)" % (i + 1))
		_range("waves", i, w, "duration", 25, 45)       # 单波时长锚点(02 §9)
		_range("waves", i, w, "base_hp", 15, 30)        # 敌兵基础 HP 锚点(01 §6)
		_range("waves", i, w, "base_atk", 3, 12)
		_range("waves", i, w, "gold_total", 15, 30)     # 波掉落锚点(01 §6)
		var comp: Dictionary = w.get("composition", {})
		if comp.is_empty():
			_err("waves", i, wid, "composition 为空")
		for id in comp:
			if not enemy_ids.has(str(id)):
				_err("waves", i, wid, "composition 引用不存在的敌人 '%s'" % str(id))
			if int(comp[id]) <= 0:
				_err("waves", i, wid, "敌人 %s 数量非法" % str(id))
		for a in w.get("after", []):
			var s := str(a)
			if s != "triselect" and s != "shop" and s != "victory" and not s.begins_with("event_"):
				_err("waves", i, wid, "after 队列含未知项 '%s'" % s)
		# --- 关卡剧本校验(docs/03-关卡设计.md §2):主题/目标/分批投放/扇区 ---
		if w.has("theme") and str(w["theme"]).is_empty():
			_err("waves", i, wid, "theme 为空字符串")
		if w.has("objective"):
			var obj: Dictionary = w.get("objective", {})
			if str(obj.get("type", "")).is_empty() or str(obj.get("label", "")).is_empty():
				_err("waves", i, wid, "objective 缺 type/label")
		var plan: Dictionary = w.get("spawn_plan", {})
		if not plan.is_empty():
			var default_arc: Array = plan.get("arc", [])
			_validate_arc(i, default_arc, wid)
			var batches: Array = plan.get("batches", [])
			if batches.is_empty():
				_err("waves", i, wid, "spawn_plan.batches 为空")
			var sums := {}
			var last_t := -1.0
			var max_t := float(w.get("duration", 30)) * 0.5   # 与 SPAWN_WINDOW 一致
			for bi in batches.size():
				var b: Dictionary = batches[bi]
				var t := float(b.get("t", -1.0))
				if t < 0.0 or t > max_t:
					_err("waves", i, wid, "批次 %d t=%.1f 越出投放窗口 [0, %.1f]" % [bi, t, max_t])
				if t < last_t:
					_err("waves", i, wid, "批次 %d 时间非单调(%.1f < %.1f)" % [bi, t, last_t])
				last_t = t
				_validate_arc(i, b.get("arc", default_arc), wid)
				var sp: Dictionary = b.get("spawn", {})
				if sp.is_empty():
					_err("waves", i, wid, "批次 %d spawn 为空" % bi)
				for id in sp:
					if not enemy_ids.has(str(id)):
						_err("waves", i, wid, "批次 %d 引用不存在的敌人 '%s'" % [bi, str(id)])
					if int(sp[id]) <= 0:
						_err("waves", i, wid, "批次 %d 敌人 %s 数量非法" % [bi, str(id)])
					sums[str(id)] = int(sums.get(str(id), 0)) + int(sp[id])
			for id in comp:
				if int(sums.get(str(id), 0)) != int(comp[id]):
					_err("waves", i, wid, "spawn_plan 与 composition 数量不一致: %s" % str(id))
			for id in sums:
				if not comp.has(str(id)):
					_err("waves", i, wid, "spawn_plan 多出 composition 未声明的敌人: %s" % str(id))
		var rf: Dictionary = w.get("reinforcement", {})
		if rf.has("arc"):
			_validate_arc(i, rf.get("arc", []), wid)

## arc 必须为 [起,止] 且 -180 <= 起 < 止 <= 180;空数组由调用方按全向处理。
func _validate_arc(row: int, arc, wid: String) -> void:
	if arc == null:
		return
	if not (arc is Array):
		_err("waves", row, wid, "arc 应为 [起,止] 数组")
		return
	var a: Array = arc
	if a.size() != 2:
		_err("waves", row, wid, "arc 长度应为 2")
		return
	var lo := float(a[0])
	var hi := float(a[1])
	if lo < -180.0 or hi > 180.0 or lo >= hi:
		_err("waves", row, wid, "arc=[%.1f,%.1f] 非法(应 -180<=起<止<=180)" % [lo, hi])

func _validate_relics() -> void:
	if relics.is_empty():
		return
	_unique_ids(relics, "relics")
	for i in relics.size():
		var r: Dictionary = relics[i]
		_need(r, ["id", "name", "rarity", "price", "effects"], "relics", i)
		var rar := str(r.get("rarity", ""))
		if not ["normal", "rare", "epic"].has(rar):
			_err("relics", i, str(r.get("id", "?")), "未知稀有度 %s" % rar)
		_range("relics", i, r, "price", 20, 60)         # 商店单品价锚点(02 §9)
		if r.has("effects") and (r["effects"] as Dictionary).is_empty():
			_err("relics", i, str(r.get("id", "?")), "effects 为空")

func _validate_upgrades() -> void:
	if upgrades.is_empty():
		return
	_unique_ids(upgrades, "upgrades")
	for i in upgrades.size():
		var u: Dictionary = upgrades[i]
		_need(u, ["id", "name", "effect", "desc"], "upgrades", i)
		if u.has("effect") and (u["effect"] as Dictionary).is_empty():
			_err("upgrades", i, str(u.get("id", "?")), "effect 为空")
		if u.has("shop_price") and float(u["shop_price"]) > 0.0:
			_range("upgrades", i, u, "shop_price", 20, 35)

func _validate_events() -> void:
	var pro: Dictionary = events.get("prologue", {})
	_need(pro, ["title", "lines"], "events", -1)
	var evs: Array = events.get("events", [])
	_unique_ids(evs, "events")
	var expected := {2: true, 4: true, 6: true}
	for i in evs.size():
		var ev: Dictionary = evs[i]
		_need(ev, ["id", "name", "wave", "story", "option_a", "option_b"], "events", i)
		var w := int(ev.get("wave", -1))
		if not expected.has(w):
			_err("events", i, str(ev.get("id", "?")), "事件触发波 %d 不在 {2,4,6}" % w)
		expected.erase(w)
		for key in ["option_a", "option_b"]:
			var opt: Dictionary = ev.get(key, {})
			_need(opt, ["label", "effect", "desc"], "events", i)
	if not expected.is_empty():
		_err("events", -1, "-", "缺少触发波次: %s" % str(expected.keys()))

func _validate_shop() -> void:
	if shop.is_empty():
		return
	_need(shop, ["shop_waves", "slots", "refresh_price", "relic_price"], "shop", -1)
	var sw: Array = shop.get("shop_waves", [])
	var sw_ints := {}
	for w in sw:
		sw_ints[int(w)] = true
	if not (sw_ints.has(4) and sw_ints.has(6)):
		_err("shop", -1, "-", "shop_waves 应为 [4, 6](已拍板排程)")
	_range("shop", -1, shop, "slots", 4, 8)
	_range("shop", -1, shop, "refresh_price", 10, 50)
	var rp: Dictionary = shop.get("relic_price", {})
	for rar in ["normal", "rare", "epic"]:
		if rp.has(rar):
			_range("shop", -1, rp, rar, 20, 60)
		else:
			_err("shop", -1, rar, "缺稀有度定价")
