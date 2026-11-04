extends "res://tests/test_base.gd"
## test_levels(关卡设计 v0.2,docs/03-关卡设计.md §2/§4):
## 8 波剧本字段契约、分批投放与 composition 对齐、扇区合法性、难度曲线、
## W2 断崖修复口径、W8 Boss 口径,以及运行时 spawn_queue / 刷怪方向的真实生效。
## 依赖 run_all.gd 注册的 autoload(DataDB/RunState/…)。

const BATTLE_SCENE := "res://scenes/battle.tscn"

func _run() -> void:
	DataDB.load_all()
	var prev_atk := 0.0
	var prev_hp := 0.0
	for i in range(1, 9):
		var w: Dictionary = DataDB.wave(i)
		check(not w.is_empty(), "波 %d 存在" % i)
		check(str(w.get("theme", "")) != "", "波 %d 有主题名" % i)
		var obj: Dictionary = w.get("objective", {})
		check(str(obj.get("type", "")) != "" and str(obj.get("label", "")) != "", "波 %d 有目标类型与文案" % i)
		var plan: Dictionary = w.get("spawn_plan", {})
		check(not plan.is_empty(), "波 %d 有分批剧本" % i)
		var batches: Array = plan.get("batches", [])
		check(batches.size() >= 1, "波 %d 至少 1 批" % i)
		var max_t := float(w.get("duration", 30)) * 0.5
		var last_t := -1.0
		var sums := {}
		for b in batches:
			var bt := float(b.get("t", -1.0))
			check(bt >= 0.0 and bt <= max_t, "波 %d 批次 t=%.1f 在投放窗口内" % [i, bt])
			check(bt >= last_t, "波 %d 批次时间单调" % i)
			last_t = bt
			var barc: Array = b.get("arc", plan.get("arc", []))
			check(barc.size() == 2 and float(barc[0]) < float(barc[1]), "波 %d 扇区合法" % i)
			var bsp: Dictionary = b.get("spawn", {})
			check(not bsp.is_empty(), "波 %d 批次 spawn 非空" % i)
			for id in bsp:
				sums[str(id)] = int(sums.get(str(id), 0)) + int(bsp[id])
		var comp_i: Dictionary = w.get("composition", {})
		for id in comp_i:
			check(int(sums.get(str(id), 0)) == int(comp_i[id]), "波 %d 剧本数量对齐 composition: %s" % [i, str(id)])
		check(sums.size() == comp_i.size(), "波 %d 剧本未多刷敌人" % i)
		var atk := float(w.get("base_atk", 0))
		var hp := float(w.get("base_hp", 0))
		check(atk >= prev_atk and hp >= prev_hp, "波 %d 基础攻击/HP 不低于上一波" % i)
		prev_atk = atk
		prev_hp = hp

	# --- W2 断崖修复(实机 4 局 3 次 W2 阵亡) ---
	var w1: Dictionary = DataDB.wave(1)
	var w2: Dictionary = DataDB.wave(2)
	check(float(w2.get("base_atk", 99)) <= float(w1.get("base_atk", 0)), "W2 基准攻击不高于 W1")
	var comp2: Dictionary = w2.get("composition", {})
	check(int(comp2.get("huangjin_gongshou", 0)) <= 2, "W2 弓手不超过 2 名")
	var archer_t := -1.0
	var plan2: Dictionary = w2.get("spawn_plan", {})
	for b in plan2.get("batches", []):
		var asp: Dictionary = b.get("spawn", {})
		if asp.has("huangjin_gongshou"):
			archer_t = float(b.get("t", -1.0))
	check(archer_t >= 10.0, "W2 弓手延后至 >=10s 投放(实测 %.1fs)" % archer_t)
	var total1 := 0
	var total2 := 0
	var comp1: Dictionary = w1.get("composition", {})
	for id in comp1:
		total1 += int(comp1[id])
	for id in comp2:
		total2 += int(comp2[id])
	check(total2 <= total1 + 3, "W1→W2 敌兵增量 <=3(一次只引入一个新变量)")

	# --- W8 Boss 口径未被关卡重设计破坏 ---
	var w8: Dictionary = DataDB.wave(8)
	var comp8: Dictionary = w8.get("composition", {})
	check(comp8.has("huaxiong"), "W8 华雄在场")
	var after8: Array = w8.get("after", [])
	check(after8.has("victory"), "W8 胜利结算队列")
	var rf8: Dictionary = w8.get("reinforcement", {})
	check(not rf8.is_empty(), "W8 增援配置存在")
	var obj8: Dictionary = w8.get("objective", {})
	check(str(obj8.get("type", "")) == "boss", "W8 目标类型为 boss")

	# --- 运行时:分批队列与扇区真实生效(不是回退均匀刷新) ---
	RunState.reset(903)
	var battle = (load(BATTLE_SCENE) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(battle)
	var d = battle.get_node("WaveDirector")
	var comp_rt: Dictionary = d.wave_data.get("composition", {})
	var total := 0
	for id in comp_rt:
		total += int(comp_rt[id])
	check(d.spawn_queue.size() == total, "W1 运行时队列长度 = composition 总数(%d)" % total)
	var q_last := -1.0
	var with_arc := 0
	var distinct_t := {}
	for item in d.spawn_queue:
		var qt := float(item["t"])
		check(qt >= q_last, "W1 运行时队列按 t 升序")
		q_last = qt
		distinct_t[qt] = true
		var iarc: Array = item.get("arc", [])
		if iarc.size() == 2:
			with_arc += 1
	check(with_arc == total, "W1 每只敌人都带扇区配置")
	check(distinct_t.has(5.0) and distinct_t.has(10.0), "W1 按剧本 0/5/10s 分批投放(非均匀刷新)")

	# --- 扇区刷怪方向:东路落点偏 +X,北路落点偏 -Z ---
	var spawner: Spawner = d.spawner
	var lord: Node3D = battle.get_node("Units/PlayerLord")
	var e := spawner.ring_position([-10, 10]) - lord.global_position
	var n := spawner.ring_position([-100, -80]) - lord.global_position
	check(absf(e.z) < absf(e.x) and e.x > 0.0, "东路扇区落点偏 +X")
	check(n.z < 0.0, "北路扇区落点偏 -Z")
	battle.free()
