extends Control
## 序章「桃园结义」(M3;M6 视频接入,主 Agent 本卡拍板「尽力而为」):
## 检测到 assets/opening/taoyuan_intro.ogv → 播放开场视频(任意键/点击跳过);
## 无 ogv → 回退现有卷轴对话卡(events.json 序章文本)。

const VIDEO_PATH := "res://assets/opening/taoyuan_intro.ogv"

var _done := false
var _video: VideoStreamPlayer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 米纸底(两种模式共用兜底底色)
	var path := "res://assets/textures/ground/ground_paper.png"
	if ResourceLoader.exists(path):
		var bg := TextureRect.new()
		bg.texture = load(path)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(bg)
	else:
		var bg := ColorRect.new()
		bg.color = UiTheme.col("paper", Color(0.95, 0.92, 0.83))
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
	if _build_video():
		return
	_build_scroll()

## 开场视频(尽力而为):ogv 存在即播;缺失/加载失败回退卷轴
func _build_video() -> bool:
	if not ResourceLoader.exists(VIDEO_PATH):
		print("[Prologue] 无 ogv 开场视频,回退卷轴对话卡")
		return false
	var stream = load(VIDEO_PATH)
	if stream == null:
		print("[Prologue] ogv 加载失败,回退卷轴对话卡")
		return false
	var black := ColorRect.new()
	black.color = Color(0.05, 0.04, 0.03)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	_video = VideoStreamPlayer.new()
	_video.stream = stream
	_video.expand = true
	_video.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video.finished.connect(confirm)
	add_child(_video)
	var hint := UiTheme.label("按任意键跳过", 16, Color(1, 1, 1, 0.75), 4)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.position = Vector2(-160, -40)
	hint.size = Vector2(140, 22)
	add_child(hint)
	_video.play()
	print("[Prologue] 开场视频播放中(20s,任意键跳过)")
	return true

func _build_scroll() -> void:
	var pro: Dictionary = DataDB.events.get("prologue", {})
	# 卷轴面板
	var panel := UiTheme.scroll_panel(Vector2(900, 520))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-450, -260)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)
	var title := UiTheme.label("【%s】" % str(pro.get("title", "桃园结义")), 44, UiTheme.col("cinnabar", Color.RED))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var rule := ColorRect.new()
	rule.color = UiTheme.col("gold", Color(0.79, 0.66, 0.42))
	rule.custom_minimum_size = Vector2(200, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(rule)
	for line in pro.get("lines", []):
		var l := UiTheme.label(str(line), 22, UiTheme.col("dark_brown", Color(0.35, 0.27, 0.2)))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(700, 0)
		vb.add_child(l)
	var hint := UiTheme.label("—— 按任意键,整队迎敌 ——", 18, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var mb := event as InputEventMouseButton
	if (key != null and key.pressed and not key.echo) or (mb != null and mb.pressed):
		confirm()

## 任意键跳过 → 战斗(保留 start_run 已建的单局状态,不重置)
func confirm() -> void:
	if _done:
		return
	_done = true
	if _video != null and is_instance_valid(_video):
		_video.stop()
	SceneRouter.goto_battle(false)
