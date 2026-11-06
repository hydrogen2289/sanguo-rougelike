extends Node
## DataDB —— 数据层 autoload(M0;M8 扩 economy;M9 扩 campaign;M10 扩 tower)。
## 启动时一次性加载 data/ 下 11 个 JSON(见 TABLE_NAMES)并做 schema 校验;
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
var economy: Dictionary = {}           # M8 养成/招募/结算参数(02 §4.5)
var campaign: Dictionary = {}          # M9 战役关卡表:章节→关卡→波次脚本(02 §4.2/§4.3)
var tower: Dictionary = {}             # M10 试炼塔层参数与生成规则(02 §4.4)

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
		# 表数按实际加载清单点数,别再手写死数字(加表后忘了改会误导排障)
		print("[DataDB] %d 表加载 + schema 校验通过。" % _loaded_table_count())

# ---------------------------------------------------------------- 加载

## 已加载的表数(启动打印用):表清单的唯一出处,加表只改这里
const TABLE_NAMES := ["palette", "heroes", "enemies", "waves", "relics", "upgrades",
	"events", "shop", "economy", "campaign", "tower"]

func _loaded_table_count() -> int:
	return TABLE_NAMES.size()

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
	economy = _load_dict("economy")
	campaign = _load_dict("campaign")
	tower = _load_dict("tower")
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

## 战役关卡行(M9,02 §4.2):返回关卡表副本并带出所属章节 chapter_id;
## 波次脚本(waves)随副本带出,wave_director 闯关模式据此逐波喂入。
func stage_by_id(stage_id: String) -> Dictionary:
	for ch in campaign.get("chapters", []):
		for st in ch.get("stages", []):
			if str(st.get("id", "")) == stage_id:
				var out: Dictionary = (st as Dictionary).duplicate(true)
				out["chapter_id"] = str(ch.get("id", ""))
				return out
	return {}

## 章节列表(M9,02 §4.2):按 order 升序;返回表内引用(只读约定,不复制)。
func chapter_list() -> Array:
	var out: Array = []
	for ch in campaign.get("chapters", []):
		out.append(ch)
	out.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return out

# ---------------------------------------------------------------- 塔(M10,02 §4.4)

## 塔层波次(02 §4.2 查询器 tower_floor):
## 1~floors_ref.to 层取 waves.json 对应波;gen_from 起交给 TowerWaveGen 按 seed 生成;
## 生成失败返回空字典(TowerWaveGen.last_error 带原因),调用方按波次缺失兜底。
## seed 由调用方(SceneRouter 注入的塔 seed)传入,保证同局可复现。
func tower_floor(n: int, tower_seed: int = 0) -> Dictionary:
	if n < 1:
		return {}
	var ref: Dictionary = tower.get("floors_ref", {})
	var ref_to := int(ref.get("to", 8))
	if n <= ref_to:
		return wave(n) if str(ref.get("source", "waves.json")) == "waves.json" else {}
	if tower.is_empty():
		return {}
	return TowerWaveGen.generate(n, tower_seed if tower_seed != 0 else n)

## 该层是否为 Boss 层(boss_every 的整数倍,02 §4.4)
func tower_is_boss_floor(n: int) -> bool:
	var every := int(tower.get("boss_every", 8))
	return every > 0 and n > 0 and n % every == 0

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
	_validate_economy()
	_validate_campaign()
	_validate_tower()

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
		_validate_wave_entry(w, "waves", i, wid, enemy_ids)

## 单波契约校验(waves.json 与 campaign.json 同源,02 §4.3):
## 锚点区间 / composition 引用与数量 / after 白名单 / 主题目标 / 分批投放与扇区 / 增援扇区。
## idx 顺序性由各表调用方自校(waves 全表 i+1;campaign 按关内 i+1)。
##
## check_anchors=false 供试炼塔随机生成用(M10,02 §8.3「同款校验」):结构契约
## (composition 引用与汇总一致 / 批次时间窗与单调 / arc / after 白名单)一字不改,
## 只跳过 duration/base_hp/base_atk/gold_total 的**手写剧本调参锚点** —— 塔层难度
## 就该越爬越高,拿 8 波剧本的锚点卡它会把塔锁死在第一段。
func _validate_wave_entry(w: Dictionary, table: String, row: int, wid: String, enemy_ids: Dictionary,
		check_anchors := true) -> void:
	_range(table, row, w, "duration", 25, 45)       # 单波时长锚点(02 §9)
	if check_anchors:
		_range(table, row, w, "base_hp", 15, 30)    # 敌兵基础 HP 锚点(01 §6)
		_range(table, row, w, "base_atk", 3, 12)
		_range(table, row, w, "gold_total", 15, 30) # 波掉落锚点(01 §6)
	var comp: Dictionary = w.get("composition", {})
	if comp.is_empty():
		_err(table, row, wid, "composition 为空")
	for id in comp:
		if not enemy_ids.has(str(id)):
			_err(table, row, wid, "composition 引用不存在的敌人 '%s'" % str(id))
		if int(comp[id]) <= 0:
			_err(table, row, wid, "敌人 %s 数量非法" % str(id))
	for a in w.get("after", []):
		var s := str(a)
		if s != "triselect" and s != "shop" and s != "victory" and not s.begins_with("event_"):
			_err(table, row, wid, "after 队列含未知项 '%s'" % s)
	# --- 关卡剧本校验(docs/03-关卡设计.md §2):主题/目标/分批投放/扇区 ---
	if w.has("theme") and str(w["theme"]).is_empty():
		_err(table, row, wid, "theme 为空字符串")
	if w.has("objective"):
		var obj: Dictionary = w.get("objective", {})
		if str(obj.get("type", "")).is_empty() or str(obj.get("label", "")).is_empty():
			_err(table, row, wid, "objective 缺 type/label")
	var plan: Dictionary = w.get("spawn_plan", {})
	if not plan.is_empty():
		var default_arc: Array = plan.get("arc", [])
		_validate_arc(table, row, default_arc, wid)
		var batches: Array = plan.get("batches", [])
		if batches.is_empty():
			_err(table, row, wid, "spawn_plan.batches 为空")
		var sums := {}
		var last_t := -1.0
		var max_t := float(w.get("duration", 30)) * 0.5   # 与 SPAWN_WINDOW 一致
		for bi in batches.size():
			var b: Dictionary = batches[bi]
			var t := float(b.get("t", -1.0))
			if t < 0.0 or t > max_t:
				_err(table, row, wid, "批次 %d t=%.1f 越出投放窗口 [0, %.1f]" % [bi, t, max_t])
			if t < last_t:
				_err(table, row, wid, "批次 %d 时间非单调(%.1f < %.1f)" % [bi, t, last_t])
			last_t = t
			_validate_arc(table, row, b.get("arc", default_arc), wid)
			var sp: Dictionary = b.get("spawn", {})
			if sp.is_empty():
				_err(table, row, wid, "批次 %d spawn 为空" % bi)
			for id in sp:
				if not enemy_ids.has(str(id)):
					_err(table, row, wid, "批次 %d 引用不存在的敌人 '%s'" % [bi, str(id)])
				if int(sp[id]) <= 0:
					_err(table, row, wid, "批次 %d 敌人 %s 数量非法" % [bi, str(id)])
				sums[str(id)] = int(sums.get(str(id), 0)) + int(sp[id])
		for id in comp:
			if int(sums.get(str(id), 0)) != int(comp[id]):
				_err(table, row, wid, "spawn_plan 与 composition 数量不一致: %s" % str(id))
		for id in sums:
			if not comp.has(str(id)):
				_err(table, row, wid, "spawn_plan 多出 composition 未声明的敌人: %s" % str(id))
	var rf: Dictionary = w.get("reinforcement", {})
	if rf.has("arc"):
		_validate_arc(table, row, rf.get("arc", []), wid)

## arc 必须为 [起,止] 且 -180 <= 起 < 止 <= 180;空数组由调用方按全向处理。
func _validate_arc(table: String, row: int, arc, wid: String) -> void:
	if arc == null:
		return
	if not (arc is Array):
		_err(table, row, wid, "arc 应为 [起,止] 数组")
		return
	var a: Array = arc
	if a.size() != 2:
		_err(table, row, wid, "arc 长度应为 2")
		return
	var lo := float(a[0])
	var hi := float(a[1])
	if lo < -180.0 or hi > 180.0 or lo >= hi:
		_err(table, row, wid, "arc=[%.1f,%.1f] 非法(应 -180<=起<止<=180)" % [lo, hi])

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

## 经济表(M8,02 §4.5):养成曲线常数 / 招募定价 / 稀有度分档 / 结算系数。
## 这里只校验自身内在一致;与 SaveState 常量(LEVEL_CAP=30 / STAR_CAP=5)的
## 一致由 tests/test_meta.gd 交叉断言——DataDB 先于 SaveState 加载,不能反向依赖。
const ECON_LEVEL_CAP := 30
const ECON_STAR_CAP := 5

func _validate_economy() -> void:
	if economy.is_empty():
		return
	_need(economy, ["level", "star", "star_up_cost", "recruit", "rarity", "settle"], "economy", -1)
	var lv: Dictionary = economy.get("level", {})
	_need(lv, ["cap", "growth_per_level", "cost_base", "cost_exp"], "economy", -1)
	if int(lv.get("cap", 0)) != ECON_LEVEL_CAP:
		_err("economy", -1, "level.cap", "应为 %d" % ECON_LEVEL_CAP)
	_range("economy", -1, lv, "growth_per_level", 0.01, 0.5)
	_range("economy", -1, lv, "cost_base", 1, 1000)
	_range("economy", -1, lv, "cost_exp", 1.0, 2.5)
	var st: Dictionary = economy.get("star", {})
	_need(st, ["cap", "mult_per_star"], "economy", -1)
	if int(st.get("cap", 0)) != ECON_STAR_CAP:
		_err("economy", -1, "star.cap", "应为 %d" % ECON_STAR_CAP)
	_range("economy", -1, st, "mult_per_star", 0.05, 0.5)
	# 升星消耗表:长度 = 星级上限-1(1→2 … cap-1→cap)
	var costs: Array = economy.get("star_up_cost", [])
	if costs.size() != ECON_STAR_CAP - 1:
		_err("economy", -1, "star_up_cost", "长度应为 %d" % (ECON_STAR_CAP - 1))
	var prev := 0
	for c in costs:
		if int(c) <= prev:
			_err("economy", -1, "star_up_cost", "消耗应严格递增")
		prev = int(c)
	# 招募:三档定价齐全且递增
	var rec: Dictionary = economy.get("recruit", {})
	_need(rec, ["buy_price", "fuse_cost", "dupe_to_fragment"], "economy", -1)
	var bp: Dictionary = rec.get("buy_price", {})
	var fc: Dictionary = rec.get("fuse_cost", {})
	var last_price := 0
	for rar in ["normal", "rare", "epic"]:
		if not bp.has(rar) or not fc.has(rar):
			_err("economy", -1, rar, "缺招募定价/合成消耗")
			continue
		if int(bp[rar]) <= last_price:
			_err("economy", -1, rarity_key(rar), "直购价应严格递增")
		last_price = int(bp[rar])
	_range("economy", -1, rec, "dupe_to_fragment", 1, 100)
	# 稀有度分档:每个 id 合法且只出现一次;合起来覆盖全部武将
	var legal := {}
	for h in heroes:
		legal[str(h.get("id", ""))] = true
	var seen := {}
	for tier in ["starting", "normal", "rare", "epic"]:
		if not (economy.get("rarity", {}).get(tier) is Array):
			_err("economy", -1, tier, "稀有度分档缺失或非数组")
			continue
		for id in economy["rarity"][tier]:
			if not legal.has(str(id)):
				_err("economy", -1, str(id), "稀有度分档含非法武将 id")
			if seen.has(str(id)):
				_err("economy", -1, str(id), "武将 id 在多个稀有度分档重复")
			seen[str(id)] = true
	for id in legal:
		if not seen.has(id):
			_err("economy", -1, id, "武将未登记稀有度分档")
	# 结算系数非负(公式归 RewardSettle,M11)
	var se: Dictionary = economy.get("settle", {})
	for k in ["retreat_mult", "death_mult", "repeat_mult", "repeat_fragments"]:
		_range("economy", -1, se, k, 0.0, 10.0)

func rarity_key(rar: String) -> String:
	return "recruit.buy_price." + rar

## 武将稀有度("starting"/"normal"/"rare"/"epic");未登记返回 "normal"
func hero_rarity(hero_id: String) -> String:
	var rr: Dictionary = economy.get("rarity", {})
	for tier in ["starting", "normal", "rare", "epic"]:
		if str(hero_id) in rr.get(tier, []):
			return tier
	return "normal"

## 战役关卡表(M9,02 §4.3):结构 / 引用完整性 / 波次契约 / 奖励字段,
## fail fast 风格与 9 表一致(启动即校验,坏表拒绝进游戏)。
func _validate_campaign() -> void:
	if campaign.is_empty():
		return
	var chapters = campaign.get("chapters", [])
	if not (chapters is Array) or (chapters as Array).is_empty():
		_err("campaign", -1, "-", "chapters 缺失或为空")
		return
	var enemy_ids := {}
	for e in enemies:
		enemy_ids[str(e.get("id", ""))] = true
	var hero_ids := {}
	for h in heroes:
		hero_ids[str(h.get("id", ""))] = true
	# --- 第一遍:章节/关卡结构与波次契约 ---
	var stage_ids := {}
	var chapter_ids := {}
	var has_entry_stage := false
	for ci in (chapters as Array).size():
		var ch: Dictionary = chapters[ci]
		_need(ch, ["id", "name", "order", "unlock", "stages"], "campaign", ci)
		var cid := str(ch.get("id", ""))
		if cid.is_empty():
			_err("campaign", ci, "-", "章节缺 id")
		elif chapter_ids.has(cid):
			_err("campaign", ci, cid, "章节 id 重复")
		chapter_ids[cid] = true
		_range("campaign", ci, ch, "order", 1, 99)
		var stages = ch.get("stages", [])
		if not (stages is Array) or (stages as Array).is_empty():
			_err("campaign", ci, cid, "章节缺 stages 或为空")
			continue
		for si in (stages as Array).size():
			var st: Dictionary = stages[si]
			_need(st, ["id", "name", "unlock_after", "waves", "first_clear", "repeat_clear", "boss_stage"],
				"campaign", si)
			var sid := str(st.get("id", ""))
			if sid.is_empty():
				_err("campaign", si, "-", "关卡缺 id")
			elif stage_ids.has(sid):
				_err("campaign", si, sid, "关卡 id 重复")
			stage_ids[sid] = true
			_range("campaign", si, st, "rec_power", 0, 1000000)
			var wv = st.get("waves", [])
			if not (wv is Array) or (wv as Array).is_empty():
				_err("campaign", si, sid, "关卡无波次脚本")
				continue
			if (wv as Array).size() > 3:
				_err("campaign", si, sid, "波次 %d 越出 [1,3](01 §3.1 短关卡锚点)" % (wv as Array).size())
			if bool(st.get("boss_stage", false)) and (wv as Array).size() > 1:
				var last_w: Dictionary = wv[(wv as Array).size() - 1]
				var boss_in_last := false
				for eid in last_w.get("composition", {}):
					if str(enemy_by_id(str(eid)).get("ai", "")) == "boss":
						boss_in_last = true
				if not boss_in_last:
					_err("campaign", si, sid, "boss_stage=true 但末波 composition 无 Boss 敌人")
			for wi in (wv as Array).size():
				var w: Dictionary = wv[wi]
				_need(w, ["idx", "duration", "base_hp", "base_atk", "composition", "gold_total"],
					"campaign", si)
				if int(w.get("idx", -1)) != wi + 1:
					_err("campaign", si, sid, "第 %d 波 idx 应为 %d(关内顺序排列)" % [wi + 1, wi + 1])
				if not (w.get("after", []) as Array).is_empty():
					_err("campaign", si, sid, "第 %d 波 after 队列恒为空(波间弹窗为塔专属,02 §4.3)" % (wi + 1))
				_validate_wave_entry(w, "campaign", si, "%s/W%d" % [sid, wi + 1], enemy_ids)
			# 奖励字段(结算来源,01 §8.2)
			var fc: Dictionary = st.get("first_clear", {})
			_need(fc, ["junzi"], "campaign", si)
			if fc.has("junzi") and int(fc["junzi"]) < 0:
				_err("campaign", si, sid, "first_clear.junzi 为负")
			if fc.has("fragments"):
				if not (fc["fragments"] is Dictionary):
					_err("campaign", si, sid, "first_clear.fragments 应为 {武将id: 数量}")
				else:
					for hid in fc["fragments"]:
						if not hero_ids.has(str(hid)):
							_err("campaign", si, sid, "first_clear 绑定不存在的武将 '%s'" % str(hid))
						elif int(fc["fragments"][hid]) <= 0:
							_err("campaign", si, sid, "first_clear 碎片数量非法: %s" % str(hid))
			var rc: Dictionary = st.get("repeat_clear", {})
			_need(rc, ["junzi"], "campaign", si)
			if rc.has("junzi") and int(rc["junzi"]) < 0:
				_err("campaign", si, sid, "repeat_clear.junzi 为负")
			# 注意:str(null) 在 Godot 里是 "<null>" 而非空串,不能拿 str() 和 "" 比,
			# 否则任何 unlock_after=null 的入门关卡都判不中,推图链会被误判成无起点。
			if st.get("unlock_after") == null:
				has_entry_stage = true
	# --- 第二遍:引用完整性(unlock_after 可指向前文,统一两遍扫描) ---
	for ci in (chapters as Array).size():
		var ch: Dictionary = chapters[ci]
		var unlock: Dictionary = ch.get("unlock", {})
		var req = unlock.get("require")
		if req != null and not chapter_ids.has(str(req)):
			_err("campaign", ci, str(ch.get("id", "?")), "章节 unlock.require 引用不存在的章节 '%s'" % str(req))
		var stages = ch.get("stages", [])
		for si in (stages as Array).size():
			var st: Dictionary = stages[si]
			var ua = st.get("unlock_after")
			if ua != null and not stage_ids.has(str(ua)):
				_err("campaign", si, str(st.get("id", "?")), "unlock_after 引用不存在的关卡 '%s'" % str(ua))
	if not has_entry_stage:
		_err("campaign", -1, "-", "没有任何 unlock_after=null 的入门关卡(推图链无起点,01 §3.4)")

## 塔参数表(M10,02 §4.4):层引用区间 / 生成起点 / Boss 周期 / 生成器的曲线与池。
## 只校验自身与 enemies 表的引用一致性;生成出来的每一波另由 TowerWaveGen 走
## _validate_wave_entry 同款校验(02 §8.3),这里管表本身。
func _validate_tower() -> void:
	if tower.is_empty():
		return
	_need(tower, ["floors_ref", "gen_from", "boss_every", "gen", "boss_pool"], "tower", -1)
	var ref: Dictionary = tower.get("floors_ref", {})
	_need(ref, ["from", "to", "source"], "tower", -1)
	var rfrom := int(ref.get("from", 0))
	var rto := int(ref.get("to", 0))
	if rfrom != 1:
		_err("tower", -1, "floors_ref.from", "应为 1(塔自第 1 层起)")
	if rto < rfrom:
		_err("tower", -1, "floors_ref.to", "应 >= from")
	# 1~floors_ref.to 层逐映射到 waves.json,层数不能多于剧本波数(约束 6:1~8 层复用现剧本)
	if str(ref.get("source", "")) != "waves.json":
		_err("tower", -1, "floors_ref.source", "应为 waves.json(1~8 层沿用现剧本,02 §4.3)")
	elif rto > waves.size():
		_err("tower", -1, "floors_ref.to", "%d 超出 waves.json 波数 %d" % [rto, waves.size()])
	var gen_from := int(tower.get("gen_from", 0))
	if gen_from != rto + 1:
		_err("tower", -1, "gen_from", "应为 floors_ref.to+1 = %d(两段无缝衔接)" % (rto + 1))
	var every := int(tower.get("boss_every", 0))
	if every <= 0:
		_err("tower", -1, "boss_every", "应为正整数")
	var gen: Dictionary = tower.get("gen", {})
	_need(gen, ["base_hp", "base_atk", "count", "batch_n", "enemy_pool", "elite_from_floor", "ranged_ratio"],
		"tower", -1)
	for key in ["base_hp", "base_atk"]:
		var c: Dictionary = gen.get(key, {})
		_need(c, ["f0", "growth"], "tower", -1)
		if c.has("f0") and float(c["f0"]) <= 0.0:
			_err("tower", -1, key, "f0 应为正")
		if c.has("growth") and float(c["growth"]) < 1.0:
			_err("tower", -1, key, "growth 应 >= 1(同层递进不降)")
	var cnt: Dictionary = gen.get("count", {})
	_need(cnt, ["f0", "per_floor", "cap"], "tower", -1)
	if cnt.has("cap") and int(cnt["cap"]) < int(cnt.get("f0", 0)):
		_err("tower", -1, "count.cap", "应 >= f0")
	var bn: Array = gen.get("batch_n", [])
	if bn.size() != 2 or int(bn[0]) < 1 or int(bn[1]) < int(bn[0]) or int(bn[1]) > 8:
		_err("tower", -1, "batch_n", "应为 [最小, 最大] 且 1 <= 最小 <= 最大 <= 8")
	var rr: Array = gen.get("ranged_ratio", [])
	if rr.size() != 2 or float(rr[0]) < 0.0 or float(rr[1]) > 1.0 or float(rr[1]) < float(rr[0]):
		_err("tower", -1, "ranged_ratio", "应为 [最小, 最大] 且 0 <= 最小 <= 最大 <= 1")
	# 敌池:每个 id 必须在 enemies.json 里且不是 Boss(Boss 只走 boss_pool)
	var pool: Array = gen.get("enemy_pool", [])
	if pool.is_empty():
		_err("tower", -1, "enemy_pool", "为空")
	for id in pool:
		var e: Dictionary = enemy_by_id(str(id))
		if e.is_empty():
			_err("tower", -1, str(id), "enemy_pool 引用不存在的敌人")
		elif str(e.get("ai", "")) == "boss":
			_err("tower", -1, str(id), "Boss 不应进 enemy_pool(走 boss_pool)")
	var boss_pool: Array = tower.get("boss_pool", [])
	if boss_pool.is_empty():
		_err("tower", -1, "boss_pool", "为空")
	for id in boss_pool:
		var e: Dictionary = enemy_by_id(str(id))
		if e.is_empty():
			_err("tower", -1, str(id), "boss_pool 引用不存在的敌人")
		elif str(e.get("ai", "")) != "boss":
			_err("tower", -1, str(id), "boss_pool 只能放 ai=boss 的敌人")
	_range("tower", -1, gen, "elite_from_floor", 1, 99)
