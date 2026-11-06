class_name TowerSave
extends RefCounted
## TowerSave —— 跨局试炼塔域(M10,01 §4.4、02 §3.2/§4.4/§8.4)。
## 只管 SaveState.data.tower(最高层 / 最好击杀),不做界面、不落盘(调用方调 SaveState.flush)。
## 返回约定与 HeroSave/CampaignSave 一致:写操作返回 {ok, reason, ...};失败不改存档。
##
## 口径:
## - highest_floor = 已通过的最高层(0 = 一层未过),只增不减。
## - 难度按**本局当前层**算(02 §4.4 默认口径),不读 highest_floor 做难度缩放;
##   最高层只用于界面展示与结算加成,不参与波次生成。
## - 层数上限 = tower.json 里可生成的最深层;表里没写就按 MAX_FLOOR 兜底(防越界写脏档)。

const MAX_FLOOR := 999          # 兜底上限(tower.json 未给 max_floor 时用)

# ---------------------------------------------------------------- 读

static func highest_floor() -> int:
	if SaveState.data.is_empty():
		return 0
	var t = SaveState.data.get("tower", {})
	if not (t is Dictionary):
		return 0
	return maxi(0, int(t.get("highest_floor", 0)))

## 当前可开爬的起始层:最高层已过 N → 下一次从 N+1 起(爬塔总是从第 1 层重开,
## 本函数只给界面显示「已到第 N 层」与统计用,不改变 goto_tower 自 1 层起的状态机)
static func next_floor() -> int:
	return highest_floor() + 1

static func floor_cap() -> int:
	var cap := int(DataDB.tower.get("max_floor", MAX_FLOOR))
	return clampi(cap, 1, MAX_FLOOR)

## Boss 层判定(转 DataDB,单一真源:boss_every)
static func is_boss_floor(n: int) -> bool:
	return DataDB.tower_is_boss_floor(n)

# ---------------------------------------------------------------- 写

## 推进最高层:只增不减、非负、不越界。返回 {ok, changed, highest, reason}。
## 失败(负数/越界/存档未初始化)不改任何数据。
static func record_floor(floor_reached: int) -> Dictionary:
	if SaveState.data.is_empty():
		return {"ok": false, "changed": false, "highest": 0, "reason": "存档未初始化"}
	if floor_reached < 0:
		return {"ok": false, "changed": false, "highest": highest_floor(),
			"reason": "层数不能为负: %d" % floor_reached}
	var cap := floor_cap()
	if floor_reached > cap:
		return {"ok": false, "changed": false, "highest": highest_floor(),
			"reason": "层数 %d 越出上限 %d" % [floor_reached, cap]}
	if not (SaveState.data.get("tower") is Dictionary):
		SaveState.data["tower"] = {"highest_floor": 0}
	var cur := highest_floor()
	if floor_reached <= cur:
		return {"ok": true, "changed": false, "highest": cur, "reason": ""}
	SaveState.data["tower"]["highest_floor"] = floor_reached
	return {"ok": true, "changed": true, "highest": floor_reached, "reason": ""}

## 本局最好击杀数(统计域 stats.tower_best_kill,只增不减);塔结算时记一次。
static func record_kills(kills: int) -> Dictionary:
	if SaveState.data.is_empty():
		return {"ok": false, "changed": false, "reason": "存档未初始化"}
	if kills < 0:
		return {"ok": false, "changed": false, "reason": "击杀数不能为负: %d" % kills}
	var stats = SaveState.data.get("stats", {})
	if not (stats is Dictionary):
		stats = {}
	var cur := int(stats.get("tower_best_kill", 0))
	if kills <= cur:
		return {"ok": true, "changed": false, "reason": ""}
	stats["tower_best_kill"] = kills
	SaveState.data["stats"] = stats
	return {"ok": true, "changed": true, "reason": ""}
