class_name HeroUnit
extends UnitBase
## 武将(主公与跟随武将共用)(M1;M4 加个性机制/refresh_stats/普攻命中回调)。
## 跟随 AI:formation 后方扇形 + 软分离 0.9m + 归队加速(02 §7.1);
## 索敌普攻:0.2s 节拍取 8m 内最近敌人,近战直伤 / 远程走 projectile(01 §3)。

const TARGET_ACQUIRE_DIST := 8.0   # 自动索敌 8m 内最近敌人(01 §3)
const RANGED_THRESHOLD := 2.5      # 攻距超过此值走弹道

var formation_index := 0
var lord: Node3D = null
var hero_data: Dictionary = {}
var skill_comp: Node = null

# --- M4 个性机制状态(01 §4) ---
var _trait_data: Dictionary = {}
var _enraged := false
var _roar_t := 0.0
var _aura_t := 0.0
var _base_atk_interval := 1.0
var _base_atk_range := 1.5
# --- 魏延「反骨/狂骨」(03 §3.3,数值占位) ---
var _fangu_applied := false
var _frenzy_mult := 0.0        # >0 = 狂骨攻速 buff 生效中(skill_component 驱动到期还原)
# --- 03 第三批个性机制状态(05 §2)---
var _backstab_mult := 0.0      # 甘宁背袭:>0 = 下次普攻一次性乘区(arm_backstab 武装/consume 清零)
var _jinfan_mult := 0.0        # 甘宁锦帆:>0 = 击杀移速 buff 生效中
var _luoyi_on := false         # 许褚裸衣:HP<50% 减伤 30% 生效中(_tick_trait 切换)
# --- M8 出场基础值(P1 修复,02 §5.4):表值 × 养成乘区,实例化时算一次并缓存 ---
# refresh_stats() 一律以此二者为 base 再进 RunState.stat() 修饰符体系;
# 绝不在 refresh 内重算/重复乘 grow。取「表值 × HeroSave.factors()」而非
# unit_base.setup_from_data() 已写好的 max_hp/atk —— 后者已含 RunState.stat 结果,
# 直接拿来当 base 会把上一次的 stat 结果再乘一次(双乘 stat),故独立算纯基础值。
var _base_max_hp := 0.0
var _base_atk := 0.0

func _ready() -> void:
	add_to_group("friendlies")
	hero_data = DataDB.hero_by_id(unit_id)
	_trait_data = hero_data.get("trait", {})
	setup_from_data(hero_data)
	_cache_base_stats()                 # 归一:setup 后、首次 refresh 前算一次出场基础值
	refresh_stats()                    # 应用 RunState 修饰符 + 个体加成(以缓存值为 base)
	super()                            # UnitBase._ready(group/MeleeRange)
	skill_comp = get_node_or_null("Skill")
	if skill_comp != null:
		skill_comp.setup(self)
	_apply_rig()
	# 遗物/强化/事件修饰符变动 → 存量单位即时刷新(01 §8/§9)
	RunState.mods_changed.connect(refresh_stats)
	# 击杀触发类被动(03 第三批):周瑜「英物」点燃杀减 CD / 甘宁「锦帆」击杀移速
	var tt := str(_trait_data.get("type", ""))
	if tt == "burn_kill_cd" or tt == "kill_burst_move":
		EventBus.enemy_died.connect(_on_enemy_died_passive)

## 击杀触发类被动统一入口(按词条类型分发)
func _on_enemy_died_passive(unit: Node) -> void:
	if dead or skill_comp == null or not is_instance_valid(skill_comp):
		return
	if unit == null or not is_instance_valid(unit):
		return
	match str(_trait_data.get("type", "")):
		"burn_kill_cd":
			# 周瑜「英物」(05 §2.4 占位):被点燃的敌人死亡 → 火雨 CD -1s(下限 0)
			var burning := int(unit.get("burn_ticks_left")) if "burn_ticks_left" in unit else 0
			if burning > 0:
				skill_comp.cd_left = maxf(0.0, skill_comp.cd_left - float(_trait_data.get("cd_reduce", 1.0)))
		"kill_burst_move":
			# 甘宁「锦帆」(05 §2.3 占位):击杀(最后直伤者是本武将)→ 移速 +20% 持续 3s,刷新不叠加
			var la = unit.get("last_attacker")
			if la != null and la.get_ref() == self:
				apply_jinfan_buff(float(_trait_data.get("move_pct", 0.20)))
				if skill_comp != null and "_jinfan_left" in skill_comp:
					skill_comp._jinfan_left = float(_trait_data.get("duration", 3.0))
				_spawn_float("锦帆!", Color(0.75, 0.4, 0.3))

## 表现升级:程序化拼装 3D 小人(不再加载 units/*.png 当人物本体,贴图仅作 UI 图标)
func _apply_rig() -> void:
	apply_visual(1.0)

func bind_lord(l: Node3D) -> void:
	lord = l

## 出场基础值归一(M8 P1,02 §5.4):表值 × HeroSave.factors(unit_id),只算一次。
## 与 unit_base.setup_from_data() 的 grow 同源,但不含 RunState.stat —— 供 refresh_stats
## 反复作为纯 base 使用。refresh 内不再触碰 HeroSave(避免战斗层读存档耦合,审计 F-05)。
func _cache_base_stats() -> void:
	if hero_data.is_empty():
		_base_max_hp = 100.0
		_base_atk = 5.0
		return
	var grow := HeroSave.factors(unit_id)
	_base_max_hp = float(hero_data.get("hp", 100)) * grow
	_base_atk = float(hero_data.get("atk", 5)) * grow

## 重新计算属性(RunState 修饰符变动:遗物/强化/事件,01 §8/§9)。
## max_hp 增加时同步加到当前 HP;不整活满血。
## M8 P1:一律以缓存的「出场基础值」为 base 再进 RunState.stat(),养成乘区不再被覆盖回 1.0。
func refresh_stats() -> void:
	if hero_data.is_empty():
		return
	var d := hero_data
	var old_max := max_hp
	max_hp = RunState.stat(_base_max_hp, "maxhp")
	if is_lord:
		max_hp += RunState.lord_maxhp_bonus()
	atk = RunState.stat(_base_atk, "atk") * RunState.hero_atk_mult(unit_id)
	atk_interval = 1.0 / maxf(0.1, float(d.get("atk_speed", 1.0)))
	atk_range = float(d.get("range", 1.5))
	move_speed = RunState.stat(float(d.get("move_speed", 4.0)), "move")
	if is_lord:
		move_speed *= RunState.lord_move_mult()
	_base_atk_interval = atk_interval
	_base_atk_range = atk_range
	_apply_enrage_multipliers()
	_apply_fangu_passive()
	if _frenzy_mult > 0.0:
		atk_interval = _base_atk_interval / _frenzy_mult   # 狂骨攻速 buff 跨 refresh_stats 保持
	if _jinfan_mult > 0.0:
		move_speed *= _jinfan_mult                          # 锦帆移速 buff 跨 refresh_stats 保持
	if old_max > 0.0 and max_hp > old_max:
		hp += max_hp - old_max
	hp = minf(hp, max_hp)
	_sync_run_state_hp()

## 魏延「反骨」(03 §3.3,占位):攻击 ×1.4、受伤 ×1.25(第一个「双刃」武将)。
## 攻击乘区在 refresh_stats 尾部叠加(不进 RunState mods,避免污染全队口径);
## 受伤乘区走 take_damage 内 dmg_taken_mult 钩子(UnitBase 通用字段,敌方无此被动时为 1)。
func _apply_fangu_passive() -> void:
	var ttype := str(_trait_data.get("type", ""))
	if ttype != "fangu":
		if _fangu_applied:                 # 词条被移除(理论不发生)时还原
			atk /= float(_trait_data.get("atk_mult", 1.4))
			dmg_taken_mult = 1.0
			_fangu_applied = false
		return
	if _fangu_applied:
		return                             # 只叠加一次(refresh_stats 可能多次进入)
	var am := float(_trait_data.get("atk_mult", 1.4))
	atk *= am
	dmg_taken_mult = float(_trait_data.get("dmg_taken_mult", 1.25))
	_fangu_applied = true

## 狂骨攻速 buff(skill_component 持续期驱动,03 §3.3 占位 ×1.6)
func apply_frenzy_buff(speed_mult: float) -> void:
	_frenzy_mult = maxf(_frenzy_mult, speed_mult)
	atk_interval = _base_atk_interval / _frenzy_mult
	_spawn_float("狂骨!", Color(0.85, 0.45, 0.28))

func clear_frenzy_buff() -> void:
	if _frenzy_mult <= 0.0:
		return
	_frenzy_mult = 0.0
	atk_interval = _base_atk_interval

# ---------------------------------------------------------------- 03 第三批个性机制(05 §2,数值占位)

## 甘宁「锦帆」(05 §2.3 占位):击杀敌人后移速 +20% 持续 3s,可叠?否 —— 刷新不叠加。
## 乘区在 refresh_stats 尾部保持(不进 RunState mods);skill_component 计时到期还原。
func apply_jinfan_buff(move_pct: float) -> void:
	var new_mult := 1.0 + maxf(0.0, move_pct)
	if _jinfan_mult <= 0.0:
		move_speed *= new_mult   # 首次叠加:即时生效
	else:
		move_speed = move_speed / _jinfan_mult * new_mult   # 刷新:按旧乘区先还原再乘新
	_jinfan_mult = new_mult

func clear_jinfan_buff() -> void:
	if _jinfan_mult <= 0.0:
		return
	move_speed /= _jinfan_mult
	_jinfan_mult = 0.0

## 甘宁「背袭」:dash 落点武装(skill_component 驱动);下次普攻一次性 ×backstab_mult 后清零
func arm_backstab(mult: float) -> void:
	_backstab_mult = maxf(_backstab_mult, mult)
	_spawn_float("背袭!", Color(0.75, 0.4, 0.3))

## 消耗背袭乘区(普攻命中后);返回本次实际乘区(未武装返回 1.0)
func consume_backstab() -> float:
	var m := _backstab_mult
	if m > 0.0:
		_backstab_mult = 0.0
	return m if m > 0.0 else 1.0

## 05 §3 换人规则 1:被换者离队 —— HP/buff/被动全回收,不入阵亡灰化流程,可再抽回。
## 回收口径:狂骨攻速/锦帆移速/背袭/裸衣减伤/狂化全部还原;反骨乘区随节点销毁消失;
## 不 mark_casualty(不折将)、不发 hero_died;退场动画复用敌兵 rig 淡出(rig_sink_out)。
func leave_team() -> void:
	if dead:
		return
	dead = true                      # 让索敌/AI 立即停手(复用 dead 守卫,不走 _die 的阵亡登记)
	clear_frenzy_buff()
	clear_jinfan_buff()
	_backstab_mult = 0.0
	_luoyi_on = false
	dr_percent = 0.0
	apply_enrage_off()
	remove_from_group("friendlies")
	remove_from_group("units")
	collision_layer = 0
	set_physics_process(false)
	if skill_comp != null and is_instance_valid(skill_comp):
		skill_comp.set_physics_process(false)
	if OS.is_debug_build():
		print("[Hero] %s 离队入候选池(替换,非阵亡)" % display_name)
	if is_inside_tree():
		rig_sink_out(0.5)            # 复用敌兵退场淡出;「折将灰化倒地」不复用(不是阵亡)
	else:
		queue_free.call_deferred()

## 张辽「止啼」/ 貂蝉「连环」共用口径(05 §1/§2):敌人处于受控态(恐惧/嘲讽/倒戈/眩晕)时
## 对其伤害 +15%。静态便于 test_formulas 直测。
static func controlled_amp(applier_trait: Dictionary, target_controlled: bool) -> float:
	if not target_controlled:
		return 1.0
	if str(applier_trait.get("type", "")) == "controlled_amp":
		return 1.0 + float(applier_trait.get("dmg_amp", 0.15))
	return 1.0

## 许褚「裸衣」(05 §2.2 占位):HP < 50% 时自身减伤 30%(进入/退出由 _tick_trait 切换)。
## 减伤走 dr_percent 通用字段(张飞当阳桥吼同口径),跨 refresh_stats 不受影响。
static func luoyi_should_on(hp_ratio: float, threshold := 0.5) -> bool:
	return hp_ratio < threshold

func _sync_run_state_hp() -> void:
	for m in RunState.team:
		if str(m.hero_id) == unit_id:
			m["max_hp"] = max_hp
			m["hp"] = hp

func _apply_enrage_multipliers() -> void:
	if not _enraged:
		return
	atk_interval = _base_atk_interval / maxf(1.0, float(_trait_data.get("atk_speed_mult", 1.4)))
	atk_range = _base_atk_range * maxf(1.0, float(_trait_data.get("range_mult", 1.3)))

func _move(delta: float) -> void:
	if is_lord:
		_move_by_input(delta)          # 保底:主公移动走输入
	else:
		_move_follow(delta)

## 主公输入移动( PlayerLord 覆写后的公共实现)
func _move_by_input(delta: float) -> void:
	var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3(iv.x, 0.0, iv.y)
	var sep := separation_push()
	if dir.length_squared() > 0.001:
		velocity = dir.normalized() * move_speed + sep
		facing = dir.normalized()
	else:
		velocity = sep
	move_and_slide()
	_clamp_to_arena()

## 跟随 AI:队形槽位 + 归队加速 + 软分离(02 §7.1)
func _move_follow(delta: float) -> void:
	if lord == null or not is_instance_valid(lord):
		velocity = separation_push()
		move_and_slide()
		return
	var followers := 0
	for h in get_tree().get_nodes_in_group("friendlies"):
		if not h.is_lord and not h.dead:
			followers += 1
	var tp: Vector3 = lord.global_position + Formation.slot_offset(formation_index, followers, lord.facing)
	var to_tp := tp - global_position
	to_tp.y = 0.0
	var lord_dist := _flat_dist(lord.global_position)
	var sp := move_speed * (1.5 if lord_dist > Formation.RETURN_DIST else 1.0)
	var sep := separation_push()
	if to_tp.length() > 0.25:
		velocity = to_tp.normalized() * sp + sep
		facing = to_tp.normalized()
	else:
		velocity = sep
	move_and_slide()
	_clamp_to_arena()

func _tick() -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		target = acquire_target("enemies", TARGET_ACQUIRE_DIST)
	_tick_trait()
	_try_attack()

## 个性机制 0.2s 节拍:光环(仁政/青囊)与燕人狂怒(01 §4)
func _tick_trait() -> void:
	if dead:
		return
	var ttype := str(_trait_data.get("type", ""))
	if ttype == "aura":
		_aura_t += DECISION_TICK
		if _aura_t >= 1.0:
			var amt := float(_trait_data.get("heal_per_sec", 0.8)) * _aura_t
			var radius := float(_trait_data.get("radius", 3.0))
			_aura_t -= 1.0
			for f in get_tree().get_nodes_in_group("friendlies"):
				if is_instance_valid(f) and not f.dead and _flat_dist(f.global_position) <= radius:
					f.heal(amt)    # heal() 内部 × 青囊书 heal_mult
	elif ttype == "enrage":
		_tick_enrage()
	elif ttype == "lowhp_dr":
		# 许褚「裸衣」(05 §2.2 占位):HP < 50% 减伤 30%;dr_percent 与张飞吼共用,只在本被动内写
		var on := HeroUnit.luoyi_should_on(hp / maxf(1.0, max_hp), float(_trait_data.get("hp_ratio", 0.5)))
		if on and not _luoyi_on:
			_luoyi_on = true
			dr_percent = float(_trait_data.get("dr", 0.30))
			_spawn_float("裸衣!", Color(0.85, 0.6, 0.3))
		elif not on and _luoyi_on:
			_luoyi_on = false
			dr_percent = 0.0

## 燕人狂怒:HP<35% 狂化(攻速+40% 攻距+30%,每 5s 吼退 2m 内敌 2m);HP≥50% 解除(01 §4)
func _tick_enrage() -> void:
	var ratio := hp / maxf(1.0, max_hp)
	var enter := float(_trait_data.get("enter_ratio", 0.35))
	var exit := float(_trait_data.get("exit_ratio", 0.50))
	if not _enraged and ratio < enter:
		_enraged = true
		_roar_t = 0.0
		_apply_enrage_multipliers()
		_spawn_float("狂", Color(0.71, 0.29, 0.23))
		Quips.say(self, "燕人张飞在此!")
	elif _enraged and ratio >= exit:
		_enraged = false
		_roar_t = 0.0
		apply_enrage_off()
	if _enraged:
		_roar_t += DECISION_TICK
		if _roar_t >= float(_trait_data.get("roar_interval", 5.0)):
			_roar_t -= float(_trait_data.get("roar_interval", 5.0))
			_roar()

func apply_enrage_off() -> void:
	_enraged = false
	atk_interval = _base_atk_interval
	atk_range = _base_atk_range

## 狂化吼退:2m 内敌兵击退 2m(01 §4)
func _roar() -> void:
	var radius := float(_trait_data.get("roar_radius", 2.0))
	var dist := float(_trait_data.get("roar_knockback", 2.0))
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead and _flat_dist(e.global_position) <= radius:
			e.apply_knockback(e.global_position - global_position, dist)

## 拖刀计可否斩杀(静态便于 test_formulas):普通敌兵当前 HP ≤ 最大 15%,Boss 免疫(01 §4)
static func can_execute_target(target_hp: float, target_max_hp: float, target_boss: bool, threshold := 0.15) -> bool:
	if target_boss or target_hp <= 0.0:
		return false
	return target_hp <= target_max_hp * threshold

static func enrage_should_enter(hp_ratio: float, enter := 0.35) -> bool:
	return hp_ratio < enter

static func enrage_should_exit(hp_ratio: float, exit := 0.50) -> bool:
	return hp_ratio >= exit

func _try_attack() -> void:
	if stun_left > 0.0:
		return
	if target == null or not is_instance_valid(target) or target.dead:
		return
	if _atk_cd > 0.0:
		return
	var d := _flat_dist(target.global_position)
	if d > atk_range + 0.4:
		return
	_atk_cd = atk_interval
	face_towards(target.global_position)
	if atk_range > RANGED_THRESHOLD:
		# 远程:命中效果(灼烧/斩杀)移到弹道真正命中时经 shooter 回调结算(P2-②);
		# 出手只生成弹道,不再直调命中回调(原实现会挂空 + 与弹道侧双重附加)
		_spawn_projectile()
	else:
		target.take_damage(_attack_damage(target), self)
		Sfx.play("slash", -10.0)      # 挥砍(M6;Sfx 内限频防刷)
		_attack_anim()
		_post_attack_hit(target)      # 近战直伤命中即回调,行为不变

## 普攻伤害合成:背袭一次性乘区(甘宁,05 §2.3)+ 受控增伤共用乘区(止啼/连环,05 §1)
func _attack_damage(target: Node) -> int:
	var amp := consume_backstab()
	var controlled := false
	if target != null and is_instance_valid(target) and target.has_method("is_controlled"):
		controlled = bool(target.is_controlled())
	amp *= HeroUnit.controlled_amp(_trait_data, controlled)
	return UnitBase.compute_damage(atk, amp)
## 普攻命中回调(02 §7.4):拖刀计斩杀 + 东风灼烧附加(01 §4)。
## 近战在 _try_attack 直伤后调用;远程由 projectile 真正命中时回调(_on_body_entered)。
func _post_attack_hit(target: Node) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		return
	var ttype := str(_trait_data.get("type", ""))
	if ttype == "execution":
		var thr := float(_trait_data.get("threshold_ratio", 0.15))
		if HeroUnit.can_execute_target(float(target.hp), float(target.max_hp), bool(target.get("boss")), thr):
			target.executed_by(self)
			EventBus.executed_kill.emit()   # 全屏「斩!」白闪(01 §12,M6)
			Quips.say(self, "鼠辈,安敢挡我")
			return
	# 借东风:天气为全体普攻附加灼烧(已拍板;01 §4 说明 2)
	var wm := get_tree().get_first_node_in_group("weather_manager")
	if wm != null:
		wm.try_apply_burn(target)

func _spawn_projectile() -> void:
	if battle == null:
		return
	var proj_scene: PackedScene = load("res://scenes/units/projectile.tscn")
	if proj_scene == null:
		return
	var proj := proj_scene.instantiate()
	var to: Vector3 = target.global_position - global_position
	var dir := Vector3(to.x, 0.0, to.z).normalized()
	proj.setup(dir, 10.0, UnitBase.compute_damage(atk, 1.0), true, self)   # 携带射手:命中回调用
	battle.get_node("Projectiles").add_child(proj)
	proj.global_position = global_position + Vector3(0.0, 1.0, 0.0)

func _attack_anim() -> void:
	if not is_inside_tree() or target == null or not is_instance_valid(target):
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	var dir: Vector3 = to.normalized() * 0.15 if to.length_squared() > 0.001 else Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(rig, "position", Vector3(dir.x, 0.0, dir.z), 0.06)
	tw.tween_property(rig, "position", Vector3(0.0, 0.0, 0.0), 0.10)

## 死亡:武将灰化倒地 2s 后移除,本局退场不可复活(01 §5 / 02 §7.7)
func _die() -> void:
	super()
	if OS.is_debug_build():
		print("[Hero] %s 阵亡" % display_name)
	remove_from_group("friendlies")
	remove_from_group("units")
	collision_layer = 0
	set_physics_process(false)
	RunState.mark_casualty(unit_id)
	EventBus.hero_died.emit(unit_id)
	if is_lord:
		# 主公阵亡事件 → 失败结算(WaveDirector 挂 M3)
		EventBus.lord_died.emit()
	if is_inside_tree():
		_set_grayscale()                                   # 灰化(取亮度,原 0.45 灰)
		rig.rotation.z = PI * 0.5                          # 倒地
		rig.position.y = 0.15
		var tw := create_tween()
		tw.tween_interval(1.4)
		tw.tween_property(rig, "scale", Vector3.ONE * _rig_scale * 0.05, 0.4)   # 缩到 0
		tw.tween_callback(queue_free)
	else:
		queue_free.call_deferred()
