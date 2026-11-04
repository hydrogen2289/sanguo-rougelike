extends Control
## 主菜单正式版(M3,01 §10/§11):米纸底图 + 标题 + 开始游戏/退出。
## 底图与装饰全部用程序化生成贴图(ground_paper/vignette/btn_seal,已拍板不下载素材);
## 标题字走 SystemFont 程序化渲染,朱砂印签由代码绘制。

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_title()
	_build_buttons()
	_build_footer()
	Sfx.play_bgm()                     # BGM 五声音阶氛围(M6),主菜单与战斗共用

func _build_background() -> void:
	# 米纸底图(程序化生成,01 §11)
	var path := "res://assets/textures/ground/ground_paper.png"
	if ResourceLoader.exists(path):
		var bg := TextureRect.new()
		bg.texture = load(path)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(bg)
	# 底部渐深青条 + 顶部细条(卷轴装帧感)
	var top := ColorRect.new()
	top.color = UiTheme.col("deep_green", Color(0.31, 0.44, 0.32))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size = Vector2(0, 14)
	add_child(top)
	var bottom := ColorRect.new()
	bottom.color = UiTheme.col("deep_green", Color(0.31, 0.44, 0.32))
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.custom_minimum_size = Vector2(0, 14)
	add_child(bottom)
	# 边缘渐晕
	var vp := "res://assets/textures/ui/vignette.png"
	if ResourceLoader.exists(vp):
		var v := TextureRect.new()
		v.texture = load(vp)
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.stretch_mode = TextureRect.STRETCH_SCALE
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(v)

func _build_title() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-400, 150)
	box.size = Vector2(800, 300)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := UiTheme.label("桃  源  乱  武", 96, UiTheme.col("dark_brown", Color(0.35, 0.27, 0.2)), 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	# 朱砂分隔印线(代码绘制,程序化)
	var rule := ColorRect.new()
	rule.color = UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23))
	rule.custom_minimum_size = Vector2(320, 5)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(rule)
	var sub := UiTheme.label("三国实时幸存者肉鸽 · 垂直切片", 24, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	# 朱砂小印(程序化「印」字方章)
	var seal := UiTheme.label("印", 20, UiTheme.col("paper", Color.WHITE), 0)
	seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.custom_minimum_size = Vector2(34, 34)
	seal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	seal.add_theme_color_override("font_outline_color", UiTheme.col("cinnabar", Color.RED))
	seal.add_theme_constant_override("outline_size", 16)
	box.add_child(seal)

func _build_buttons() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-130, -10)
	box.size = Vector2(260, 160)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	add_child(box)
	var start := UiTheme.button("开 始 游 戏", 26, Vector2(260, 60))
	start.pressed.connect(_on_start)
	box.add_child(start)
	var quit := UiTheme.button("退 出", 22, Vector2(260, 50))
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)

func _build_footer() -> void:
	var hint := UiTheme.label("WASD 走位 · 武将自动普攻 · 1~6 武将技能 · 空格 主公技 · ESC 暂停", 16, UiTheme.col("dark_brown", Color(0.4, 0.36, 0.3)))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-340, -50)
	hint.size = Vector2(680, 24)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	var ver := UiTheme.label("v0.5 · M5 Boss与平衡 + M6 音效打磨", 13, UiTheme.col("dark_brown", Color(0.5, 0.46, 0.4)))
	ver.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ver.position = Vector2(-300, -28)
	ver.size = Vector2(600, 20)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(ver)

## 开始游戏 → 序章「桃园结义」(01 §10 界面流程)
func _on_start() -> void:
	SceneRouter.start_run()
