class_name TriSelectPool
extends RefCounted
## 三选一卡池(M3,01 §7;03 第三批换人规则 1+2,05 §3)。
## 类别权重 强化 50 / 遗物 30 / 武将 20;保底 1 张强化卡;
## 武将门槛 recruit_min_wave(赵云 W2 / 华佗 W3 / 诸葛 W4;第三批:周瑜 W3,余 W2);
## 满员换人规则(05 §3):满员 → 武将卡变「替换卡」(可再出,选定后弹 6 选 1 指定离队者);
## 阵亡空位 → 该武将卡恢复可出(招募卡,填补空位,不复活本人)。
## 遗物池空转强化;武将池空(非满员)权重转遗物。全部随机走 RunState.rng。

const WEIGHT_HERO := 20
const WEIGHT_RELIC := 30
const WEIGHT_UPGRADE := 50
const HAND_SIZE := 3

static func hero_candidates(wave_idx: int, team_ids: Array, team_size: int, max_team: int) -> Array:
	# 05 §3 换人规则:满员后武将卡照出(替换卡),不再因满员清空池
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
	# 05 §3 换人规则 1:满员时武将卡为「替换卡」——选定后需指定一名在场武将离队
	var replace := RunState.team.size() >= RunState.MAX_TEAM and not _team_has_id(str(h.get("id", "")))
	return {"kind": "hero", "id": str(h.get("id", "")), "name": str(h.get("name", "?")),
		"desc": "\n".join(PackedStringArray(lines)), "rarity": "",
		"icon": "res://assets/textures/units/%s.png" % str(h.get("id", "")),
		"replace": replace}

static func _team_has_id(hero_id: String) -> bool:
	for m in RunState.team:
		if str(m.hero_id) == hero_id:
			return true
	return false

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
		# --- 03 第二批 ---
		"charge":
			return "向目标突进 %dm,路径敌人受 %d%% 伤害并减速 %d%%(%ds)" % [int(sk.get("distance", 0)), int(float(sk.get("dmg_mult", 1.0)) * 100.0), int(float(sk.get("slow_ratio", 0.0)) * 100.0), int(sk.get("slow_duration", 0))]
		"snipe":
			return "射场上 HP 最高的敌人(含 Boss),必中 %d%% 攻击伤害" % int(float(sk.get("dmg_mult", 1.0)) * 100.0)
		"frenzy":
			return "%ds 内攻速 +60%%,期间每秒流失 %d HP(不可致死)" % [int(sk.get("duration", 0)), int(sk.get("hp_loss_per_sec", 0))]
		# --- 03 第三批(05 §2)---
		"fear":
			return "半径 %dm 内敌人恐惧 %ds(Boss %ds):逃离且不可攻击" % [int(sk.get("radius", 0)), int(sk.get("fear_duration", 0)), int(float(sk.get("fear_duration", 0)) * float(sk.get("boss_duration_mult", 0.5)))]
		"taunt":
			return "半径 %dm 内敌人强制攻击许褚 %ds(Boss %ds)" % [int(sk.get("radius", 0)), int(sk.get("taunt_duration", 0)), int(float(sk.get("taunt_duration", 0)) * float(sk.get("boss_duration_mult", 0.5)))]
		"dash_assassin":
			return "向目标突进 %dm,下一次普攻伤害 ×%.1f(背袭)" % [int(sk.get("distance", 0)), float(sk.get("backstab_mult", 2.5))]
		"fire_rain":
			return "目标区域 %dm,%d 轮火矢每轮 %d%% 伤害并点燃 %ds" % [int(sk.get("radius", 0)), int(sk.get("rounds", 0)), int(float(sk.get("dmg_mult", 1.0)) * 100.0), int(sk.get("burn_duration", 0))]
		"charm":
			return "单体魅惑 %ds(倒戈攻击敌方;Boss 踌躇 %ds 不倒戈)" % [int(sk.get("duration", 0)), int(sk.get("boss_duration", 0))]
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
		# --- 03 第二批 ---
		"fangu":
			# 双刃词条:负面必须明示(03 §4 验收口径)
			return "攻击 +40%%,受到的伤害 +25%%(反骨:强攻带代价)"
		# --- 03 第三批(05 §2)---
		"controlled_amp":
			return "处于恐惧/嘲讽/倒戈/眩晕状态的敌人受到的伤害 +15%%"
		"lowhp_dr":
			return "HP < %d%% 时自身减伤 %d%%" % [int(float(t.get("hp_ratio", 0.5)) * 100.0), int(float(t.get("dr", 0.3)) * 100.0)]
		"kill_burst_move":
			return "击杀敌人后移速 +%d%% 持续 %ds(刷新不叠加)" % [int(float(t.get("move_pct", 0.2)) * 100.0), int(t.get("duration", 0))]
		"burn_kill_cd":
			return "被点燃的敌人死亡时,火雨 CD -%ds" % int(t.get("cd_reduce", 0))
		"auraless":
			return "无被动"
	return ""

## 选定即生效(01 §7);返回结果文本(供横幅)
## 05 §3 换人规则 1:满员时武将卡走 replace_team_member(替换 UI 由 triselect 先行收集离队者)
static func apply_pick(card: Dictionary) -> String:
	return apply_pick_with_replace(card, "")

## 带替换的武将入队:replace_id 非空即先让其离队入候选池(可再抽回,不视为阵亡)
static func apply_pick_with_replace(card: Dictionary, replace_id: String) -> String:
	match str(card.get("kind", "")):
		"hero":
			var new_id := str(card.get("id", ""))
			if replace_id != "":
				if RunState.replace_team_member(new_id, replace_id):
					var old_name := str(RunState.member(replace_id).get("name", replace_id))
					return "「%s」替换「%s」入场,离队者回候选池!" % [str(card.get("name", "")), old_name]
				return "替换失败(「%s」未能入队)" % str(card.get("name", ""))
			if RunState.add_team_member(new_id):
				return "「%s」已入队!" % str(card.get("name", ""))
			return "队伍已满,「%s」未能入队" % str(card.get("name", ""))
		"relic":
			if RunState.add_relic(str(card.get("id", ""))):
				return "获得遗物「%s」" % str(card.get("name", ""))
			return "「%s」已拥有(同名遗物全场唯一)" % str(card.get("name", ""))
		_:
			RunState.add_upgrade(str(card.get("id", "")))
			return "强化「%s」生效" % str(card.get("name", ""))
