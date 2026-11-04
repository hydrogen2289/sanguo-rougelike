extends Control
## 结算(M3,01 §10):胜「桃园功成」/ 败「大意失荆州」+ 4 项统计
## (到达波次/总击杀/剩余军资/用时,数据走 RunState.dump())+ 再来一局 / 回主菜单。

var victory := false
var _built := false

func open(is_victory: bool, stats: Dictionary) -> void:
	add_to_group("modal")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	victory = is_victory
	Sfx.play("win" if is_victory else "lose", -2.0)   # 胜利短句 / 失败低音锣(01 §12)
	if _built:
		return
	_built = true
	var dim := UiTheme.dim_bg()
	dim.color = Color(0.1, 0.09, 0.07, 0.62)
	add_child(dim)
	var panel := UiTheme.scroll_panel(Vector2(640, 480))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-320, -240)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)
	var title := UiTheme.label(
		"桃 园 功 成" if is_victory else "大 意 失 荆 州",
		56,
		UiTheme.col("spring_green" if is_victory else "cinnabar", Color.GREEN if is_victory else Color.RED))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := UiTheme.label(
		"黄巾既平,桃园之誓,功成于野。" if is_victory else "主公陨落,大业未竟,且重来过。",
		18, UiTheme.col("dark_brown", Color.BLACK))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var stats_l := UiTheme.label(_stats_text(stats), 22, UiTheme.col("dark_brown", Color.BLACK))
	stats_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(stats_l)
	var team_l := UiTheme.label(_team_text(stats), 16, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)))
	team_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(team_l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	var again := UiTheme.button("再来一局", 22, Vector2(200, 52))
	again.pressed.connect(_on_restart)
	row.add_child(again)
	var menu := UiTheme.button("回主菜单", 22, Vector2(200, 52))
	menu.pressed.connect(_on_menu)
	row.add_child(menu)

func _stats_text(stats: Dictionary) -> String:
	var wave := int(stats.get("wave_idx", 0))
	var total := DataDB.waves.size()
	return "到达波次 %d/%d    总击杀 %d\n剩余军资 %d    用时 %s" % [
		wave, total, int(stats.get("kills", 0)), int(stats.get("gold", 0)), _fmt_time(float(stats.get("run_time", 0.0)))]

func _team_text(stats: Dictionary) -> String:
	var team: Array = stats.get("team", [])
	var alive := 0
	for m in team:
		if bool(m.get("alive", false)):
			alive += 1
	return "队伍存活 %d/%d" % [alive, team.size()]

func _fmt_time(t: float) -> String:
	return "%d分%02d秒" % [int(t) / 60, int(t) % 60]

## 再来一局:重置后直接进战斗,不重播序章(01 §10)
func _on_restart() -> void:
	visible = false
	SceneRouter.restart_battle()

## 回主菜单(01 §10)
func _on_menu() -> void:
	visible = false
	SceneRouter.goto_menu()
