class_name TriSelectPool
extends RefCounted
## 三选一卡池(M3,01 §7)。
## 类别权重 强化 50 / 遗物 30 / 武将 20;保底 1 张强化卡;
## 武将门槛 recruit_min_wave(赵云 W2 / 华佗 W3 / 诸葛 W4);队伍满 7 不出武将卡;
## 遗物池空转强化;武将池空/满员权重转遗物(遗物也空则转强化)。全部随机走 RunState.rng。

const WEIGHT_HERO := 20
const WEIGHT_RELIC := 30
const WEIGHT_UPGRADE := 50
const HAND_SIZE := 3

static func hero_candidates(wave_idx: int, team_ids: Array, team_size: int, max_team: int) -> Array:
	if team_size >= max_team:
		return []
	var out: Array = []
	for h in DataDB.heroes:
		var id := str(h.get("id", ""))
		if str(h.get("recruit_source", "")) != "triselect":
			continue
		if int(h.get("recruit_min_wave", 99)) > wave_idx:
			continue
		if team_ids.has(id):
			continue
		out.append(h)
	return out

static func relic_candidates(owned: Array) -> Array:
	var out: Array = []
	for r in DataDB.relics:
		if not owned.has(str(r.get("id", ""))):
			out.append(r)
	return out

static func upgrade_candidates() -> Array:
	# 数值强化可重复出现、可无限叠加(01 §7)
	return DataDB.upgrades.duplicate()

## 类别权重结算:池空按 01 §7 转移(武将 20 → 遗物 30 → 强化 50 逐级兜底)
static func weights(hero_n: int, relic_n: int) -> Dictionary:
	var wh := WEIGHT_HERO
	var wr := WEIGHT_RELIC
	var wu := WEIGHT_UPGRADE
	if hero_n <= 0:
		wr += wh                   # 武将池空/满员 → 权重转遗物
		wh = 0
	if relic_n <= 0:
		wu += wr                   # 遗物池空 → 遗物(含武将转入)权重转强化
		wr = 0
	return {"hero": wh, "relic": wr, "upgrade": wu}

## 抽一手 3 卡(固定 seed 可复现;测试直接调)
static func offer(rng: RandomNumberGenerator, wave_idx: int) -> Array:
	var team_ids: Array = []
	for m in RunState.team:
		team_ids.append(str(m.hero_id))
	var heroes := hero_candidates(wave_idx, team_ids, RunState.team.size(), RunState.MAX_TEAM)
	var relics := relic_candidates(RunState.relics)
	var upgrades := upgrade_candidates()
	var pools := {"hero": heroes, "relic": relics, "upgrade": upgrades}
	var w := weights(heroes.size(), relics.size())
	var cards: Array = []
	var used := {}
	# 保底 1 张数值强化卡(01 §7)
	var first := _draw(rng, "upgrade", pools, used)
	if not first.is_empty():
		cards.append(first)
	var guard := 0
	while cards.size() < HAND_SIZE and guard < 30:
		guard += 1
		var kind := _weighted_kind(rng, w, pools, used)
		var c := _draw(rng, kind, pools, used)
		if c.is_empty():
			c = _draw(rng, "upgrade", pools, used)   # 该池已尽 → 强化兜底
		if not c.is_empty():
			cards.append(c)
	return cards

static func _weighted_kind(rng: RandomNumberGenerator, w: Dictionary, pools: Dictionary, used: Dictionary) -> String:
	var total := 0
	var avail := {}
	for kind in ["hero", "relic", "upgrade"]:
		var weight := int(w.get(kind, 0))
		if weight > 0 and _unused_count(pools[kind], used) > 0:
			avail[kind] = weight
			total += weight
	if total <= 0:
		return "upgrade"
	var roll := rng.randi_range(1, total)
	for kind in avail:
		roll -= int(avail[kind])
		if roll <= 0:
			return kind
	return "upgrade"

static func _unused_count(pool: Array, used: Dictionary) -> int:
	var n := 0
	for item in pool:
		if not used.has(str(item.get("id", ""))):
			n += 1
	return n

static func _draw(rng: RandomNumberGenerator, kind: String, pools: Dictionary, used: Dictionary) -> Dictionary:
	var pool: Array = pools.get(kind, [])
	var cands: Array = []
	for item in pool:
		if not used.has(str(item.get("id", ""))):
			cands.append(item)
	if cands.is_empty():
		return {}
	var picked: Dictionary = cands[rng.randi_range(0, cands.size() - 1)]
	var id := str(picked.get("id", ""))
	used[id] = true
	match kind:
		"hero":
			return _hero_card(picked)
		"relic":
			return {"kind": "relic", "id": id, "name": str(picked.get("name", id)),
				"desc": str(picked.get("desc", "")), "rarity": str(picked.get("rarity", "normal")),
				"icon": "res://assets/textures/icons/relics/%s.png" % id}
		_:
			return {"kind": "upgrade", "id": id, "name": str(picked.get("name", id)),
				"desc": str(picked.get("desc", "")), "rarity": "", "icon": ""}

static func _hero_card(h: Dictionary) -> Dictionary:
	var sk: Dictionary = h.get("skill", {})
	var lines: Array = []
	if not sk.is_empty():
		lines.append("主动:%s(CD %d 秒)" % [str(sk.get("name", "?")), int(sk.get("cd", 0))])
		lines.append(_skill_desc(sk))
	var t: Dictionary = h.get("trait", {})
	if not t.is_empty():
		lines.append("%s:%s" % [str(t.get("name", "")), _trait_desc(t)])
	return {"kind": "hero", "id": str(h.get("id", "")), "name": str(h.get("name", "?")),
		"desc": "\n".join(PackedStringArray(lines)), "rarity": "",
		"icon": "res://assets/textures/units/%s.png" % str(h.get("id", ""))}

static func _skill_desc(sk: Dictionary) -> String:
	match str(sk.get("type", "")):
		"shield":
			return "3.5m 内友军获盾 %d(6s)并回复 %d" % [int(sk.get("shield_amount", 0)), int(sk.get("heal_amount", 0))]
		"cone":
			return "%d° 扇形 %dm,%d%% 攻击伤害并击退" % [int(sk.get("angle_deg", 0)), int(sk.get("radius", 0)), int(float(sk.get("dmg_mult", 1.0)) * 100.0)]
		"nova":
			return "半径 %dm,%d%% 伤害 + 击退 %dm + 眩晕 %ds" % [int(sk.get("radius", 0)), int(float(sk.get("dmg_mult", 1.0)) * 100.0), int(sk.get("knockback", 0)), int(sk.get("stun", 0))]
		"dash":
			return "冲向 %dm 内最远敌,沿途 %d%% 伤害,短暂无敌" % [int(sk.get("radius", 0)), int(float(sk.get("dmg_mult", 1.0)) * 100.0)]
		"weather":
			return "东风 %ds:全队普攻附加灼烧,火伤 +30%%" % int(sk.get("duration", 0))
		"heal_all":
			return "全体友军立即回复 %d HP" % int(sk.get("heal_amount", 0))
		"triple_nova":
			return "自身周围 %dm 三段斩,每段 %d%% 伤害" % [int(sk.get("radius", 0)), int(float(sk.get("dmg_mult", 1.0)) * 100.0)]
	return ""

static func _trait_desc(t: Dictionary) -> String:
	match str(t.get("type", "")):
		"aura":
			return "半径 %dm 内友军每秒回复 %.1f HP" % [int(t.get("radius", 0)), float(t.get("heal_per_sec", 0.0))]
		"execution":
			return "普攻可斩杀当前 HP ≤ 15%% 的普通敌兵"
		"enrage":
			return "HP < 35%% 狂化:攻速 +40%%、攻距 +30%%"
		"disobey":
			return "30%% 概率延迟 3s 生效,伤害 ×1.5"
	return ""

## 选定即生效(01 §7);返回结果文本(供横幅)
static func apply_pick(card: Dictionary) -> String:
	match str(card.get("kind", "")):
		"hero":
			if RunState.add_team_member(str(card.get("id", ""))):
				return "「%s」已入队!" % str(card.get("name", ""))
			return "队伍已满,「%s」未能入队" % str(card.get("name", ""))
		"relic":
			if RunState.add_relic(str(card.get("id", ""))):
				return "获得遗物「%s」" % str(card.get("name", ""))
			return "「%s」已拥有(同名遗物全场唯一)" % str(card.get("name", ""))
		_:
			RunState.add_upgrade(str(card.get("id", "")))
			return "强化「%s」生效" % str(card.get("name", ""))
