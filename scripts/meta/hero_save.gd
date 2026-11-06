class_name HeroSave
extends RefCounted
## HeroSave —— 跨局养成域(M8,02 §5):等级/星级曲线、升级升星、招募、编队席位。
## 只读写 SaveState.data 与 DataDB.economy;不做界面、不落盘(界面改完调 SaveState.flush)。
## 曲线常数全部取自 data/economy.json —— 调平衡只改表(02 §12.3)。
## 返回约定:所有写操作返回 {ok: bool, reason: String, ...额外字段};失败不改动存档。

# ---------------------------------------------------------------- 曲线(02 §5.1/§5.2)

static func _econ() -> Dictionary:
	return DataDB.economy

static func level_cap() -> int:
	return int(_econ().get("level", {}).get("cap", 30))

static func star_cap() -> int:
	return int(_econ().get("star", {}).get("cap", 5))

## 等级乘区:1 + 0.08×(L−1),乘在出场基础 HP/ATK 上(02 §5.1)
static func level_mult(level: int) -> float:
	var g := float(_econ().get("level", {}).get("growth_per_level", 0.08))
	return 1.0 + g * float(maxi(1, level) - 1)

## 星级乘区:1 + 0.15×(S−1)(02 §5.2)
static func star_mult(star: int) -> float:
	var g := float(_econ().get("star", {}).get("mult_per_star", 0.15))
	return 1.0 + g * float(maxi(1, star) - 1)

## 出场基础值乘区 = 等级 × 星级;战斗层单位实例化读表后乘此值(02 §5.4)
static func factors(hero_id: String) -> float:
	var e := entry(hero_id)
	if not bool(e.get("owned", true)):
		return 1.0
	return level_mult(int(e.get("level", 1))) * star_mult(int(e.get("star", 1)))

## 升级耗军资:round(50 × L^1.4),L→L+1(02 §5.1)
static func level_cost(level: int) -> int:
	var e: Dictionary = _econ().get("level", {})
	var base := float(e.get("cost_base", 50))
	var exp := float(e.get("cost_exp", 1.4))
	return int(round(base * pow(float(level), exp)))

## 升星耗碎片:S→S+1 查 star_up_cost[S−1](02 §5.2)
static func star_cost(star: int) -> int:
	var costs: Array = _econ().get("star_up_cost", [])
	if star < 1 or star > costs.size():
		return 0
	return int(costs[star - 1])

# ---------------------------------------------------------------- 名册读写

static func entry(hero_id: String) -> Dictionary:
	var roster: Dictionary = SaveState.data.get("roster", {})
	return roster.get(hero_id, {})

static func owned(hero_id: String) -> bool:
	return bool(entry(hero_id).get("owned", false))

static func level_of(hero_id: String) -> int:
	return int(entry(hero_id).get("level", 0))

static func star_of(hero_id: String) -> int:
	return int(entry(hero_id).get("star", 0))

## 已拥有的全部武将 id,按 heroes.json 表序(界面名册顺序稳定)
static func owned_ids() -> Array:
	var out := []
	for h in DataDB.heroes:
		var id := str(h.get("id", ""))
		if id != "" and owned(id):
			out.append(id)
	return out

## 未拥有的武将 id,按稀有度升序(普通在前,便于酒馆按档展示)
static func unowned_ids() -> Array:
	var order := {"starting": 0, "normal": 1, "rare": 2, "epic": 3}
	var out := []
	for h in DataDB.heroes:
		var id := str(h.get("id", ""))
		if id != "" and not owned(id):
			out.append(id)
	out.sort_custom(func(a, b):
		var ra := int(order.get(DataDB.hero_rarity(str(a)), 1))
		var rb := int(order.get(DataDB.hero_rarity(str(b)), 1))
		if ra != rb:
			return ra < rb
		return str(a) < str(b))
	return out

# ---------------------------------------------------------------- 升级 / 升星

static func upgrade_level(hero_id: String) -> Dictionary:
	if not owned(hero_id):
		return {"ok": false, "reason": "尚未拥有该武将"}
	var e := entry(hero_id)
	var cost := level_cost(int(e.get("level", 1)))
	if int(e.get("level", 1)) >= level_cap():
		return {"ok": false, "reason": "已达等级上限"}
	if not SaveState.try_spend_junzi(cost):
		return {"ok": false, "reason": "军资不足(需 %d)" % cost}
	e["level"] = int(e.get("level", 1)) + 1
	return {"ok": true, "reason": "", "level": int(e["level"]), "cost": cost}

static func star_up(hero_id: String) -> Dictionary:
	if not owned(hero_id):
		return {"ok": false, "reason": "尚未拥有该武将"}
	var e := entry(hero_id)
	var star := int(e.get("star", 1))
	if star >= star_cap():
		return {"ok": false, "reason": "已达星级上限"}
	var cost := star_cost(star)
	if SaveState.fragments_of(hero_id) < cost:
		return {"ok": false, "reason": "%s碎片不足(需 %d)" % [_name(hero_id), cost]}
	SaveState.add_fragments(hero_id, -cost)
	e["star"] = star + 1
	return {"ok": true, "reason": "", "star": int(e["star"]), "cost": cost}

# ---------------------------------------------------------------- 招募(02 §7 酒馆)

static func buy_price(hero_id: String) -> int:
	var bp: Dictionary = _econ().get("recruit", {}).get("buy_price", {})
	return int(bp.get(DataDB.hero_rarity(hero_id), 800))

static func fuse_cost(hero_id: String) -> int:
	var fc: Dictionary = _econ().get("recruit", {}).get("fuse_cost", {})
	return int(fc.get(DataDB.hero_rarity(hero_id), 20))

## 直购:军资 → 直接拥有(level 1 / star 1)
static func recruit_buy(hero_id: String) -> Dictionary:
	if owned(hero_id):
		return {"ok": false, "reason": "已拥有该武将"}
	if DataDB.hero_by_id(hero_id).is_empty():
		return {"ok": false, "reason": "武将 id 非法"}
	var price := buy_price(hero_id)
	if not SaveState.try_spend_junzi(price):
		return {"ok": false, "reason": "军资不足(需 %d)" % price}
	_grant(hero_id)
	return {"ok": true, "reason": "", "cost": price}

## 合成:定向碎片集齐 → 拥有;已拥有时碎片按 dupe_to_fragment 折军资(?)
static func recruit_fuse(hero_id: String) -> Dictionary:
	if owned(hero_id):
		return {"ok": false, "reason": "已拥有该武将"}
	if DataDB.hero_by_id(hero_id).is_empty():
		return {"ok": false, "reason": "武将 id 非法"}
	var need := fuse_cost(hero_id)
	var have := SaveState.fragments_of(hero_id)
	if have < need:
		return {"ok": false, "reason": "%s碎片不足(%d/%d)" % [_name(hero_id), have, need]}
	SaveState.add_fragments(hero_id, -need)
	_grant(hero_id)
	return {"ok": true, "reason": "", "cost": need}

static func _grant(hero_id: String) -> void:
	var roster: Dictionary = SaveState.data.get("roster", {})
	var e: Dictionary = roster.get(hero_id, {})
	e["owned"] = true
	e["level"] = 1
	e["star"] = 1
	e["source"] = e.get("source", "recruit")
	roster[hero_id] = e
	SaveState.data["roster"] = roster

# ---------------------------------------------------------------- 校场编队(02 §5.3)

static func slot_cap() -> int:
	return int(SaveState.data.get("squad", {}).get("slot_cap", SaveState.INITIAL_SLOT_CAP))

static func slots() -> Array:
	var sq: Dictionary = SaveState.data.get("squad", {})
	return sq.get("slots", []).duplicate()

## 编队写入:slots[0] 恒为主公;去重;全部已拥有;数量 ≤ 席位。
static func set_squad(new_slots: Array) -> Dictionary:
	if new_slots.is_empty() or str(new_slots[0]) != "liubei":
		return {"ok": false, "reason": "主公刘备必须居首并上阵"}
	if new_slots.size() > slot_cap():
		return {"ok": false, "reason": "超出席位 %d" % slot_cap()}
	var seen := {}
	for s in new_slots:
		var id := str(s)
		if seen.has(id):
			return {"ok": false, "reason": "%s 重复上阵" % _name(id)}
		if not owned(id):
			return {"ok": false, "reason": "%s 尚未拥有" % _name(id)}
		seen[id] = true
	SaveState.data["squad"]["slots"] = new_slots.duplicate()
	return {"ok": true, "reason": ""}

## 一键上阵(校场「按战力补满」):主公 + 等级/星级最高者补满席位
static func auto_fill() -> void:
	var pool := owned_ids()
	pool.sort_custom(func(a, b):
		var fa := factors(str(a))
		var fb := factors(str(b))
		if not is_equal_approx(fa, fb):
			return fa > fb
		return str(a) < str(b))
	var out := ["liubei"]
	for id in pool:
		if out.size() >= slot_cap():
			break
		if str(id) != "liubei":
			out.append(str(id))
	SaveState.data["squad"]["slots"] = out

## 扩展席位(酒馆道具,价格 item_price.slot_cap[当前-初始]);上限 SaveState.MAX_SLOT_CAP
static func buy_slot_cap() -> Dictionary:
	var cur := slot_cap()
	if cur >= SaveState.MAX_SLOT_CAP:
		return {"ok": false, "reason": "席位已达上限(%d)" % SaveState.MAX_SLOT_CAP}
	var prices: Array = _econ().get("item_price", {}).get("slot_cap", [])
	var idx := cur - SaveState.INITIAL_SLOT_CAP
	if idx < 0 or idx >= prices.size():
		return {"ok": false, "reason": "席位扩展表缺档"}
	var price := int(prices[idx])
	if not SaveState.try_spend_junzi(price):
		return {"ok": false, "reason": "军资不足(需 %d)" % price}
	SaveState.data["squad"]["slot_cap"] = mini(SaveState.MAX_SLOT_CAP, cur + 1)
	return {"ok": true, "reason": "", "slot_cap": slot_cap(), "cost": price}

## 武将显示名(界面/提示统一走这里,避免各处读表拼装)
static func _name(hero_id: String) -> String:
	return str(DataDB.hero_by_id(hero_id).get("name", hero_id))
