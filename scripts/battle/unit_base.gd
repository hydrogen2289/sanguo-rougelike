class_name UnitBase
extends CharacterBody3D
## 单位基类:主公/武将/敌兵共用(M1;M4 扩充击退/眩晕/临时减伤/灼烧/直伤)。
## 0.2s 决策节拍 + 软分离 + 伤害公式 + 护盾池 + 死亡流程(02 §7)。
## 表现升级:Sprite3D 立牌 → 程序化拼装 Q 版 3D 低模小人(02 §4),
## 白闪改为遍历 rig 材质 lerp 到白,灰化改为逐材质取亮度,朝向改为 rig 整体转 Y。

signal died(unit: Node)

const DECISION_TICK := 0.2            # 决策节拍 0.2s(01 §3 / 02 §7.10)
const SEPARATION_RADIUS := 0.9
const KB_DURATION := 0.3              # 击退冲量 0.3s 内衰减(01 §3)
const FLASH_TIME := 0.10              # 受击白闪时长(约 0.08~0.12s)
const TURN_SPEED := 10.0              # 平滑转向速率(每秒弧度插值系数)

@export var unit_id := ""
@export var is_lord := false

var display_name := ""
var max_hp := 100.0
var hp := 100.0
var atk := 10.0
var atk_interval := 1.0               # 两次普攻间隔(秒)
var atk_range := 1.5
var move_speed := 4.0
var size_mult := 1.0
var shield := 0.0
var shield_t := 0.0
var invincible := false               # F1 调试钩子 / 赵云冲锋无敌(M4)
var dead := false
var facing := Vector3(0.0, 0.0, -1.0)
var target: Node = null
var battle: Node = null               # battle.tscn 根,用于取 Projectiles/Units 挂点

# --- M4 控制与生存状态 ---
var kb_vel := Vector3.ZERO            # 击退冲量速度
var kb_left := 0.0
var stun_left := 0.0                  # 眩晕:禁 AI 与普攻(01 §3)
var dr_percent := 0.0                 # 临时减伤(张飞当阳桥吼 2s 30%)
var dmg_taken_mult := 1.0             # 受伤乘区(魏延「反骨」1.25,03 §3.3;默认 1 不影响他人)
var burn_ticks_left := 0              # 灼烧 dot(东风附加,独立结算 01 §3/§4)
var burn_tick_dmg := 0.0
var burn_interval := 0.5
var burn_t := 0.0
var last_attacker: WeakRef = null     # 最近一次直伤来源(甘宁「锦帆」击杀移速判定,03 第三批)

var _atk_cd := 0.0
var _tick_t := 0.0
var _walk_t := 0.0
var _body_y := 0.0                    # 走路浮动基准(rig 根 y)
var _flash_tween: Tween
var _rig_scale := 1.0                 # scale_mult 语义保留(力士/Boss 体格)

@onready var rig: Node3D = $Rig

## 伤害公式(01 §3):最终伤害 = max(1, round(攻击力 × 技能倍率))
static func compute_damage(atk_v: float, mult: float) -> int:
	return maxi(1, roundi(atk_v * mult))

## 灼烧 tick 数:每 0.5s 受 2 点、持续 3s → 6 tick(01 §4;静态便于 test_formulas)
static func burn_tick_count(duration: float, interval: float) -> int:
	if interval <= 0.0:
		return 0
	return int(ceil(duration / interval))

func setup_from_data(d: Dictionary) -> void:
	unit_id = str(d.get("id", unit_id))
	display_name = str(d.get("name", unit_id))
	max_hp = RunState.stat(float(d.get("hp", 100)), "maxhp")
	if is_lord:
		max_hp += RunState.lord_maxhp_bonus()
	hp = max_hp
	atk = RunState.stat(float(d.get("atk", 5)), "atk")
	atk_interval = 1.0 / maxf(0.1, float(d.get("atk_speed", 1.0)))
	atk_range = float(d.get("range", 1.5))
	move_speed = RunState.stat(float(d.get("move_speed", 4.0)), "move")
	if is_lord:
		move_speed *= RunState.lord_move_mult()

func _ready() -> void:
	add_to_group("units")
	# MeleeRange 形状按本单位攻距重建(子资源为同场景实例共享,不能直接改)
	var shape_node: CollisionShape3D = $MeleeRange/MeleeShape
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(0.5, atk_range)
	shape_node.shape = sphere

## 程序化拼装 3D 小人(替代原立牌贴图;保留函数名以最小化调用方改动)。
## rig 已在 tscn 中由 build 脚本挂好,此处只做 scale_mult 体格与浮动基准。
func apply_visual(scale_mult := 1.0) -> void:
	_rig_scale = scale_mult
	rig.scale = Vector3.ONE * scale_mult
	_body_y = 0.0

## 遍历 rig 收集 MeshInstance3D(rig 缺失时返回空)
func rig_meshes() -> Array:
	if rig == null:
		return []
	return rig.find_children("*", "MeshInstance3D", true, false)

## 受击白闪:所有 mesh albedo 临时 lerp 到白再还原(替代 hit_flash shader 贴 Sprite3D)
func _hit_flash() -> void:
	if not is_inside_tree():
		return
	var meshes := rig_meshes()
	if meshes.is_empty():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
		for m in meshes:   # 上次闪烁未收尾,先还原基色
			_set_mesh_tint(m, 0.0)
	for m in meshes:
		_set_mesh_tint(m, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_flash_strength, 1.0, 0.0, FLASH_TIME)

## t:1.0 全白 → 0.0 原色(按 meta base_albedo 还原)
func _set_flash_strength(t: float) -> void:
	for m in rig_meshes():
		_set_mesh_tint(m, t)

func _set_mesh_tint(m: MeshInstance3D, t: float) -> void:
	var mat: StandardMaterial3D = m.material_override
	if mat == null:
		return
	var base: Color = m.get_meta("base_albedo", mat.albedo_color)
	mat.albedo_color = base.lerp(Color.WHITE, t)

## 灰化(阵亡):所有材质 albedo 转灰度(取亮度)并压到 0.45 明度,原 0.45 灰效果
func _set_grayscale() -> void:
	for m in rig_meshes():
		var mat: StandardMaterial3D = m.material_override
		if mat == null:
			continue
		var c := mat.albedo_color
		var l: float = (c.r + c.g + c.b) / 3.0 * 0.45   # 亮度近似( Godot Color 无 luminance)
		mat.albedo_color = Color(l, l, l, c.a)

## 死亡退场公共实现:沉入地面 + 缩放到 0 后自毁(子类死亡/退场流程复用)
func rig_sink_out(dur := 0.9) -> Tween:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(rig, "position:y", -0.55, dur).set_ease(Tween.EASE_IN)
	tw.tween_property(rig, "scale", Vector3.ONE * 0.05 * _rig_scale, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)
	return tw

func _physics_process(delta: float) -> void:
	if dead:
		return
	_tick_t += delta
	if _tick_t >= DECISION_TICK:
		_tick_t -= DECISION_TICK
		_tick()
	_atk_cd = maxf(0.0, _atk_cd - delta)
	_tick_shield(delta)
	_tick_burn(delta)
	_tick_controls(delta)
	_move(delta)
	_animate(delta)

## 0.2s 决策节拍:索敌等,由子类覆写
func _tick() -> void:
	pass

## 每帧移动,由子类覆写(眩晕时不移动不攻击,由子类检查 stun_left)
func _move(delta: float) -> void:
	pass

func _animate(delta: float) -> void:
	if velocity.length_squared() > 0.5:
		_walk_t += delta * velocity.length()
		rig.position.y = _body_y + absf(sin(_walk_t * 3.0)) * 0.05
	else:
		rig.position.y = _body_y
	# 平滑转向:rig 面朝本地 +Z,rotation.y = atan2(dir.x, dir.z) 时 +Z 恰指向 dir
	var target_yaw := atan2(facing.x, facing.z)
	rig.rotation.y = lerp_angle(rig.rotation.y, target_yaw, minf(1.0, TURN_SPEED * delta))

# ---------------------------------------------------------------- 控制(M4)

## 击退:位移冲量,KB_DURATION 内线性衰减;受击退抗性削减(01 §3)
func knockback_resist() -> float:
	return 0.0

func apply_knockback(dir: Vector3, dist: float) -> void:
	if dead or dist <= 0.01:
		return
	var eff := dist * (1.0 - clampf(knockback_resist(), 0.0, 1.0))
	if eff <= 0.01:
		return
	var d := dir
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return
	kb_vel = d.normalized() * eff / (KB_DURATION * 0.5)   # 线性衰减总位移 ≈ eff
	kb_left = KB_DURATION

## 眩晕:禁 AI 与普攻(01 §3);Boss 免疫由子类覆写 stun_immune
func stun_immune() -> bool:
	return false

func apply_stun(duration: float) -> void:
	if dead or stun_immune():
		return
	stun_left = maxf(stun_left, duration)

func _tick_controls(delta: float) -> void:
	if kb_left > 0.0:
		global_position += kb_vel * delta
		kb_left -= delta
		if kb_left <= 0.0:
			kb_left = 0.0
			kb_vel = Vector3.ZERO
		_clamp_to_arena()
	if stun_left > 0.0:
		stun_left = maxf(0.0, stun_left - delta)

# ---------------------------------------------------------------- 战斗

func take_damage(amount: float, from: Node = null) -> void:
	if dead or invincible:
		return
	if from != null and is_instance_valid(from):
		last_attacker = weakref(from)      # 记录直伤来源(锦帆等击杀触发类被动判定)
	var left := amount
	if dr_percent > 0.0:
		left *= (1.0 - clampf(dr_percent, 0.0, 0.9))   # 临时减伤(张飞吼后 2s)
	left *= dmg_taken_mult                              # 受伤乘区(魏延反骨 ×1.25,03 §3.3)
	if is_lord:
		left *= RunState.lord_damage_taken_mult()      # 双股剑等主公减伤(01 §8)
	if left <= 0.0:
		return
	if shield > 0.0:
		# 护盾先于 HP 扣除(01 §4)
		var absorbed := minf(shield, left)
		shield -= absorbed
		left -= absorbed
		_spawn_float("盾-%d" % roundi(absorbed), Color(0.75, 0.85, 1.0))
	if left > 0.0:
		hp -= left
		_spawn_float(str(roundi(left)), Color.WHITE)
		Sfx.play("hit", -12.0)             # 命中低频 thud(M6;Sfx 内限频防刷)
	_hit_flash()
	if hp <= 0.0:
		hp = 0.0
		_die()

## 无视护盾/减伤直接扣当前 HP(事件「鞭打督邮」A,01 §9)。
## 不致死(下限 1 HP):事件代价是权衡而非处刑。
func lose_hp_direct(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	hp = maxf(1.0, hp - amount)
	_spawn_float("-%d" % roundi(amount), Color(0.85, 0.45, 0.28))

func heal(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	# 青囊书:全部治疗效果 +30%(01 §8)
	var real := minf(amount * RunState.heal_mult(), max_hp - hp)
	hp += real
	if real >= 1.0:
		_spawn_float("+" + str(roundi(real)), Color(0.56, 0.68, 0.55))

func give_shield(amount: float, duration: float) -> void:
	# 青囊书:护盾效果同样 +30%(01 §8)
	shield = maxf(shield, amount * RunState.heal_mult())
	shield_t = maxf(shield_t, duration)

## 灼烧 dot(东风附加):每 0.5s 受 tick_dmg、持续 duration(01 §4),独立于普攻结算
func apply_burn(tick_dmg: float, tick_interval: float, duration: float) -> void:
	if dead:
		return
	burn_tick_dmg = maxf(burn_tick_dmg, tick_dmg)
	burn_interval = maxf(0.05, tick_interval)
	burn_t = 0.0
	burn_ticks_left = maxi(burn_ticks_left, UnitBase.burn_tick_count(duration, burn_interval))

func _tick_burn(delta: float) -> void:
	if dead or burn_ticks_left <= 0:
		return
	burn_t += delta
	while burn_t >= burn_interval and burn_ticks_left > 0 and not dead:
		burn_t -= burn_interval
		burn_ticks_left -= 1
		hp -= burn_tick_dmg
		_spawn_float("火%d" % roundi(burn_tick_dmg), Color(0.85, 0.45, 0.2))
		if hp <= 0.0:
			hp = 0.0
			_die()
			return

## 关羽拖刀计斩杀入口:清 HP + 金字「斩!」+ 白闪,走常规死亡流程(掉军资/计击杀)
func executed_by(by: Node = null) -> void:
	if dead:
		return
	_spawn_float("斩!", Color(0.79, 0.66, 0.42))
	_hit_flash()
	hp = 0.0
	_die()

func _tick_shield(delta: float) -> void:
	if shield_t > 0.0:
		shield_t -= delta
		if shield_t <= 0.0:
			shield_t = 0.0
			shield = 0.0           # 护盾到期清零(02 §7.4)

func _spawn_float(text: String, color: Color) -> void:
	if battle == null or not is_inside_tree():
		return
	var units_root := battle.get_node_or_null("Units")
	if units_root != null:
		FloatText.spawn(units_root, global_position + Vector3(0.0, 1.9, 0.0), text, color)

## 索敌:group 扫描代替物理查询(02 §7.10)
func acquire_target(group_name: String, max_dist: float) -> Node:
	var best: Node = null
	var best_d := max_dist
	for u in get_tree().get_nodes_in_group(group_name):
		if u == self or not is_instance_valid(u) or u.dead:
			continue
		var d := _flat_dist(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best

func collect_separation_positions(group_name: String) -> Array:
	var arr: Array = []
	for u in get_tree().get_nodes_in_group(group_name):
		if u == self or not is_instance_valid(u) or u.dead:
			continue
		arr.append(u.global_position)
	return arr

## 跨阵营软分离同样生效(友军间/敌间/跨阵营一律软分离,02 §3)
func separation_push() -> Vector3:
	return Formation.separation(global_position, collect_separation_positions("units"), UnitBase.SEPARATION_RADIUS)

func _flat_dist(p: Vector3) -> float:
	return Vector2(global_position.x - p.x, global_position.z - p.z).length()

## 朝向:记录 facing,rig 平滑转向在 _animate 中统一插值(不再 flip)
func face_towards(p: Vector3) -> void:
	var to := p - global_position
	to.y = 0.0
	if to.length_squared() > 0.001:
		facing = to.normalized()

func _clamp_to_arena() -> void:
	var p := global_position
	p.x = clampf(p.x, -19.4, 19.4)
	p.z = clampf(p.z, -19.4, 19.4)
	global_position = p

## 死亡流程,由子类覆写(友军灰化倒地/敌兵淡出,02 §7.7)
func _die() -> void:
	if dead:
		return
	dead = true
	died.emit(self)
