class_name EventEffects
extends RefCounted
## 事件选项效果结算(M3,01 §9 事件表)。
## 修饰符类(zhangfei_atk_pct / team_maxhp_flat / heal_all_ratio)经 RunState._apply_effect;
## 特判类(team_hp_loss / random_relic / recruit+cost_gold / gold)在此结算。
## 返回结果文本(供横幅);全部随机走 RunState.rng。

static func apply(effect: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for k in effect:
		var v = effect[k]
		match str(k):
			"zhangfei_atk_pct":
				RunState._apply_effect("zhangfei_atk_pct", float(v))
				parts.append("张飞攻击 +%.0f%%(本场)" % (float(v) * 100.0))
			"team_maxhp_flat":
				RunState._apply_effect("team_maxhp_flat", float(v))
				parts.append("全队 HP 上限 +%d(本场)" % int(v))
			"heal_all_ratio":
				RunState._apply_effect("heal_all_ratio", float(v))
				parts.append("全队回复 %.0f%% HP" % (float(v) * 100.0))
			"gold":
				RunState.add_gold(int(v))
				parts.append("获得 %d 军资" % int(v))
			"team_hp_loss":
				parts.append(_team_hp_loss(float(v)))
			"random_relic":
				parts.append(_random_relic(str(v)))
			"recruit":
				parts.append(_recruit(str(v), int(effect.get("cost_gold", 0))))
			"cost_gold":
				pass                 # 随 recruit 一并结算
			"this_run":
				pass                 # 本场标记:本切片所有事件效果均本场有效(01 §9)
			_:
				RunState._apply_effect(str(k), float(v) if v is float or v is int else 0.0)
	return "、".join(parts)

## 全队当前 HP -amount(01 §9);不致死(下限 1 HP)
static func _team_hp_loss(amount: float) -> String:
	var n := 0
	for u in _friendlies():
		if is_instance_valid(u) and not u.dead:
			u.lose_hp_direct(amount)
			n += 1
	_sync_team_hp()
	return "全队当前 HP -%d" % roundi(amount)

## 随机获得 1 件指定稀有度遗物("normal|rare" 竖线分隔,01 §9 三让徐州 B)
static func _random_relic(rarities: String) -> String:
	var want := rarities.split("|")
	var cands: Array = []
	for r in DataDB.relics:
		if RunState.relics.has(str(r.get("id", ""))):
			continue
		if want.has(str(r.get("rarity", ""))):
			cands.append(r)
	if cands.is_empty():
		# 遗物已集齐兜底:折算 15 军资(口径见收口上报)
		RunState.add_gold(15)
		return "遗物已集齐,折得 15 军资"
	var picked: Dictionary = cands[RunState.rng.randi_range(0, cands.size() - 1)]
	RunState.add_relic(str(picked.get("id", "")))
	return "获得遗物「%s」" % str(picked.get("name", ""))

## 付费招募(吕布,01 §9 虎牢关):队伍未满且军资足够才生效
static func _recruit(hero_id: String, cost: int) -> String:
	if RunState.team.size() >= RunState.MAX_TEAM:
		return "队伍已满,%s 婉拒入队" % _hero_name(hero_id)
	if not RunState.try_spend(cost):
		return "军资不足(需 %d)" % cost
	if not RunState.add_team_member(hero_id):
		RunState.add_gold(cost)
		return "%s 已在队中" % _hero_name(hero_id)
	return "%s 已入队!(-%d 军资)" % [_hero_name(hero_id), cost]

static func _hero_name(hero_id: String) -> String:
	var h: Dictionary = DataDB.hero_by_id(hero_id)
	return str(h.get("name", hero_id))

static func _friendlies() -> Array:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).get_nodes_in_group("friendlies")
	return []

## 单位当前 HP 回写 RunState.team(结算快照/统计口径)
static func _sync_team_hp() -> void:
	for m in RunState.team:
		for u in _friendlies():
			if is_instance_valid(u) and str(u.unit_id) == str(m.hero_id) and not u.dead:
				m["hp"] = u.hp
				m["max_hp"] = u.max_hp
