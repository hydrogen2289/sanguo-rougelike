class_name CampaignSave
extends RefCounted
## CampaignSave —— 跨局战役闯关域(M9,01 §3/§8、02 §4.3/§8.4)。
## 只读写 SaveState.data.campaign 与 DataDB.campaign;不做界面、不落盘(界面改完调 SaveState.flush)。
## 返回约定与 HeroSave 一致:写操作返回 {ok: bool, reason: String, ...额外字段};失败不改动存档。
##
## 规则出处:
## - 评星三元(01 §3.3 提案默认):★1 通关 / ★2 通关且无武将阵亡 / ★3 通关且主公结算 HP≥50%。
## - 推图解锁(01 §3.4):通关 N 关解锁 N+1 关(由 unlock_after 链 + cleared 推导,不存冗余标记);
##   通关整章解锁下一章(写下一章 chapters[cid].unlocked)。
## - 首通/重复奖励(02 §4.3 定稿口径):关卡表 first_clear/repeat_clear 自带,
##   入库走 SaveState 既有钱包管道(add_junzi/add_fragments),不另造第二套经济记账。
## - 评星宝箱(01 §3.3/§8.2 占位):每章 3/6/9 星各 1 箱,军资 200/400/600。

const BOX_TIERS := [3, 6, 9]                    # 每章评星宝箱星数档(01 §3.3,占位)
const BOX_REWARDS := {3: 200, 6: 400, 9: 600}   # 宝箱军资(01 §8.2 占位)
const LORD_HP_STAR3 := 0.5                      # ★3 主公结算 HP 门槛(01 §3.3)

# ---------------------------------------------------------------- 结构补齐(旧档兼容)

## 会话内把 campaign 域(章节解锁/关卡条目/宝箱领取)按 DataDB.campaign 补齐:
## 表新增关卡、旧档缺条目时回填默认值;不删除多余条目(save_state.validate 只查评星区间)。
## settle / 查询 / 界面前均可安全调用,幂等。
static func ensure_progress() -> void:
	if SaveState.data.is_empty():
		return
	var camp: Dictionary = SaveState.data.get("campaign", {})
	if not (camp.get("chapters") is Dictionary):
		camp["chapters"] = {}
	if not (camp.get("boxes") is Dictionary):
		camp["boxes"] = {}
	var chapters: Dictionary = camp["chapters"]
	var boxes: Dictionary = camp["boxes"]
	for ch in DataDB.chapter_list():
		var cid := str(ch.get("id", ""))
		if cid.is_empty():
			continue
		if not (chapters.get(cid) is Dictionary):
			chapters[cid] = {"unlocked": _chapter_default_unlocked(ch), "stages": {}}
		var cst: Dictionary = chapters[cid]
		if not (cst.get("stages") is Dictionary):
			cst["stages"] = {}
		var stages: Dictionary = cst["stages"]
		for st in ch.get("stages", []):
			var sid := str(st.get("id", ""))
			if sid.is_empty():
				continue
			var e = stages.get(sid)
			if not (e is Dictionary):
				e = {"cleared": false, "stars": 0}
				stages[sid] = e
			if not (e.get("cleared") is bool):
				e["cleared"] = false
			e["stars"] = clampi(int(e.get("stars", 0)), 0, 3)
		if not (boxes.get(cid) is Dictionary):
			boxes[cid] = {}
		var box: Dictionary = boxes[cid]
		for t in BOX_TIERS:
			if not box.has(str(t)):
				box[str(t)] = false
	SaveState.data["campaign"] = camp

## 章节默认解锁态:unlock.require == null 的章节(首章)直接开放(01 §3.4)
static func _chapter_default_unlocked(ch: Dictionary) -> bool:
	var req = ch.get("unlock", {}).get("require")
	return req == null

# ---------------------------------------------------------------- 查询(界面/测试共用)

static func chapter_id_of(stage_id: String) -> String:
	return str(DataDB.stage_by_id(stage_id).get("chapter_id", ""))

## 关卡进度条目 {cleared, stars};ensure_progress 先行,读不到按未通关处理
static func stage_state(stage_id: String) -> Dictionary:
	var cid := chapter_id_of(stage_id)
	if cid.is_empty() or SaveState.data.is_empty():
		return {"cleared": false, "stars": 0}
	var st = SaveState.data.get("campaign", {}).get("chapters", {}).get(cid, {}).get("stages", {}).get(stage_id, {})
	if not (st is Dictionary):
		return {"cleared": false, "stars": 0}
	return {"cleared": bool(st.get("cleared", false)), "stars": int(st.get("stars", 0))}

static func stars_of(stage_id: String) -> int:
	return int(stage_state(stage_id).get("stars", 0))

static func chapter_unlocked(cid: String) -> bool:
	if SaveState.data.is_empty():
		return _chapter_default_unlocked(_chapter_row(cid))
	ensure_progress()
	var cst: Dictionary = SaveState.data.get("campaign", {}).get("chapters", {}).get(cid, {})
	if cst.has("unlocked"):
		return bool(cst["unlocked"])
	return _chapter_default_unlocked(_chapter_row(cid))

## 推图解锁判定(01 §3.4):章节开放 + unlock_after 前置关卡已通关
static func is_unlocked(stage_id: String) -> bool:
	var row: Dictionary = DataDB.stage_by_id(stage_id)
	if row.is_empty():
		return false
	if not chapter_unlocked(str(row.get("chapter_id", ""))):
		return false
	var ua = row.get("unlock_after")
	if ua == null:
		return true
	return bool(stage_state(str(ua)).get("cleared", false))

static func chapter_stars(cid: String) -> int:
	var total := 0
	for st in _chapter_row(cid).get("stages", []):
		total += stars_of(str(st.get("id", "")))
	return total

## 评星三元(01 §3.3 提案默认);outcome 由战场事实构成:
## victory 恒真(settle 只在胜利时调);no_casualty:本关无武将阵亡;lord_hp_ratio:主公结算 HP 比。
static func calc_stars(outcome: Dictionary) -> int:
	if not bool(outcome.get("victory", true)):
		return 0
	var stars := 1
	if bool(outcome.get("no_casualty", true)):
		stars = 2
		if float(outcome.get("lord_hp_ratio", 1.0)) >= LORD_HP_STAR3:
			stars = 3
	return stars

## 评星宝箱领取态 {tier:int: claimed:bool}
static func box_state(cid: String) -> Dictionary:
	if SaveState.data.is_empty():
		return {}
	ensure_progress()
	var out := {}
	var box: Dictionary = SaveState.data.get("campaign", {}).get("boxes", {}).get(cid, {})
	for t in BOX_TIERS:
		out[int(t)] = bool(box.get(str(t), false))
	return out

## 主城战役入口兜底:表序第一个已解锁关卡
static func first_unlocked_stage() -> String:
	ensure_progress()
	for ch in DataDB.chapter_list():
		var cid := str(ch.get("id", ""))
		if not chapter_unlocked(cid):
			continue
		for st in ch.get("stages", []):
			var sid := str(st.get("id", ""))
			if is_unlocked(sid):
				return sid
	return ""

# ---------------------------------------------------------------- 结算入库(01 §8.1/§8.2)

## 闯关胜利结算:通关标记 + 评星取历史最高 + 首通/重复奖励入库 + 整章通关解锁下一章。
## outcome:{victory, no_casualty, lord_hp_ratio}(战场事实,由结算方从 RunState.dump() 提取)。
## 返回 {ok, first, stars, rewards:{junzi, fragments}, reason};失败不发奖励、不改存档。
static func settle_stage(stage_id: String, outcome: Dictionary) -> Dictionary:
	if SaveState.data.is_empty():
		return {"ok": false, "reason": "存档未初始化(战斗层与存档解耦,结算须在主城会话内)"}
	var row: Dictionary = DataDB.stage_by_id(stage_id)
	if row.is_empty():
		return {"ok": false, "reason": "关卡不存在: " + stage_id}
	if not bool(outcome.get("victory", false)):
		return {"ok": true, "first": false, "stars": 0, "rewards": {}, "reason": "失败不发奖励(01 §8.1)"}
	ensure_progress()
	var cid := str(row.get("chapter_id", ""))
	var st: Dictionary = stage_state(stage_id)
	var first := not bool(st.get("cleared", false))
	var stars := calc_stars(outcome)
	# 通关标记 + 评星取历史最高(01 §3.3「每关独立评星,取历史最高」)
	var entry: Dictionary = SaveState.data["campaign"]["chapters"][cid]["stages"][stage_id]
	entry["cleared"] = true
	entry["stars"] = maxi(int(entry.get("stars", 0)), stars)
	# 奖励(关卡表自带,02 §4.3;入库走 SaveState 既有管道)
	var rewards := {"junzi": 0, "fragments": {}}
	if first:
		var fc: Dictionary = row.get("first_clear", {})
		rewards["junzi"] = int(fc.get("junzi", 0))
		for hid in fc.get("fragments", {}):
			rewards["fragments"][str(hid)] = int(fc["fragments"][hid])
	else:
		rewards["junzi"] = int(row.get("repeat_clear", {}).get("junzi", 0))
		# 重复通关碎片(01 §8.2 占位:碎片=1 枚):发该关首通绑定的武将;无绑定关不发
		var rf := int(DataDB.economy.get("settle", {}).get("repeat_fragments", 0))
		if rf > 0:
			for hid in row.get("first_clear", {}).get("fragments", {}):
				rewards["fragments"][str(hid)] = rf
				break
	if int(rewards["junzi"]) > 0:
		SaveState.add_junzi(int(rewards["junzi"]))
	for hid in rewards["fragments"]:
		SaveState.add_fragments(str(hid), int(rewards["fragments"][hid]))
	_unlock_next_chapter(cid)
	var stats: Dictionary = SaveState.data.get("stats", {})
	stats["total_runs"] = int(stats.get("total_runs", 0)) + 1
	SaveState.data["stats"] = stats
	return {"ok": true, "first": first, "stars": stars, "rewards": rewards, "reason": ""}

## 通关整章 → 解锁下一章(01 §3.4);本章仍有未通关卡则不动
static func _unlock_next_chapter(cid: String) -> void:
	var all_cleared := true
	for ch in DataDB.chapter_list():
		if str(ch.get("id", "")) != cid:
			continue
		for st in ch.get("stages", []):
			if not bool(stage_state(str(st.get("id", ""))).get("cleared", false)):
				all_cleared = false
	if not all_cleared:
		return
	for ch in DataDB.chapter_list():
		var unlock: Dictionary = ch.get("unlock", {})
		if str(unlock.get("require")) == cid:
			var nid := str(ch.get("id", ""))
			SaveState.data["campaign"]["chapters"][nid]["unlocked"] = true

# ---------------------------------------------------------------- 评星宝箱(01 §3.3/§8.2 占位)

static func claim_box(cid: String, tier: int) -> Dictionary:
	if not BOX_TIERS.has(tier):
		return {"ok": false, "reason": "宝箱档位非法: %d" % tier}
	if SaveState.data.is_empty():
		return {"ok": false, "reason": "存档未初始化"}
	var row = DataDB.campaign.get("chapters", [])
	var found := false
	for ch in row:
		if str(ch.get("id", "")) == cid:
			found = true
	if not found:
		return {"ok": false, "reason": "章节不存在: " + cid}
	ensure_progress()
	var boxes: Dictionary = SaveState.data["campaign"]["boxes"]
	var box: Dictionary = boxes[cid]
	if bool(box.get(str(tier), false)):
		return {"ok": false, "reason": "宝箱已领取"}
	var stars := chapter_stars(cid)
	if stars < tier:
		return {"ok": false, "reason": "星数不足(%d/%d)" % [stars, tier]}
	box[str(tier)] = true
	var reward := int(BOX_REWARDS.get(tier, 0))
	if reward > 0:
		SaveState.add_junzi(reward)
	return {"ok": true, "reason": "", "reward": reward}

# ---------------------------------------------------------------- 内部工具

static func _chapter_row(cid: String) -> Dictionary:
	for ch in DataDB.chapter_list():
		if str(ch.get("id", "")) == cid:
			return ch
	return {}
