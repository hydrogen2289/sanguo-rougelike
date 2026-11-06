extends Control
## 暂停菜单(M3,01 §10):ESC 半透明遮罩,继续/重开/回主菜单。
## 波间界面响应不依赖暂停态:本节点与各模态 PROCESS_MODE_ALWAYS,
## WaveDirector 等战斗节点 PAUSABLE(02 §7.9)。

var _built := false

func _ready() -> void:
	add_to_group("pause_menu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # 遮罩挡住底层点击

func open() -> void:
	if _other_modal_open():
		return                    # 三选一/事件/商店/结算必须先决,不开暂停
	if _battle_ended():
		return                    # 战斗已结束(败北演出/结算中):暂停入口无效化,防「继续」解冻已 ENDED 战场(P2-④)
	_ensure_built()
	visible = true
	get_tree().paused = true

func close() -> void:
	visible = false
	get_tree().paused = false

## 战斗是否已结束(WaveDirector ENDED:主公死后褪色演出窗口 / 胜负结算期间)
func _battle_ended() -> bool:
	var wd = get_tree().get_first_node_in_group("wave_director")
	if wd == null:
		return false
	return int(wd.state) == int(wd.State.ENDED)

func _other_modal_open() -> bool:
	for m in get_tree().get_nodes_in_group("modal"):
		if is_instance_valid(m) and m.visible:
			return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if visible:
		close()                   # 再按 ESC 继续
	elif not _other_modal_open():
		open()

func _build() -> void:
	_built = true
	var dim := UiTheme.dim_bg()
	dim.color = Color(0.1, 0.09, 0.07, 0.5)
	add_child(dim)
	var panel := UiTheme.scroll_panel(Vector2(420, 380))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-210, -190)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)
	var title := UiTheme.label("暂 停", 36, UiTheme.col("cinnabar", Color.RED))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var resume := UiTheme.button("继 续", 20, Vector2(240, 48))
	resume.pressed.connect(close)
	vb.add_child(resume)
	var restart := UiTheme.button("重 开", 20, Vector2(240, 48))
	restart.pressed.connect(_on_restart)
	vb.add_child(restart)
	# 塔无尽模式:撤退结算入库(02 §8.4,折算 retreat_mult),闯关不显示
	if RunState.mode == &"tower" and bool(RunState.context.get("endless", false)):
		var retreat := UiTheme.button("撤 退 结 算", 20, Vector2(240, 48))
		retreat.pressed.connect(_on_retreat)
		vb.add_child(retreat)
	var menu := UiTheme.button("回主菜单", 20, Vector2(240, 48))
	menu.pressed.connect(_on_menu)
	vb.add_child(menu)

func _ensure_built() -> void:
	if not _built:
		_build()

## 重开(冒烟/按钮共用):重置单局 → 直接进战斗
func _on_restart() -> void:
	visible = false
	SceneRouter.restart_battle()

## 塔撤退:结算入库(02 §8.4)→ 结算页 → 回主城。暂停中也能点(PROCESS_MODE_ALWAYS)
func _on_retreat() -> void:
	visible = false
	var wd = get_tree().get_first_node_in_group("wave_director")
	if wd != null and is_instance_valid(wd) and wd.has_method("retreat"):
		get_tree().paused = false
		wd.retreat()
		return
	SceneRouter.goto_city()

## 回主菜单(冒烟/按钮共用)
func _on_menu() -> void:
	visible = false
	SceneRouter.goto_menu()
