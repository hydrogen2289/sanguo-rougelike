extends "res://tests/test_base.gd"
## test_tower_gen(M10,02 §4.4/§8.3/§12.2-3):
## 塔随机波次生成器契约 + 塔层推进(TowerSave)。
## - 同 seed 同输出(确定性)、不同 seed 不同输出
## - 生成结果过 DataDB._validate_wave_entry 同款结构校验
## - 敌数/批次时间/arc/composition 全部满足契约(与 waves.json 同源约束)
## - Boss 层出 Boss(每 boss_every 层)、Boss 层无波间(02 §8.2)
## - 层数递进难度单调(敌数不降、base_hp/base_atk 不降)
## - 1~8 层走 waves.json 原剧本(约束 6)
## - TowerSave 最高层只增不减、负数/越界拒绝
## 存档走测试专用文件 test_tower_unit.json,套件结束清理并恢复默认,不碰玩家真实存档。

const FLOORS := 100     # 02 §12.2-3:输出 100 层全部通过校验

var _st: SceneTree

func _run() -> void:
	_st = Engine.get_main_loop() as SceneTree
	DataDB.load_all()
	var old_file: String = SaveState.save_file
	SaveState.save_file = "test_tower_unit.json"
	SaveState.delete_save()
	SaveState.load_game()
	_test_table()
	_test_determinism()
	_test_contract_all_floors()
	_test_monotonic()
	_test_boss_layers()
	_test_ref_floors()
	_test_reject_paths()
	_test_tower_save()
	SaveState.delete_save()
	SaveState.save_file = old_file
	SaveState.data = {}

# ---------------------------------------------------------------- 1. 表

func _test_table() -> void:
	check(not DataDB.tower.is_empty(), "tower.json 已加载")
	check(DataDB.last_errors.is_empty(), "tower 表过 DataDB 校验(last_errors 空: %s)" % str(DataDB.last_errors))
	var gen_from := int(DataDB.tower.get("gen_from", 0))
	var ref_to := int(DataDB.tower.get("floors_ref", {}).get("to", 0))
	check(gen_from == ref_to + 1, "gen_from(%d) 与 floors_ref.to(%d) 无缝衔接" % [gen_from, ref_to])
	check(ref_to == DataDB.waves.size(), "1~%d 层全部复用 waves.json(约束 6)" % ref_to)
	check(int(DataDB.tower.get("boss_every", 0)) == 8, "boss_every=8")

# ---------------------------------------------------------------- 2. 确定性

func _test_determinism() -> void:
	var a: Dictionary = TowerWaveGen.generate(12, 4242)
	var b: Dictionary = TowerWaveGen.generate(12, 4242)
	check(not a.is_empty() and a == b, "同 seed 同层 → 输出完全一致(确定性)")
	var c: Dictionary = TowerWaveGen.generate(12, 4243)
	check(not c.is_empty() and a != c, "不同 seed → 输出不同")
	# 纯函数:不碰全局/RunState 随机流
	var seed_before := RunState.rng.seed
	var state_before := RunState.rng.state
	var _x: Dictionary = TowerWaveGen.generate(15, 99)  # 只为触发一次生成
	check(RunState.rng.seed == seed_before and RunState.rng.state == state_before,
		"生成不消耗 RunState.rng(纯函数,不污染本局随机)")

# ---------------------------------------------------------------- 3. 100 层契约

func _test_contract_all_floors() -> void:
	var enemy_ids := {}
	for e in DataDB.enemies:
		enemy_ids[str(e.get("id", ""))] = true
	var bad := 0
	var checked := 0
	for f in range(9, 9 + FLOORS):
		var w: Dictionary = TowerWaveGen.generate(f, 20261106)
		if w.is_empty():
			bad += 1
			printerr("    [gen] 第 %d 层生成失败: %s" % [f, TowerWaveGen.last_error])
			continue
		# 走 DataDB 同款结构校验(_validate_wave_entry:契约全项;手写剧本调参锚点不适用塔)
		var before: int = DataDB.last_errors.size()
		DataDB._validate_wave_entry(w, "test_tower", 0, "tower/%d" % f, enemy_ids, false)
		if DataDB.last_errors.size() > before:
			bad += 1
			printerr("    [gen] 第 %d 层校验失败: %s" % [f, DataDB.last_errors[before]])
			while DataDB.last_errors.size() > before:
				DataDB.last_errors.remove_at(DataDB.last_errors.size() - 1)
			continue
		checked += 1
		if not _contract_ok(w, f):
			bad += 1
	check(bad == 0, "9~%d 共 %d 层全部生成并过同款校验(失败 %d / 过检 %d)" % [8 + FLOORS, FLOORS, bad, checked])

## 逐项契约(02 §4.4 生成规则)
func _contract_ok(w: Dictionary, f: int) -> bool:
	var ok := true
	var comp: Dictionary = w.get("composition", {})
	if comp.is_empty():
		printerr("    [gen] 第 %d 层 composition 为空" % f)
		ok = false
	var total := 0
	for id in comp:
		total += int(comp[id])
	# 敌数 = f0 + per_floor×(f−gen_from),封顶 cap
	var cnt: Dictionary = DataDB.tower.gen.count as Dictionary
	var want := clampi(int(cnt.f0) + int(cnt.per_floor) * (f - 9), 1, int(cnt.cap))
	if bool(DataDB.tower_is_boss_floor(f)):
		if int(comp.get("huaxiong", 0)) != 1:
			printerr("    [gen] 第 %d 层是 Boss 层却没有华雄" % f)
			ok = false
	elif total != want:
		printerr("    [gen] 第 %d 层敌数 %d != 期望 %d" % [f, total, want])
		ok = false
	# 批次:时间单调不减、∈ [0, duration×0.5]、各批 spawn 汇总逐项等于 composition
	var plan: Dictionary = w.get("spawn_plan", {})
	var batches: Array = plan.get("batches", [])
	if batches.is_empty():
		printerr("    [gen] 第 %d 层无批次" % f)
		ok = false
	var max_t := float(w.get("duration", 0)) * 0.5
	var last_t := -1.0
	var sums := {}
	for b in batches:
		var t := float(b.get("t", -1.0))
		if t < 0.0 or t > max_t + 0.001:
			printerr("    [gen] 第 %d 层批次 t=%.1f 越出 [0,%.1f]" % [f, t, max_t])
			ok = false
		if t < last_t - 0.001:
			printerr("    [gen] 第 %d 层批次时间非单调(%.1f < %.1f)" % [f, t, last_t])
			ok = false
		last_t = t
		for id in b.get("spawn", {}):
			sums[str(id)] = int(sums.get(str(id), 0)) + int(b["spawn"][id])
	for id in comp:
		if int(sums.get(str(id), 0)) != int(comp[id]):
			printerr("    [gen] 第 %d 层 spawn 汇总 %s=%d != composition %d" % [
				f, str(id), int(sums.get(str(id), 0)), int(comp[id])])
			ok = false
	# arc:每批 [起,止] 且 -180 <= 起 < 止 <= 180
	for b in batches:
		var arc = b.get("arc", null)
		if arc == null:
			continue
		var a: Array = arc
		if a.size() != 2 or float(a[0]) < -180.0 or float(a[1]) > 180.0 or float(a[0]) >= float(a[1]):
			printerr("    [gen] 第 %d 层 arc 非法: %s" % [f, str(arc)])
			ok = false
	# 近远比在 ranged_ratio 内(非 Boss 层)
	if not bool(DataDB.tower_is_boss_floor(f)):
		var rr: Array = DataDB.tower.gen.ranged_ratio as Array
		var ranged_n := 0
		for id in comp:
			if str(DataDB.enemy_by_id(str(id)).get("ai", "")) == "ranged":
				ranged_n += int(comp[id])
		var ratio := float(ranged_n) / maxf(1.0, float(total))
		# 四舍五入留 1 只容差
		if ratio > float(rr[1]) + 0.06 or ratio < float(rr[0]) - 0.06:
			printerr("    [gen] 第 %d 层远程占比 %.2f 越出 %s" % [f, ratio, str(rr)])
			ok = false
	return ok

# ---------------------------------------------------------------- 4. 难度单调

func _test_monotonic() -> void:
	var prev_hp := 0.0
	var prev_atk := 0.0
	var prev_count := 0
	var bad := 0
	for f in range(9, 9 + FLOORS):
		var w: Dictionary = TowerWaveGen.generate(f, 777)
		if w.is_empty():
			continue
		var hp := float(w.get("base_hp", 0))
		var atk := float(w.get("base_atk", 0))
		if hp < prev_hp - 0.001 or atk < prev_atk - 0.001:
			printerr("    [mono] 第 %d 层基础值回落(HP %.1f→%.1f ATK %.1f→%.1f)" % [f, prev_hp, hp, prev_atk, atk])
			bad += 1
		prev_hp = hp
		prev_atk = atk
		# 敌数:Boss 层带杂兵,不参与「普通层敌数单调」比较
		if not bool(DataDB.tower_is_boss_floor(f)):
			var total := 0
			for id in w.get("composition", {}):
				total += int(w["composition"][id])
			if total < prev_count:
				printerr("    [mono] 第 %d 层敌数回落(%d→%d)" % [f, prev_count, total])
				bad += 1
			prev_count = total
	check(bad == 0, "9~%d 层难度单调:base_hp/base_atk 不降、普通层敌数不降" % (8 + FLOORS))

# ---------------------------------------------------------------- 5. Boss 层

func _test_boss_layers() -> void:
	var every := int(DataDB.tower.get("boss_every", 8))
	var bad := 0
	var boss_hits := 0
	for f in range(9, 9 + FLOORS):
		var w: Dictionary = TowerWaveGen.generate(f, 31337)
		if w.is_empty():
			continue
		var is_boss := f % every == 0
		var has_boss := false
		for id in w.get("composition", {}):
			if str(DataDB.enemy_by_id(str(id)).get("ai", "")) == "boss":
				has_boss = true
		if is_boss != has_boss:
			printerr("    [boss] 第 %d 层 Boss 标记不符(应 %s,实际 %s)" % [f, str(is_boss), str(has_boss)])
			bad += 1
		if is_boss:
			boss_hits += 1
			# Boss 层后无波间(02 §8.2)
			if not (w.get("after", []) as Array).is_empty():
				printerr("    [boss] 第 %d 层 Boss 层不该有波间队列: %s" % [f, str(w.after)])
				bad += 1
			if (w.get("reinforcement", {}) as Dictionary).is_empty():
				printerr("    [boss] 第 %d 层缺增援结构" % f)
				bad += 1
			if str(w.get("objective", {}).get("type", "")) != "boss":
				printerr("    [boss] 第 %d 层目标类型应为 boss" % f)
				bad += 1
	check(bad == 0, "Boss 层排程正确(每 %d 层出 Boss,共 %d 层;Boss 层无波间 + 带增援)" % [every, boss_hits])
	# boss_pool 越界拒绝
	var saved: Array = DataDB.tower.get("boss_pool", []) as Array
	DataDB.tower["boss_pool"] = ["不存在的老虎"]
	var r: Dictionary = TowerWaveGen.generate(16, 1)
	check(r.is_empty() and TowerWaveGen.last_error != "", "boss_pool 引用非法敌人 → 生成拒绝并给错误信息")
	DataDB.tower["boss_pool"] = saved

# ---------------------------------------------------------------- 6. 1~8 层原剧本

func _test_ref_floors() -> void:
	var bad := 0
	for f in range(1, 9):
		var w: Dictionary = DataDB.tower_floor(f, 1)
		var ref: Dictionary = DataDB.wave(f)
		if w.is_empty() or w != ref:
			bad += 1
	check(bad == 0, "1~8 层逐层等于 waves.json 原剧本(约束 6,不做任何改写)")
	var r9: Dictionary = TowerWaveGen.generate(8, 1)
	check(r9.is_empty(), "生成器拒绝 1~8 层(归 waves.json,职责边界)")
	check(TowerWaveGen.last_error != "", "拒绝时 last_error 有原因,不静默返回")

# ---------------------------------------------------------------- 7. 拒绝路径

func _test_reject_paths() -> void:
	check(TowerWaveGen.generate(0, 1).is_empty(), "第 0 层被拒")
	check(TowerWaveGen.generate(-3, 1).is_empty(), "负层被拒")
	check(DataDB.tower_floor(0, 1).is_empty(), "DataDB.tower_floor(0) 返回空")
	# 坏池:enemy_pool 里塞不存在的敌人 → 生成阶段拒绝,不产坏数据
	var saved: Array = DataDB.tower.gen.get("enemy_pool", [])
	DataDB.tower.gen["enemy_pool"] = ["huangjin_zu"]
	var w: Dictionary = TowerWaveGen.generate(10, 5)
	check(not w.is_empty(), "池缩减到单兵种仍能生成(健壮性)")
	if not w.is_empty():
		var only := {}
		for id in w.get("composition", {}):
			only[str(id)] = true
		check(only.has("huangjin_zu"), "单兵种池 → composition 只含该兵种")
	DataDB.tower.gen["enemy_pool"] = saved

# ---------------------------------------------------------------- 8. TowerSave

func _test_tower_save() -> void:
	SaveState.delete_save()
	SaveState.load_game()
	check(TowerSave.highest_floor() == 0, "新档最高层 0")
	check(TowerSave.next_floor() == 1, "next_floor = 最高层+1")
	var r1: Dictionary = TowerSave.record_floor(5)
	check(bool(r1.get("ok", false)) and bool(r1.get("changed", false)) and TowerSave.highest_floor() == 5,
		"推进到第 5 层")
	var r2: Dictionary = TowerSave.record_floor(3)
	check(bool(r2.get("ok", false)) and not bool(r2.get("changed", true)) and TowerSave.highest_floor() == 5,
		"回落到第 3 层不降(只增不减)")
	check(TowerSave.record_floor(9).get("ok", false) and TowerSave.highest_floor() == 9, "推进到第 9 层")
	check(not TowerSave.record_floor(-1).get("ok", true) and TowerSave.highest_floor() == 9,
		"负数层被拒且不改存档")
	check(not TowerSave.record_floor(TowerSave.floor_cap() + 1).get("ok", true)
		and TowerSave.highest_floor() == 9, "越界层被拒且不改存档")
	check(SaveState.validate(SaveState.data).is_empty(), "推进后存档通过校验")
	check(TowerSave.is_boss_floor(8) and TowerSave.is_boss_floor(16) and not TowerSave.is_boss_floor(9),
		"Boss 层判定与 tower.json boss_every 一致")
	# 击杀统计
	check(TowerSave.record_kills(120).get("ok", false)
		and int(SaveState.data.stats.get("tower_best_kill", 0)) == 120, "最好击杀记录 120")
	check(not TowerSave.record_kills(50).get("changed", true)
		and int(SaveState.data.stats.get("tower_best_kill", 0)) == 120, "击杀数只增不减")
	# 落盘往返
	SaveState.flush()
	SaveState.data = {}
	SaveState.load_game()
	check(TowerSave.highest_floor() == 9, "最高层持久化:读回仍为 9")
