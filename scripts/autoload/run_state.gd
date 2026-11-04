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
	for id in INITIAL_TEAM:
		add_team_member(id)

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
	var max_hp := float(h.get("hp", 60))
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
	}
