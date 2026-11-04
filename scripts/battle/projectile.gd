extends Area3D
## 直线弹道(M1):黄巾弓手箭矢 / 诸葛亮普攻(数据驱动,02 §3)。
## 友军弹道命中时回调射手普攻命中效果(灼烧/斩杀,P2-②:命中效果统一在真正命中时结算)。

var velocity := Vector3.ZERO
var dmg := 5
var from_friendly := true
var life := 3.0
var shooter: Node = null           # 友军弹道射手(HeroUnit);命中时回调其 _post_attack_hit

func setup(dir: Vector3, speed: float, damage: int, friendly: bool, owner_node: Node = null) -> void:
	velocity = dir.normalized() * speed
	dmg = damage
	from_friendly = friendly
	shooter = owner_node

func _ready() -> void:
	collision_layer = 16              # bit5 Projectile
	collision_mask = 2 if from_friendly else 1
	monitorable = false
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	life -= delta
	if life <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body != null and body.has_method("take_damage") and not body.dead:
		body.take_damage(float(dmg), self)
		# 普攻命中效果(拖刀计斩杀/借东风灼烧)统一在弹道真正命中时结算(P2-②)
		if from_friendly and not body.dead:
			if shooter != null and is_instance_valid(shooter) and not shooter.dead \
					and shooter.has_method("_post_attack_hit"):
				shooter._post_attack_hit(body)
			else:
				# 无射手/射手已亡的友军弹道兜底:保留东风灼烧附加(01 §4)
				var wm = body.get_tree().get_first_node_in_group("weather_manager")
				if wm != null:
					wm.try_apply_burn(body)
		queue_free()
