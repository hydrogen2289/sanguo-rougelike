class_name SkillComponent
extends Node
## 技能组件(M4):CD 计时 + activate() 分发 + 7 种数据驱动原型(02 §7.3,数值 01 §4)。
## 原型:shield(刘备)/ cone(关羽)/ nova(张飞)/ dash(赵云)/
##       weather(诸葛亮)/ heal_all(华佗)/ triple_nova(吕布)。
## 03 第二批追加:charge(马超铁骑冲锋)/ snipe(黄忠百步穿杨)/ frenzy(魏延狂骨)。
## 03 第三批追加(05 §2):fear(张辽威压)/ taunt(许褚虎痴)/ dash_assassin(甘宁百翎直袭)/
##       fire_rain(周瑜火雨)/ charm(貂蝉闭月)。
## 吕布「不受令」:activate 时 30% 概率延迟 3s 生效,延迟生效每段伤害 ×1.5。

var host: UnitBase = null
var skill_data: Dictionary = {}
var cd_left := 0.0
var delayed_left := -1.0      # ≥0 → 「不受令」延迟倒计时(HUD 红闪读此值)
var delayed_mult := 1.0
var _pulse_queue: Array = []  # 吕布三段斩后续段 [{t, radius, mult}]:_process 节拍驱动(P2-①,弹窗暂停期冻结)
var _frenzy_left := 0.0       # 魏延「狂骨」剩余时间(攻速加成 + 每秒自伤,_process 节拍驱动)
var _frenzy_tick := 0.0       # 狂骨自伤 1s 节拍累计
# --- 03 第三批(05 §2)---
var _firerain_queue: Array = []   # 周瑜火雨后续轮次 [{t, radius, mult, burn_dur}]:_process 节拍驱动(随树暂停)
var _backstab_armed := false      # 甘宁背袭:dash 后武装,下次普攻一次性 ×backstab_mult
var _jinfan_left := 0.0           # 甘宁「锦帆」击杀移速 buff 剩余时间(host 侧还原)

func setup(h: UnitBase) -> void:
	host = h
	if h.hero_data.is_empty():
		return
	skill_data = h.hero_data.get("skill", {})
	cd_left = initial_cd(float(skill_data.get("cd", 10.0)), RunState.cd_mult())

## 技能开局即减半冷却(01 §3);静态便于 test_formulas
static func initial_cd(cd_base: float, cd_mult: float) -> float:
	return cd_base * cd_mult * 0.5

## 「不受令」掷骰(静态便于 test_formulas 1000 次采样)
static func roll_disobey(rng: RandomNumberGenerator, chance: float) -> bool:
	return rng.randf() < chance

func _process(delta: float) -> void:
	if cd_left > 0.0:
		cd_left = maxf(0.0, cd_left - delta)
	if delayed_left >= 0.0:
		delayed_left -= delta
		if delayed_left < 0.0:
			delayed_left = -1.0
			if host != null and is_instance_valid(host) and not host.dead and is_inside_tree():
				_execute(delayed_mult)
	# 吕布三段后续段:节拍驱动,随树暂停(P2-①:原 SceneTreeTimer 暂停中照走)
	if not _pulse_queue.is_empty():
		for p in _pulse_queue.duplicate():
			p["t"] = float(p["t"]) - delta
			if float(p["t"]) <= 0.0:
				_pulse_queue.erase(p)
				_nova_pulse(float(p["radius"]), float(p["mult"]))
	# 魏延「狂骨」持续期:每秒流失 HP(最低留 1,不可致死,03 §3.3);
	# 节拍驱动随树暂停(与三段斩同口径);到期由 _frenzy_end 还原攻速
	if _frenzy_left > 0.0:
		_frenzy_left -= delta
		_frenzy_tick += delta
		while _frenzy_tick >= 1.0 and _frenzy_left > -0.5:
			_frenzy_tick -= 1.0
			_frenzy_drain()
		if _frenzy_left <= 0.0:
			_frenzy_left = 0.0
			_frenzy_end()
	# 周瑜火雨后续轮次:节拍驱动,随树暂停(与三段斩同口径,03 第三批)
	if not _firerain_queue.is_empty():
		for p in _firerain_queue.duplicate():
			p["t"] = float(p["t"]) - delta
			if float(p["t"]) <= 0.0:
				_firerain_queue.erase(p)
				_firerain_pulse(float(p["radius"]), float(p["mult"]), float(p["burn_dur"]))
	# 甘宁「锦帆」击杀移速 buff 到期还原(host 侧计时,03 第三批)
	if _jinfan_left > 0.0:
		_jinfan_left -= delta
		if _jinfan_left <= 0.0:
			_jinfan_left = 0.0
			if host != null and is_instance_valid(host) and host.has_method("clear_jinfan_buff"):
				host.clear_jinfan_buff()

func _disobey_data() -> Dictionary:
	var t: Dictionary = host.hero_data.get("trait", {}) if host != null else {}
	if str(t.get("type", "")) == "disobey":
		return t
	return {}

func _final_cd() -> float:
	return float(skill_data.get("cd", 10.0)) * RunState.cd_mult()

func cd_ratio() -> float:
	var full := _final_cd()
	if full <= 0.0:
		return 0.0
	return clampf(cd_left / full, 0.0, 1.0)

func can_activate() -> bool:
	return not skill_data.is_empty() and cd_left <= 0.0

func activate() -> bool:
	if not can_activate():
		return false
	if host == null or not is_instance_valid(host) or host.dead:
		return false
	# dash / charge / dash_assassin 需目标在场,无目标不放(不空耗 CD)
	if str(skill_data.get("type", "")) == "dash" and _dash_target() == null:
		return false
	if str(skill_data.get("type", "")) == "charge" and _charge_target() == null:
		return false
	if str(skill_data.get("type", "")) == "dash_assassin" and _dash_assassin_target() == null:
		return false
	# fire_rain / charm 需有敌可作用,否则不空耗 CD(与 dash 同口径)
	if str(skill_data.get("type", "")) == "fire_rain" and _rain_target() == null:
		return false
	if str(skill_data.get("type", "")) == "charm" and _charm_target() == null:
		return false
	var disobey := _disobey_data()
	delayed_mult = 1.0
	if not disobey.is_empty() and SkillComponent.roll_disobey(RunState.rng, float(disobey.get("chance", 0.30))):
		# 不受令:延迟 3s 生效,每段伤害 ×1.5(01 §4)
		delayed_left = float(disobey.get("delay", 3.0))
		delayed_mult = float(disobey.get("dmg_mult", 1.5))
		cd_left = _final_cd()
		Quips.say(host, "末将……不愿受令!", Color(0.71, 0.29, 0.23))
		return true
	cd_left = _final_cd()
	_execute(1.0)
	return true

func _execute(extra_mult: float) -> void:
	if host == null or not is_instance_valid(host) or host.dead:
		return
	match str(skill_data.get("type", "")):
		"shield":
			_cast_shield()
			Sfx.play("rende")
		"cone":
			_cast_cone(extra_mult)
			Sfx.play("qinglong")
		"nova":
			_cast_nova(extra_mult)
			Sfx.play("dangyang")
		"dash":
			_cast_dash()
			Sfx.play("qijin")
		"weather":
			_cast_weather()          # 音效由 WeatherManager 播(eastwind),避免双放
		"heal_all":
			_cast_heal_all()
			Sfx.play("miaoshou")
		"triple_nova":
			_cast_triple_nova(extra_mult)
			Sfx.play("fangtian")
		"charge":
			_cast_charge()
			Sfx.play("qijin")            # 占位复用七进七出音效(无新 wav,验收后按需补)
		"snipe":
			_cast_snipe()
			Sfx.play("slash")            # 占位复用挥砍音效(无新 wav,验收后按需补)
		"frenzy":
			_cast_frenzy()
			Sfx.play("dangyang")         # 占位复用狂化音效(无新 wav,验收后按需补)
		# --- 03 第三批(05 §2)---
		"fear":
			_cast_fear()
			Sfx.play("dangyang")         # 占位复用吼类音效(无新 wav,验收后按需补)
		"taunt":
			_cast_taunt()
			Sfx.play("horn", -6.0)       # 占位复用号角音效(无新 wav,验收后按需补)
		"dash_assassin":
			_cast_dash_assassin()
			Sfx.play("qijin")            # 占位复用七进七出音效(无新 wav,验收后按需补)
		"fire_rain":
			_cast_fire_rain()
			Sfx.play("eastwind", -4.0)   # 占位复用东风音效(无新 wav,验收后按需补)
		"charm":
			_cast_charm()
			Sfx.play("miaoshou", -4.0)   # 占位复用治疗音效(无新 wav,验收后按需补)
		_:
			pass

# ---------------------------------------------------------------- 原型实现

## 刘备 仁德之泽:3.5m 内友军获得护盾 20(6s)并立即回复 12(CD 10s,01 §4)
func _cast_shield() -> void:
	var radius := float(skill_data.get("radius", 3.5))
	var amount := float(skill_data.get("shield_amount", 20.0))
	var dur := float(skill_data.get("shield_duration", 6.0))
	var heal := float(skill_data.get("heal_amount", 12.0))
	for f in _allies_in_radius(radius):
		f.give_shield(amount, dur)      # give_shield 内部 × heal_mult
		f.heal(heal)
	_vfx("ring", radius, Color(0.75, 0.85, 1.0, 0.7))

## 关羽 青龙偃月·扫:120° 扇形 3m,250% 攻击 + 击退 1m(CD 8s,01 §4)
func _cast_cone(extra_mult: float) -> void:
	var radius := float(skill_data.get("radius", 3.0))
	var angle := float(skill_data.get("angle_deg", 120))
	var mult := float(skill_data.get("dmg_mult", 2.5)) * extra_mult
	var kb := float(skill_data.get("knockback", 1.0))
	for e in _enemies_in_cone(radius, angle):
		e.take_damage(UnitBase.compute_damage(host.atk, mult), host)
		e.apply_knockback(e.global_position - host.global_position, kb)
	_vfx("slash", radius, Color(1.0, 0.97, 0.9, 0.8), true)

## 张飞 当阳桥吼:3m,180% + 击退 3m + 眩晕 1s,自身 2s 减伤 30%(CD 12s,01 §4)
func _cast_nova(extra_mult: float) -> void:
	var radius := float(skill_data.get("radius", 3.0))
	var mult := float(skill_data.get("dmg_mult", 1.8)) * extra_mult
	var kb := float(skill_data.get("knockback", 3.0))
	var stun := float(skill_data.get("stun", 1.0))
	for e in _enemies_in_radius(radius):
		e.take_damage(UnitBase.compute_damage(host.atk, mult), host)
		e.apply_knockback(e.global_position - host.global_position, kb)
		e.apply_stun(stun)
	host.dr_percent = float(skill_data.get("self_dr", 0.30))
	var dur := float(skill_data.get("self_dr_duration", 2.0))
	var wr: WeakRef = weakref(host)
	# process_always=false:弹窗/结算暂停期间减伤计时不流逝(P2-①)
	var tm := host.get_tree().create_timer(dur, false)
	tm.timeout.connect(func() -> void:
		var h = wr.get_ref()
		if h != null and is_instance_valid(h):
			h.dr_percent = 0.0)
	_vfx("ring", radius, Color(0.85, 0.6, 0.4, 0.75))

## 赵云 七进七出:冲向 6m 内最远敌,沿途 150%,冲锋期间无敌 0.8s(CD 9s,01 §4)
func _cast_dash() -> void:
	var tgt := _dash_target()
	if tgt == null:
		return
	var radius := float(skill_data.get("radius", 6.0))
	var mult := float(skill_data.get("dmg_mult", 1.5))
	var invuln := float(skill_data.get("invuln", 0.8))
	var p0: Vector3 = host.global_position
	var to: Vector3 = tgt.global_position - p0
	to.y = 0.0
	var seg := to.length()
	var dir := to.normalized() if seg > 0.001 else host.facing
	var p1: Vector3 = tgt.global_position - dir * 0.8
	p1.x = clampf(p1.x, -19.0, 19.0)
	p1.z = clampf(p1.z, -19.0, 19.0)
	# 沿途伤害:到线段距离 ≤ 1.0 的敌人(静态几何便于测试)
	for e in host.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead:
			if SkillComponent.point_segment_dist_xz(e.global_position, p0, p1) <= 1.0:
				e.take_damage(UnitBase.compute_damage(host.atk, mult), host)
	var prev_invincible: bool = host.invincible
	host.invincible = true
	var dur := clampf(p0.distance_to(p1) / 18.0, 0.12, 0.3)
	var tw := host.create_tween()
	tw.tween_property(host, "global_position", p1, dur)
	var wr: WeakRef = weakref(host)
	# process_always=false:弹窗/结算暂停期间无敌计时不流逝(P2-①)
	var tm := host.get_tree().create_timer(invuln, false)
	tm.timeout.connect(func() -> void:
		var h = wr.get_ref()
		if h != null and is_instance_valid(h):
			h.invincible = prev_invincible)
	_vfx("ring", 1.2, Color(0.9, 0.95, 1.0, 0.8))

## 诸葛亮 借东风:东风 10s,全队普攻附加灼烧 + 火伤 +30%(CD 15s,01 §4;已拍板口径)
func _cast_weather() -> void:
	EventBus.eastwind_started.emit(float(skill_data.get("duration", 10.0)))
	_vfx("ring", 2.0, Color(0.56, 0.68, 0.55, 0.8))

## 华佗 妙手回春:全体友军立即回复 20(CD 12s,01 §4)
func _cast_heal_all() -> void:
	var amount := float(skill_data.get("heal_amount", 20.0))
	for f in _allies_in_radius(999.0):
		f.heal(amount)
	Quips.say(host, "医者仁心", Color(0.56, 0.68, 0.55))
	_vfx("ring", 2.4, Color(0.56, 0.75, 0.55, 0.7))

## 吕布 方天乱舞:3.5m 三段斩,每段 120%(CD 10s,01 §4)。
## 首段即刻,后续段入 _pulse_queue 由 _process 节拍驱动(P2-①:原 SceneTreeTimer 暂停中照走);
## 宿主死亡时 _nova_pulse 内部守卫作废剩余段,与原语义一致。
func _cast_triple_nova(extra_mult: float) -> void:
	var hits := int(skill_data.get("hits", 3))
	var radius := float(skill_data.get("radius", 3.5))
	var mult := float(skill_data.get("dmg_mult", 1.2)) * extra_mult
	for i in hits:
		if i == 0:
			_nova_pulse(radius, mult)
		else:
			_pulse_queue.append({"t": float(i) * 0.25, "radius": radius, "mult": mult})

func _nova_pulse(radius: float, mult: float) -> void:
	if host == null or not is_instance_valid(host) or host.dead:
		return
	for e in _enemies_in_radius(radius):
		e.take_damage(UnitBase.compute_damage(host.atk, mult), host)
	_vfx("ring", radius, Color(0.71, 0.29, 0.23, 0.7))

# ---------------------------------------------------------------- 03 第二批原型(数值占位,验收实测调整)

## 马超 铁骑冲锋(03 §3.1):向索敌目标方向突进 4m,路径敌人受 120% 攻击伤害 + 减速 30% 1.5s。
## 位移取舍:复用赵云 dash 的 create_tween 直改 global_position(0.3s 内插值到落点),
## 不走 move_and_slide —— 突进是瞬发位移不该被软分离/击退打断,且保持与 dash 同一套暂停口径。
## 突进期间跳过受击:占位实现 —— host.invincible 置 true 至 tween 完成(tween 0.12~0.3s),
## 定稿写「突进期间不可被选中」,未给独立字段,暂以无敌近似,TODO:验收后按拍板补「不可被索敌」标记。
## 减速取舍:enemy 无移速字段乘区,本次给 EnemyUnit 加 slow_mult(移速乘区,1s/次衰减由 enemy 侧 _physics_process 计时);
## Boss 免疫眩晕但不禁减速(03 §6 未写豁免,待拍板)。
func _cast_charge() -> void:
	var tgt := _charge_target()
	if tgt == null:
		return
	var dist := float(skill_data.get("distance", 4.0))
	var mult := float(skill_data.get("dmg_mult", 1.2))
	var slow := float(skill_data.get("slow_ratio", 0.30))
	var slow_dur := float(skill_data.get("slow_duration", 1.5))
	var skip_hit := float(skill_data.get("skip_hit", 0.3))
	var p0: Vector3 = host.global_position
	var dir: Vector3 = tgt.global_position - p0
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.001 else host.facing
	var p1: Vector3 = p0 + dir * dist
	p1.x = clampf(p1.x, -19.0, 19.0)
	p1.z = clampf(p1.z, -19.0, 19.0)
	host.face_towards(p1)
	# 路径敌人:到线段 XZ 距离 ≤ 1.0(与赵云 dash 同口径,静态几何便于测试)
	for e in host.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead:
			if SkillComponent.point_segment_dist_xz(e.global_position, p0, p1) <= 1.0:
				e.take_damage(UnitBase.compute_damage(host.atk, mult), host)
				if e.has_method("apply_slow"):
					e.apply_slow(slow, slow_dur)
	var prev_invincible: bool = host.invincible
	host.invincible = true
	var dur := clampf(p0.distance_to(p1) / 14.0, 0.12, 0.3)
	var tw := host.create_tween()
	tw.tween_property(host, "global_position", p1, dur)
	var wr: WeakRef = weakref(host)
	# 突进期间跳过受击占位:无敌至 tween 结束 + skip_hit 兜底计时(双保险,防 tween 被 kill)
	# TODO 占位:「不可被选中」按定稿语义应是索敌过滤,当前以无敌近似,验收后拍板补
	var tm := host.get_tree().create_timer(maxf(skip_hit, dur), false)
	tm.timeout.connect(func() -> void:
		var h = wr.get_ref()
		if h != null and is_instance_valid(h):
			h.invincible = prev_invincible)
	_vfx("ring", 1.2, Color(0.9, 0.95, 1.0, 0.8))

## 马超突进目标:当前索敌目标,无则 4m 内最近(空放不耗 CD,由 activate 分流)
func _charge_target() -> Node:
	if target_valid(host.target):
		return host.target
	var best: Node = null
	var near := float(skill_data.get("distance", 4.0))
	for e in host.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead:
			var d: float = host._flat_dist(e.global_position)
			if d <= near:
				near = d
				best = e
	return best

## 黄忠 百步穿杨(03 §3.2):对场上 HP 最高敌人(含 Boss)射必中箭,250% 攻击伤害。
## 复用 projectile 管线,速度 ×2(speed_mult);「必中」= 直线弹道恒朝目标当前位置,
## 项目里弹道无追踪,对静止目标即必中;TODO 占位:验收若发现走位脱靶,再补轻微追踪
## (弹道每帧 lerp 方向)—— 先按定稿「必中」字面 + 直线实现。
func _cast_snipe() -> void:
	var tgt := _snipe_target()
	if tgt == null or host.battle == null:
		return
	var proj_scene: PackedScene = load("res://scenes/units/projectile.tscn")
	if proj_scene == null:
		return
	var proj := proj_scene.instantiate()
	var to: Vector3 = tgt.global_position - host.global_position
	var dir := Vector3(to.x, 0.0, to.z).normalized()
	var speed := 10.0 * float(skill_data.get("speed_mult", 2.0))
	proj.setup(dir, speed, UnitBase.compute_damage(host.atk, float(skill_data.get("dmg_mult", 2.5))), true, host)
	host.battle.get_node("Projectiles").add_child(proj)
	proj.global_position = host.global_position + Vector3(0.0, 1.0, 0.0)
	# 出手即回朝向,读感对齐「瞄准」
	host.face_towards(tgt.global_position)

## 黄忠狙杀目标:全场 HP 最高敌人(含 Boss;含玩家全场,999m 索敌,03 §3.2)
func _snipe_target() -> Node:
	var best: Node = null
	var best_hp := -1.0
	for e in host.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead:
			var hpv: float = float(e.hp)
			if hpv > best_hp:
				best_hp = hpv
				best = e
	return best

## 魏延 狂骨(03 §3.3):8s 攻速 ×1.6,期间每秒 -2 HP,最低留 1 HP(不可致死)。
## 攻速走 HostUnit 基础攻速除区(与燕人狂怒同口径);自伤节拍在 _process(随树暂停)。
func _cast_frenzy() -> void:
	_frenzy_left = float(skill_data.get("duration", 8.0))
	_frenzy_tick = 0.0
	if host.has_method("apply_frenzy_buff"):
		host.apply_frenzy_buff(float(skill_data.get("atk_speed_mult", 1.6)))
	Quips.say(host, "谁敢杀我!", Color(0.71, 0.29, 0.23))
	_vfx("ring", 1.6, Color(0.85, 0.45, 0.28, 0.8))

## 狂骨每秒自伤:最低留 1 HP —— 走 lose_hp_direct(同为不致死语义,浮字区分)
func _frenzy_drain() -> void:
	if host == null or not is_instance_valid(host) or host.dead:
		return
	var dmg := float(skill_data.get("hp_loss_per_sec", 2.0))
	host.hp = maxf(float(skill_data.get("hp_floor", 1.0)), host.hp - dmg)
	host._spawn_float("狂-%d" % roundi(dmg), Color(0.85, 0.45, 0.28))

## 狂骨到期:还原攻速(host 侧记 buff 基准,避免与 refresh_stats/enrage 互相踩)
func _frenzy_end() -> void:
	if host == null or not is_instance_valid(host) or host.dead:
		return
	if host.has_method("clear_frenzy_buff"):
		host.clear_frenzy_buff()

# ---------------------------------------------------------------- 03 第三批原型(数值占位,05 §2,验收实测调整)

## 张辽 威压(05 §2.1):自身为圆心 r3.5m 内敌人恐惧 2s(远离张辽、不可攻击、不可索敌)。
## Boss 恐惧时长减半(boss_duration_mult=0.5,不做免疫,留应对窗口)。
## 恐惧态与眩晕互斥、后到覆盖(enemy_unit._overwrite_controls 统一口径)。
func _cast_fear() -> void:
	var radius := float(skill_data.get("radius", 3.5))
	var dur := float(skill_data.get("fear_duration", 2.0))
	var boss_mult := float(skill_data.get("boss_duration_mult", 0.5))
	var hit := false
	for e in _enemies_in_radius(radius):
		var d := dur * (boss_mult if bool(e.get("boss")) else 1.0)
		if e.has_method("apply_fear"):
			e.apply_fear(d, host)
			hit = true
	if hit:
		Quips.say(host, "辽来辽来!", Color(0.45, 0.35, 0.55))
	_vfx("ring", radius, Color(0.45, 0.35, 0.55, 0.75))

## 许褚 虎痴(05 §2.2):r4m 内敌人强制索敌许褚 3s(嘲讽态);Boss 不豁免但时长减半。
func _cast_taunt() -> void:
	var radius := float(skill_data.get("radius", 4.0))
	var dur := float(skill_data.get("taunt_duration", 3.0))
	var boss_mult := float(skill_data.get("boss_duration_mult", 0.5))
	for e in _enemies_in_radius(radius):
		var d := dur * (boss_mult if bool(e.get("boss")) else 1.0)
		if e.has_method("apply_taunt"):
			e.apply_taunt(d, host)
	Quips.say(host, "虎痴在此!", Color(0.85, 0.6, 0.3))
	_vfx("ring", radius, Color(0.85, 0.6, 0.3, 0.7))

## 甘宁 百翎直袭(05 §2.3):向索敌目标 dash 4m(复用马超 charge 位移几何),
## 落地后武装「背袭」:下一次普攻一次性 ×2.5(dash 期间记标记 → _post_attack_hit 结算)。
## 与 charge 的区别:不沿途伤害,只标记首击乘区。
func _cast_dash_assassin() -> void:
	var tgt := _dash_assassin_target()
	if tgt == null:
		return
	var dist := float(skill_data.get("distance", 4.0))
	var p0: Vector3 = host.global_position
	var dir: Vector3 = tgt.global_position - p0
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.001 else host.facing
	var p1: Vector3 = p0 + dir * dist
	p1.x = clampf(p1.x, -19.0, 19.0)
	p1.z = clampf(p1.z, -19.0, 19.0)
	host.face_towards(p1)
	host.invincible = true
	var dur := clampf(p0.distance_to(p1) / 18.0, 0.12, 0.3)
	var wr: WeakRef = weakref(host)
	# 落点武装背袭:位移完成才武装,避免 dash 途中顺手普攻提前耗掉乘区
	var tw := host.create_tween()
	tw.tween_property(host, "global_position", p1, dur)
	tw.tween_callback(func() -> void:
		var h = wr.get_ref()
		if h != null and is_instance_valid(h) and not h.dead:
			_backstab_armed = true
			if h.has_method("arm_backstab"):
				h.arm_backstab(float(skill_data.get("backstab_mult", 2.5))))
	# 突进期间无敌兜底计时(与 charge 同口径:防 tween 被 kill)
	var tm := host.get_tree().create_timer(maxf(0.5, dur + 0.2), false)
	tm.timeout.connect(func() -> void:
		var h = wr.get_ref()
		if h != null and is_instance_valid(h):
			h.invincible = false)
	_vfx("ring", 1.2, Color(0.75, 0.4, 0.3, 0.8))

## 甘宁突袭目标:当前索敌目标,无则 4m 内最近(与 charge 同口径)
func _dash_assassin_target() -> Node:
	if target_valid(host.target):
		return host.target
	var best: Node = null
	var near := float(skill_data.get("distance", 4.0))
	for e in host.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead:
			var d: float = host._flat_dist(e.global_position)
			if d <= near:
				near = d
				best = e
	return best

## 周瑜 火雨(05 §2.4):以索敌目标为中心 r2.5m,3 轮火矢(间隔 0.8s),
## 每轮 80% 攻击伤害 + 点燃 3s(复用灼烧 apply_burn 结算路径;点燃可刷新不可叠加)。
## 首轮即刻,后续轮入 _firerain_queue 由 _process 节拍驱动(与吕布三段斩同口径)。
func _cast_fire_rain() -> void:
	var tgt := _rain_target()
	if tgt == null:
		return
	var rounds := int(skill_data.get("rounds", 3))
	var interval := float(skill_data.get("interval", 0.8))
	var radius := float(skill_data.get("radius", 2.5))
	var mult := float(skill_data.get("dmg_mult", 0.8))
	var burn_dur := float(skill_data.get("burn_duration", 3.0))
	_rain_center = tgt.global_position
	_firerain_queue.clear()
	for i in rounds:
		if i == 0:
			_firerain_pulse(radius, mult, burn_dur)
		else:
			_firerain_queue.append({"t": float(i) * interval, "radius": radius,
				"mult": mult, "burn_dur": burn_dur})
	host.face_towards(_rain_center)

## 火雨落点中心(快照):索敌目标位置;无目标时取 6m 内最近敌(activate 已守非空)
var _rain_center := Vector3.ZERO

func _rain_target() -> Node:
	if target_valid(host.target):
		return host.target
	var best: Node = null
	var near := 6.0
	for e in host.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead:
			var d: float = host._flat_dist(e.global_position)
			if d <= near:
				near = d
				best = e
	return best

func _firerain_pulse(radius: float, mult: float, burn_dur: float) -> void:
	if host == null or not is_instance_valid(host) or host.dead:
		return
	for e in host.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead \
				and host._flat_dist(e.global_position) <= radius + 0.3:
			# 按施法瞬间落点圆心判定(火雨是区域轰炸,不追人)
			if Vector2(e.global_position.x - _rain_center.x, e.global_position.z - _rain_center.z).length() <= radius:
				e.take_damage(UnitBase.compute_damage(host.atk, mult), host)
				if e.has_method("apply_burn"):
					# 点燃复用灼烧:每 0.5s 2 点 × 东风火伤乘区口径,刷新不叠加(apply_burn 内 maxf)
					e.apply_burn(2.0, 0.5, burn_dur)
	_vfx("ring", radius, Color(0.85, 0.45, 0.2, 0.8))

## 貂蝉 闭月(05 §2.5):单体魅惑 4s —— 倒戈攻击最近的敌方单位;结束恢复。
## 对 Boss 只踌躇不倒戈:魅惑 1.5s 走眩晕折算(Boss 免疫眩晕 → 改为 0 伤害控制的「踌躇」实现:
## 复用眩晕路径但 Boss 免疫,故对 Boss 以 apply_stun 走不通,改为 Boss 也短暂停手 ——
## 实现取舍:Boss 直接 apply_stun 不生效(免疫),因此对 Boss 记为「踌躇」用减速近似:
## 沿用 05 §1 预案口径,实现风险低、不翻转敌我判定;普通敌走真倒戈。
func _cast_charm() -> void:
	var tgt := _charm_target()
	if tgt == null:
		return
	if bool(tgt.get("boss")):
		# Boss 只踌躇:时长 1.5s 以眩晕施加(免疫则无效,尽力而为)+ 减速兜底表达「踌躇」
		var bd := float(skill_data.get("boss_duration", 1.5))
		if tgt.has_method("apply_stun"):
			tgt.apply_stun(bd)
		if tgt.has_method("apply_slow"):
			tgt.apply_slow(0.7, bd)   # -70% 移速 1.5s:踌躇读感
		_spawn_float_c(host, "踌躇!", Color(0.75, 0.4, 0.6))
	else:
		var dur := float(skill_data.get("duration", 4.0))
		if tgt.has_method("apply_defect"):
			tgt.apply_defect(dur, host)
		_spawn_float_c(host, "惑!", Color(0.75, 0.4, 0.6))
	Quips.say(host, "闭月之姿,倾倒众生", Color(0.75, 0.4, 0.6))
	_vfx("ring", 1.0, Color(0.75, 0.4, 0.6, 0.8))

## 魅惑目标:普通敌优先取最近的;无则全场最近(activate 已守非空)
func _charm_target() -> Node:
	var best: Node = null
	var near := 999.0
	for e in host.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead:
			var d: float = host._flat_dist(e.global_position)
			if d < near:
				near = d
				best = e
	return best

## 浮字小助手(host 无 battle 时静默)
func _spawn_float_c(u: Node, text: String, color: Color) -> void:
	if u != null and is_instance_valid(u) and u.has_method("_spawn_float"):
		u._spawn_float(text, color)


# ---------------------------------------------------------------- 选择几何(静态便于测试)

## 扇形选择:与朝向夹角 ≤ angle/2 且距离 ≤ radius(01 §4 关羽)
static func in_cone(origin: Vector3, facing: Vector3, point: Vector3, radius: float, angle_deg: float) -> bool:
	var to := point - origin
	to.y = 0.0
	if to.length() > radius:
		return false
	var f := Vector3(facing.x, 0.0, facing.z)
	if f.length_squared() < 0.0001:
		return true
	if to.length_squared() < 0.0001:
		return true
	return f.normalized().dot(to.normalized()) >= cos(deg_to_rad(angle_deg * 0.5))

## 点到线段 XZ 距离(赵云沿途伤害)
static func point_segment_dist_xz(p: Vector3, a: Vector3, b: Vector3) -> float:
	var pa := Vector2(p.x - a.x, p.z - a.z)
	var ba := Vector2(b.x - a.x, b.z - a.z)
	var l2 := ba.length_squared()
	if l2 < 0.0001:
		return pa.length()
	var t := clampf(pa.dot(ba) / l2, 0.0, 1.0)
	var proj := ba * t
	return pa.distance_to(proj)

func _dash_target() -> Node:
	# 6m 内最远敌人(01 §4 赵云)
	var best: Node = null
	var far := 0.0
	for e in host.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead:
			var d: float = host._flat_dist(e.global_position)
			if d <= float(skill_data.get("radius", 6.0)) and d > far:
				far = d
				best = e
	return best

## 节点有效性小助手(马超 charge 目标检查)
static func target_valid(n: Node) -> bool:
	return n != null and is_instance_valid(n) and not n.dead

func _enemies_in_radius(radius: float) -> Array:
	var out: Array = []
	for e in host.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead and host._flat_dist(e.global_position) <= radius:
			out.append(e)
	return out

func _enemies_in_cone(radius: float, angle_deg: float) -> Array:
	var out: Array = []
	for e in host.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead and \
				SkillComponent.in_cone(host.global_position, host.facing, e.global_position, radius, angle_deg):
			out.append(e)
	return out

func _allies_in_radius(radius: float) -> Array:
	var out: Array = []
	for f in host.get_tree().get_nodes_in_group("friendlies"):
		if is_instance_valid(f) and not f.dead and (radius >= 999.0 or host._flat_dist(f.global_position) <= radius):
			out.append(f)
	return out

# ---------------------------------------------------------------- 表现

## 轻量 VFX:ring(平铺圆环)/ slash(扇形),0.5s 淡出 → 对象池复用(02 §7.10,M6 接线)
func _vfx(kind: String, radius: float, color: Color, forward := false) -> void:
	if host == null or host.battle == null or not is_inside_tree():
		return
	var vfx_root := host.battle.get_node_or_null("VFX")
	if vfx_root == null:
		return
	var path := "res://assets/textures/fx/%s.png" % kind
	if not ResourceLoader.exists(path):
		return
	var sp: Sprite3D = SkillComponent._get_vfx_pool().acquire()
	if sp == null or not is_instance_valid(sp):
		sp = Sprite3D.new()
	if sp.get_parent() != null:
		sp.get_parent().remove_child(sp)
	sp.texture = load(path)
	var tex_w: float = float(sp.texture.get_width())
	sp.pixel_size = (radius * 2.2) / maxf(1.0, tex_w)
	sp.shaded = false
	sp.no_depth_test = true
	sp.modulate = color
	sp.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	if forward:
		var ang := atan2(-host.facing.x, -host.facing.z)
		sp.rotation_degrees.y = rad_to_deg(ang)
		sp.position = host.global_position + Vector3(host.facing.x, 0.05, host.facing.z) * radius * 0.55 + Vector3(0.0, 0.05, 0.0)
	else:
		sp.position = host.global_position + Vector3(0.0, 0.05, 0.0)
	vfx_root.add_child(sp)
	var tw := sp.create_tween()
	tw.tween_property(sp, "modulate:a", 0.0, 0.45).set_delay(0.1)
	tw.tween_callback(func() -> void: SkillComponent._release_vfx(sp))

static var _vfx_pool: ObjectPool = null
const VFX_POOL_CAP := 48

static func _get_vfx_pool() -> ObjectPool:
	if _vfx_pool == null:
		_vfx_pool = ObjectPool.new(
			func() -> Variant: return Sprite3D.new(),
			func(sp: Sprite3D) -> void:
				sp.texture = null
				sp.modulate = Color.WHITE
				sp.scale = Vector3.ONE
				sp.rotation_degrees = Vector3.ZERO)
	return _vfx_pool

static func _release_vfx(sp: Sprite3D) -> void:
	if sp == null or not is_instance_valid(sp):
		return
	if sp.get_parent() != null:
		sp.get_parent().remove_child(sp)
	if _vfx_pool != null and _vfx_pool.size() < VFX_POOL_CAP:
		_vfx_pool.release(sp)
	else:
		sp.free()
