class_name SkillComponent
extends Node
## 技能组件(M4):CD 计时 + activate() 分发 + 7 种数据驱动原型(02 §7.3,数值 01 §4)。
## 原型:shield(刘备)/ cone(关羽)/ nova(张飞)/ dash(赵云)/
##       weather(诸葛亮)/ heal_all(华佗)/ triple_nova(吕布)。
## 吕布「不受令」:activate 时 30% 概率延迟 3s 生效,延迟生效每段伤害 ×1.5。

var host: UnitBase = null
var skill_data: Dictionary = {}
var cd_left := 0.0
var delayed_left := -1.0      # ≥0 → 「不受令」延迟倒计时(HUD 红闪读此值)
var delayed_mult := 1.0
var _pulse_queue: Array = []  # 吕布三段斩后续段 [{t, radius, mult}]:_process 节拍驱动(P2-①,弹窗暂停期冻结)

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
	# dash 需 6m 内有目标,无目标不放(不空耗 CD)
	if str(skill_data.get("type", "")) == "dash" and _dash_target() == null:
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
