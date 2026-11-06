extends "res://tests/test_base.gd"
## test_reward(M11,02 §8.4/§12.2-2/§12.2-4):
## 结算统一管道 RewardSettle。
## - 闯关:首通/重复奖励入库、评星、奖励清单逐项与入库一致
## - 闯关失败:不发奖励、不改存档
## - 塔:按层结算、Boss 层 ×boss_mult、阵亡 0.5 折算、撤退 1.0 折算
## - **局内军资不入库**(02 §8.4 硬约束):RunState.gold 结算后一个字都不进钱包
## - 塔内临时武将不入 roster
## - 最高层随结算推进、只增不减
## - 结算页 result.gd 的奖励清单与 settle 返回值同源(前端不重算)
## 存档走测试专用文件 test_reward_unit.json,套件结束清理并恢复默认。

var _st: SceneTree

func _run() -> void:
	_st = Engine.get_main_loop() as SceneTree
	DataDB.load_all()
	var old_file: String = SaveState.save_file
	SaveState.save_file = "test_reward_unit.json"
	_test_campaign_settle()
	_test_campaign_failure()
	_test_tower_settle()
	_test_currency_not_banked()
	_test_roster_untouched()
	_test_bad_inputs()
	await _test_battle_wiring()
	await _test_result_page()
	SaveState.delete_save()
	SaveState.save_file = old_file
	SaveState.data = {}

# ---------------------------------------------------------------- 工具

func _fresh() -> void:
	SaveState.delete_save()
	SaveState.load_game()

func _close(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps

# ---------------------------------------------------------------- 1. 闯关结算

func _test_campaign_settle() -> void:
	_fresh()
	RunState.reset(4242)
	RunState.mode = &"campaign"
	RunState.context = {"stage_id": "1-1", "wave_total": 1}
	var j0 := SaveState.junzi()
	var r: Dictionary = RewardSettle.settle("campaign",
		{"victory": true, "no_casualty": true, "lord_hp_ratio": 0.9})
	check(bool(r.get("ok", false)) and bool(r.get("victory", false)), "闯关胜利结算 ok")
	check(bool(r.get("first", false)), "1-1 首通判定")
	check(int(r.get("stars", 0)) == 3, "无阵亡 + 主公 HP 90% → ★3")
	var rewards: Dictionary = r.get("rewards", {})
	check(int(rewards.get("junzi", 0)) > 0, "首通发军资(%d)" % int(rewards.get("junzi", 0)))
	check(SaveState.junzi() == j0 + int(rewards.get("junzi", 0)),
		"军资入库额 = 返回清单额(%d)" % int(rewards.get("junzi", 0)))
	# 奖励清单逐项与 rewards 一致(前端不重算的硬保证)
	var items: Array = r.get("items", [])
	check(not items.is_empty(), "返回奖励清单 items 非空")
	var item_junzi := 0
	var item_frag := {}
	var item_stars := 0
	for it in items:
		match str(it.get("kind", "")):
			"junzi": item_junzi += int(it.get("amount", 0))
			"fragment": item_frag[str(it.get("id", ""))] = int(it.get("amount", 0))
			"stars": item_stars += int(it.get("amount", 0))
	check(item_junzi == int(rewards.get("junzi", 0)), "items 军资合计 = rewards.junzi")
	check(item_stars == int(r.get("stars", 0)), "items 评星 = 结算评星")
	var rf: Dictionary = rewards.get("fragments", {})
	check(item_frag.size() == rf.size(), "items 碎片项数 = rewards.fragments 项数")
	for hid in rf:
		check(int(item_frag.get(str(hid), -1)) == int(rf[hid]), "items 碎片 %s 数量一致" % str(hid))
		check(SaveState.fragments_of(str(hid)) >= int(rf[hid]), "碎片入库:%s" % str(hid))
	# 重复通关
	var j1 := SaveState.junzi()
	var r2: Dictionary = RewardSettle.settle("campaign",
		{"victory": true, "no_casualty": true, "lord_hp_ratio": 0.9})
	check(not bool(r2.get("first", true)), "二次通关判为重复")
	check(int(r2.get("rewards", {}).get("junzi", 0)) < int(rewards.get("junzi", 1)),
		"重复奖励小于首通(%d < %d)" % [int(r2.get("rewards", {}).get("junzi", 0)), int(rewards.get("junzi", 0))])
	check(SaveState.junzi() == j1 + int(r2.get("rewards", {}).get("junzi", 0)), "重复奖励入账")
	# 评星取历史最高:第二次差评不降星
	var r3: Dictionary = RewardSettle.settle("campaign",
		{"victory": true, "no_casualty": false, "lord_hp_ratio": 0.1})
	check(int(r3.get("stars", 0)) == 1, "有阵亡 → 本次 ★1")
	check(CampaignSave.stars_of("1-1") == 3, "存档评星取历史最高(仍 ★3)")

# ---------------------------------------------------------------- 2. 闯关失败

func _test_campaign_failure() -> void:
	_fresh()
	RunState.mode = &"campaign"
	RunState.context = {"stage_id": "1-2", "wave_total": 1}
	var j0 := SaveState.junzi()
	var fr0 := SaveState.fragments_total()
	var r: Dictionary = RewardSettle.settle("campaign",
		{"victory": false, "no_casualty": false, "lord_hp_ratio": 0.0})
	check(bool(r.get("ok", false)) and not bool(r.get("victory", true)), "闯关失败结算 ok 但 victory=false")
	check(int(r.get("rewards", {}).get("junzi", -1)) == 0, "失败不发军资")
	check((r.get("items", []) as Array).is_empty(), "失败奖励清单为空")
	check(SaveState.junzi() == j0 and SaveState.fragments_total() == fr0, "失败不改钱包")
	check(not bool(CampaignSave.stage_state("1-2").get("cleared", true)), "失败不记通关")

# ---------------------------------------------------------------- 3. 塔结算

func _test_tower_settle() -> void:
	_fresh()
	RunState.reset(7777)
	RunState.mode = &"tower"
	RunState.context = {"floor_start": 1, "endless": true}
	var tc: Dictionary = DataDB.economy.settle.tower_floor
	var j0 := SaveState.junzi()
	# 通过 5 层(无 Boss 层)
	var r: Dictionary = RewardSettle.settle("tower",
		{"floors_cleared": 5, "died": false, "retreat": false, "kills": 60})
	check(bool(r.get("ok", false)), "塔结算 ok")
	check(int(r.get("floors", 0)) == 5, "返回通过层数 5")
	var want := 0.0
	for f in range(1, 6):
		want += float(tc.junzi.base) + float(tc.junzi.per_floor) * float(f)
	check(_close(float(SaveState.junzi() - j0), want),
		"塔 5 层军资 = Σ(base+per_floor×n) = %d(实际 %d)" % [int(want), SaveState.junzi() - j0])
	check(TowerSave.highest_floor() == 6, "通过 5 层 → 最高层记 6(下一层待爬)")
	# Boss 层 ×boss_mult:清到第 8 层
	_fresh()
	j0 = SaveState.junzi()
	var r8: Dictionary = RewardSettle.settle("tower",
		{"floors_cleared": 8, "died": false, "retreat": false, "kills": 100})
	var want8 := 0.0
	for f in range(1, 9):
		var g := float(tc.junzi.base) + float(tc.junzi.per_floor) * float(f)
		if DataDB.tower_is_boss_floor(f):
			g *= float(tc.boss_mult)
		want8 += g
	check(_close(float(SaveState.junzi() - j0), want8),
		"塔 8 层含 Boss 层 ×%.1f 倍(%d)" % [float(tc.boss_mult), int(want8)])
	# 阵亡折算 0.5
	_fresh()
	j0 = SaveState.junzi()
	var rd: Dictionary = RewardSettle.settle("tower",
		{"floors_cleared": 4, "died": true, "retreat": false, "kills": 30})
	var wantd := 0.0
	for f in range(1, 5):
		wantd += float(tc.junzi.base) + float(tc.junzi.per_floor) * float(f)
	wantd *= float(DataDB.economy.settle.death_mult)
	check(_close(float(SaveState.junzi() - j0), wantd),
		"阵亡按 death_mult=%.1f 折算(%d)" % [float(DataDB.economy.settle.death_mult), int(wantd)])
	check(str(rd.get("reason", "")) != "", "阵亡结算带折算说明")
	check(not bool(rd.get("victory", true)), "阵亡不算胜利")
	# 撤退折算 1.0
	_fresh()
	j0 = SaveState.junzi()
	var rr: Dictionary = RewardSettle.settle("tower",
		{"floors_cleared": 3, "died": false, "retreat": true, "kills": 20})
	var wantr := 0.0
	for f in range(1, 4):
		wantr += float(tc.junzi.base) + float(tc.junzi.per_floor) * float(f)
	wantr *= float(DataDB.economy.settle.retreat_mult)
	check(_close(float(SaveState.junzi() - j0), wantr), "撤退按 retreat_mult 结算(%d)" % int(wantr))
	check(str(rr.get("reason", "")) != "", "撤退结算带说明")
	# 一层未过:零奖励
	_fresh()
	j0 = SaveState.junzi()
	var rz: Dictionary = RewardSettle.settle("tower",
		{"floors_cleared": 0, "died": true, "retreat": false, "kills": 3})
	check(int(rz.get("rewards", {}).get("junzi", -1)) == 0 and SaveState.junzi() == j0,
		"一层未过 → 零奖励")
	# 最高层只增不减:低层结算不回退
	_fresh()
	RewardSettle.settle("tower", {"floors_cleared": 12, "died": false, "retreat": false, "kills": 0})
	var hi := TowerSave.highest_floor()
	RewardSettle.settle("tower", {"floors_cleared": 2, "died": true, "retreat": false, "kills": 0})
	check(TowerSave.highest_floor() == hi, "低层结算不回退最高层(%d)" % hi)

# ---------------------------------------------------------------- 4. 局内军资不入库(硬约束)

func _test_currency_not_banked() -> void:
	_fresh()
	RunState.reset(1234)
	RunState.mode = &"tower"
	RunState.context = {"floor_start": 1, "endless": true}
	RunState.add_gold(999)          # 塔内商店货币:故意留一大笔不花
	var before := SaveState.junzi()
	var r: Dictionary = RewardSettle.settle("tower",
		{"floors_cleared": 2, "died": false, "retreat": false, "kills": 10})
	var gained := SaveState.junzi() - before
	check(gained == int(r.get("rewards", {}).get("junzi", -1)),
		"入库额恰等于结算清单额,不含 RunState.gold(留 %d 只入库 %d)" % [RunState.gold, gained])
	check(gained < 999, "局内军资 999 未混入入库(02 §8.4 防留钱双赚)")
	# 闯关同理
	_fresh()
	RunState.reset(1)
	RunState.mode = &"campaign"
	RunState.context = {"stage_id": "1-3", "wave_total": 2}
	RunState.add_gold(500)
	var b2 := SaveState.junzi()
	var r2: Dictionary = RewardSettle.settle("campaign",
		{"victory": true, "no_casualty": true, "lord_hp_ratio": 1.0})
	check(SaveState.junzi() - b2 == int(r2.get("rewards", {}).get("junzi", -1)),
		"闯关入库额也排除局内军资")

# ---------------------------------------------------------------- 5. 临时武将不入 roster

func _test_roster_untouched() -> void:
	_fresh()
	RunState.reset(555)
	RunState.mode = &"tower"
	RunState.context = {"floor_start": 1, "endless": true}
	var roster_before := (SaveState.data.get("roster", {}) as Dictionary).duplicate(true)
	RunState.add_team_member("zhaoyun")     # 模拟塔内三选一临时入队
	RunState.add_team_member("lvbu")
	var team_size := RunState.team.size()
	RewardSettle.settle("tower", {"floors_cleared": 3, "died": true, "retreat": false, "kills": 40})
	var roster_after: Dictionary = SaveState.data.get("roster", {})
	check(team_size > 3, "局内队伍确实多了临时武将(%d 人)" % team_size)
	check(JSON.stringify(roster_before) == JSON.stringify(roster_after),
		"塔内临时武将不入 roster(存档名册一字未动)")
	check(SaveState.validate(SaveState.data).is_empty(), "结算后存档通过校验")

# ---------------------------------------------------------------- 6. 坏输入

func _test_bad_inputs() -> void:
	_fresh()
	var a: Dictionary = RewardSettle.settle("tower_typo", {})
	check(not bool(a.get("ok", true)) and str(a.get("reason", "")) != "", "未知模式 → ok=false + 原因")
	RunState.mode = &"campaign"
	RunState.context = {}
	var b: Dictionary = RewardSettle.settle("campaign", {"victory": true})
	check(not bool(b.get("ok", true)), "缺 stage_id 的闯关结算 → 拒绝")
	var c: Dictionary = RewardSettle.settle("campaign", {"victory": true, "stage_id": "9-9"})
	check(not bool(c.get("ok", true)), "不存在的关卡 → 拒绝")
	var d: Dictionary = RewardSettle.settle("tower", {"floors_cleared": -5, "died": false})
	check(bool(d.get("ok", false)) and int(d.get("floors", -1)) == 0, "负层按 0 处理不写脏档")
	check(TowerSave.highest_floor() >= 0, "坏输入后最高层仍非负")


# ---------------------------------------------------------------- 6.5 战斗层接线(端到端)

## 真战斗场景 → WaveDirector._settle → RewardSettle,验证「战斗层只交战场事实、
## 结算全走单一管道」。单测直接调 settle_tower 查不出接线 bug(如撤退被当成阵亡),
## 必须过一遍真实场景节点。
const BATTLE_SCENE := "res://scenes/battle.tscn"

func _test_battle_wiring() -> void:
	# --- 塔:主动撤退按 retreat_mult 入库(不得按 death_mult 折算) ---
	_fresh()
	RunState.reset(31415)
	SceneRouter.prepare_tower()          # 主城塔入口口径:mode=tower + endless
	check(RunState.mode == &"tower" and bool(RunState.context.get("endless", false)),
		"接线前置:塔入口进入无尽模式")
	var b1: Node = (load(BATTLE_SCENE) as PackedScene).instantiate()
	_st.root.add_child(b1)
	var d1 = b1.get_node("WaveDirector")
	d1.wave_idx = 5
	d1._floors_cleared = 5               # 模拟已打到第 6 层
	var j0 := SaveState.junzi()
	d1.retreat()
	check(d1.state == d1.State.ENDED, "撤退 → 战斗结束(ENDED)")
	var gained := SaveState.junzi() - j0
	var cfg: Dictionary = DataDB.economy.settle
	var tf: Dictionary = cfg.tower_floor
	var want_retreat := 0.0
	for f in range(1, 6):
		var g := float(tf.junzi.base) + float(tf.junzi.per_floor) * float(f)
		if DataDB.tower_is_boss_floor(f):
			g *= float(tf.boss_mult)
		want_retreat += g
	want_retreat *= float(cfg.retreat_mult)
	check(gained == int(round(want_retreat)),
		"接线:撤退经真实战斗层按 retreat_mult 入库(%d,若按 death_mult 会是 %d)" % [
			gained, int(round(want_retreat * 0.5))])
	_st.paused = false
	b1.free()

	# --- 塔:主公阵亡帧按 death_mult 入库 ---
	_fresh()
	RunState.reset(2718)
	SceneRouter.prepare_tower()
	var b2: Node = (load(BATTLE_SCENE) as PackedScene).instantiate()
	_st.root.add_child(b2)
	var d2 = b2.get_node("WaveDirector")
	d2.wave_idx = 4
	d2._floors_cleared = 3
	var j1 := SaveState.junzi()
	d2._on_lord_died()
	await _st.process_frame
	await _st.create_timer(1.6, true).timeout      # 等褪色演出 1.2s 后弹结算
	var gained2 := SaveState.junzi() - j1
	var want_death := 0.0
	for f in range(1, 4):
		var g2 := float(tf.junzi.base) + float(tf.junzi.per_floor) * float(f)
		want_death += g2
	want_death *= float(cfg.death_mult)
	check(gained2 == int(round(want_death)),
		"接线:主公阵亡经真实战斗层按 death_mult 入库(%d)" % gained2)
	_st.paused = false
	b2.free()

	# --- 闯关:胜利经真实战斗层落袋,失败不落袋 ---
	_fresh()
	RunState.reset(900)
	RunState.mode = &"campaign"
	RunState.context = {"stage_id": "1-1", "wave_total": 1}
	var b3: Node = (load(BATTLE_SCENE) as PackedScene).instantiate()
	_st.root.add_child(b3)
	var d3 = b3.get_node("WaveDirector")
	var j2 := SaveState.junzi()
	d3._show_result(true)
	await _st.process_frame
	var fc: Dictionary = DataDB.stage_by_id("1-1").first_clear
	check(SaveState.junzi() - j2 == int(fc.get("junzi", -1)),
		"接线:闯关胜利经真实战斗层发首通奖励(%d)" % int(fc.get("junzi", 0)))
	var res = d3.modal
	check(res != null and str(res._title.text).replace(" ", "") == "桃园功成", "接线:结算页已弹出")
	check(res != null and res._reward_box.get_child_count() > 0,
		"接线:结算页奖励清单已由 settle 结果填充(前端不重算)")
	_st.paused = false
	b3.free()

# ---------------------------------------------------------------- 7. 结算页同源

func _test_result_page() -> void:
	_fresh()
	RunState.reset(9001)
	RunState.mode = &"campaign"
	RunState.context = {"stage_id": "1-1", "wave_total": 1}
	var settle: Dictionary = RewardSettle.settle("campaign",
		{"victory": true, "no_casualty": true, "lord_hp_ratio": 1.0})
	var res: Node = (load("res://scenes/ui/result.tscn") as PackedScene).instantiate()
	_st.root.add_child(res)
	await _st.process_frame
	res.open(true, RunState.dump(), settle)
	await _st.process_frame
	var lines: Array = []
	for c in res._reward_box.get_children():
		for l in c.find_children("*", "Label", true, false):
			lines.append(str(l.text))
	check(not lines.is_empty(), "结算页渲染出奖励清单行(%d 行)" % lines.size())
	var joined := " ".join(PackedStringArray(lines))
	var items: Array = settle.get("items", [])
	check(lines.size() >= items.size(),
		"奖励清单行数覆盖全部奖励项(%d 行 / %d 项)" % [lines.size(), items.size()])
	for it in items:
		var amt := int(it.get("amount", 0))
		if str(it.get("kind", "")) == "junzi":
			check(joined.contains("+%d" % amt), "军资项按 settle 数值渲染 +%d" % amt)
		elif str(it.get("kind", "")) == "fragment":
			check(joined.contains(str(it.get("name", ""))), "碎片项按 settle 名称渲染")
		elif str(it.get("kind", "")) == "stars":
			check(joined.contains("★".repeat(maxi(0, amt))), "评星按 settle 星数渲染")
	check(str(res._title.text).replace(" ", "") == "桃园功成", "胜利标题")
	check(str(res._again_btn.text) != "" and str(res._exit_btn.text) != "", "按钮组就位")
	# 无奖励时给出明确文案,不显示空白区块
	res.open(false, RunState.dump(), {"ok": true, "mode": "campaign", "items": [], "rewards": {}})
	await _st.process_frame
	check(str(res._reward_head.text) != "" and res._reward_box.get_child_count() == 0,
		"无奖励 → 显示「本局无奖励」且不残留旧行")
	res.queue_free()
	await _st.process_frame
