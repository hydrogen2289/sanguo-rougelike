class_name BossHuaxiong
extends EnemyUnit
## Boss 华雄(M5,01 §6 技能组 / §10 出场演出):
## - 挥砍:近身 2m 单体 20 伤害,间隔 1.5s(基础 AI,attack_range 读表);
## - 冲锋:锁定主公当前位置,前摇 0.8s(地面红色警示痕)后直线冲 8m,
##   命中 16 伤害 + 击退 2m,CD 8s;
## - 震地:前摇 1.0s 后以自身为圆心、半径 4m 造成 16 伤害 + 击退 3m,CD 12s;
## - 二阶段(HP < 50%):移速/攻速 +25%,每 12s 召唤西凉亲卫 ×4;
## - 免疫击退/眩晕/斩杀(数据在 enemies.json:kb_resist=1 / immune_* / boss 标记)。
## 警示痕用 PlaneMesh + 程序化贴图(运行时生成一次,静态缓存,固定形状无随机)。

const CHARGE_TELEGRAPH := 0.8     # 冲锋前摇(01 §6)
const SLAM_TELEGRAPH := 1.0       # 震地前摇(01 §6)
const CHARGE_DIST := 8.0          # 冲锋距离 8m
const CHARGE_HIT_WIDTH := 1.3     # 冲锋命中带宽(路径两侧)
const CHARGE_SPEED := 16.0        # 冲锋移动速度(8m ≈ 0.5s)
const CHARGE_TRIGGER_RANGE := 14.0
const SLAM_RADIUS := 4.0
const SLAM_TRIGGER_RANGE := 4.5
const CHARGE_KB := 2.0
const SLAM_KB := 3.0
const CHARGE_CD := 8.0
const SLAM_CD := 12.0
const FIRST_CHARGE_DELAY := 4.0   # 出场后首次技能缓冲(平衡口径,收口上报)
const FIRST_SLAM_DELAY := 7.0
const ARENA_HALF := 19.0

enum SkillState { NONE, CHARGE_WINDUP, CHARGING, SLAM_WINDUP }

var skill_state: SkillState = SkillState.NONE
var phase2 := false

var _charge_cd := FIRST_CHARGE_DELAY
var _slam_cd := FIRST_SLAM_DELAY
var _telegraph_left := 0.0
var _dash_left := 0.0
var _dash_dir := Vector3.ZERO
var _dash_target_pos := Vector3.ZERO
var _charge_hit_set: Array = []
var _summon_t := 0.0
var _base_move_speed := 2.6
var _base_atk_interval := 1.5
var _warn: MeshInstance3D = null

static var _tex_circle: ImageTexture
static var _tex_line: ImageTexture

# ---------------------------------------------------------------- 静态几何/判定(纯函数,test_formulas 直测)

## 冲锋终点:从 from 朝 locked 方向,最多 max_dist,夹回战场内(01 §6 直线冲 8m)
static func charge_end(from: Vector3, locked: Vector3, max_dist: float) -> Vector3:
	var to := locked - from
	to.y = 0.0
	var d := to.length()
	var dir := to.normalized() if d > 0.001 else Vector3(0.0, 0.0, -1.0)
	var dist := minf(d, max_dist)
	var end := from + dir * dist
	end.x = clampf(end.x, -ARENA_HALF, ARENA_HALF)
	end.z = clampf(end.z, -ARENA_HALF, ARENA_HALF)
	return end

## 冲锋命中:点到冲锋线段 XZ 距离 ≤ 命中带宽
static func charge_hits(p0: Vector3, p1: Vector3, point: Vector3) -> bool:
	return SkillComponent.point_segment_dist_xz(point, p0, p1) <= CHARGE_HIT_WIDTH

## 二阶段进入判定:HP 严格低于 phase2 比例(01 §6 HP < 50%)
static func phase2_should_enter(hp: float, max_hp: float, ratio := 0.5) -> bool:
	if max_hp <= 0.0:
		return false
	return hp / max_hp < ratio

## 召唤站位:以 center 为圆心均匀环形 4 点(半径 2m),确定性
static func summon_positions(center: Vector3, count: int) -> Array:
	var out: Array = []
	var r := 2.0
	for i in count:
		var ang := TAU * float(i) / float(maxi(1, count)) + 0.4
		var p := center + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		p.x = clampf(p.x, -ARENA_HALF, ARENA_HALF)
		p.z = clampf(p.z, -ARENA_HALF, ARENA_HALF)
		out.append(p)
	return out

# ---------------------------------------------------------------- 生命周期

func _setup_from_enemy_data() -> void:
	super()
	var e := DataDB.enemy_by_id(unit_id)
	if not e.is_empty():
		attack_range = float(e.get("attack_range", 2.0))   # 挥砍近身 2m(01 §6)
	_base_move_speed = move_speed
	_base_atk_interval = atk_interval
	# 首技缓冲:入场后先走一会再放技能(平衡占位,收口上报)
	_charge_cd = FIRST_CHARGE_DELAY
	_slam_cd = FIRST_SLAM_DELAY

func _ready() -> void:
	super()
	add_to_group("boss")
	# 出场震屏(Boss 登场即有威压感,01 §10 出场红字横幅由 WaveDirector 发)
	EventBus.screen_shake.emit(0.45, 0.7)

# ---------------------------------------------------------------- 决策节拍

func _tick() -> void:
	super()                       # 基础索敌 + 挥砍( EnemyUnit )
	if dead:
		return
	_check_phase()
	_tick_skills(DECISION_TICK)
	_tick_summon(DECISION_TICK)

func _check_phase() -> void:
	if phase2 or dead:
		return
	if BossHuaxiong.phase2_should_enter(hp, max_hp, float(DataDB.enemy_by_id(unit_id).get("phase2_hp_ratio", 0.5))):
		_enter_phase2()

## 二阶段:移速/攻速 +25%,召唤计时启动(01 §6)
func _enter_phase2() -> void:
	phase2 = true
	var mult := float(DataDB.enemy_by_id(unit_id).get("phase2_speed_mult", 1.25))
	move_speed = _base_move_speed * mult
	atk_interval = _base_atk_interval / maxf(1.1, mult)
	_summon_t = 0.0
	FloatText.spawn(_vfx_parent(), global_position + Vector3(0.0, 2.6, 0.0), "狂暴", Color(0.71, 0.29, 0.23), 72)
	EventBus.boss_phase_changed.emit(2)
	EventBus.screen_shake.emit(0.3, 0.4)

func _tick_skills(dt: float) -> void:
	_charge_cd = maxf(0.0, _charge_cd - dt)
	_slam_cd = maxf(0.0, _slam_cd - dt)
	match skill_state:
		SkillState.NONE:
			if _charge_cd <= 0.0 and _lord_in_range(CHARGE_TRIGGER_RANGE):
				_start_charge()
			elif _slam_cd <= 0.0 and _any_friendly_near(SLAM_TRIGGER_RANGE):
				_start_slam()
		SkillState.CHARGE_WINDUP, SkillState.SLAM_WINDUP:
			_telegraph_left -= dt
			if _telegraph_left <= 0.0:
				if skill_state == SkillState.CHARGE_WINDUP:
					_launch_charge()
				else:
					_do_slam()
		SkillState.CHARGING:
			pass                   # 冲锋位移在 _move 逐帧推进

func _tick_summon(dt: float) -> void:
	if not phase2 or dead:
		return
	_summon_t += dt
	if _summon_t >= float(DataDB.enemy_by_id(unit_id).get("summon_interval", 12.0)):
		_summon_t = 0.0
		_summon()

## 召唤西凉亲卫 ×4(01 §6 二阶段)
func _summon() -> void:
	var e := DataDB.enemy_by_id(unit_id)
	var summon_id := str(e.get("summon_id", "xiliang_qinwei"))
	var count := int(e.get("summon_count", 4))
	var wd := get_tree().get_first_node_in_group("wave_director")
	if wd == null or wd.get("spawner") == null:
		return
	var sp = wd.get("spawner")     # Spawner 为 RefCounted,保持 Variant 动态调用
	# 同屏硬上限:召唤与增援共用 WaveDirector.MAX_ENEMIES,否则打不死华雄时
	# 增援被夹住、召唤却继续堆兵,同屏数量依旧失控(冒烟实测 116 兵)。
	var cap := int(wd.get("MAX_ENEMIES")) if wd != null else 60
	var alive: int = get_tree().get_nodes_in_group("enemies").size()
	count = maxi(mini(count, cap - alive), 0)
	if count == 0:
		return
	var pts: Array = BossHuaxiong.summon_positions(global_position, count)
	for i in count:
		var u = sp.spawn_enemy(summon_id, wave_base_hp, wave_base_atk)
		if u != null and is_instance_valid(u) and i < pts.size():
			u.global_position = pts[i]
	FloatText.spawn(_vfx_parent(), global_position + Vector3(0.0, 2.4, 0.0), "西凉亲卫,护我!", Color(0.71, 0.29, 0.23), 56)

# ---------------------------------------------------------------- 技能:冲锋

func _start_charge() -> void:
	var lord: Node3D = _lord()
	if lord == null:
		return
	skill_state = SkillState.CHARGE_WINDUP
	_telegraph_left = CHARGE_TELEGRAPH
	var end := BossHuaxiong.charge_end(global_position, lord.global_position, CHARGE_DIST)
	_dash_dir = (end - global_position)
	_dash_dir.y = 0.0
	if _dash_dir.length_squared() < 0.0001:
		_dash_dir = Vector3(0.0, 0.0, -1.0)
	_dash_dir = _dash_dir.normalized()
	_dash_target_pos = end
	_dash_left = global_position.distance_to(end)
	_charge_hit_set.clear()
	_spawn_warning_line(global_position, end)
	_charge_cd = float(DataDB.enemy_by_id(unit_id).get("charge_cd", CHARGE_CD))

func _launch_charge() -> void:
	_clear_warning()
	skill_state = SkillState.CHARGING
	Sfx.play("qinglong", -4.0)

## 冲锋命中:路径两侧带宽内友军(单体一次),16 伤害 + 击退 2m(01 §6)
func _charge_hit_check() -> void:
	for f in get_tree().get_nodes_in_group("friendlies"):
		if not is_instance_valid(f) or f.dead or _charge_hit_set.has(f):
			continue
		if BossHuaxiong.charge_hits(global_position, _dash_target_pos, f.global_position) \
				or _flat_dist(f.global_position) <= 1.3:
			_charge_hit_set.append(f)
			f.take_damage(UnitBase.compute_damage(float(DataDB.enemy_by_id(unit_id).get("atk_charge", 16)), 1.0), self)
			f.apply_knockback(f.global_position - global_position, CHARGE_KB)

# ---------------------------------------------------------------- 技能:震地

func _start_slam() -> void:
	skill_state = SkillState.SLAM_WINDUP
	_telegraph_left = SLAM_TELEGRAPH
	_spawn_warning_circle(global_position, SLAM_RADIUS)
	_slam_cd = float(DataDB.enemy_by_id(unit_id).get("slam_cd", SLAM_CD))

## 震地:自身圆心 4m,16 伤害 + 击退 3m(01 §6)
func _do_slam() -> void:
	_clear_warning()
	skill_state = SkillState.NONE
	for f in get_tree().get_nodes_in_group("friendlies"):
		if is_instance_valid(f) and not f.dead and _flat_dist(f.global_position) <= SLAM_RADIUS + 0.3:
			f.take_damage(UnitBase.compute_damage(float(DataDB.enemy_by_id(unit_id).get("atk_slam", 16)), 1.0), self)
			f.apply_knockback(f.global_position - global_position, SLAM_KB)
	EventBus.screen_shake.emit(0.4, 0.5)
	_spawn_ring_vfx(SLAM_RADIUS)

# ---------------------------------------------------------------- 移动(覆盖:前摇站定 / 冲锋推进)

func _move(delta: float) -> void:
	if dead:
		return
	if skill_state == SkillState.CHARGE_WINDUP or skill_state == SkillState.SLAM_WINDUP:
		velocity = Vector3.ZERO            # 前摇期间站定蓄力
		move_and_slide()
		return
	if skill_state == SkillState.CHARGING:
		velocity = _dash_dir * CHARGE_SPEED
		move_and_slide()
		_dash_left -= CHARGE_SPEED * delta
		_charge_hit_check()
		_clamp_to_arena()
		if _dash_left <= 0.0:
			skill_state = SkillState.NONE
			velocity = Vector3.ZERO
		return
	super(delta)

# ---------------------------------------------------------------- 警示痕与特效(程序化,固定形状)

func _spawn_warning_line(from: Vector3, to: Vector3) -> void:
	var root := _vfx_parent()
	if root == null:
		return
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var mi := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1.6, len)
	mesh.material = _warn_material(_line_tex())
	mi.mesh = mesh
	var dir := (to - from).normalized()
	mi.rotation.y = atan2(dir.x, dir.z)
	root.add_child(mi)
	mi.global_position = (from + to) * 0.5 + Vector3(0.0, 0.06, 0.0)
	_warn = mi
	_pulse_warning(mi)

func _spawn_warning_circle(center: Vector3, radius: float) -> void:
	var root := _vfx_parent()
	if root == null:
		return
	var mi := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(radius * 2.0, radius * 2.0)
	mesh.material = _warn_material(_circle_tex())
	mi.mesh = mesh
	root.add_child(mi)
	mi.global_position = center + Vector3(0.0, 0.06, 0.0)
	_warn = mi
	_pulse_warning(mi)

func _warn_material(tex: ImageTexture) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.71, 0.29, 0.23, 0.32)   # 朱砂警示(01 §11 警示色)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	return mat

## 前摇期间警示痕呼吸闪烁,结束时淡出
func _pulse_warning(mi: MeshInstance3D) -> void:
	if mi == null or not is_instance_valid(mi) or not mi.is_inside_tree():
		return
	var mat: StandardMaterial3D = (mi.mesh as PlaneMesh).material
	var dur := CHARGE_TELEGRAPH if skill_state == SkillState.CHARGE_WINDUP else SLAM_TELEGRAPH
	var tw := mi.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(func(a: float) -> void: mat.albedo_color.a = a, 0.25, 0.55, dur * 0.5)
	tw.tween_method(func(a: float) -> void: mat.albedo_color.a = a, 0.55, 0.25, dur * 0.5)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(mi.queue_free)

func _clear_warning() -> void:
	if _warn != null and is_instance_valid(_warn):
		var mat: StandardMaterial3D = (_warn.mesh as PlaneMesh).material
		var w := _warn
		var tw := w.create_tween()
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.2)
		tw.tween_callback(w.queue_free)
	_warn = null

func _spawn_ring_vfx(radius: float) -> void:
	var root := _vfx_parent()
	if root == null:
		return
	var path := "res://assets/textures/fx/ring.png"
	if not ResourceLoader.exists(path):
		return
	var sp := Sprite3D.new()
	sp.texture = load(path)
	sp.pixel_size = (radius * 2.4) / maxf(1.0, float(sp.texture.get_width()))
	sp.shaded = false
	sp.no_depth_test = true
	sp.modulate = Color(0.85, 0.45, 0.3, 0.8)
	sp.rotation_degrees.x = -90.0
	root.add_child(sp)
	sp.global_position = global_position + Vector3(0.0, 0.05, 0.0)
	var tw := sp.create_tween()
	tw.tween_property(sp, "modulate:a", 0.0, 0.45).set_delay(0.05)
	tw.tween_callback(sp.queue_free)

## 警示纹理:白色填充(色由 albedo_color 调),固定形状无随机,进程内缓存
func _circle_tex() -> ImageTexture:
	if _tex_circle != null:
		return _tex_circle
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c := Vector2(sz * 0.5, sz * 0.5)
	for y in sz:
		for x in sz:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (sz * 0.5)
			var a := 1.0 if d <= 0.86 else maxf(0.0, 1.0 - (d - 0.86) / 0.14)
			if d <= 0.62:
				a = maxf(a, 0.35)   # 内圈淡填充 + 外沿实圈
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_tex_circle = ImageTexture.create_from_image(img)
	return _tex_circle

func _line_tex() -> ImageTexture:
	if _tex_line != null:
		return _tex_line
	var w := 32
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dx := absf(float(x) + 0.5 - w * 0.5) / (w * 0.5)
			var a := maxf(0.0, 1.0 - dx * dx)
			var edge := 1.0 if y < 3 or y > h - 4 else 0.5
			img.set_pixel(x, y, Color(1, 1, 1, a * edge))
	_tex_line = ImageTexture.create_from_image(img)
	return _tex_line

# ---------------------------------------------------------------- 工具

func _lord() -> Node3D:
	for u in get_tree().get_nodes_in_group("friendlies"):
		if is_instance_valid(u) and u.is_lord and not u.dead:
			return u
	return null

func _lord_in_range(max_d: float) -> bool:
	var l := _lord()
	return l != null and _flat_dist(l.global_position) <= max_d

func _any_friendly_near(max_d: float) -> bool:
	for f in get_tree().get_nodes_in_group("friendlies"):
		if is_instance_valid(f) and not f.dead and _flat_dist(f.global_position) <= max_d:
			return true
	return false

func _vfx_parent() -> Node:
	if battle != null and is_instance_valid(battle):
		return battle.get_node_or_null("VFX")
	return null
