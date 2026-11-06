extends Control
## 结算页(M3 立页;M11 改造为统一结算出口,02 §8.4 / §6.2):
## 胜「桃园功成」/ 败「大意失荆州」+ 4 项统计(到达波次/总击杀/剩余军资/用时),
## 以及**奖励清单逐项展示**(军资 / 定向碎片 / 评星 / 通过层数)。
##
## 奖励数值一律来自 RewardSettle.settle() 的返回值(items 清单),前端不重算 ——
## 界面与入库共用同一份数据,杜绝「显示 +100 实际入库 +80」这类漂移。
## 按钮按模式变化(02 §8.4):闯关「重打 / 回主城」;塔「再来一次 / 回主城」。

var victory := false
var _built := false
var _root_vb: VBoxContainer
var _title: Label
var _sub: Label
var _stats_l: Label
var _team_l: Label
var _reward_head: Label
var _reward_box: VBoxContainer
var _row: HBoxContainer
var _again_btn: Button
var _exit_btn: Button
var _last_settle: Dictionary = {}

func open(is_victory: bool, stats: Dictionary, settle: Dictionary = {}) -> void:
	add_to_group("modal")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	victory = is_victory
	_last_settle = settle if not settle.is_empty() else {}
	Sfx.play("win" if is_victory else "lose", -2.0)   # 胜利短句 / 失败低音锣(01 §12)
	if not _built:
		_build()
	_fill(stats, _last_settle)

# ---------------------------------------------------------------- 构建(只建一次)

func _build() -> void:
	_built = true
	var dim := UiTheme.dim_bg()
	dim.color = Color(0.1, 0.09, 0.07, 0.62)
	add_child(dim)
	var panel := UiTheme.scroll_panel(Vector2(720, 560))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-360, -280)
	add_child(panel)
	_root_vb = VBoxContainer.new()
	_root_vb.add_theme_constant_override("separation", 14)
	_root_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(_root_vb)
	_title = UiTheme.label("", 52, UiTheme.col("spring_green", Color.GREEN))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_vb.add_child(_title)
	_sub = UiTheme.label("", 18, UiTheme.col("dark_brown", Color.BLACK))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_vb.add_child(_sub)
	_stats_l = UiTheme.label("", 22, UiTheme.col("dark_brown", Color.BLACK))
	_stats_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_vb.add_child(_stats_l)
	_team_l = UiTheme.label("", 16, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)))
	_team_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_vb.add_child(_team_l)
	# --- 奖励清单区块(M11)---
	_reward_head = UiTheme.label("本局收获", 22, UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23)))
	_reward_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_vb.add_child(_reward_head)
	_reward_box = VBoxContainer.new()
	_reward_box.add_theme_constant_override("separation", 6)
	_reward_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_root_vb.add_child(_reward_box)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 32)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_root_vb.add_child(_row)
	_again_btn = UiTheme.button("再来一局", 22, Vector2(200, 52))
	_again_btn.pressed.connect(_on_restart)
	_row.add_child(_again_btn)
	_exit_btn = UiTheme.button("回主菜单", 22, Vector2(200, 52))
	_exit_btn.pressed.connect(_on_menu)
	_row.add_child(_exit_btn)

# ---------------------------------------------------------------- 填充(每次结算刷新)

func _fill(stats: Dictionary, settle: Dictionary) -> void:
	var tower_mode := str(stats.get("mode", "")) == "tower" and bool(stats.get("context", {}).get("endless", false))
	_title.text = "桃 园 功 成" if victory else ("塔 中 折 戟" if tower_mode else "大 意 失 荆 州")
	_title.add_theme_color_override("font_color",
		UiTheme.col("spring_green" if victory else "cinnabar", Color.GREEN if victory else Color.RED))
	_sub.text = ("黄巾既平,桃园之誓,功成于野。" if victory else "主公陨落,大业未竟,且重来过。") \
		if not tower_mode else \
		("层数已记,塔中再候。" if victory else "主公陨落,塔中道阻且长。")
	_stats_l.text = _stats_text(stats)
	_team_l.text = _team_text(stats)
	_fill_rewards(settle)
	# 按钮按模式变化(02 §8.4):塔「再来一次」,闯关「重打」,出口都是回主城
	if tower_mode:
		_again_btn.text = "再来一次"
		_exit_btn.text = "回主城"
	else:
		_again_btn.text = "再来一局"
		_exit_btn.text = "回主菜单"

func _fill_rewards(settle: Dictionary) -> void:
	for c in _reward_box.get_children():
		_reward_box.remove_child(c)
		c.queue_free()
	var items: Array = settle.get("items", [])
	if items.is_empty():
		_reward_head.visible = true
		_reward_head.text = "本局无奖励" if not bool(settle.get("ok", true)) else "本局无可结算项"
		return
	_reward_head.visible = true
	var first := bool(settle.get("first", false))
	_reward_head.text = "本局收获 · 首通" if first else "本局收获"
	for it in items:
		_reward_box.add_child(_reward_line(it))
	var reason := str(settle.get("reason", ""))
	if reason != "":
		var rl := UiTheme.label(reason, 15, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)))
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_reward_box.add_child(rl)

## 单项奖励行:图标色点 + 名称 + 数量(星用 ★ 重复,层数单独表述)
func _reward_line(it: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var kind := str(it.get("kind", ""))
	var amount := int(it.get("amount", 0))
	var text := str(it.get("name", ""))
	var color := UiTheme.col("gold", Color(0.79, 0.66, 0.42))
	match kind:
		"stars":
			text = "评星 " + "★".repeat(maxi(0, amount))
		"floor":
			text = "%s %d 层" % [text, amount]
			color = UiTheme.col("spring_green", Color(0.31, 0.60, 0.36))
		_:
			text = "%s +%d" % [text, amount]
	var l := UiTheme.label(text, 20, color, 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(l)
	return row

# ---------------------------------------------------------------- 统计文本

func _stats_text(stats: Dictionary) -> String:
	var wave := int(stats.get("wave_idx", 0))
	var tower_mode := str(stats.get("mode", "")) == "tower" and bool(stats.get("context", {}).get("endless", false))
	var at := ("塔第 %d 层" % wave) if tower_mode else ("到达波次 %d/%d" % [wave, DataDB.waves.size()])
	return "%s    总击杀 %d\n剩余军资 %d    用时 %s" % [
		at, int(stats.get("kills", 0)), int(stats.get("gold", 0)), _fmt_time(float(stats.get("run_time", 0.0)))]

func _team_text(stats: Dictionary) -> String:
	var team: Array = stats.get("team", [])
	var alive := 0
	for m in team:
		if bool(m.get("alive", false)):
			alive += 1
	return "队伍存活 %d/%d" % [alive, team.size()]

func _fmt_time(t: float) -> String:
	return "%d分%02d秒" % [int(t) / 60, int(t) % 60]

# ---------------------------------------------------------------- 按钮

## 再来一局:重置后直接进战斗,不重播序章(01 §10);塔则重开爬塔(自第 1 层)
func _on_restart() -> void:
	visible = false
	if str(_last_settle.get("mode", "")) == "tower":
		SceneRouter.goto_tower()
		return
	SceneRouter.restart_battle()

## 出口(02 §8.4):塔 → 回主城;闯关 → 回主城(主城读档落盘),无主城归档时回主菜单
func _on_menu() -> void:
	visible = false
	if str(_last_settle.get("mode", "")) == "tower":
		SceneRouter.goto_city()
		return
	if not SaveState.data.is_empty():
		SceneRouter.goto_city()
		return
	SceneRouter.goto_menu()
