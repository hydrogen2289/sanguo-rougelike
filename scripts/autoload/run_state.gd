extends Node
## RunState —— 单局状态 autoload(M0)。
## 全部随机一律走 RunState.rng(固定 run_seed 可复现,已拍板约束 10)。
## 数值合成模型(02 §6):最终属性 = base × (1 + Σadd%) + Σflat;
## 技能 CD = base × (1 − Σ缩减),总缩减封顶 40%。

signal gold_changed(gold: int)
signal team_changed
signal mods_changed                  # 遗物/强化/事件修饰符变动(M3:存量单位即时刷新)
signal heal_all_requested(ratio: float)   # 军医诊治/军医草药等群体治疗(M3)

const MAX_TEAM := 7                      # 队伍上限 7 = 主公 + 6 武将(已拍板约束 7)
const INITIAL_TEAM := ["liubei", "guanyu", "zhangfei"]   # 桃园结义开局三人组(01 §2)
const CD_REDUCTION_CAP := 0.4

var run_seed: int = 0
var rng := RandomNumberGenerator.new()
var gold: int = 0
var wave_idx: int = 0
var kills: int = 0
var run_time: float = 0.0
var team: Array = []                     # [{hero_id, name, hp, max_hp, alive}]
var relics: Array[String] = []           # 同名遗物全场唯一
var upgrades: Dictionary = {}            # 强化 id -> 叠加次数
var mods_flat: Dictionary = {}           # stat -> flat 加值
var mods_pct: Dictionary = {}            # stat -> add% 加成
# 模式上下文(M7,02 §8.1):闯关="campaign" / 塔="tower";battle 稍后(M9/M10)只读此二者,
# 战斗层不感知存档(SaveState)。现 8 波剧本即塔初始层带(01 §4.4),默认塔。
var mode: StringName = &"tower"
var context: Dictionary = {"floor_start": 1}

func _process(delta: float) -> void:
	if not team.is_empty():
		run_time += delta

# ---------------------------------------------------------------- 生命周期

func reset(new_seed: int = -1) -> void:
	if new_seed < 0:
		new_seed = int(Time.get_unix_time_from_system() * 1000.0) % 2147483647
	run_seed = new_seed
	rng.seed = run_seed
	gold = 0
	wave_idx = 0
	kills = 0
	run_time = 0.0
	team = []
	relics = []
	upgrades = {}
	mods_flat = {}
	mods_pct = {}
	mode = &"tower"                       # reset 归位默认塔模式(02 §8.1)
	context = {"floor_start": 1}
	for id in _opening_team():
		add_team_member(id)

## 开局队伍(02 §5.3):存档已初始化且编队合法时按 squad.slots,否则桃园三人组。
## 战斗层不感知存档结构,只经此单点取参赛名单。
func _opening_team() -> Array:
	if SaveState.data.is_empty():
		return INITIAL_TEAM
	var slots: Array = SaveState.data.get("squad", {}).get("slots", [])
	if slots.is_empty() or str(slots[0]) != "liubei":
		return INITIAL_TEAM
	return slots.duplicate()

# ---------------------------------------------------------------- 经济

func add_gold(v: int) -> void:
	gold = maxi(0, gold + v)
	gold_changed.emit(gold)

func try_spend(v: int) -> bool:
	if gold < v:
		return false
	gold -= v
	gold_changed.emit(gold)
	return true

func add_kill() -> void:
	kills += 1

# ---------------------------------------------------------------- 队伍

func add_team_member(hero_id: String) -> bool:
	if team.size() >= MAX_TEAM:
		return false
	for m in team:
		if str(m.hero_id) == hero_id:
			return false
	var h: Dictionary = DataDB.hero_by_id(hero_id)
	if h.is_empty():
		return false
	# 养成乘区进队伍快照(02 §5.4):HUD 血条/DOT 基数与 HeroUnit 出场值同口径
	var max_hp := float(h.get("hp", 60)) * HeroSave.factors(hero_id)
	team.append({
		"hero_id": hero_id,
		"name": str(h.get("name", hero_id)),
		"max_hp": max_hp,
		"hp": max_hp,
		"alive": true,
	})
	team_changed.emit()
	return true

func member(hero_id: String) -> Dictionary:
	for m in team:
		if str(m.hero_id) == hero_id:
			return m
	return {}

## 05 §3 满员换人规则 1:满员时替换 —— old_id 离队入「候选池」(可再抽回、不视为阵亡、
## 不算折将),new_id 入队。数值零跳变:离队者仅移出 team,不进阵亡流程;
## 离队者的个人 buff/被动全回收口径由 HeroUnit.leave_team 回收(replace UI 驱动),
## RunState 层只做 roster 变动;main 主公光环只对在场者生效,离队自然失效。
## 返回 false 的情况:old 不在队 / new 已在队 / old==new / new 非法 id。
func replace_team_member(new_id: String, old_id: String) -> bool:
	if old_id == new_id or member(old_id).is_empty():
		return false
	if not member(new_id).is_empty():
		return false
	var h: Dictionary = DataDB.hero_by_id(new_id)
	if h.is_empty():
		return false
	# 离队:旧成员原位替换(HP 回满值记录新将基础值;存活 true;不进 casualty)
	var old_name := str(member(old_id).get("name", old_id))
	var idx := team.find(member(old_id))
	team.remove_at(idx)
	team.insert(idx, {
		"hero_id": new_id,
		"name": str(h.get("name", new_id)),
		"max_hp": float(h.get("hp", 60)),
		"hp": float(h.get("hp", 60)),
		"alive": true,
	})
	team_changed.emit()
	if OS.is_debug_build():
		print("[RunState] 换人:「%s」离队入候选池 ←「%s」入场" % [old_name, str(h.get("name", new_id))])
	return true

func mark_casualty(hero_id: String) -> void:
	# 武将阵亡 = 本局退场,不可复活(01 §5)
	var m := member(hero_id)
	if not m.is_empty():
		m["alive"] = false
		team_changed.emit()

func alive_members() -> Array:
	var out: Array = []
	for m in team:
		if bool(m.alive):
			out.append(m)
	return out

## 05 §3 换人规则 2:阵亡补位 —— 阵亡武将的 triselect 武将卡恢复可出现在三选一池。
## hero_candidates 已不排除阵亡者(它只排除在队者),本函数供 UI/测试显式查询:
## 阵亡的 recruit_source=triselect 武将可再出卡(填补空位,不复活本人)。
func re_recruitable(hero_id: String) -> bool:
	var h: Dictionary = DataDB.hero_by_id(hero_id)
	if h.is_empty() or str(h.get("recruit_source", "")) != "triselect":
		return false
	var m := member(hero_id)
	if m.is_empty():
		return true          # 不在队(含从未入队、已离队回池)→ 可出卡
	return not bool(m.get("alive", true))   # 在队且阵亡 → 也可出卡(补位)

# ---------------------------------------------------------------- 遗物 / 强化

func add_relic(id: String) -> bool:
	# 同名遗物全场唯一(01 §8)
	if relics.has(id):
		return false
	relics.append(id)
	var r: Dictionary = DataDB.relic_by_id(id)
	if not r.is_empty():
		for k in r.get("effects", {}):
			_apply_effect(str(k), float(r["effects"][k]))
	return true

func add_upgrade(id: String) -> void:
	upgrades[id] = int(upgrades.get(id, 0)) + 1
	var u: Dictionary = DataDB.upgrade_by_id(id)
	if not u.is_empty():
		for k in u.get("effect", {}):
			_apply_effect(str(k), float(u["effect"][k]))

func _apply_effect(key: String, v: float) -> void:
	# 修饰符三类:flat / add% / 特判(斩杀/狂化/灼烧由单位机制读表)
	match key:
		"atk_pct": add_pct("atk", v)
		"atk_speed_pct": add_pct("atk_speed", v)
		"move_pct": add_pct("move", v)
		"lord_move_pct": add_pct("lord_move_pct", v)
		"maxhp_pct": add_pct("maxhp", v)
		"lord_maxhp_flat": add_flat("lord_maxhp", v)
		"maxhp_flat": add_flat("maxhp", v)
		"cd_reduction": add_pct("cd_reduction", v)
		"heal_pct": add_pct("heal", v)
		"lord_dmg_reduction": add_pct("lord_dmg_reduction", v)
		"gold_flat": add_gold(int(v))
		"zhangfei_atk_pct": add_pct("zhangfei_atk", v)   # 事件「鞭打督邮」A(本场,01 §9)
		"team_maxhp_flat": add_flat("maxhp", v)          # 事件「三让徐州」A(本场,存量单位由 mods_changed 刷新)
		"heal_all_ratio": heal_all_requested.emit(v)     # 军医诊治/军医草药(即时群体治疗)
		"instant": pass
		_:
			pass  # team_hp_loss / random_relic / recruit 等事件特判在 EventEffects 结算
	mods_changed.emit()

# ---------------------------------------------------------------- 数值合成

func add_flat(stat_name: String, v: float) -> void:
	mods_flat[stat_name] = float(mods_flat.get(stat_name, 0.0)) + v

func add_pct(stat_name: String, v: float) -> void:
	mods_pct[stat_name] = float(mods_pct.get(stat_name, 0.0)) + v

## 最终属性 = base × (1 + Σadd%) + Σflat(02 §6)
func stat(base: float, stat_name: String) -> float:
	return base * (1.0 + float(mods_pct.get(stat_name, 0.0))) + float(mods_flat.get(stat_name, 0.0))

## 技能 CD 最终 = base × (1 − Σ缩减),总缩减封顶 40%(01 §8)
func cd_mult() -> float:
	return maxf(1.0 - CD_REDUCTION_CAP, 1.0 - float(mods_pct.get("cd_reduction", 0.0)))

func lord_move_mult() -> float:
	return 1.0 + float(mods_pct.get("lord_move_pct", 0.0))

func lord_damage_taken_mult() -> float:
	return 1.0 - clampf(float(mods_pct.get("lord_dmg_reduction", 0.0)), 0.0, 0.6)

func lord_maxhp_bonus() -> float:
	return float(mods_flat.get("lord_maxhp", 0.0))

## 治疗与护盾效果加成(青囊书 +30%,01 §8)
func heal_mult() -> float:
	return 1.0 + float(mods_pct.get("heal", 0.0))

## 武将个体攻击加成(事件「鞭打督邮」张飞 +15%,01 §9)
func hero_atk_mult(hero_id: String) -> float:
	return 1.0 + float(mods_pct.get(hero_id + "_atk", 0.0))

# ---------------------------------------------------------------- 结算快照

func dump() -> Dictionary:
	# 结算快照(02 §6):供结算页(M3)与 CSV 日志
	return {
		"run_seed": run_seed,
		"wave_idx": wave_idx,
		"kills": kills,
		"gold": gold,
		"run_time": run_time,
		"team": team.duplicate(true),
		"relics": relics.duplicate(),
		"upgrades": upgrades.duplicate(),
		"mode": mode,                     # M7:模式上下文随快照带出(结算管道 02 §8.4 用)
		"context": context.duplicate(true),
	}
