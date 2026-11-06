extends Control
## 主城(M7,02 §6.2/§7):Control 卷轴全景形态(提案默认,01 §13-10,不做 3D 可走动主城)。
## 节点(02 §6.2):CityBg(程序化全景)/ TopBar(货币余额)/ HubButtons(五入口)/
## SubPanelHost(选关/编队/招募/养成子面板互斥挂载,M8+ 接管,M7 留空)。
## 五入口(M9 战役接选关):战役 → 选关页 → 编队确认 → 闯关;试炼塔 → 编队 → 塔(M10 接塔层);
## 酒馆 → tavern.gd 招募;武将府 → hero_up.gd 养成;校场 → squad_edit.gd 编队。
## 三个养成面板挂 SubPanelHost 下互斥显示,收起后回主城。
## 音效:入口按钮沿用 UiTheme.button 的 button 音(02 §10 增量音效随 M8 结算/招募管道接)。

const VIGNETTE := "res://assets/textures/ui/vignette.png"
const LOCKED_HINT := "尚未开放"

var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tw: Tween
var _pending_mode := &""              # 出征前记录的入口模式:campaign / tower
var _pending_stage := ""              # 出征前选定的关卡(M9 选关页带出)

func _ready() -> void:
	Sfx.play_bgm()                     # 主城沿用营地 BGM(Sfx 幂等)
	_build_vignette()
	_build_hub()
	_build_toast()
	if not SaveState.last_note.is_empty():
		_toast(SaveState.last_note)    # 坏档备份恢复 / 重开新档横幅(02 §3.1)

func _build_vignette() -> void:
	if ResourceLoader.exists(VIGNETTE):
		var v := TextureRect.new()
		v.texture = load(VIGNETTE)
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.stretch_mode = TextureRect.STRETCH_SCALE
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(v)
		move_child(v, 1)               # 压在 CityBg 之上、TopBar/入口之下

## 五入口(02 §7 界面流):战役 / 试炼塔 / 酒馆 / 武将府 / 校场
func _build_hub() -> void:
	var vb: VBoxContainer = $HubButtons
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	var head := UiTheme.label("桃  源  城", 40, UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23)), 6)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head)
	var sub := UiTheme.label("选择去处(界面操作以鼠标点击为主)", 16, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)), 3)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var rule := ColorRect.new()
	rule.color = UiTheme.col("gold", Color(0.79, 0.66, 0.42))
	rule.custom_minimum_size = Vector2(240, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(rule)
	var entries := [
		{"kind": "campaign", "label": "战  役", "locked": false},
		{"kind": "tower", "label": "试 炼 塔", "locked": false},
		{"kind": "tavern", "label": "酒  馆", "locked": false},
		{"kind": "barracks", "label": "武 将 府", "locked": false},
		{"kind": "drill", "label": "校  场", "locked": false},
	]
	for e in entries:
		var b := UiTheme.button(str(e["label"]), 26, Vector2(380, 74))
		b.icon = ProcIcon.building(str(e["kind"]))
		b.add_theme_constant_override("icon_max_width", 52)
		b.add_to_group("hub_entry")
		if bool(e["locked"]):
			b.modulate = Color(1.0, 1.0, 1.0, 0.55)     # 灰置(保留可点,提示未开放)
			b.tooltip_text = "未开放:" + LOCKED_HINT
			b.pressed.connect(_on_locked.bind(_plain(str(e["label"]))))
		else:
			b.pressed.connect(_on_entry.bind(str(e["kind"])))
		vb.add_child(b)

func _plain(s: String) -> String:
	return s.replace(" ", "")

## 可进入口 → 三层路由(02 §7):战役 → 选关(M9)→ 编队确认 → 闯关;试炼塔 → 塔
func _on_entry(kind: String) -> void:
	match kind:
		"campaign":
			_pending_mode = &"campaign"
			_open_stage_select()
		"tower":
			_pending_mode = &"tower"
			_open_squad(true)
		"tavern":
			_open_panel("res://scripts/ui/tavern.gd")
		"barracks":
			_open_panel("res://scripts/ui/hero_up.gd")
		"drill":
			_open_squad(false)

## 养成子面板互斥挂载(02 §6.2 SubPanelHost):同一时刻最多一个,收起即删。
func _open_panel(script_path: String) -> void:
	var host := $SubPanelHost as Control
	for c in host.get_children():
		c.queue_free()
	var s = load(script_path)
	if s == null:
		_toast("面板加载失败")
		return
	var panel: Control = s.new()
	host.add_child(panel)

## 战役 → 选关页(M9,02 §7 界面流):章节内关卡列表 → 选关 → 编队确认 → 开战
func _open_stage_select() -> void:
	var host := $SubPanelHost as Control
	for c in host.get_children():
		c.queue_free()
	var panel: Control = load("res://scripts/ui/stage_select.gd").new()
	host.add_child(panel)
	panel.stage_chosen.connect(_on_stage_chosen)

## 选定关卡:带出 id,换编队确认面板(squad_edit 复用,01 §3.2)
func _on_stage_chosen(stage_id: String) -> void:
	_pending_stage = stage_id
	_open_squad(true)

## 校场:confirm=true 时带「披挂出征」,确认后按当前模式直接开打(M9 战役先经选关页)
func _open_squad(confirm: bool) -> void:
	var host := $SubPanelHost as Control
	for c in host.get_children():
		c.queue_free()
	var panel: Control = load("res://scripts/ui/squad_edit.gd").new()
	panel.setup(confirm)
	host.add_child(panel)
	if confirm:
		panel.confirmed.connect(_on_squad_confirmed)

func _on_squad_confirmed(_slots: Array) -> void:
	if _pending_mode == &"campaign":
		var sid := _pending_stage
		if sid.is_empty():
			sid = CampaignSave.first_unlocked_stage()   # 兜底:表序首个已解锁关卡
		if sid.is_empty():
			sid = "1-1"
		SceneRouter.goto_stage(sid)
	else:
		SceneRouter.goto_tower()

func _on_locked(name_cn: String) -> void:
	_toast("「%s」未开放(%s)" % [name_cn, LOCKED_HINT])

# ---------------------------------------------------------------- 提示横幅(轻量 toast)

func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.add_theme_stylebox_override("panel", UiTheme.panel_style())
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 150)
	_toast_panel.modulate.a = 0.0
	add_child(_toast_panel)
	_toast_label = UiTheme.label("", 22, UiTheme.col("dark_brown", Color(0.35, 0.27, 0.2)), 3)
	_toast_panel.add_child(_toast_label)

func _toast(msg: String) -> void:
	if _toast_panel == null:
		return
	_toast_label.text = msg
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_panel.modulate.a = 0.0
	_toast_tw = create_tween()
	_toast_tw.tween_property(_toast_panel, "modulate:a", 1.0, 0.15)
	_toast_tw.tween_interval(2.4)
	_toast_tw.tween_property(_toast_panel, "modulate:a", 0.0, 0.5)
