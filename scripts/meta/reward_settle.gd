class_name RewardSettle
extends RefCounted
## RewardSettle —— 结算入库统一管道(M11,02 §8.4)。
##
## 战斗层只读 RunState,结算全部经本管道入库:
##   settle(mode, outcome) -> Dictionary
## 闯关:按 campaign.json 的 first_clear / repeat_clear 发奖(转 CampaignSave,单一真源)。
## 塔  :按通过层数结算,更新 tower.highest_floor;局内军资(RunState.gold)结算时丢弃,
##       不入库(02 §8.4:防「留钱不花双赚」);塔内三选一临时武将不入 roster
##       (RunState.team 与存档 roster 本就是两套,此处不写 roster 即为丢弃)。
## 失败不给奖励。
##
## 返回结构(结算页只消费这个,不在前端重算):
## {
##   "ok": bool, "mode": String, "reason": String,
##   "victory": bool, "first": bool, "stars": int,
##   "floors": int,          # 塔:本次到达层数;闯关:0
##   "rewards": {"junzi": int, "fragments": {hero_id: int}},
##   "items": [ {"kind": "junzi"|"fragment"|"stars"|"floor", "id": String,
##               "name": String, "amount": int} ],   # 结算页逐项展示
## }
## items 恒与 rewards 一致(items 是渲染用的扁平清单,不另算一套数值)。

const KIND_JUNZI := "junzi"
const KIND_FRAGMENT := "fragment"
const KIND_STARS := "stars"
const KIND_FLOOR := "floor"

# ---------------------------------------------------------------- 入口

static func settle(mode: String, outcome: Dictionary) -> Dictionary:
	if mode == "campaign":
		return settle_campaign(outcome)
	if mode == "tower":
		return settle_tower(outcome)
	return _fail(mode, "未知结算模式: " + mode)

# ---------------------------------------------------------------- 闯关

## outcome: {victory, no_casualty, lord_hp_ratio, stage_id?}
## stage_id 缺省取 RunState.context.stage_id(战斗层上下文,结算时仍有效)。
static func settle_campaign(outcome: Dictionary) -> Dictionary:
	var stage_id := str(outcome.get("stage_id", RunState.context.get("stage_id", "")))
	if stage_id.is_empty():
		return _fail("campaign", "缺 stage_id")
	var victory := bool(outcome.get("victory", false))
	if not victory:
		# 失败不发奖励(02 §8.4);不改存档
		return {"ok": true, "mode": "campaign", "reason": "", "victory": false,
			"first": false, "stars": 0, "floors": 0,
			"rewards": {"junzi": 0, "fragments": {}}, "items": []}
	var r: Dictionary = CampaignSave.settle_stage(stage_id, outcome)
	if not bool(r.get("ok", false)):
		return _fail("campaign", str(r.get("reason", "闯关结算失败")))
	var rewards: Dictionary = r.get("rewards", {})
	var items: Array = []
	var junzi := int(rewards.get("junzi", 0))
	if junzi > 0:
		items.append({"kind": KIND_JUNZI, "id": "", "name": "军资", "amount": junzi})
	for hid in rewards.get("fragments", {}):
		var n := int(rewards["fragments"][hid])
		if n > 0:
			items.append({"kind": KIND_FRAGMENT, "id": str(hid),
				"name": hero_name(str(hid)) + "碎片", "amount": n})
	var stars := int(r.get("stars", 0))
	if stars > 0:
		items.append({"kind": KIND_STARS, "id": stage_id, "name": "评星", "amount": stars})
	return {"ok": true, "mode": "campaign", "reason": "", "victory": true,
		"first": bool(r.get("first", false)), "stars": stars, "floors": 0,
		"rewards": {"junzi": junzi, "fragments": (rewards.get("fragments", {}) as Dictionary).duplicate(true)},
		"items": items, "stage_id": stage_id}

# ---------------------------------------------------------------- 塔

## outcome: {floors_cleared: int, died: bool, retreat: bool, kills?: int}
## - floors_cleared: 本局实际通过的层数(杀 Boss 才算过层)
## - died: 主公阵亡 → death_mult;retreat: 主动撤退 → retreat_mult
## 局内军资不入库(02 §8.4),这里一个字都不读 RunState.gold。
static func settle_tower(outcome: Dictionary) -> Dictionary:
	var cleared := maxi(0, int(outcome.get("floors_cleared", 0)))
	var died := bool(outcome.get("died", false))
	var retreat := bool(outcome.get("retreat", false))
	var kills := int(outcome.get("kills", RunState.kills))
	var settle_cfg: Dictionary = DataDB.economy.get("settle", {})
	var tf: Dictionary = settle_cfg.get("tower_floor", {})
	if tf.is_empty():
		return _fail("tower", "economy.json 缺 settle.tower_floor")
	var mult := 1.0
	if died:
		mult = float(settle_cfg.get("death_mult", 0.5))
	elif retreat:
		mult = float(settle_cfg.get("retreat_mult", 1.0))
	var boss_mult := float(tf.get("boss_mult", 1.0))
	var junzi_cfg: Dictionary = tf.get("junzi", {})
	var frag_cfg: Dictionary = tf.get("fragments", {})
	var junzi := 0
	var frag_n := 0
	for floor_n in range(1, cleared + 1):
		var gain := float(junzi_cfg.get("base", 0)) + float(junzi_cfg.get("per_floor", 0)) * float(floor_n)
		if DataDB.tower_is_boss_floor(floor_n):
			gain *= boss_mult
		junzi += int(round(gain))
		frag_n += int(frag_cfg.get("base", 0)) + int(frag_cfg.get("per_4_floor", 0)) * (floor_n / 4)
	junzi = int(round(float(junzi) * mult))
	frag_n = int(round(float(frag_n) * mult))
	# 失败(阵亡)也按折算发,但一层未过则什么都没拿
	if cleared <= 0:
		junzi = 0
		frag_n = 0
	var frag_target := _fragment_target()
	var rewards := {"junzi": junzi, "fragments": {}}
	if frag_n > 0 and frag_target != "":
		rewards["fragments"][frag_target] = frag_n
	# --- 入库(全走 SaveState 既有钱包管道 + TowerSave 层推进) ---
	if not SaveState.data.is_empty():
		if junzi > 0:
			SaveState.add_junzi(junzi)
		if frag_n > 0 and frag_target != "":
			SaveState.add_fragments(frag_target, frag_n)
		# 最高层只增不减(被杀在半路也算到达过该层)
		var reached := cleared + (0 if (died or retreat) else 1)
		reached = mini(reached, TowerSave.floor_cap())
		if reached > 0:
			TowerSave.record_floor(reached)
		TowerSave.record_kills(kills)
		var stats: Dictionary = SaveState.data.get("stats", {})
		stats["total_runs"] = int(stats.get("total_runs", 0)) + 1
		stats["total_kills"] = int(stats.get("total_kills", 0)) + kills
		SaveState.data["stats"] = stats
	var items: Array = []
	if junzi > 0:
		items.append({"kind": KIND_JUNZI, "id": "", "name": "军资", "amount": junzi})
	if frag_n > 0 and frag_target != "":
		items.append({"kind": KIND_FRAGMENT, "id": frag_target,
			"name": hero_name(frag_target) + "碎片", "amount": frag_n})
	if cleared > 0:
		items.append({"kind": KIND_FLOOR, "id": "", "name": "通过层数", "amount": cleared})
	var reason := ""
	if died:
		reason = "主公阵亡,奖励按 %.0f%% 折算" % (mult * 100.0)
	elif retreat:
		reason = "主动撤退,奖励按 %.0f%% 结算" % (mult * 100.0)
	return {"ok": true, "mode": "tower", "reason": reason,
		"victory": cleared > 0 and not died, "first": false, "stars": 0, "floors": cleared,
		"rewards": rewards, "items": items, "died": died, "retreat": retreat}

## 塔结算碎片的绑定武将:编队里第一个非主公(没有就用主公),确定性、不随机
static func _fragment_target() -> String:
	var slots: Array = SaveState.data.get("squad", {}).get("slots", []) if not SaveState.data.is_empty() else []
	for id in slots:
		if str(id) != "liubei":
			return str(id)
	if not slots.is_empty():
		return str(slots[0])
	return str(RunState.INITIAL_TEAM[1]) if RunState.INITIAL_TEAM.size() > 1 else "liubei"

# ---------------------------------------------------------------- 工具

static func hero_name(hero_id: String) -> String:
	return str(DataDB.hero_by_id(hero_id).get("name", hero_id))

## 结算页展示用的单行摘要(测试与横幅共用,避免两处各拼一套)
static func items_text(items: Array) -> String:
	var parts: Array = []
	for it in items:
		parts.append("%s+%d" % [str(it.get("name", "")), int(it.get("amount", 0))])
	return " ".join(PackedStringArray(parts))

static func _fail(mode: String, reason: String) -> Dictionary:
	printerr("[RewardSettle] " + reason)
	return {"ok": false, "mode": mode, "reason": reason, "victory": false,
		"first": false, "stars": 0, "floors": 0,
		"rewards": {"junzi": 0, "fragments": {}}, "items": []}
