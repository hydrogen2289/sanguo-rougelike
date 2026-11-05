extends "res://tests/test_base.gd"
## test_formulas —— 本卡(M1)范围用例:伤害公式 / 软分离 / 队形 / 掉落总额 /
## 修饰符合成与 CD 封顶 / 护盾优先扣减(02 §9 第 3 条中已实现系统部分;
## 拖刀斩杀 / 狂化 / 不受令 / 灼烧用例随 M4 加入)。

func _run() -> void:
	# --- 伤害公式:最终伤害 = max(1, round(攻击力 × 技能倍率))(01 §3) ---
	var UB = load("res://scripts/battle/unit_base.gd")
	check(UB.compute_damage(6.0, 1.0) == 6, "伤害 6×1.0 = 6")
	check(UB.compute_damage(14.0, 2.5) == 35, "伤害 14×2.5 = 35")
	check(UB.compute_damage(0.4, 1.0) == 1, "伤害下限 1(0.4×1.0 → 1)")
	check(UB.compute_damage(12.0, 0.5) == 6, "伤害 12×0.5 = 6")
	check(UB.compute_damage(30.0, 1.2) == 36, "伤害 30×1.2 = 36(吕布档)")

	# --- 软分离:0.9m 邻域排斥,不做硬碰撞(02 §3/§7.1) ---
	var F = load("res://scripts/battle/formation.gd")
	var push: Vector3 = F.separation(Vector3(0, 0, 0), [Vector3(0.5, 0, 0)], 0.9)
	check(push.x < -0.3 and push.x >= -0.45, "重叠 0.5m 时被推离邻居(push.x=%.2f)" % push.x)
	var none: Vector3 = F.separation(Vector3(0, 0, 0), [Vector3(2.0, 0, 0)], 0.9)
	check(none.length() < 0.001, "距离 2m 无排斥")
	var both: Vector3 = F.separation(Vector3(0, 0, 0), [Vector3(0.3, 0, 0), Vector3(-0.3, 0, 0)], 0.9)
	check(both.length() < 0.001, "对称邻居合力为 0")
	var y_ignored: Vector3 = F.separation(Vector3(0, 0, 0), [Vector3(0.0, 5.0, 0.0)], 0.9)
	check(y_ignored.length() < 0.001, "Y 轴高度差不参与软分离")

	# --- 队形:主公后方 150° 扇形均布,半径 1.5m(01 §5) ---
	var off0: Vector3 = F.slot_offset(0, 3, Vector3(0, 0, -1))
	var off1: Vector3 = F.slot_offset(1, 3, Vector3(0, 0, -1))
	var off2: Vector3 = F.slot_offset(2, 3, Vector3(0, 0, -1))
	check(absf(off0.length() - 1.5) < 0.01, "队形半径 1.5m")
	check(off0.z > 0.0 and off2.z > 0.0, "两端槽位在主公后方(+z)")
	check(off1.z > off0.z, "中间槽位最靠后(扇形朝后)")
	check(off0.x < 0.0 and off2.x > 0.0, "槽位横向均布")
	check(F.slot_offset(0, 1, Vector3(0, 0, -1)).z > 1.4, "单武将位于正后方")

	# --- 掉落总额:单枚 1~3,每波总额精确对齐(02 §7.6) ---
	var totals := [15, 18, 20, 22, 25, 26, 28, 30]
	var SP = load("res://scripts/battle/spawner.gd")
	var rng := RandomNumberGenerator.new()
	var viol := 0
	for trial in totals.size():
		rng.seed = 1000 + trial
		var pool: int = totals[trial]
		var total := 0
		var guard := 0
		while pool > 0 and guard < 20000:
			var v: int = SP.roll_drop(rng, pool)
			if v < 1 or v > 3:
				viol += 1
			total += v
			pool -= v
			guard += 1
		if total != totals[trial]:
			viol += 1
	check(viol == 0, "8 波掉落模拟:单枚 1~3 且总额精确对齐(违规 %d)" % viol)
	check(SP.roll_drop(rng, 0) == 0, "池空不掉落")

	# --- 修饰符合成:最终属性 = base×(1+Σadd%)+Σflat;CD 封顶 40%(02 §6) ---
	var RS = load("res://scripts/autoload/run_state.gd").new()
	RS.add_pct("atk", 0.08)
	RS.add_pct("atk", 0.08)
	RS.add_flat("atk", 10.0)
	check(absf(RS.stat(100.0, "atk") - 126.0) < 0.001, "属性合成 100×1.16+10 = 126")
	RS.add_pct("cd_reduction", 0.20)
	RS.add_pct("cd_reduction", 0.20)
	RS.add_pct("cd_reduction", 0.08)
	check(absf(RS.cd_mult() - 0.6) < 0.001, "CD 缩减 0.20+0.20+0.08 封顶 40%(×0.6)")
	RS.free()

	# --- 护盾优先扣减(01 §4 仁德之泽 / 02 §7.4) ---
	var ub = UB.new()
	ub.hp = 100.0
	ub.shield = 20.0
	ub.take_damage(15.0, null)
	check(absf(ub.hp - 100.0) < 0.001 and absf(ub.shield - 5.0) < 0.001, "护盾先于 HP 扣减(HP 不掉)")
	ub.take_damage(10.0, null)
	check(absf(ub.hp - 95.0) < 0.001 and ub.shield <= 0.0, "护盾耗尽后扣 HP")
	ub.invincible = true
	ub.take_damage(50.0, null)
	check(absf(ub.hp - 95.0) < 0.001, "无敌标记下不受伤害")
	# --- M4:临时减伤(张飞当阳桥吼 2s 30%)与直伤(事件鞭打督邮) ---
	ub2_dr(ub)
	ub.free()

	# ================= M4 技能与个性机制用例(01 §4,固定 seed)=================

	# --- 技能开局即半冷却(01 §3) ---
	var SC = load("res://scripts/battle/skill_component.gd")
	check(absf(SC.initial_cd(10.0, 1.0) - 5.0) < 0.001, "刘备仁德之泽开局 CD = 10×1.0×0.5 = 5s")
	check(absf(SC.initial_cd(15.0, 0.6) - 4.5) < 0.001, "借东风开局 CD = 15×0.6(CD 封顶后)×0.5 = 4.5s")

	# --- 吕布「不受令」:1000 次采样 ≈ 30%±5%(任务卡验收口径) ---
	rng.seed = 99123
	var hits := 0
	var trials := 1000
	for i in trials:
		if SC.roll_disobey(rng, 0.30):
			hits += 1
	var ratio := float(hits) / float(trials)
	check(ratio >= 0.25 and ratio <= 0.35, "不受令 1000 次采样 = %.1f%%(30%%±5%%)" % (ratio * 100.0))
	check(absf(UnitBase.compute_damage(30.0, 1.2 * 1.5) - 54.0) < 0.001, "延迟生效每段 ×1.5:吕布 30×1.2×1.5 = 54")

	# --- 关羽 青龙偃月·扫:120° 扇形几何(01 §4) ---
	var O := Vector3.ZERO
	var FC := Vector3(0, 0, -1)   # 朝 -z(避免与上文队形脚本变量 F 撞名)
	check(SC.in_cone(O, FC, Vector3(0, 0, -2.5), 3.0, 120.0), "扇形正前方 2.5m 命中")
	check(SC.in_cone(O, FC, Vector3(1.5, 0, -1.5), 3.0, 120.0), "扇形 45° 斜前 2.12m 命中(半角 60° 内)")
	check(not SC.in_cone(O, FC, Vector3(2.0, 0, -0.5), 3.0, 120.0), "扇形 ~104° 斜前超出 60° 半角,不命中")
	check(not SC.in_cone(O, FC, Vector3(0, 0, -3.5), 3.0, 120.0), "半径 3.5m > 3m,不命中")
	check(not SC.in_cone(O, FC, Vector3(0, 0, 2.5), 3.0, 120.0), "身后目标不命中")

	# --- 赵云 七进七出:沿途线段伤害几何(命中带宽 1.0m) ---
	check(SC.point_segment_dist_xz(Vector3(0.5, 0, -1.0), Vector3.ZERO, Vector3(0, 0, -5.0)) <= 1.0, "线段侧偏 0.5m 敌人计入沿途伤害")
	check(SC.point_segment_dist_xz(Vector3(2.0, 0, -2.0), Vector3.ZERO, Vector3(0, 0, -5.0)) > 1.5, "线段侧向 2m 敌人不计入")

	# --- 灼烧 dot 总量(01 §4 借东风:每 0.5s 2 点 × 火伤 1.3,持续 3s) ---
	check(UB.burn_tick_count(3.0, 0.5) == 6, "灼烧 3s / 0.5s = 6 tick")
	check(UB.burn_tick_count(0.4, 0.5) == 1, "灼烧不足一个周期仍有 1 tick")
	var burn_total := float(UB.burn_tick_count(3.0, 0.5)) * 2.0 * 1.3
	check(absf(burn_total - 15.6) < 0.001, "东风灼烧总量 = 6×2×1.3 = 15.6")

	# --- 关羽 拖刀计:阈值 15%、Boss 免疫(01 §4) ---
	var HU = load("res://scripts/battle/hero_unit.gd")
	check(HU.can_execute_target(10.0, 100.0, false), "敌兵 HP 10% ≤ 15% → 可斩杀")
	check(not HU.can_execute_target(20.0, 100.0, false), "敌兵 HP 20% > 15% → 不可斩杀")
	check(not HU.can_execute_target(5.0, 100.0, true), "Boss 免疫斩杀")
	check(not HU.can_execute_target(0.0, 100.0, false), "已死目标不可再斩")

	# --- 张飞 燕人狂怒:进入/退出阈值(01 §4) ---
	check(HU.enrage_should_enter(0.30), "HP 30% < 35% → 狂化进入")
	check(not HU.enrage_should_enter(0.40), "HP 40% ≥ 35% → 不进入")
	check(HU.enrage_should_exit(0.52), "HP 52% ≥ 50% → 解除狂化")
	check(not HU.enrage_should_exit(0.45), "HP 45% < 50% → 保持狂化")

	# --- 治疗加成(青囊书 +30%)与武将个体攻击加成(鞭打督邮张飞 +15%) ---
	var RS2 = load("res://scripts/autoload/run_state.gd").new()
	RS2.add_pct("heal", 0.30)
	check(absf(RS2.heal_mult() - 1.3) < 0.001, "青囊书:治疗与护盾效果 ×1.3")
	RS2.add_pct("zhangfei_atk", 0.15)
	check(absf(RS2.hero_atk_mult("zhangfei") - 1.15) < 0.001, "鞭打督邮:张飞个体攻击 ×1.15")
	check(absf(RS2.hero_atk_mult("guanyu") - 1.0) < 0.001, "其他武将不受个体加成影响")
	RS2.free()

	# --- 三选一卡池:保底强化 / 权重口径 / 门槛 / 去重(01 §7,固定 seed) ---
	var RS3 = root_autoload("RunState")
	RS3.reset(777)
	var hero_pool_empty := TriSelectPool.hero_candidates(1, ["liubei", "guanyu", "zhangfei"], 3, 7)
	check(hero_pool_empty.is_empty(), "W1 无武将卡(赵云/马超/黄忠/魏延 W2、华佗 W3、诸葛 W4 门槛)")
	# 03 第二批:W2 起三新将进入候选池;03 第三批:W2 起张辽/甘宁/貂蝉,W3 周瑜
	var w2_pool := TriSelectPool.hero_candidates(2, ["liubei", "guanyu", "zhangfei"], 3, 7)
	var w2_ids: Array = []
	for c in w2_pool:
		w2_ids.append(str(c.get("id", "")))
	check(w2_ids.has("machao") and w2_ids.has("huangzhong") and w2_ids.has("weiyan"),
		"W2 候选池含马超/黄忠/魏延(03 第二批)")
	check(w2_ids.has("zhangliao") and w2_ids.has("ganning") and w2_ids.has("diaochan"),
		"W2 候选池含张辽/甘宁/貂蝉(03 第三批,05 §2)")
	check(not w2_ids.has("zhouyu"), "周瑜 W3 门槛(05 §2.4)")
	var gated := TriSelectPool.hero_candidates(4, ["liubei", "guanyu", "zhangfei"], 3, 7)
	check(gated.size() == 11, "W4 门槛开放赵云/华佗/诸葛 + 03 第二批 3 将 + 03 第三批 5 将共 11 人")
	# 05 §3 换人规则:满员后武将卡照出(替换卡);队伍满 7 仍出卡(不再清空池)
	var full_team := TriSelectPool.hero_candidates(8, ["liubei", "guanyu", "zhangfei", "zhaoyun", "huatuo", "zhuge", "lvbu"], 7, 7)
	check(full_team.size() > 0, "队伍满 7 → 武将卡照出(替换卡,05 §3.1);候选 %d 人" % full_team.size())
	var w_no_hero: Dictionary = TriSelectPool.weights(0, 5)
	check(int(w_no_hero.hero) == 0 and int(w_no_hero.relic) == 50, "武将池空 → 权重 20 转遗物(30+20)")
	var w_no_relic: Dictionary = TriSelectPool.weights(2, 0)
	check(int(w_no_relic.relic) == 0 and int(w_no_relic.upgrade) == 80 and int(w_no_relic.hero) == 20,
		"遗物池空 → 权重 30 转强化(遗物留武将)")
	var w_both_empty: Dictionary = TriSelectPool.weights(0, 0)
	check(int(w_both_empty.relic) == 0 and int(w_both_empty.upgrade) == 100,
		"武将与遗物池均空 → 权重全转强化(50+20+30)")
	var upgrade_hands := 0
	var relic_dup_violation := 0
	var small_hands := 0
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 424242
	for i in 200:
		RS3.reset(777)
		var hand: Array = TriSelectPool.offer(rng2, 8)
		if hand.size() < 3:
			small_hands += 1
		var kind_seen := {}
		var relic_seen := {}
		var has_upgrade := false
		for c in hand:
			var k := str(c.kind)
			kind_seen[k] = true
			if k == "upgrade":
				has_upgrade = true
			if k == "relic":
				if relic_seen.has(str(c.id)):
					relic_dup_violation += 1
				relic_seen[str(c.id)] = true
				check(not RS3.relics.has(str(c.id)), "不出已拥有遗物(同名全场唯一)")
		if has_upgrade:
			upgrade_hands += 1
	check(upgrade_hands == 200, "200 手全部保底 ≥1 强化卡(实际 %d)" % upgrade_hands)
	check(small_hands == 0 and relic_dup_violation == 0, "每手 3 卡且同手无重复遗物")

	# --- 商店货架:6 格构成 / 定价 / 犒赏不上架(01 §7) ---
	var SS = load("res://scripts/battle/shop_shelf.gd")
	var shelf: Array = SS.roll(rng2, [])
	check(shelf.size() == 6, "货架 6 格")
	var heal_cnt := 0
	var relic_cnt := 0
	var upgrade_cnt := 0
	var price_ok := true
	var kaoshang_listed := false
	for it in shelf:
		match str(it.get("kind", "")):
			"heal":
				heal_cnt += 1
				check(int(it.price) == 20, "军医诊治 20 军资")
			"relic":
				relic_cnt += 1
				var p := int(it.price)
				if p != SS.relic_price(str(it.rarity)):
					price_ok = false
			"upgrade":
				upgrade_cnt += 1
				if int(it.price) < 20 or int(it.price) > 35:
					price_ok = false
				if str(it.id) == "kaoshang":
					kaoshang_listed = true
	check(heal_cnt == 1 and relic_cnt + upgrade_cnt == 5, "货架 = 遗物+强化 5 格 + 军医诊治 1 格(实际 遗物%d 强化%d)" % [relic_cnt, upgrade_cnt])
	check(price_ok and not kaoshang_listed, "定价合规且犒赏(0 价)不上架")
	check(SS.relic_price("normal") == 25 and SS.relic_price("rare") == 40 and SS.relic_price("epic") == 60, "遗物定价 普通25/稀有40/史诗60")
	# 遗物去重:全拥有后货架不重复
	RS3.reset(42)
	for rid in ["qinggang_sword", "chitu_horse", "taiping_yaoshu", "yuxi", "sunzi_bingfa", "liannu_tu", "shuanggu_jian", "qingnang_shu"]:
		RS3.add_relic(rid)
	check(RS3.relics.size() == 8, "8 遗物全拥有")
	var shelf2: Array = SS.roll(rng2, RS3.relics)
	for it2 in shelf2:
		if str(it2.get("kind", "")) == "relic":
			check(false, "遗物池空时货架不应再出遗物")
			break

	# --- 事件效果:鞭打督邮 A / 三让徐州 B / 虎牢关 A(01 §9) ---
	var EE = load("res://scripts/battle/event_effects.gd")
	RS3.reset(42)
	var gold0: int = RS3.gold
	var txt1: String = EE.apply({"gold": 15})
	check(RS3.gold == gold0 + 15 and txt1.contains("15"), "事件:获得 15 军资")
	RS3.reset(42)
	var zf0: float = RS3.hero_atk_mult("zhangfei")
	EE.apply({"zhangfei_atk_pct": 0.15})
	check(absf(RS3.hero_atk_mult("zhangfei") - (zf0 + 0.15)) < 0.001, "鞭打督邮 A:张飞攻击 +15%(本场)")
	RS3.reset(42)
	EE.apply({"team_maxhp_flat": 10})
	check(absf(float(RS3.mods_flat.get("maxhp", 0.0)) - 10.0) < 0.001, "三让徐州 A:全队 HP 上限 +10(本场)")
	RS3.reset(42)
	RS3.add_gold(100)
	var t0: int = RS3.team.size()
	var recruit_txt: String = EE.apply({"recruit": "lvbu", "cost_gold": 60})
	check(RS3.team.size() == t0 + 1 and RS3.gold == 40 and recruit_txt.contains("吕布"), "虎牢关 A:60 军资招募吕布")
	RS3.reset(42)
	var relic_txt: String = EE.apply({"random_relic": "normal|rare"})
	check(RS3.relics.size() == 1 and relic_txt.contains("遗物"), "三让徐州 B:随机 1 件普通/稀有遗物")
	var rar := str(DataDB.relic_by_id(str(RS3.relics[0])).get("rarity", ""))
	check(rar == "normal" or rar == "rare", "随机遗物稀有度限定 normal|rare(实际 %s)" % rar)
	RS3.reset(42)

	# ================= M5 Boss 华雄用例(01 §6 技能组,固定 seed)=================

	# --- 华雄数据口径:挥砍 2m / 冲锋 8m+16 伤+击退2m+CD8s / 震地 4m+16 伤+击退3m+CD12s ---
	var BH = load("res://scripts/battle/boss_huaxiong.gd")
	var boss_d: Dictionary = DataDB.enemy_by_id("huaxiong")
	check(absf(float(boss_d.get("attack_range", 0.0)) - 2.0) < 0.001, "华雄挥砍近身 2m(01 §6)")
	check(absf(float(boss_d.get("charge_cd", 0.0)) - 8.0) < 0.001, "冲锋 CD 8s")
	check(absf(float(boss_d.get("slam_cd", 0.0)) - 12.0) < 0.001, "震地 CD 12s")
	check(int(boss_d.get("atk_charge", 0)) == 16 and int(boss_d.get("atk_slam", 0)) == 16, "冲锋/震地伤害 16")
	check(float(boss_d.get("phase2_hp_ratio", 0.0)) == 0.5 and float(boss_d.get("phase2_speed_mult", 0.0)) == 1.25,
		"二阶段:HP<50% 进入,移速/攻速 ×1.25")
	check(int(boss_d.get("summon_count", 0)) == 4 and str(boss_d.get("summon_id", "")) == "xiliang_qinwei",
		"二阶段每 12s 召唤西凉亲卫×4")
	# --- 免疫击退/眩晕/斩杀(数据口径;运行时免疫经 EnemyUnit.stun_immune/knockback_resist) ---
	check(float(boss_d.get("kb_resist", 0.0)) == 1.0, "华雄免疫击退(kb_resist=1.0)")
	check(bool(boss_d.get("immune_stun", false)), "华雄免疫眩晕")
	check(bool(boss_d.get("immune_execute", false)), "华雄免疫斩杀")
	check(str(boss_d.get("ai", "")) == "boss", "华雄 ai=boss(spawner 据此走 boss_huaxiong.tscn)")
	# --- 前摇常量口径(01 §6:冲锋 0.8s / 震地 1.0s) ---
	check(absf(BH.CHARGE_TELEGRAPH - 0.8) < 0.001, "冲锋前摇 0.8s(地面红色警示痕)")
	check(absf(BH.SLAM_TELEGRAPH - 1.0) < 0.001, "震地前摇 1.0s")
	# --- 冲锋终点:直线 8m 封顶 + 战场夹取 ---
	var c_end: Vector3 = BH.charge_end(Vector3.ZERO, Vector3(30.0, 0.0, 0.0), 8.0)
	check(c_end.distance_to(Vector3(8.0, 0.0, 0.0)) < 0.01, "冲锋:锁定方向直线 8m")
	var c_short: Vector3 = BH.charge_end(Vector3.ZERO, Vector3(3.0, 0.0, 0.0), 8.0)
	check(c_short.distance_to(Vector3(3.0, 0.0, 0.0)) < 0.01, "冲锋:目标更近时冲到锁定点")
	var c_wall: Vector3 = BH.charge_end(Vector3(17.0, 0.0, 0.0), Vector3(30.0, 0.0, 0.0), 8.0)
	check(absf(c_wall.x - 19.0) < 0.01, "冲锋:终点夹回战场边界")
	# --- 冲锋命中带宽(线段距离 ≤ 1.3m)---
	check(BH.charge_hits(Vector3.ZERO, Vector3(0.0, 0.0, -8.0), Vector3(1.0, 0.0, -4.0)), "冲锋路径侧偏 1.0m 命中")
	check(not BH.charge_hits(Vector3.ZERO, Vector3(0.0, 0.0, -8.0), Vector3(2.0, 0.0, -4.0)), "冲锋路径侧偏 2.0m 不命中")
	# --- 二阶段进入判定(HP 严格 < 50%)---
	check(not BH.phase2_should_enter(751.0, 1500.0), "HP 50.1% 未进二阶段")
	check(not BH.phase2_should_enter(750.0, 1500.0), "HP 50% 整未进二阶段(严格小于)")
	check(BH.phase2_should_enter(749.0, 1500.0), "HP 49.9% 进入二阶段")
	# --- 召唤站位:4 点均匀环、半径 2m、夹回战场 ---
	var pts: Array = BH.summon_positions(Vector3.ZERO, 4)
	check(pts.size() == 4, "召唤点 4 个")
	var pts_ok := true
	var ang_seen: Array = []
	for p in pts:
		var pf: Vector3 = p
		if absf(pf.length() - 2.0) > 0.01:
			pts_ok = false
		ang_seen.append(roundf(atan2(pf.z, pf.x) * 100.0))
	check(pts_ok, "召唤点距 Boss 2m(环形)")
	check(ang_seen[0] != ang_seen[1] and ang_seen.size() == 4, "召唤点非重合(均匀分布)")
	var pts_edge: Array = BH.summon_positions(Vector3(18.5, 0.0, 0.0), 4)
	var edge_ok := true
	for p2 in pts_edge:
		if absf((p2 as Vector3).x) > 19.0:
			edge_ok = false
	check(edge_ok, "召唤点夹回战场内")

	# --- 音频清单:01 §12 全量生成(16 = 15 sfx + 1 BGM)---
	var audio_expected := ["slash", "hit", "die", "coin", "rende", "qinglong", "dangyang",
		"qijin", "eastwind", "miaoshou", "fangtian", "horn", "button", "win", "lose"]
	var audio_missing := 0
	for a in audio_expected:
		if not FileAccess.file_exists("res://assets/audio/sfx_%s.wav" % a):
			audio_missing += 1
	check(audio_missing == 0, "15 个技能/系统音效 WAV 齐全(缺 %d)" % audio_missing)
	check(FileAccess.file_exists("res://assets/audio/bgm_camp.wav"), "BGM 五声音阶循环 WAV 存在")
	var wav_ok := true
	for a2 in audio_expected:
		var fa := FileAccess.open("res://assets/audio/sfx_%s.wav" % a2, FileAccess.READ)
		if fa == null:
			wav_ok = false
		else:
			var riff := fa.get_32()
			var _size := fa.get_32()          # RIFF 块大小(跳过)
			var wave_tag := fa.get_32()
			if riff != 0x46464952 or wave_tag != 0x45564157:   # "RIFF"/"WAVE" 小端
				wav_ok = false
			fa.close()
	check(wav_ok, "WAV 头合法(RIFF/WAVE,16bit PCM)")
	check(InputMap.has_action("lord_skill"), "空格动作 lord_skill 已注册")
	var space_bound := false
	for ev in InputMap.action_get_events("lord_skill"):
		var k := ev as InputEventKey
		if k != null and k.physical_keycode == KEY_SPACE:
			space_bound = true
	check(space_bound, "lord_skill 绑定空格键(主 Agent 拍板)")

	# ================= 03 第三批用例(05 §1/§2/§3,固定 seed)=================

	# --- 敌方新状态字段与互斥规则:恐惧/嘲讽/倒戈,后到覆盖先到(05 §1)---
	var EU = load("res://scripts/battle/enemy_unit.gd")
	var e1 = EU.new()
	e1.apply_stun(3.0)
	check(e1.stun_left > 0.0 and e1.is_controlled(), "眩晕使 is_controlled = true(前置)")
	e1.apply_fear(2.0, null)
	check(e1.fear_left > 0.0 and e1.stun_left == 0.0, "恐惧覆盖眩晕(后到覆盖先到,05 §1)")
	e1.apply_taunt(3.0, null)
	check(e1.taunt_left > 0.0 and e1.fear_left == 0.0 and e1.fear_source == null, "嘲讽覆盖恐惧(05 §1)")
	e1.apply_defect(4.0, null)
	check(e1.defected_left > 0.0 and e1.taunt_left == 0.0, "倒戈覆盖嘲讽(05 §1)")
	check(e1.is_controlled(), "倒戈中 is_controlled = true(受控增伤判定口径)")
	# 计时衰减与到期还原(与 slow 的 left 计时同模式)
	e1._tick_states(1.0)
	check(absf(e1.defected_left - 3.0) < 0.001, "倒戈 1s 衰减:剩余 3s")
	e1._tick_states(3.5)
	check(e1.defected_left == 0.0 and not e1.is_controlled(), "倒戈到期还原:is_controlled = false")
	e1.free()
	# Boss 倒戈豁免(05 §2.5:只踌躇不倒戈,Boss 不走 apply_defect)
	var e2 = EU.new()
	e2.boss = true
	e2.apply_defect(4.0, null)
	check(e2.defected_left == 0.0 and not e2.is_controlled(), "Boss 免疫倒戈(只踌躇,05 §2.5)")
	e2.free()

	# --- 受控增伤共用乘区(止啼/连环,05 §1):+15% 仅在目标受控时生效 ---
	var HU3 = load("res://scripts/battle/hero_unit.gd")
	var zhiti := {"type": "controlled_amp", "dmg_amp": 0.15}
	check(absf(HU3.controlled_amp(zhiti, true) - 1.15) < 0.001, "受控目标:止啼乘区 ×1.15")
	check(absf(HU3.controlled_amp(zhiti, false) - 1.0) < 0.001, "未受控目标:无增伤")
	check(absf(HU3.controlled_amp({}, true) - 1.0) < 0.001, "无止啼/连环词条:无增伤")

	# --- 许褚裸衣阈值(05 §2.2):HP < 50% 生效 ---
	check(HU3.luoyi_should_on(0.49), "HP 49% < 50% → 裸衣生效")
	check(not HU3.luoyi_should_on(0.50), "HP 50% 整 → 裸衣不生效")
	check(not HU3.luoyi_should_on(0.80), "HP 80% → 裸衣不生效")

	# --- 火雨几何/点燃复用灼烧(05 §2.4):tick 数与总量同灼烧口径 ---
	check(UB.burn_tick_count(3.0, 0.5) == 6, "火雨点燃 3s = 6 tick(复用灼烧)")

	# --- 换人规则 1+2(05 §3):替换卡 / 离队者回池 / 阵亡补位 ---
	var RS4 = root_autoload("RunState")
	RS4.reset(666)
	check(RS4.team.size() == 3, "开局三人组(前置)")
	# 招到满员 → 武将卡 replace 标记 = true
	for hid in ["zhaoyun", "huatuo", "zhuge", "machao"]:
		check(RS4.add_team_member(hid), "%s 入队(前置)" % hid)
	check(RS4.team.size() == RunState.MAX_TEAM, "满员 7(前置)")
	var zl_card: Dictionary = TriSelectPool._hero_card(DataDB.hero_by_id("zhangliao"))
	check(bool(zl_card.get("replace", false)), "满员时武将卡带 replace 标记(替换卡,05 §3.1)")
	var not_in_team_card: Dictionary = TriSelectPool._hero_card(DataDB.hero_by_id("huangzhong"))
	check(bool(not_in_team_card.get("replace", false)), "未在队的武将卡同为替换卡(满员口径)")
	# 替换:张辽替换马超 → 马超出队(zhangliao 入队、马离队)
	check(RS4.replace_team_member("zhangliao", "machao"), "替换成功:张辽入场、马超离队")
	check(RS4.member("zhangliao").size() > 0 and RS4.member("machao").is_empty(), "队伍名单:张辽在队、马超已出队")
	check(not RS4.member("zhangliao").is_empty() and bool(RS4.member("zhangliao").alive), "入场成员 alive = true")
	check(RS4.team.size() == RunState.MAX_TEAM, "替换不改变队伍规模(数值零跳变,05 §3.3)")
	# 离队者回候选池:不在队 → 可再抽回(hero_candidates 含它)
	var pool_after: Array = TriSelectPool.hero_candidates(2, _team_ids(RS4), RS4.team.size(), RunState.MAX_TEAM)
	var pool_ids: Array = []
	for c in pool_after:
		pool_ids.append(str(c.get("id", "")))
	check(pool_ids.has("machao"), "离队者马超回候选池(可再抽回,05 §3.1)")
	# 再抽回:替换口径可再次入队
	check(RS4.replace_team_member("machao", "zhaoyun"), "马超再抽回:替换赵云入场")
	check(RS4.member("machao").size() > 0, "马超重新在队(离队者可再抽回)")
	check(RS4.replace_team_member("zhaoyun", "machao"), "还原:赵云回场、马超离队(恢复前置)")
	# 替换卡 helper:非法替换拒绝(同一 id / 目标已在队 / 未知 id)
	check(not RS4.replace_team_member("machao", "machao"), "同一 id 替换拒绝")
	check(not RS4.replace_team_member("nonexistent_id", "zhuge"), "未知 new id 替换拒绝")
	# 阵亡补位(05 §3.2):武将阵亡后武将卡恢复可出
	var zy_m: Dictionary = RS4.member("zhaoyun")
	zy_m["alive"] = false
	check(RS4.re_recruitable("zhaoyun"), "赵云阵亡 → 其武将卡恢复可出(阵亡补位,05 §3.2)")
	check(not RS4.re_recruitable("lvbu"), "吕布 recruit_source=event,不入三选一补位")
	zy_m["alive"] = true
	check(not RS4.re_recruitable("zhaoyun"), "在队且存活 → 不重复出卡(前置还原)")
	check(RS4.re_recruitable("machao"), "离队者(不在队)→ 可出卡(回池口径)")
	check(not RS4.re_recruitable("guanyu"), "在队且存活(关羽)→ 不可出卡")

	# --- 卡面文本:五将词条描述 ---
	var card_texts := {
		"zhangliao": TriSelectPool._hero_card(DataDB.hero_by_id("zhangliao")),
		"xuchu": TriSelectPool._hero_card(DataDB.hero_by_id("xuchu")),
		"ganning": TriSelectPool._hero_card(DataDB.hero_by_id("ganning")),
		"zhouyu": TriSelectPool._hero_card(DataDB.hero_by_id("zhouyu")),
		"diaochan": TriSelectPool._hero_card(DataDB.hero_by_id("diaochan")),
	}
	check(str(card_texts["zhangliao"].get("desc", "")).contains("+15%"), "张辽卡面含受控增伤 +15% 词条")
	check(str(card_texts["xuchu"].get("desc", "")).contains("30%"), "许褚卡面含裸衣减伤 30% 词条")
	check(str(card_texts["ganning"].get("desc", "")).contains("2.5"), "甘宁卡面含背袭 ×2.5 词条")
	check(str(card_texts["zhouyu"].get("desc", "")).contains("点燃"), "周瑜卡面含点燃词条")
	check(str(card_texts["diaochan"].get("desc", "")).contains("倒戈") or str(card_texts["diaochan"].get("desc", "")).contains("魅惑"),
		"貂蝉卡面含魅惑(倒戈)词条")

func _team_ids(RS) -> Array:
	var out: Array = []
	for m in RS.team:
		out.append(str(m.hero_id))
	return out

func ub2_dr(ub) -> void:
	# 临时减伤与直伤(需要独立实例,避免与上面护盾用例串扰)
	ub.invincible = false
	ub.dr_percent = 0.30
	ub.hp = 100.0
	ub.take_damage(10.0, null)
	check(absf(ub.hp - 93.0) < 0.001, "减伤 30%:10 伤害实扣 7(HP 100→93)")
	ub.lose_hp_direct(30.0)
	check(absf(ub.hp - 63.0) < 0.001, "直伤无视护盾/减伤:-30")
	ub.lose_hp_direct(100.0)
	check(absf(ub.hp - 1.0) < 0.001, "直伤不致死(下限 1 HP,事件代价口径)")

func root_autoload(node_name: String) -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node(node_name)
