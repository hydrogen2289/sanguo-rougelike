extends "res://tests/test_base.gd"
## test_balance_sim(M5 升级,02 §9 第 5 条):
## 纯数学离散模拟(headless 即时跑完,不依赖帧推进):dt=0.5s,
## 初始三人组 + 标准招募线(赵云 W2 / 华佗 W3 / 诸葛 W4,01 §7 门槛),
## 无遗物无强化(最坏口径);技能输出按 +20% 团队 DPS 摊入。
## M5 新增:华雄按 01 §6 技能组建模——挥砍(2m 单体 20/1.5s)、冲锋(16/8s)、
## 震地(16/12s);HP<50% 进二阶段(攻速 ×1.25,每 12s 召唤西凉亲卫×4);
## W8 每 10s 增援黄巾卒×4(waves.json reinforcement)。
## 模型假设(收口上报):W1~W7 敌普攻随机选存活武将(≈玩家适度走位/聚怪,与上一棒口径一致);
## W8 走「前排承伤」口径——近战敌/华雄 60~100% 命中前排近战武将(玩家把脆皮留在后排,
## 01 §2 乐趣支柱「走位与队形」),华雄技能 50~70% 命中(前摇警示痕可躲,主公移速 4.2 > 华雄 2.6 可拉开)。
## 逐波输出 user://wave_log.csv(波次/用时/剩余敌数/队伍存活);
## 断言:W1~W7 清波用时 ≤ 各波时长上限(+3s 容差);W8 击杀华雄 ≤ 60s 且主公存活;
## 无遗物开局 W3 前不灭团。

const DT := 0.5
const SPAWN_WINDOW := 0.5     # 与 wave_director.gd 同步(M5 平衡调整 0.6→0.5)
const RING_DIST := 13.0       # 环形刷在视野外(01 §6,12~15m 取中)
const SKILL_DPS_MULT := 1.2   # 自动放技能对普攻 DPS 的加成(保守估计)
const W8_BOSS_BUDGET := 60.0
const MELEE_REACH := 1.5      # 模拟中近战接敌距离

var rng := RandomNumberGenerator.new()
var debug := false              # 置 true 打印 W8 逐秒血量(平衡调参用)

class SimHero:
	var id: String
	var hp: float
	var max_hp: float
	var atk: float
	var aspd: float      # 次/秒
	var rng_m: float     # 攻距
	var alive: bool

class SimEnemy:
	var id: String
	var ehp: float
	var max_ehp: float
	var atk: float
	var interval: float
	var speed: float
	var dist: float      # 距队伍中心的 XZ 距离
	var atk_cd: float
	var is_boss := false
	# Boss 专用
	var slash_cd := 0.0
	var charge_cd := 0.0
	var slam_cd := 0.0
	var summon_t := 0.0
	var phase2 := false

func _run() -> void:
	DataDB.load_all()
	rng.seed = 20261104
	CsvLogger.ensure_header()
	# 初始三人组(01 §2 桃园结义开局)
	var team: Array = [
		_mk_hero("liubei", DataDB.hero_by_id("liubei")),
		_mk_hero("guanyu", DataDB.hero_by_id("guanyu")),
		_mk_hero("zhangfei", DataDB.hero_by_id("zhangfei")),
	]
	var wiped := false
	for w in range(1, 9):
		var wd: Dictionary = DataDB.wave(w)
		# 标准招募线:W2 赵云 / W3 华佗 / W4 诸葛(01 §7 门槛,三选一标准路线)
		if w == 2:
			team.append(_mk_hero("zhaoyun", DataDB.hero_by_id("zhaoyun")))
		elif w == 3:
			team.append(_mk_hero("huatuo", DataDB.hero_by_id("huatuo")))
		elif w == 4:
			team.append(_mk_hero("zhuge", DataDB.hero_by_id("zhuge")))
		var r := _sim_wave(wd, team)
		CsvLogger.append_row([w, snappedf(r.clear_time, 0.1), r.enemies_left,
			_alive_hp_snapshot(team), "cleared" if r.cleared else ("wipe" if not r.any_alive else "time_up")])
		check(r.any_alive, "W%d 未灭团(存活 %d/%d)" % [w, _alive_count(team), team.size()])
		if w <= 7:
			check(r.cleared and r.clear_time <= float(wd.duration) + 3.0,
				"W%d 清波 %.1fs ≤ 时长上限 %.0fs(+3s 容差)" % [w, r.clear_time, float(wd.duration)])
		else:
			check(r.cleared and r.clear_time <= W8_BOSS_BUDGET,
				"W8 击杀华雄 %.1fs ≤ %ds(02 §9)" % [r.clear_time, int(W8_BOSS_BUDGET)])
			check(r.lord_alive, "W8 主公存活(主公死即本局失败,01 §5)")
	check(not wiped, "无遗物开局 W3 前不灭团(全程存活口径,02 §9)")

func _mk_hero(id: String, h: Dictionary) -> SimHero:
	var m := SimHero.new()
	m.id = id
	m.max_hp = float(h.get("hp", 60))
	m.hp = m.max_hp
	m.atk = float(h.get("atk", 5))
	m.aspd = float(h.get("atk_speed", 1.0))
	m.rng_m = maxf(float(h.get("range", 1.5)), 1.6)
	m.alive = true
	return m

class SimResult:
	var clear_time := 0.0
	var enemies_left := 0
	var cleared := false
	var any_alive := true
	var lord_alive := true

## 单波模拟。
## 普通波:敌人环形 13m 外按波表窗口(前 50%)刷入、走向队伍中心、进 1.5m 后普攻随机存活武将;
## 武将站桩(中心)打射程内最近敌,团队 DPS ×1.2 计入技能贡献;华佗光环/刘备光环 +
## 妙手回春(每 12s 全体 +20,自身 CD 口径)。
## W8:华雄冲锋/震地/挥砍 + 每 10s 增援黄巾卒×4 + 二阶段(HP<50%:攻速 ×1.25,
## 每 12s 召唤西凉亲卫×4);击杀华雄才算清波(01 §3)。
func _sim_wave(wd: Dictionary, team: Array) -> SimResult:
	var res := SimResult.new()
	var comp: Dictionary = wd.get("composition", {})
	var total_n := 0
	for id in comp:
		total_n += int(comp[id])
	var duration := float(wd.get("duration", 30))
	var base_hp := float(wd.get("base_hp", 15))
	var base_atk := float(wd.get("base_atk", 5))
	var is_w8 := int(wd.get("idx", 0)) >= DataDB.waves.size()
	var spawn_interval := duration * SPAWN_WINDOW / maxf(1.0, float(total_n))
	var spawn_left: Array = []
	for id in comp:
		for i in int(comp[id]):
			spawn_left.append(str(id))
	var spawned := 0
	var enemies: Array = []
	var t := 0.0
	var lord_dead := false
	var miaoshou_t := 0.0
	var rende_t := 0.0
	var reinforce_t := 0.0
	var rf: Dictionary = wd.get("reinforcement", {})
	var fuse := duration * 4.0
	while t < fuse:
		t += DT
		# --- 刷入 ---
		if not is_w8:
			while spawned < total_n and float(spawned) * spawn_interval <= t:
				var eid := str(spawn_left.pop_front())
				spawned += 1
				enemies.append(_mk_enemy(eid, base_hp, base_atk))
		else:
			# 华雄开场即在场(W8 先演出后战斗,演出计时未计入 Boss 战预算口径,02 §9)
			if spawned < total_n:
				spawned += 1
				enemies.append(_mk_enemy("huaxiong", base_hp, base_atk))
			# 每 10s 增援黄巾卒×4(Boss 在场才增援,与 wave_director 同口径)
			var boss_alive := _boss_of(enemies) != null
			if boss_alive and not rf.is_empty():
				reinforce_t += DT
				if reinforce_t >= float(rf.get("interval", 10.0)):
					reinforce_t -= float(rf.get("interval", 10.0))
					for i in int(rf.get("count", 4)):
						enemies.append(_mk_enemy(str(rf.get("enemy", "huangjin_zu")), base_hp, base_atk))
		# --- 武将输出:站桩打射程内最近敌;技能摊入 ×1.2 ---
		# 命中容差 +0.4m 与 HeroUnit._try_attack(范围+0.4)同口径
		for h in team:
			if not h.alive:
				continue
			var tgt: SimEnemy = null
			var best := 999.0
			for e in enemies:
				if e.dist <= h.rng_m + 0.4 and e.dist < best:
					best = e.dist
					tgt = e
			if tgt != null:
				tgt.ehp -= h.atk * h.aspd * DT * SKILL_DPS_MULT
		# --- 治疗:光环摊最残 + 华佗妙手回春(W8 Boss 战的关键续航,01 §4)---
		var heal_per_s := 0.0
		for h in team:
			if h.alive and (h.id == "huatuo" or h.id == "liubei"):
				heal_per_s += 1.5 if h.id == "huatuo" else 0.8
		if heal_per_s > 0.0:
			var wounded: SimHero = _most_wounded(team)
			if wounded != null:
				wounded.hp = minf(wounded.hp + heal_per_s * DT, wounded.max_hp)
		miaoshou_t += DT
		if miaoshou_t >= 12.0:
			miaoshou_t -= 12.0
			for h in team:
				if h.alive:
					h.hp = minf(h.hp + 20.0, h.max_hp)
		# 刘备仁德之泽(空格=主公技,玩家口径必按):每 10s 给 2 名最残前排 盾20+回12(01 §4)
		rende_t += DT
		if rende_t >= 10.0:
			rende_t -= 10.0
			var front_alive: Array = []
			for h in team:
				if h.alive and _is_front(h):
					front_alive.append(h)
			front_alive.sort_custom(func(a, b) -> bool: return a.hp / a.max_hp < b.hp / b.max_hp)
			for k in mini(2, front_alive.size()):
				front_alive[k].hp = minf(front_alive[k].hp + 12.0, front_alive[k].max_hp)
		# --- 存活检查 ---
		var any_alive := false
		for h in team:
			if h.alive:
				any_alive = true
		if not any_alive:
			lord_dead = true
			break
		# --- Boss 技能组(01 §6):挥砍随机 / 冲锋 16 / 震地 16 ---
		var boss: SimEnemy = _boss_of(enemies)
		if boss != null and boss.ehp > 0.0:
			_boss_act(boss, team, DT, enemies, base_hp, base_atk)
		# --- 敌人移动/攻击/死亡 ---
		# 敌人走到贴身距离(普通敌 1.5m / Boss 1.8m = attack_range×0.9,同 _move_melee),
		# 攻击容差 +0.4 与 _try_attack 同口径(先贴近再出手)。
		for i in range(enemies.size() - 1, -1, -1):
			var e: SimEnemy = enemies[i]
			if e.ehp <= 0.0:
				enemies.remove_at(i)
				continue
			var stop_at := 1.8 if e.is_boss else MELEE_REACH
			var reach := stop_at + 0.4
			if e.dist > stop_at:
				e.dist = maxf(stop_at, e.dist - e.speed * DT)
				continue
			e.atk_cd -= DT
			if e.atk_cd <= 0.0:
				e.atk_cd = e.interval
				var targets: Array = _alive(team)
				if targets.is_empty():
					lord_dead = true
					break
				var victim: SimHero
				if e.is_boss:
					# Boss 挥砍:65% 命中(击退/走位拉扯)、50% 前排承伤
					if rng.randf() < 0.65:
						victim = _pick_victim(team, 0.5)
						victim.hp -= e.atk
						if victim.hp <= 0.0:
							victim.hp = 0.0
							victim.alive = false
							if victim.id == "liubei":
								lord_dead = true
								break
					continue
				elif is_w8:
					victim = _pick_victim(team, 0.6)    # W8 增援/召唤:60% 前排
				else:
					victim = targets[rng.randi_range(0, targets.size() - 1)]
				victim.hp -= e.atk
				if victim.hp <= 0.0:
					victim.hp = 0.0
					victim.alive = false
					if victim.id == "liubei":
						lord_dead = true
						break
		if lord_dead:
			break
		if debug and absf(fmod(t, 2.0)) < DT * 0.5:
			var boss_dbg: SimEnemy = _boss_of(enemies)
			var hp_dbg := ""
			for h in team:
				hp_dbg += "%s:%d " % [h.id, roundi(h.hp)]
			print("  [t=%.1f] boss=%s dist=%.1f adds=%d | %s" % [t,
				("-1" if boss_dbg == null else str(roundi(boss_dbg.ehp))),
				(-1.0 if boss_dbg == null else boss_dbg.dist),
				enemies.size() - (1 if boss_dbg != null else 0), hp_dbg])
		# --- 结束条件 ---
		if is_w8:
			if _boss_of(enemies) == null:
				break                       # 击杀华雄才结束(01 §3)
		elif enemies.is_empty() and spawned >= total_n:
			break
	res.clear_time = t
	res.enemies_left = enemies.size()
	if is_w8:
		res.cleared = _boss_of(enemies) == null
	else:
		res.cleared = enemies.is_empty() and spawned >= total_n
	var any2 := false
	for h in team:
		if h.alive:
			any2 = true
	res.any_alive = any2
	res.lord_alive = not lord_dead
	return res

## Boss 行为:走向队伍(移速入 dist),技能组按 CD 触发;二阶段召唤。
## 规避口径(模型假设,收口上报):主公移速 4.2 > 华雄 2.6,走位可拉开;
## 前摇警示痕(0.8s/1.0s)可躲 —— 挥砍 70% 命中、冲锋/震地各 50% 命中。
func _boss_act(boss: SimEnemy, team: Array, dt: float, enemies: Array, base_hp: float, base_atk: float) -> void:
	var bd: Dictionary = DataDB.enemy_by_id("huaxiong")
	# 二阶段:HP<50% → 攻速 ×1.25 + 每 12s 召唤西凉亲卫×4(01 §6)
	if not boss.phase2 and boss.ehp / maxf(1.0, boss.max_ehp) < float(bd.get("phase2_hp_ratio", 0.5)):
		boss.phase2 = true
		boss.interval = float(bd.get("atk_interval", 1.5)) / 1.25
		boss.summon_t = 0.0
	if boss.phase2:
		boss.summon_t += dt
		if boss.summon_t >= float(bd.get("summon_interval", 12.0)):
			boss.summon_t -= float(bd.get("summon_interval", 12.0))
			for i in int(bd.get("summon_count", 4)):
				var q: SimEnemy = _mk_enemy(str(bd.get("summon_id", "xiliang_qinwei")), base_hp, base_atk)
				q.dist = boss.dist + rng.randf_range(1.0, 2.5)   # 召唤在 Boss 身旁(代码同口径)
				enemies.append(q)
	# 挥砍已并入通用近战循环(20/1.5s;65% 命中/50% 前排——走位拉扯口径),此处只管冲锋/震地/二阶段。
	# 冲锋(16,CD 8s,首 4s;前摇 0.8s 可躲 50%,命中前排)
	boss.charge_cd -= dt
	if boss.charge_cd <= 0.0:
		boss.charge_cd = float(bd.get("charge_cd", 8.0))
		if rng.randf() < 0.50:
			_hit_victim(team, float(bd.get("atk_charge", 16.0)), 1.0)
	# 震地(16,CD 12s,首 7s;前摇 1.0s 可躲 50%,4m 内以前排为主)
	boss.slam_cd -= dt
	if boss.slam_cd <= 0.0:
		boss.slam_cd = float(bd.get("slam_cd", 12.0))
		if rng.randf() < 0.50:
			_hit_victim(team, float(bd.get("atk_slam", 16.0)), 1.0)

func _hit_victim(team: Array, dmg: float, front_bias: float) -> void:
	var victim: SimHero = _pick_victim(team, front_bias)
	if victim == null:
		return
	victim.hp -= dmg
	if victim.hp <= 0.0:
		victim.hp = 0.0
		victim.alive = false

## 受击者选择:front_bias 概率命中前排武将,否则随机存活者。
## 前排 = 近战输出三人组(关羽/张飞/赵云,及吕布);治疗(华佗)/法师(诸葛)/主公
## 由玩家留在后排 —— 编码 01 §2 乐趣支柱「走位与队形」。
func _pick_victim(team: Array, front_bias: float) -> SimHero:
	var alive := _alive(team)
	if alive.is_empty():
		return null
	if rng.randf() < front_bias:
		var front: Array = []
		for h in alive:
			if _is_front(h):
				front.append(h)
		if not front.is_empty():
			return front[rng.randi_range(0, front.size() - 1)]
	return alive[rng.randi_range(0, alive.size() - 1)]

func _is_front(h: SimHero) -> bool:
	return h.id == "guanyu" or h.id == "zhangfei" or h.id == "zhaoyun" or h.id == "lvbu"

func _boss_of(enemies: Array) -> SimEnemy:
	for e in enemies:
		if e.is_boss and e.ehp > 0.0:
			return e
	return null

func _most_wounded(team: Array) -> SimHero:
	var wounded: SimHero = null
	for h in team:
		if h.alive and (wounded == null or h.hp / h.max_hp < wounded.hp / wounded.max_hp):
			wounded = h
	return wounded

func _alive(team: Array) -> Array:
	var out: Array = []
	for h in team:
		if h.alive:
			out.append(h)
	return out

func _mk_enemy(eid: String, base_hp: float, base_atk: float) -> SimEnemy:
	var e := SimEnemy.new()
	e.id = eid
	var ed: Dictionary = DataDB.enemy_by_id(eid)
	if ed.is_empty():
		e.max_ehp = base_hp
		e.atk = base_atk
		e.interval = 1.2
		e.speed = 2.3
	elif str(ed.get("ai", "")) == "boss":
		e.max_ehp = float(ed.get("hp", 1500))     # Boss 固定 HP(01 §6)
		e.atk = float(ed.get("atk_slash", 20))
		e.interval = float(ed.get("atk_interval", 1.5))
		e.speed = float(ed.get("move_speed", 2.6))
		e.is_boss = true
		e.charge_cd = 4.0    # 首技缓冲(与 boss_huaxiong.FIRST_CHARGE_DELAY 同口径)
		e.slam_cd = 7.0
	else:
		e.max_ehp = base_hp * float(ed.get("hp_mult", 1.0))
		e.atk = float(ed.get("atk_fixed", base_atk * float(ed.get("atk_mult", 1.0))))
		e.interval = float(ed.get("atk_interval", 1.2))
		e.speed = float(ed.get("move_speed", 2.3))
	e.ehp = e.max_ehp
	e.dist = RING_DIST * rng.randf_range(0.92, 1.15)
	e.atk_cd = e.interval
	return e

func _alive_count(team: Array) -> int:
	var n := 0
	for h in team:
		if h.alive:
			n += 1
	return n

func _alive_hp_snapshot(team: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for h in team:
		parts.append("%s:%d/%d%s" % [h.id, roundi(h.hp), roundi(h.max_hp), "" if h.alive else "(阵亡)"])
	return ";".join(parts)
