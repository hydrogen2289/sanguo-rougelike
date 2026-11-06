class_name TowerWaveGen
extends RefCounted
## TowerWaveGen —— 试炼塔随机波次生成器(M10,02 §4.4/§8.3)。
##
## 契约:generate(floor, seed) -> Dictionary,纯函数 —— 随机只走本函数内按 seed 新建的
## RandomNumberGenerator,不碰全局 randi()/RunState.rng(否则跑塔会污染本局其它随机)。
## 输出与 data/waves.json 完全同契约(idx/duration/base_hp/base_atk/theme/objective/
## composition/spawn_plan{arc,batches}/gold_total/after/reinforcement),生成后先过
## DataDB 同款单波校验,不过就返回空字典 + last_error(绝不静默交坏数据给 wave_director)。
##
## 规则出处 02 §4.4:
## - 敌数 = count.f0 + count.per_floor × (f − gen_from),封顶 count.cap
## - base_hp = f0 × growth^(f − gen_from),base_atk 同理(按本局当前层算,不用历史最高层)
## - 近远比在 ranged_ratio 内随机;批次 t 单调不减且 ∈ [0, duration × 0.5]
## - arc 按批次轮换四象限,起 < 止且 ∈ [−180, 180]
## - Boss 层(每 boss_every 层)= boss_pool 顺序取,增援沿用现有 reinforcement 结构

## 最近一次失败原因(成功时清空);测试与 wave_director 取证用
static var last_error := ""

const ENEMY_MELEE := "huangjin_zu"        # 近战主力池缺省
const ENEMY_RANGED := "huangjin_gongshou" # 远程池缺省
const ENEMY_ELITE := "huangjin_lishi"     # 精英池缺省
## 四象限扇区(度,0°=+X 东,90°=+Z 南,见 spawner.ring_position)
const QUADRANTS := [[-180, -90], [-90, 0], [0, 90], [90, 180]]

# ---------------------------------------------------------------- 入口

## 生成第 floor 层的波次字典。floor < gen_from 时不属于本生成器职责(1~8 层走 waves.json),
## 返回空 + last_error。seed 决定本层全部随机。
static func generate(floor: int, gen_seed: int) -> Dictionary:
	last_error = ""
	var cfg: Dictionary = DataDB.tower
	if cfg.is_empty():
		return _fail("tower.json 未加载")
	var gen_from := int(cfg.get("gen_from", 9))
	if floor < gen_from:
		return _fail("层 %d 低于 gen_from=%d(1~%d 层引用 waves.json)" % [floor, gen_from, gen_from - 1])
	var gen: Dictionary = cfg.get("gen", {})
	if gen.is_empty():
		return _fail("tower.json 缺 gen 段")
	var boss_every := int(cfg.get("boss_every", 8))
	if boss_every <= 0:
		return _fail("boss_every 非法(%d)" % boss_every)
	if floor % boss_every == 0:
		return _build_boss(floor, cfg, gen)
	return _build_normal(floor, gen_from, gen, gen_seed)

# ---------------------------------------------------------------- 普通层

static func _build_normal(floor: int, gen_from: int, gen: Dictionary, gen_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = gen_seed
	var steps := floor - gen_from
	# --- 敌数:线性增长 + 封顶(02 §4.4) ---
	var cnt: Dictionary = gen.get("count", {})
	var count_total := int(cnt.get("f0", 20)) + int(cnt.get("per_floor", 1)) * steps
	count_total = mini(count_total, int(cnt.get("cap", 45)))
	count_total = maxi(count_total, 1)
	# --- 基础值:指数增长(占位曲线,同层单调) ---
	var hp := _curve(gen.get("base_hp", {}), steps)
	var atk := _curve(gen.get("base_atk", {}), steps)
	# --- 敌种配比:远程占比在 ranged_ratio 内随机;精英从 elite_from_floor 起按层加 1 名 ---
	var pool: Array = gen.get("enemy_pool", [ENEMY_MELEE, ENEMY_RANGED, ENEMY_ELITE])
	if pool.is_empty():
		return _fail("enemy_pool 为空")
	var ranged_id := _pick_pool(pool, ENEMY_RANGED)
	var elite_id := _pick_pool(pool, ENEMY_ELITE)
	var melee_id := _pick_pool(pool, ENEMY_MELEE)
	var rr: Array = gen.get("ranged_ratio", [0.15, 0.30])
	var ratio := rng.randf_range(float(rr[0]), float(rr[1]))
	var elite_n := 0
	if floor >= int(gen.get("elite_from_floor", 3)) and elite_id != "":
		elite_n = mini(maxi(1, (floor - int(gen.get("elite_from_floor", 3))) / 4 + 1), count_total / 5)
	var ranged_n := 0
	if ranged_id != "" and ranged_id != melee_id:
		ranged_n = clampi(roundi(float(count_total) * ratio), 0, count_total - elite_n)
	var melee_n := count_total - ranged_n - elite_n
	var comp := {}
	if melee_n > 0:
		comp[melee_id] = melee_n
	if ranged_n > 0:
		comp[ranged_id] = ranged_n
	if elite_n > 0:
		comp[elite_id] = elite_n
	if comp.is_empty():
		comp[melee_id] = count_total
	# --- 批次时间:单调撒点于 [0, duration × 0.5] ---
	var duration := _duration_for(floor)
	var bn: Array = gen.get("batch_n", [3, 5])
	var batch_count := rng.randi_range(int(bn[0]), int(bn[1]))
	batch_count = maxi(batch_count, 1)
	var max_t := duration * 0.5
	var times: Array = []
	for i in batch_count:
		times.append(snappedf(max_t * float(i) / float(batch_count), 0.1))
	# 少量抖动但保持单调不降
	for i in range(1, times.size()):
		times[i] = minf(max_t, snappedf(times[i] + rng.randf_range(0.0, 1.2), 0.1))
	# --- 把 composition 逐项摊到各批次(保证每批至少 1 只,总量逐项等于 composition) ---
	var batches := _distribute(comp, times)
	if batches.is_empty():
		return _fail("批次分配失败(敌数 %d / 批次 %d)" % [count_total, batch_count])
	var wave := {
		"idx": floor,
		"duration": duration,
		"base_hp": hp,
		"base_atk": atk,
		"theme": "塔第 %d 层" % floor,
		"objective": {"type": "clear", "label": "清剿本层黄巾"},
		"composition": comp,
		"spawn_plan": {"arc": [-180, 180], "batches": batches},
		"gold_total": gold_of(floor),
		"after": _after_queue(floor),
	}
	return _validate_and_return(wave)

# ---------------------------------------------------------------- Boss 层

static func _build_boss(floor: int, cfg: Dictionary, gen: Dictionary) -> Dictionary:
	var pool: Array = cfg.get("boss_pool", [])
	if pool.is_empty():
		return _fail("boss_pool 为空(Boss 层 %d 无 Boss 可出)" % floor)
	var boss_id := str(pool[((floor / int(cfg.get("boss_every", 8))) - 1) % pool.size()])
	if DataDB.enemy_by_id(boss_id).is_empty():
		return _fail("boss_pool 引用不存在的敌人 '%s'" % boss_id)
	var steps := maxi(0, floor - int(cfg.get("gen_from", 9)))
	var hp := _curve(gen.get("base_hp", {}), steps)
	var atk := _curve(gen.get("base_atk", {}), steps)
	# Boss 层同时带一波杂兵(Boss 单独出场不够热闹),数量少于普通层
	var esc: Dictionary = gen.get("count", {})
	var esc_n := clampi(int(esc.get("f0", 20)) / 2, 1, int(esc.get("cap", 45)))
	var melee_id := _pick_pool(gen.get("enemy_pool", []), ENEMY_MELEE)
	if melee_id == "":
		melee_id = ENEMY_MELEE
	var duration := _duration_for(floor)
	var comp := {boss_id: 1, melee_id: esc_n}
	var batches := _distribute(comp, [0.0, snappedf(duration * 0.25, 0.1)])
	if batches.is_empty():
		return _fail("Boss 层批次分配失败")
	var wave := {
		"idx": floor,
		"duration": duration,
		"base_hp": hp,
		"base_atk": atk,
		"theme": "塔第 %d 层 · 魔将镇塔" % floor,
		"objective": {"type": "boss", "label": "斩将破关"},
		"composition": comp,
		"spawn_plan": {"arc": [-180, 180], "batches": batches},
		"reinforcement": {"enemy": melee_id, "count": 4, "interval": 10.0, "arc": [120, 180]},
		"gold_total": gold_of(floor),
		# Boss 层后无波间(02 §8.2):直接进下一层
		"after": [],
	}
	return _validate_and_return(wave)

# ---------------------------------------------------------------- 工具

## 曲线:f0 × growth^steps(取整到 1 位;保证同 steps 下前后层不降)
static func _curve(c: Dictionary, steps: int) -> float:
	var f0 := float(c.get("f0", 30))
	var g := float(c.get("growth", 1.0))
	return snappedf(f0 * pow(g, float(maxi(0, steps))), 0.1)

## 层时长:随层号缓增,夹在 25~45(与 waves.json 锚点一致)
static func _duration_for(floor: int) -> float:
	return clampf(25.0 + float(floor - 9) * 0.8, 25.0, 45.0)

## 每层军资:与 waves.json gold_total 同量级(15~30,受 DataDB 锚点约束)
static func gold_of(floor: int) -> int:
	return clampi(15 + (floor - 9) / 2, 15, 30)

## 波间队列(02 §8.2:三选一 → 事件(层号触发) → 商店(第 4/6 层后))
## 9+ 层仍保留塔的波间节奏:每层三选一,每 4 层加商店。
static func _after_queue(floor: int) -> Array:
	var q: Array = ["triselect"]
	if floor % 4 == 0:
		q.append("shop")
	return q

## 池内挑 id:按既定缺省 id 优先,池里没有就取池内第一个能匹配该角色的敌人
static func _pick_pool(pool: Array, preferred: String) -> String:
	for id in pool:
		if str(id) == preferred:
			return preferred
	for id in pool:
		var e := DataDB.enemy_by_id(str(id))
		var want := "ranged" if preferred == ENEMY_RANGED else "melee"
		if str(e.get("ai", "")) == want:
			return str(id)
	return ""

## 把 composition 逐项摊到批次:每批至少 1 只,总量逐项等于 composition。
## 摊法:按各敌种余额轮转,保证时间单调(批次数组按 times 顺序输出)。
static func _distribute(comp: Dictionary, times: Array) -> Array:
	var nl := times.size()
	if nl == 0:
		return []
	var remain := {}
	for id in comp:
		remain[str(id)] = int(comp[id])
	var order: Array = []
	for id in comp:
		order.append(str(id))
	if order.is_empty():
		return []
	var batches: Array = []
	for i in nl:
		batches.append({"t": float(times[i]), "spawn": {}})
	var slot := 0
	var guard := 0
	var total := 0
	for id in remain:
		total += int(remain[id])
	# 防死循环上限必须在循环外算好:total 在循环里递减,拿它当上限会让循环提前退出,
	# 剩下一截兵没摊进批次 → spawn_plan 与 composition 数量对不上(校验必挂)。
	var guard_cap := total * nl + nl + 16
	while total > 0 and guard < guard_cap:
		guard += 1
		var placed := false
		for k in order.size():
			var id: String = str(order[(slot + k) % order.size()])
			if int(remain[id]) <= 0:
				continue
			var b: Dictionary = batches[slot % nl]
			var sp: Dictionary = b["spawn"]
			sp[id] = int(sp.get(id, 0)) + 1
			b["spawn"] = sp
			remain[id] = int(remain[id]) - 1
			total -= 1
			placed = true
			break
		slot += 1
		if not placed:
			break
	# 空批次丢弃(仍保持 t 单调)
	var out: Array = []
	for b in batches:
		if not (b["spawn"] as Dictionary).is_empty():
			out.append(b)
	if out.is_empty():
		return []
	# 扇区轮换:批次 i 用第 i%4 象限
	for i in out.size():
		var q: Array = QUADRANTS[i % QUADRANTS.size()]
		out[i]["arc"] = [q[0], q[1]]
	return out

## 生成后必过 DataDB 同款单波校验(02 §8.3):不过就空字典 + last_error,绝不静默交坏数据。
## 校验借道 DataDB._validate_wave_entry —— 该类实例只有 DataDB 一个,经单例取。
static func _validate_and_return(wave: Dictionary) -> Dictionary:
	var db: Node = DataDB
	var enemy_ids := {}
	for e in DataDB.enemies:
		enemy_ids[str(e.get("id", ""))] = true
	var before: int = db.last_errors.size()
	db._validate_wave_entry(wave, "tower_gen", 0, "tower/%d" % int(wave.get("idx", -1)), enemy_ids, false)
	if db.last_errors.size() > before:
		var msg := ""
		for i in range(before, db.last_errors.size()):
			msg += str(db.last_errors[i]) + "; "
		# 只保留本次新增的错误,不污染 DataDB 的启动校验结果
		while db.last_errors.size() > before:
			db.last_errors.remove_at(db.last_errors.size() - 1)
		return _fail(msg.strip_edges())
	return wave

static func _fail(msg: String) -> Dictionary:
	last_error = msg
	printerr("[TowerWaveGen] " + msg)
	return {}
