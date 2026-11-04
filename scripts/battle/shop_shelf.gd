class_name ShopShelf
extends RefCounted
## 商店货架(M3,01 §7):6 格 = 遗物×2 + 数值强化×2 + 军医诊治(常驻)+ 随机×1。
## 定价:普通 25 / 稀有 40 / 史诗 60,强化 20~35;刷新 20/次;
## 已购下架;同名遗物全场唯一(与三选一共用去重)。

static func relic_price(rarity: String) -> int:
	var rp: Dictionary = DataDB.shop.get("relic_price", {})
	return int(rp.get(rarity, 25))

static func sellable_upgrades() -> Array:
	# 犒赏(shop_price 0,三选一专属)等不进货架
	var out: Array = []
	for u in DataDB.upgrades:
		if int(u.get("shop_price", 0)) > 0:
			out.append(u)
	return out

## 生成一手 6 格货架;遗物池不足用强化补位
static func roll(rng: RandomNumberGenerator, owned_relics: Array) -> Array:
	var relics: Array = []
	for r in DataDB.relics:
		if not owned_relics.has(str(r.get("id", ""))):
			relics.append(r)
	var upgrades: Array = sellable_upgrades()
	var slots: Array = []
	var kinds := ["relic", "relic", "upgrade", "upgrade", "heal", "extra"]
	for kind in kinds:
		match kind:
			"relic":
				if relics.is_empty():
					slots.append(_upgrade_item(upgrades, rng))
				else:
					var idx := rng.randi_range(0, relics.size() - 1)
					slots.append(_relic_item(relics.pop_at(idx)))
			"upgrade":
				slots.append(_upgrade_item(upgrades, rng))
			"heal":
				slots.append(_heal_item())
			"extra":
				if relics.is_empty() or (not upgrades.is_empty() and rng.randf() < 0.5):
					slots.append(_upgrade_item(upgrades, rng))
				else:
					var idx2 := rng.randi_range(0, relics.size() - 1)
					slots.append(_relic_item(relics.pop_at(idx2)))
	return slots

static func _relic_item(r: Dictionary) -> Dictionary:
	var id := str(r.get("id", ""))
	return {"kind": "relic", "id": id, "name": str(r.get("name", id)),
		"desc": str(r.get("desc", "")), "rarity": str(r.get("rarity", "normal")),
		"icon": "res://assets/textures/icons/relics/%s.png" % id,
		"price": relic_price(str(r.get("rarity", "normal")))}

static func _upgrade_item(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	if pool.is_empty():
		return {}
	var u: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var id := str(u.get("id", ""))
	return {"kind": "upgrade", "id": id, "name": str(u.get("name", id)),
		"desc": str(u.get("desc", "")), "rarity": "", "icon": "",
		"price": clampi(int(u.get("shop_price", 20)), 20, 35)}

static func _heal_item() -> Dictionary:
	var hi: Dictionary = DataDB.shop.get("heal_item", {})
	return {"kind": "heal", "id": str(hi.get("id", "junyi_zhenzhi")),
		"name": str(hi.get("name", "军医诊治")),
		"desc": "全队回复 30% HP", "rarity": "", "icon": "",
		"price": int(hi.get("price", 20))}

## 购买:扣费 + 即时生效;返回 "" 成功 / 否则为失败原因(01 §7 选定即生效)
static func buy(item: Dictionary) -> String:
	if item.is_empty():
		return "该货架已售出"
	var price := int(item.get("price", 0))
	if not RunState.try_spend(price):
		return "军资不足(需 %d)" % price
	match str(item.get("kind", "")):
		"relic":
			if not RunState.add_relic(str(item.get("id", ""))):
				RunState.add_gold(price)   # 理论不可达(货架已去重),防御性退款
				return "已拥有同名遗物"
		"upgrade":
			RunState.add_upgrade(str(item.get("id", "")))
		"heal":
			RunState.heal_all_requested.emit(float(DataDB.shop.get("heal_item", {}).get("effect", {}).get("heal_all_ratio", 0.30)))
	return ""
