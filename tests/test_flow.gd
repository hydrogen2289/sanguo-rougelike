extends "res://tests/test_base.gd"
## test_flow(M3 填实,02 §9 第 4 条):
## 波次状态机全部迁移路径(含第 8 波「杀华雄才结束」);
## 三选一/事件/商店可进可选可出;主公死 → 失败结算;重开状态复位。
## 缺陷回归(M6 修复批次):W8 计时重复触发不假胜利(P1-1)/ W7 计时退场防修过头;
## 武将全局槽位表 formation_index 互异 + HUD 槽位唯一(P1-2)与 freed 组件刷新无报错;
## 远程普攻命中效果移到弹道真正命中(P2-②);暂停中增益计时器不偷跑(P2-①);
## 战斗 ENDED 后暂停入口无效化(P2-④)。上述含帧推进断言,_run 为协程(test_base.run await 透传)。
## 依赖 run_all.gd 先手动注册 autoload(RunState/DataDB/EventBus/SceneRouter/Sfx);
## 场景级同步驱动:直接调 WaveDirector 内部迁移方法与弹窗公开接口。

const BATTLE_SCENE := "res://scenes/battle.tscn"

var _st: SceneTree

func _run() -> void:
	_st = Engine.get_main_loop() as SceneTree
	DataDB.load_all()
	RunState.reset(20261104)
	# --- 开局:主菜单链路由 SceneRouter 承担(此处验证 RunState 复位口径) ---
	check(RunState.team.size() == 3 and RunState.gold == 0 and RunState.wave_idx == 0, "开局:三人组/零军资/W0")
	var battle = (load(BATTLE_SCENE) as PackedScene).instantiate()
	_st.root.add_child(battle)
	var d = battle.get_node("WaveDirector")
	check(d.state == d.State.PRELUDE and d.wave_idx == 1, "battle 就绪 → PRELUDE W1")

	# --- W1:结束 → 波间队列 [triselect] → 三选一进/选/出 ---
	d._finish_wave(true)
	# 队列语义:队首项弹出即开弹窗,after_queue 只剩未处理项
	check(d.state == d.State.INTERMISSION and d.after_queue.is_empty(), "W1 后队列 [triselect] 已弹窗")
	check(_st.paused, "弹窗期间战斗暂停(process_mode 区分)")
	var ts = _modal("triselect")
	check(ts != null and ts._cards.size() == 3, "三选一弹 3 卡")
	var kinds: Array = []
	for c in ts._cards:
		kinds.append(str(c.kind))
	check(kinds.has("upgrade"), "保底 1 张强化卡")
	var pre_upg: int = RunState.upgrades.size()
	var pre_relic: int = RunState.relics.size()
	var pre_team: int = RunState.team.size()
	ts.pick(0)   # 卡 1 恒为强化
	check(RunState.upgrades.size() == pre_upg + 1, "强化卡选定即生效")
	check(RunState.relics.size() == pre_relic and RunState.team.size() == pre_team, "其余池不受扰动")
	check(_modal("triselect") == null and not _st.paused, "选卡后关闭弹窗并解除暂停")
	check(d.wave_idx == 2 and d.state == d.State.PRELUDE, "队列清空 → 自动进 W2 PRELUDE")

	# --- W2:三选一 → 事件(鞭打督邮)可进可选可出 ---
	d._finish_wave(true)
	check(d.after_queue == ["event_biandaduyou"], "W2 后队列剩事件(三选一已弹,01 §6)")
	_modal("triselect").pick(1)
	var ev = _modal("event_popup")
	check(ev != null, "事件弹窗可进")
	var g0: int = RunState.gold
	check(ev.option_enabled("b"), "事件 B 可选")
	ev.choose("b")
	check(RunState.gold == g0 + 15, "鞭打督邮 B:+15 军资")
	check(d.wave_idx == 3, "W2 处理完自动进 W3")

	# --- W3:仅三选一 ---
	d._finish_wave(true)
	check(d.after_queue.is_empty(), "W3 后队列仅 triselect(已弹窗)")
	_modal("triselect").pick(0)

	# --- W4:三选一 → 事件(三让徐州)→ 商店 ---
	d._finish_wave(true)
	check(d.after_queue == ["event_sanrangxuzhou", "shop"], "W4 后队列 [事件/商店](三选一已弹,01 §6)")
	_modal("triselect").pick(2)
	var ev4 = _modal("event_popup")
	check(ev4 != null and ev4._event.get("id", "") == "sanrangxuzhou", "三让徐州事件弹窗")
	ev4.choose("a")
	check(float(RunState.mods_flat.get("maxhp", 0.0)) >= 10.0, "三让徐州 A:全队 HP 上限 +10(本场)")
	var shop = _modal("shop")
	check(shop != null and shop._shelf.size() == 6, "商店可进,6 格货架")
	var heal_n := 0
	var has_zero_price := false
	for it in shop._shelf:
		if it.is_empty():
			has_zero_price = true
		if str(it.get("kind", "")) == "heal":
			heal_n += 1
	check(heal_n == 1 and not has_zero_price, "货架含军医诊治且无空格")
	check(shop._slot_buttons[0].disabled == (RunState.gold < int(shop._shelf[0].price)), "余额不足置灰")
	shop.do_checkout()
	check(_modal("shop") == null and d.wave_idx == 5, "出征 → 离店进 W5")

	# --- W5/W6:吕布事件(军资不足不可选 → 补足后可选入队)---
	d._finish_wave(true)
	_modal("triselect").pick(0)
	d._finish_wave(true)
	check(d.after_queue == ["event_hulaoguan", "shop"], "W6 后队列剩虎牢关事件与商店")
	_modal("triselect").pick(0)
	var ev6 = _modal("event_popup")
	check(ev6 != null and ev6._event.get("id", "") == "hulaoguan", "虎牢关·飞将来投弹窗")
	RunState.gold = 0
	check(not ev6.option_enabled("a"), "军资不足时招募吕布不可选(01 §9)")
	RunState.add_gold(100)
	check(ev6.option_enabled("a"), "军资足够且队伍未满 → 可选")
	var team_before: int = RunState.team.size()
	ev6.choose("a")
	check(RunState.team.size() == team_before + 1, "吕布入队(即刻 +1)")
	check(RunState.member("lvbu").size() > 0, "队伍含吕布")
	check(RunState.gold == 40, "招募花 60 军资")
	_modal("shop").do_checkout()
	check(d.wave_idx == 7, "W6 处理完进 W7")

	# --- W7 → W8:胜利结算 ---
	d._finish_wave(true)
	_modal("triselect").pick(0)
	check(d.wave_idx == 8 and d.wave_data.get("idx", 0) == 8, "进入第 8 波")
	d._finish_wave(true)   # 冒烟口径:强制结束(F2 语义)→ after [victory]
	var res = _modal("result")
	check(res != null and res.victory, "第 8 波结束 → 胜利结算「桃园功成」")
	check(_st.paused and d.state == d.State.ENDED, "结算期间暂停 + 状态 ENDED")
	var dump: Dictionary = RunState.dump()
	check(dump.has_all(["run_seed", "wave_idx", "kills", "gold", "run_time", "team", "relics"]), "dump() 统计字段齐全(02 §6)")
	battle.free()
	_st.paused = false

	# --- 失败路径:主公死 → 失败结算(独立 battle 实例)---
	var battle2 = (load(BATTLE_SCENE) as PackedScene).instantiate()
	_st.root.add_child(battle2)
	var d2 = battle2.get_node("WaveDirector")
	EventBus.lord_died.emit()
	check(d2.state == d2.State.ENDED and _st.paused, "主公死 → 冻结战斗")
	# 1.2s 演出延迟走 SceneTreeTimer(process_always);无帧测试环境直调同一入口模拟到期
	d2._show_defeat_result_if_ended()
	var res2 = _modal("result")
	check(res2 != null and not res2.victory, "失败结算「大意失荆州」")
	battle2.free()
	_st.paused = false

	# --- 第 8 波「杀华雄才结束」:计时到 Boss 未死 → 普通敌退场、战斗继续(01 §3)---
	var battle3 = (load(BATTLE_SCENE) as PackedScene).instantiate()
	_st.root.add_child(battle3)
	var d3 = battle3.get_node("WaveDirector")
	d3._jump_wave(8)
	check(d3.wave_idx == 8 and d3.state == d3.State.PRELUDE, "F5 直跳 W8")
	var boss = d3.spawner.spawn_enemy("huaxiong", 30.0, 10.0)
	var zu = d3.spawner.spawn_enemy("huangjin_zu", 30.0, 10.0)
	check(is_instance_valid(boss) and boss.get("boss"), "Boss 走 boss_huaxiong.tscn(spawner 按 ai 路由)")
	check(boss.hp > 1000.0, "华雄 HP 读表(1500,非波次基础 HP)")
	_enter_battle_state(d3)
	d3._time_up()
	check(d3.state == d3.State.BATTLE, "Boss 未死 → 战斗继续")
	check(is_instance_valid(boss) and not boss.dead, "华雄在场(免疫计时退场)")
	check(zu.dead, "普通敌自动退场不给军资(01 §6)")
	# P1-1 回归:模拟下一帧再次触发(修复前此帧落入兜底 → 全体退场含 Boss + 假胜利)
	d3._time_up()
	check(d3.state == d3.State.BATTLE, "W8 计时重复触发:仍 BATTLE 不结算")
	check(is_instance_valid(boss) and not boss.dead and d3._boss_alive(), "W8 重复触发:华雄仍不退场")
	check(_modal("result") == null, "W8 计时重复触发:不弹胜利结算")

	# --- M5:华雄运行时免疫 / 二阶段召唤 / 空格主公技(数据口径在 test_formulas)---
	check(is_instance_valid(boss) and boss.stun_immune(), "运行时:华雄免疫眩晕")
	check(boss.knockback_resist() >= 1.0, "运行时:华雄免疫击退(抗性 100%)")
	var kb_pos: Vector3 = boss.global_position
	boss.apply_knockback(Vector3(1.0, 0.0, 0.0), 2.0)
	check(boss.global_position.distance_to(kb_pos) < 0.01, "击退冲量对华雄无效")
	boss.take_damage(boss.max_hp * 0.6, null)          # 压到 40%
	boss._check_phase()
	check(boss.phase2, "HP < 50% → 进入二阶段(狂化)")
	check(absf(boss.move_speed - 2.6 * 1.25) < 0.01, "二阶段移速 ×1.25")
	var n_before: int = d3._alive_enemies()
	boss._summon()
	check(d3._alive_enemies() == n_before + 4, "二阶段召唤西凉亲卫×4")
	var lord3 = battle3.get_node("Units/PlayerLord")
	check(lord3 != null and lord3.get("skill_comp") != null, "主公技能组件在位")
	lord3.skill_comp.cd_left = 0.0
	var hud3 = battle3.get_node("HUDLayer/HUD")
	hud3._cast_lord_skill()
	check(lord3.skill_comp.cd_left > 0.0, "空格链路:主公「仁德之泽」已施放并进入 CD")

	# --- 击杀华雄 → 立即胜利(增援/召唤物仍在场也算,01 §3)---
	boss.take_damage(99999.0, null)
	check(boss.dead, "华雄被击杀")
	check(d3.state == d3.State.ENDED, "杀华雄 → 波次立即结束(不等清场)")
	var res3 = _modal("result")
	check(res3 != null and res3.victory, "杀华雄后 → 胜利结算「桃园功成」")
	battle3.free()
	_st.paused = false

	# --- 重开状态复位(SceneRouter.restart_battle 的 RunState 部分口径)---
	RunState.reset(999)
	check(RunState.gold == 0 and RunState.team.size() == 3 and RunState.relics.is_empty()
		and RunState.upgrades.is_empty() and RunState.wave_idx == 0 and RunState.kills == 0
		and RunState.run_time < 0.2, "重开状态复位(军资/队伍/遗物/强化/波次/击杀/计时)")
	check(RunState.rng.seed == 999, "run_seed 固定可复现")
	# 复位后再开一局:三选一池不残留旧遗物
	var ts_cards: Array = TriSelectPool.offer(RunState.rng, 1)
	check(ts_cards.size() == 3, "重开后三选一可正常生成")

	# --- P1-1 防修过头:普通波(W7)计时到仍正常退场结束;重复触发幂等 ---
	var battle4 = (load(BATTLE_SCENE) as PackedScene).instantiate()
	_st.root.add_child(battle4)
	var d4 = battle4.get_node("WaveDirector")
	d4._jump_wave(7)
	check(d4.wave_idx == 7 and d4.state == d4.State.PRELUDE, "F5 直跳 W7")
	var e7 = d4.spawner.spawn_enemy("huangjin_zu", 30.0, 10.0)
	_enter_battle_state(d4)
	d4._time_up()
	check(d4.state == d4.State.INTERMISSION, "W7 计时到 → 正常退场结束波次(防修过头)")
	check(is_instance_valid(e7) and e7.dead, "W7 普通敌计时退场(01 §6)")
	d4._time_up()
	check(d4.state == d4.State.INTERMISSION, "W7 重复触发幂等:不二次结算")
	var ts_count := 0
	for m in _st.get_nodes_in_group("modal"):
		if is_instance_valid(m) and m.visible and m.get_script() != null \
				and String(m.get_script().resource_path).ends_with("triselect.gd"):
			ts_count += 1
	check(ts_count == 1, "W7 三选一恰弹一次")
	battle4.free()
	_st.paused = false

	# --- P1-2 回归①:F6 招满 7 人,formation_index 互异且 1~6 每槽恰一人 ---
	RunState.reset(888)
	var battle5 = (load(BATTLE_SCENE) as PackedScene).instantiate()
	_st.root.add_child(battle5)
	var d5 = battle5.get_node("WaveDirector")
	check(d5._hero_slots == {"guanyu": 0, "zhangfei": 1}, "重开后槽位表随 WaveDirector 干净重建(初始二人各占槽)")
	for hid in ["zhaoyun", "huatuo", "zhuge", "lvbu"]:
		check(RunState.add_team_member(hid), "%s 入队(F6 口径)" % hid)
	var idx5: Array = []
	for hid in ["guanyu", "zhangfei", "zhaoyun", "huatuo", "zhuge", "lvbu"]:
		var u5 := _hero_of(battle5, hid)
		check(u5 != null, "场上单位在位:%s" % hid)
		idx5.append(int(u5.formation_index))
	check(_is_permutation_0n(idx5, 6), "招满 6 武将 formation_index 恰为 0~5 各一(%s)" % str(idx5))
	check(_hud_slots_unique(battle5.get_node("HUDLayer/HUD"), 6), "HUD 槽 1~6 每槽恰一存活绑定")
	battle5.free()

	# --- P1-2 回归②:武将阵亡释放槽位,再招募取最小空闲槽,全员仍互异 ---
	RunState.reset(889)
	var battle6 = (load(BATTLE_SCENE) as PackedScene).instantiate()
	_st.root.add_child(battle6)
	var d6 = battle6.get_node("WaveDirector")
	for hid in ["zhaoyun", "huatuo", "zhuge"]:
		check(RunState.add_team_member(hid), "%s 入队(前置)" % hid)
	var hud6 = battle6.get_node("HUDLayer/HUD")
	var zy6 := _hero_of(battle6, "zhaoyun")
	var zy_slot: int = int(zy6.formation_index)
	check(zy_slot == 2, "赵云初始槽位 2(前置)")
	zy6._die()                       # 阵亡 → mark_casualty → team_changed → 槽位释放
	check(not bool(RunState.member("zhaoyun").alive), "赵云阵亡登记(不可复活口径)")
	check(not d6._hero_slots.has("zhaoyun"), "阵亡武将槽位已释放")
	zy6.free()                       # 退场动画结束 → 节点释放(其绑定暂留 _bound)
	hud6._refresh_skills()           # 修复前:freed 实例类型化赋值每帧 SCRIPT ERROR(hud.gd:528)
	check(hud6.skill_buttons[zy_slot].disabled, "freed 组件刷新:对应槽位按钮禁用且无报错")
	check(RunState.add_team_member("lvbu"), "赵云阵亡后再招募吕布")
	var lb6 := _hero_of(battle6, "lvbu")
	check(lb6 != null and int(lb6.formation_index) == zy_slot, "新招募取最小空闲槽(复用赵云释放的槽位)")
	var idx6: Array = []
	for u in battle6.get_node("Units/Heroes").get_children():
		idx6.append(int(u.formation_index))
	check(_all_distinct(idx6), "再招募后全员 formation_index 仍互异(%s)" % str(idx6))
	check(_hud_slots_unique(hud6, 5), "存活武将 5 人 → HUD 槽 1~5 各恰一唯一绑定")
	battle6.free()

	# --- P2-② 回归:远程普攻命中效果移到弹道真正命中(东风灼烧挂空/双重附加)---
	RunState.reset(890)
	var battle8 = (load(BATTLE_SCENE) as PackedScene).instantiate()
	_st.root.add_child(battle8)
	var d8 = battle8.get_node("WaveDirector")
	check(RunState.add_team_member("zhuge"), "诸葛亮入队(远程口径)")
	var zg := _hero_of(battle8, "zhuge")
	check(zg != null and float(zg.atk_range) > 2.5, "诸葛亮攻距 > 2.5 → 走弹道(前置)")
	for hid in ["guanyu", "zhangfei"]:
		var ally := _hero_of(battle8, hid)
		if ally != null:
			ally.apply_stun(60.0)    # 测试装置:冻住近战队友,隔离普攻灼烧来源
	EventBus.eastwind_started.emit(10.0)   # 测试装置:借东风开启
	d8.state = d8.State.ENDED        # 测试装置:静态化状态机,波次推进不干扰命中时序
	# 测试装置注意:刚 spawn 即被眩晕的敌人,其物理服务器代理仍留在 spawn 原点(首次 move_and_slide 才同步);
	# 置位后须先等一帧物理同步,再出手,否则弹道会在射手位置误判命中(探针 _scratch/fixprobe_miss.gd 取证)
	# ① 出手不挂灼烧;弹道真正命中 → 恰一次(6 tick)
	var tgt = d8.spawner.spawn_enemy("huangjin_zu", 500.0, 10.0)
	tgt.global_position = zg.global_position + Vector3(3.0, 0.0, 0.0)
	tgt.apply_stun(60.0)             # 站桩吃箭,命中确定
	await _st.process_frame          # 等物理同步(见上注)
	await _st.process_frame
	zg.target = tgt
	zg._atk_cd = 0.0
	zg._try_attack()
	check(tgt.burn_ticks_left == 0, "远程出手瞬间不挂灼烧(修复前此处已挂,可能挂空)")
	zg._atk_cd = 9999.0              # 关掉诸葛亮后续自动普攻,隔离计数
	var hit_deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < hit_deadline and tgt.burn_ticks_left == 0:
		await _st.process_frame      # 等弹道飞行(10m/s × 3m ≈ 0.3s)
	check(tgt.burn_ticks_left == UnitBase.burn_tick_count(3.0, 0.5), "弹道真正命中 → 灼烧恰一次(6 tick)")
	# ② 目标走位躲开 → 弹道落空 → 无灼烧挂载
	var tgt2 = d8.spawner.spawn_enemy("huangjin_zu", 500.0, 10.0)
	tgt2.global_position = zg.global_position + Vector3(-3.0, 0.0, 0.0)
	tgt2.apply_stun(60.0)
	await _st.process_frame          # 等物理同步(见上注)
	await _st.process_frame
	zg.target = tgt2
	zg._atk_cd = 0.0
	zg._try_attack()
	check(tgt2.burn_ticks_left == 0, "远程出手瞬间不挂灼烧(落空路径,修复前此处已挂)")
	tgt2.global_position = zg.global_position + Vector3(0.0, 0.0, 12.0)   # 瞬移躲开弹道(眩晕中不动)
	var miss_deadline := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < miss_deadline:
		await _st.process_frame
	check(tgt2.burn_ticks_left == 0, "弹道落空 → 无灼烧挂载(修复前出手已挂)")
	# ③ 目标在弹道飞行中死亡 → 无灼烧挂载且无报错
	var tgt3 = d8.spawner.spawn_enemy("huangjin_zu", 500.0, 10.0)
	tgt3.global_position = zg.global_position + Vector3(0.0, 0.0, -3.0)
	await _st.process_frame          # 等物理同步(见上注)
	await _st.process_frame
	zg.target = tgt3
	zg._atk_cd = 0.0
	zg._try_attack()
	tgt3.take_damage(999999.0, null)     # 出手后立刻死亡
	check(tgt3.dead and tgt3.burn_ticks_left == 0, "目标飞行中死亡:无灼烧挂载(修复前出手已挂)")
	var fly_deadline := Time.get_ticks_msec() + 800
	while Time.get_ticks_msec() < fly_deadline:
		await _st.process_frame      # 让弹道飞过尸体:命中回调对已亡射手/目标均不报错
	battle8.free()
	_st.paused = false

	# --- P2-① 回归:暂停中零散计时器偷跑(张飞减伤/赵云无敌/吕布三段后续段)---
	RunState.reset(891)
	var battle7 = (load(BATTLE_SCENE) as PackedScene).instantiate()
	_st.root.add_child(battle7)
	var d7 = battle7.get_node("WaveDirector")
	var zf := _hero_of(battle7, "zhangfei")
	check(RunState.add_team_member("zhaoyun"), "赵云入队(前置)")
	var zy7 := _hero_of(battle7, "zhaoyun")
	var dummy = d7.spawner.spawn_enemy("huangjin_zu", 500.0, 10.0)
	dummy.global_position = zy7.global_position + Vector3(2.5, 0.0, 0.0)   # 冲锋目标(6m 内)
	check(RunState.add_team_member("lvbu"), "吕布入队(前置)")
	var lb7 := _hero_of(battle7, "lvbu")
	zf.skill_comp._cast_nova(1.0)
	check(float(zf.dr_percent) > 0.0, "张飞 2s 减伤已生效(前置)")
	zy7.skill_comp._cast_dash()
	check(bool(zy7.invincible), "赵云 0.8s 无敌已生效(前置)")
	lb7.skill_comp._cast_triple_nova(1.0)
	check(lb7.skill_comp._pulse_queue.size() == 2, "吕布三段后续段已入队(前置)")
	d7.state = d7.State.ENDED        # 测试装置:静态化状态机(波次推进不干扰)
	_st.paused = true                # 模拟波间弹窗暂停
	var pause_deadline := Time.get_ticks_msec() + 2600
	while Time.get_ticks_msec() < pause_deadline:
		await _st.process_frame
	check(float(zf.dr_percent) > 0.0, "暂停 2.6s > 2s:张飞减伤计时不流逝(P2-①)")
	check(bool(zy7.invincible), "暂停 2.6s > 0.8s:赵云无敌计时不流逝(P2-①)")
	check(lb7.skill_comp._pulse_queue.size() == 2, "暂停 2.6s > 0.5s:吕布后续段不推进(P2-①)")
	_st.paused = false
	var resume_deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < resume_deadline \
			and (float(zf.dr_percent) > 0.0 or not lb7.skill_comp._pulse_queue.is_empty()):
		await _st.process_frame
	check(float(zf.dr_percent) == 0.0 and lb7.skill_comp._pulse_queue.is_empty(), "解除暂停后减伤到期、后续段正常打完")
	battle7.free()
	_st.paused = false

	# --- P2-④ 回归:战斗 ENDED 后暂停入口无效化(主公死后 1.2s 演出窗口)---
	RunState.reset(892)
	var battle9 = (load(BATTLE_SCENE) as PackedScene).instantiate()
	_st.root.add_child(battle9)
	var d9 = battle9.get_node("WaveDirector")
	d9._ensure_ui()
	var pz = _st.get_first_node_in_group("pause_menu")
	check(pz != null, "pause_menu 就位(前置)")
	d9.state = d9.State.ENDED        # 模拟主公阵亡后的褪色演出窗口(ENDED、结算未弹)
	pz.open()
	check(not pz.visible and not _st.paused, "ENDED 后开暂停无效(P2-④)")
	d9.state = d9.State.BATTLE       # 防修过头:正常战斗仍可暂停
	pz.open()
	check(pz.visible and _st.paused, "BATTLE 中暂停仍可用")
	pz.close()
	check(not pz.visible and not _st.paused, "关闭暂停恢复")
	battle9.free()
	_st.paused = false

# ---------------------------------------------------------------- 测试装置

func _hero_of(battle: Node, hero_id: String) -> Node:
	var root := battle.get_node_or_null("Units/Heroes")
	if root == null:
		return null
	for u in root.get_children():
		if is_instance_valid(u) and str(u.unit_id) == hero_id:
			return u
	return null

func _all_distinct(arr: Array) -> bool:
	var seen: Dictionary = {}
	for v in arr:
		if seen.has(v):
			return false
		seen[v] = true
	return true

func _is_permutation_0n(arr: Array, n: int) -> bool:
	if arr.size() != n:
		return false
	var sorted: Array = arr.duplicate()
	sorted.sort()
	for i in n:
		if int(sorted[i]) != i:
			return false
	return true

## HUD 绑定唯一性:槽 1~expect_slots 每槽恰一「存活生效」绑定,且绑定组件两两互异
func _hud_slots_unique(hud: Node, expect_slots: int) -> bool:
	var per: Dictionary = {}
	var comps: Array = []
	for b in hud._bound:
		var c = b.comp
		if not is_instance_valid(c):
			continue
		if c.host == null or not is_instance_valid(c.host) or bool(c.host.dead):
			continue
		var s := int(b.slot)
		if per.has(s):
			return false
		per[s] = c
		comps.append(c)
	for s in range(1, expect_slots + 1):
		if not per.has(s):
			return false
	return _all_distinct(comps)

func _enter_battle_state(d: Node) -> void:
	d.state = d.State.BATTLE
	d.battle_t = 0.0

func _modal(kind: String) -> Node:
	# 按脚本路径匹配:queue_free 的同名旧弹窗在本帧内仍占名(add_child 会自动改名)
	for m in _st.get_nodes_in_group("modal"):
		if is_instance_valid(m) and m.visible and m.get_script() != null 				and String(m.get_script().resource_path).ends_with(kind + ".gd"):
			return m
	return null
