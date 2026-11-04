extends Control
## 战斗 HUD(M1 立骨架;M4 补全;M5/M6 打磨):左上队伍列表(头像+HP 条+CD 扫罩+阵亡灰化打叉+槽位角标)/
## 右上波次+时间条(含剩余秒数)+军资 / 顶中 Boss 血条(第 8 波,阶段变色)/ 底中技能栏 6 格
## (数字键/点击,CD 转圈 + 就绪脉冲,吕布「不受令」延迟红闪)/ 中央卷轴横幅 /
## 全屏 vignette / 张飞狂化红晕 / 关羽斩杀白闪(01 §10/§12)。
## 键位口径:数字键 1~6 = 武将槽位;空格 = 主公「仁德之泽」;点头像亦可(主 Agent 拍板)。

var team_box: VBoxContainer
var wave_label: Label
var time_bar: ProgressBar
var time_secs: Label
var gold_label: Label
var banner_box: Control
var banner_label: Label
var boss_name: Label
var boss_bar: ProgressBar
var boss_phase_tag: Label
var skill_buttons: Array[Button] = []
var _skill_cd: Array[TextureProgressBar] = []
var _skill_cd_secs: Array[Label] = []
var _skill_prev_cd: Array[float] = []
var _rows := {}                     # hero_id -> {portrait, bar, cd, slot, x}
var _bound: Array = []              # [{slot:int, comp:Object}]
var _disc: ImageTexture
var _banner_tween: Tween
var _flash_rect: ColorRect
var _flash_tween: Tween
var _rage_rect: TextureRect
var _rage_target := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_disc = UiTheme.disc_texture()
	_build_vignette()
	_build_rage_vignette()
	_build_flash()
	_build_team_list()
	_build_top_right()
	_build_boss_bar()
	_build_skill_bar()
	_build_banner()
	_build_key_hint()
	EventBus.wave_banner.connect(show_banner)
	EventBus.banner_styled.connect(show_banner_styled)
	EventBus.executed_kill.connect(_on_executed_kill)
	RunState.gold_changed.connect(_on_gold_changed)
	_on_gold_changed(RunState.gold)
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	timer.timeout.connect(_refresh)
	add_child(timer)

func _col(token: String, fallback: Color) -> Color:
	return UiTheme.col(token, fallback)

func _font(size: int) -> SystemFont:
	return UiTheme.font(size)

func _mk_label(text: String, font_size: int, color: Color) -> Label:
	return UiTheme.label(text, font_size, color)

# ---------------------------------------------------------------- 构建区块

func _build_vignette() -> void:
	var path := "res://assets/textures/ui/vignette.png"
	if not ResourceLoader.exists(path):
		return
	var tr := TextureRect.new()
	tr.texture = load(path)
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	move_child(tr, 0)

func _build_team_list() -> void:
	team_box = VBoxContainer.new()
	team_box.position = Vector2(24, 24)
	team_box.add_theme_constant_override("separation", 6)
	team_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(team_box)

func _build_top_right() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.position = Vector2(-320, 24)
	box.size = Vector2(296, 110)
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	wave_label = _mk_label("第 1/8 波", 20, _col("dark_brown", Color.BLACK))
	box.add_child(wave_label)
	time_bar = ProgressBar.new()
	time_bar.custom_minimum_size = Vector2(296, 14)
	time_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = _col("paper_dark", Color(0.9, 0.87, 0.77))
	bg.border_color = _col("dark_brown", Color(0.35, 0.27, 0.2))
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = _col("cinnabar", Color.RED)
	time_bar.add_theme_stylebox_override("background", bg)
	time_bar.add_theme_stylebox_override("fill", fg)
	box.add_child(time_bar)
	time_secs = _mk_label("", 14, _col("deep_green", Color(0.31, 0.44, 0.32)))
	box.add_child(time_secs)
	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 6)
	box.add_child(gold_row)
	var coin_path := "res://assets/textures/icons/coin.png"
	if ResourceLoader.exists(coin_path):
		var coin := TextureRect.new()
		coin.texture = load(coin_path)
		coin.custom_minimum_size = Vector2(24, 24)
		coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin.stretch_mode = TextureRect.STRETCH_SCALE
		gold_row.add_child(coin)
	gold_label = _mk_label("0", 20, _col("dark_brown", Color.BLACK))
	gold_row.add_child(gold_label)

func _build_boss_bar() -> void:
	# Boss 血条(第 8 波华雄,顶部中央,01 §10;二阶段换色示警)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-330, 16)
	box.size = Vector2(660, 64)
	box.add_theme_constant_override("separation", 4)
	box.visible = false
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	boss_name = _mk_label("华雄 · 都督之威", 22, _col("cinnabar", Color(0.71, 0.29, 0.23)))
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(boss_name)
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(660, 20)
	boss_bar.show_percentage = false
	boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = _col("paper_dark", Color(0.9, 0.87, 0.77))
	bg.border_color = _col("dark_brown", Color(0.35, 0.27, 0.2))
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = _col("cinnabar", Color(0.71, 0.29, 0.23))
	fg.set_corner_radius_all(4)
	boss_bar.add_theme_stylebox_override("background", bg)
	boss_bar.add_theme_stylebox_override("fill", fg)
	box.add_child(boss_bar)
	boss_phase_tag = _mk_label("", 15, _col("cinnabar", Color(0.71, 0.29, 0.23)))
	boss_phase_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(boss_phase_tag)

## 张飞狂化:屏幕边缘红晕(01 §12),狂化期间淡入、解除淡出
func _build_rage_vignette() -> void:
	var path := "res://assets/textures/ui/vignette.png"
	if not ResourceLoader.exists(path):
		return
	_rage_rect = TextureRect.new()
	_rage_rect.texture = load(path)
	_rage_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rage_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rage_rect.modulate = Color(0.85, 0.18, 0.12, 0.0)   # 朱砂红晕
	_rage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rage_rect)

## 关羽斩杀:全屏「斩!」白闪(01 §12)
func _build_flash() -> void:
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1.0, 0.98, 0.92, 0.0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)

func _build_key_hint() -> void:
	var hint := _mk_label("WASD 走位 · 1~6 武将技能 · 空格 主公技 · ESC 暂停", 14, _col("dark_brown", Color(0.5, 0.46, 0.4)))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-240, -36)
	hint.size = Vector2(480, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)

func _build_skill_bar() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.position = Vector2(-6 * 68, -110)
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	for i in 6:
		var b := Button.new()
		b.custom_minimum_size = Vector2(60, 60)
		b.disabled = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 20)
		var idx := i
		b.pressed.connect(func() -> void: _cast_slot(idx + 1))
		# CD 转圈扫罩(程序化圆盘 + 顺时针填充)
		var cd := TextureProgressBar.new()
		cd.texture_progress = _disc
		cd.fill_mode = TextureProgressBar.FILL_CLOCKWISE
		cd.min_value = 0.0
		cd.max_value = 1.0
		cd.tint_progress = Color(0.1, 0.08, 0.06, 0.62)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd.set_anchors_preset(Control.PRESET_FULL_RECT)
		cd.value = 0.0
		b.add_child(cd)
		var secs := UiTheme.label("", 14, Color(1, 1, 1, 0.95), 2)
		secs.set_anchors_preset(Control.PRESET_CENTER)
		secs.position = Vector2(-12, -10)
		secs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(secs)
		row.add_child(b)
		skill_buttons.append(b)
		_skill_cd.append(cd)
		_skill_cd_secs.append(secs)
		_skill_prev_cd.append(0.0)
	# HUD 晚于 WaveDirector ready:重放此前存下的绑定
	for b in _bound:
		_setup_skill_button(int(b.slot), b.comp)

func _build_banner() -> void:
	# 卷轴横幅(01 §12 波次横幅卷轴展开):scroll_bg 底 + 居中大字
	banner_box = Control.new()
	banner_box.set_anchors_preset(Control.PRESET_CENTER)
	banner_box.position = Vector2(-380, -120)
	banner_box.size = Vector2(760, 132)
	banner_box.pivot_offset = Vector2(380, 66)
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_box.visible = false
	add_child(banner_box)
	var path := "res://assets/textures/ui/scroll_bg.png"
	if ResourceLoader.exists(path):
		var panel := PanelContainer.new()
		var sb := StyleBoxTexture.new()
		sb.texture = load(path)
		sb.texture_margin_left = 48
		sb.texture_margin_right = 48
		sb.texture_margin_top = 32
		sb.texture_margin_bottom = 32
		panel.add_theme_stylebox_override("panel", sb)
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner_box.add_child(panel)
	banner_label = _mk_label("", 40, _col("deep_green", Color(0.31, 0.44, 0.32)))
	banner_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_box.add_child(banner_label)

# ---------------------------------------------------------------- 技能槽(M4)

## WaveDirector 调用:把武将技能组件接到槽位按钮(数字键 1~6 / 点击等效,01 §10)。
## HUD 构建完成前先存绑定,构建完成(_build_skill_bar 末尾)统一重放。
## 槽位唯一(P1-2):同槽的「存活生效」绑定不被后到者覆盖(先到者优先);
## 旧绑定已失效(组件释放/宿主阵亡)时才允许被顶替(阵亡武将槽位由新武将接手)。
func bind_skill_slot(slot: int, skill_comp: Node) -> void:
	if slot < 1 or slot > 6 or skill_comp == null:
		return
	for b in _bound:
		if int(b.slot) != slot:
			continue
		var old = b.comp
		if old == skill_comp:
			return                   # 同一组件重复绑定:幂等
		if is_instance_valid(old) and old.host != null and is_instance_valid(old.host) \
				and not bool(old.host.dead):
			return                   # 先到者仍存活生效:不得覆盖(若发生视为缺陷)
		b.comp = skill_comp          # 旧绑定已失效 → 顶替
		if skill_buttons.size() == 6:
			_setup_skill_button(slot, skill_comp)
		return
	_bound.append({"slot": slot, "comp": skill_comp})
	if skill_buttons.size() == 6:
		_setup_skill_button(slot, skill_comp)

func _setup_skill_button(slot: int, comp: Node) -> void:
	var b := skill_buttons[slot - 1]
	b.disabled = false
	var sk: Dictionary = comp.skill_data
	var tip := "%d · %s(CD %ds)" % [slot, str(sk.get("name", "?")), int(float(sk.get("cd", 0)))]
	var host = comp.host
	if host != null:
		tip = "%s %s" % [str(host.display_name), tip]
	b.tooltip_text = tip
	var icon_path := "res://assets/textures/icons/skills/%s.png" % str(sk.get("id", ""))
	if ResourceLoader.exists(icon_path):
		b.icon = load(icon_path)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 44)

func _cast_slot(slot: int) -> void:
	if get_tree().paused:
		return
	for b in _bound:
		if int(b.slot) == slot and is_instance_valid(b.comp):
			b.comp.activate()
			return

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event.is_action_pressed("lord_skill"):
		_cast_lord_skill()
		return
	for i in 6:
		if event.is_action_pressed("skill_%d" % (i + 1)):
			_cast_slot(i + 1)
			return

## 空格 = 主公「仁德之泽」(主 Agent 本卡拍板;点头像施放保留)
func _cast_lord_skill() -> void:
	if get_tree().paused:
		return
	for u in get_tree().get_nodes_in_group("friendlies"):
		if is_instance_valid(u) and u.is_lord and not u.dead and u.get("skill_comp") != null:
			u.skill_comp.activate()
			return

# ---------------------------------------------------------------- 刷新

func show_banner(text: String, secs: float) -> void:
	show_banner_styled(text, secs, _col("deep_green", Color(0.31, 0.44, 0.32)), 40)

## 卷轴展开横幅(01 §12):scale.x 0.12→1 弹开 + 淡入,停留后淡出
func show_banner_styled(text: String, secs: float, color: Color, font_size: int) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", color)
	banner_label.add_theme_font_size_override("font_size", font_size)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	banner_box.visible = true
	banner_box.pivot_offset = banner_box.size * 0.5
	banner_box.scale = Vector2(0.12, 1.0)
	banner_box.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(banner_box, "scale:x", 1.0, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(banner_box, "modulate:a", 1.0, 0.16)
	_banner_tween.chain().tween_interval(secs)
	_banner_tween.chain().tween_property(banner_box, "modulate:a", 0.0, 0.4)
	_banner_tween.chain().tween_callback(func() -> void: banner_box.visible = false)

## 关羽斩杀白闪(01 §12)
func _on_executed_kill() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.color.a = 0.5
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, 0.3)

func _on_gold_changed(gold: int) -> void:
	if gold_label != null:
		gold_label.text = str(gold)

func _refresh() -> void:
	_refresh_team()
	_refresh_top_right()
	_refresh_skills()
	_refresh_boss_bar()
	_refresh_rage_vignette()

func _unit_of(hero_id: String) -> Node:
	for u in get_tree().get_nodes_in_group("friendlies"):
		if is_instance_valid(u) and str(u.unit_id) == hero_id:
			return u
	return null

func _refresh_team() -> void:
	if team_box == null:
		return
	var follower_i := 0
	for m in RunState.team:
		var hid := str(m.hero_id)
		var is_lord := hid == "liubei"
		if not is_lord:
			follower_i += 1
		var unit := _unit_of(hid)
		if unit != null:
			# 场上单位实时 HP 回写 RunState(结算快照口径)
			m["hp"] = unit.hp
			m["max_hp"] = unit.max_hp
		if not _rows.has(hid):
			_rows[hid] = _build_team_row(hid, is_lord)
		var r: Dictionary = _rows[hid]
		var alive := bool(m.alive)
		var hp_ratio := float(m.hp) / maxf(1.0, float(m.max_hp))
		(r["bar"] as ProgressBar).value = hp_ratio * 100.0
		var slot_label: Label = r["slot"]
		if alive:
			# 槽位角标:武将 1~6 即技能快捷键;主公无角标(01 §10)。
			# 存活武将读场上单位 formation_index+1,与快捷键严格一致(P1-2 全局槽位表)
			if is_lord:
				slot_label.text = "主"
			elif unit != null:
				slot_label.text = "%d" % (int(unit.formation_index) + 1)
			else:
				slot_label.text = "%d" % follower_i
			(r["portrait"] as Control).modulate = Color.WHITE
			slot_label.modulate = Color.WHITE
		else:
			slot_label.text = "0" if is_lord else str(follower_i)
			(r["portrait"] as Control).modulate = Color(0.45, 0.45, 0.45, 0.8)   # 阵亡灰化
			slot_label.modulate = Color(0.5, 0.5, 0.5)
		(r["x"] as Label).visible = not alive                          # 打叉
		var cd := r["cd"] as TextureProgressBar
		if unit != null and unit.get("skill_comp") != null:
			cd.value = unit.skill_comp.cd_ratio()
		else:
			cd.value = 0.0

func _build_team_row(hid: String, is_lord: bool) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	team_box.add_child(row)
	# 头像(点击 = 施放该武将技能,主公同样适用)
	var pb := TextureButton.new()
	pb.custom_minimum_size = Vector2(40, 40)
	pb.ignore_texture_size = true
	pb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	pb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var icon_path := "res://assets/textures/units/%s.png" % hid
	if ResourceLoader.exists(icon_path):
		pb.texture_normal = load(icon_path)
	pb.focus_mode = Control.FOCUS_NONE
	row.add_child(pb)
	# CD 扫罩(头像右下角小圈)
	var cd := TextureProgressBar.new()
	cd.texture_progress = _disc
	cd.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	cd.min_value = 0.0
	cd.max_value = 1.0
	cd.tint_progress = Color(0.1, 0.08, 0.06, 0.55)
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd.set_anchors_preset(Control.PRESET_FULL_RECT)
	pb.add_child(cd)
	var name_l := UiTheme.label(hid, 15, _col("dark_brown", Color.BLACK))
	name_l.custom_minimum_size = Vector2(56, 0)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hero: Dictionary = DataDB.hero_by_id(hid)
	name_l.text = str(hero.get("name", hid))
	row.add_child(name_l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(110, 14)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fg := StyleBoxFlat.new()
	fg.bg_color = _col("spring_green", Color.GREEN)
	bar.add_theme_stylebox_override("fill", fg)
	var bg := StyleBoxFlat.new()
	bg.bg_color = _col("paper_dark", Color(0.9, 0.87, 0.77))
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)
	# 槽位数字角标(主公为「主」)
	var slot_l := UiTheme.label("", 14, _col("dark_brown", Color.BLACK))
	slot_l.custom_minimum_size = Vector2(18, 0)
	slot_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(slot_l)
	# 阵亡打叉
	var x_l := UiTheme.label("✕", 20, _col("cinnabar", Color.RED))
	x_l.visible = false
	x_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(x_l)
	pb.pressed.connect(func() -> void: _cast_portrait(hid))
	return {"portrait": pb, "bar": bar, "cd": cd, "slot": slot_l, "x": x_l}

## 头像点击施放(主公技能的施放入口,武将亦可用)
func _cast_portrait(hero_id: String) -> void:
	if get_tree().paused:
		return
	var unit := _unit_of(hero_id)
	if unit != null and unit.get("skill_comp") != null:
		unit.skill_comp.activate()

func _refresh_top_right() -> void:
	var total := DataDB.waves.size()
	wave_label.text = "第 %d/%d 波" % [RunState.wave_idx, total]
	var wd := get_tree().get_first_node_in_group("wave_director")
	if wd != null and wd.wave_data.has("duration"):
		time_bar.max_value = float(wd.wave_data["duration"])
		if wd.state == wd.State.BATTLE:
			var remain := maxf(0.0, float(wd.wave_data["duration"]) - wd.battle_t)
			time_bar.value = remain
			if time_secs != null:
				# W8 Boss 战:计时到后战斗继续,改示「斩华雄」
				if wd.wave_idx >= total and wd._w8_timeup_done:
					time_secs.text = "斩华雄,方可结束!"
				else:
					time_secs.text = "剩余 %d 秒" % int(ceil(remain))
		else:
			time_bar.value = time_bar.max_value
			if time_secs != null:
				time_secs.text = ""

## Boss 血条(第 8 波):在场即显示,HP 实时;二阶段名称加「狂暴」并换深红(01 §10)
func _refresh_boss_bar() -> void:
	if boss_bar == null:
		return
	var boss: Node = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead and bool(e.get("boss")):
			boss = e
			break
	if boss == null:
		boss_bar.get_parent().visible = false
		return
	boss_bar.get_parent().visible = true
	boss_bar.max_value = maxf(1.0, float(boss.max_hp))
	boss_bar.value = maxf(0.0, float(boss.hp))
	if bool(boss.get("phase2")):
		boss_name.text = "华雄 · 狂暴"
		boss_phase_tag.text = "阶段 2 · 移速攻速提升,召唤西凉亲卫"
		boss_name.add_theme_color_override("font_color",
			Color(0.9, 0.2 + 0.15 * absf(sin(Time.get_ticks_msec() * 0.008)), 0.15))
		(boss_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(0.78, 0.16, 0.12)
	else:
		boss_name.text = "华雄 · 都督之威"
		boss_phase_tag.text = ""
		boss_name.add_theme_color_override("font_color", _col("cinnabar", Color(0.71, 0.29, 0.23)))
		(boss_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = _col("cinnabar", Color(0.71, 0.29, 0.23))

## 张飞狂化红晕:任一张飞狂化 → 淡入,否则淡出(01 §12)
func _refresh_rage_vignette() -> void:
	if _rage_rect == null:
		return
	var rage := false
	for u in get_tree().get_nodes_in_group("friendlies"):
		if is_instance_valid(u) and not u.dead and bool(u.get("_enraged")):
			rage = true
			break
	_rage_target = 0.42 if rage else 0.0
	var cur: float = _rage_rect.modulate.a
	if absf(cur - _rage_target) > 0.02:
		_rage_rect.modulate.a = lerpf(cur, _rage_target, 0.35)

## 技能栏 6 格刷新:CD 转圈 / 阵亡禁用 / 就绪脉冲 / 吕布「不受令」延迟红闪(01 §10)
func _refresh_skills() -> void:
	for b in _bound:
		var slot := int(b.slot)
		if slot < 1 or slot > skill_buttons.size():
			continue
		# 无类型读取:武将阵亡后 comp 可能是已释放实例,类型化赋值会在有效性判断前报错
		# (原 hud.gd:528 每帧 SCRIPT ERROR ×76,验收硬指标必须归零)
		var comp = b.comp
		var btn := skill_buttons[slot - 1]
		var cd := _skill_cd[slot - 1]
		var secs := _skill_cd_secs[slot - 1]
		if comp == null or not is_instance_valid(comp) or comp.host == null \
				or not is_instance_valid(comp.host) or comp.host.dead:
			btn.disabled = true
			btn.modulate = Color(0.45, 0.45, 0.45)
			cd.value = 0.0
			secs.text = ""
			_skill_prev_cd[slot - 1] = 0.0
			continue
		btn.disabled = false
		btn.modulate = Color.WHITE
		var ratio: float = comp.cd_ratio()
		# CD 走完瞬间:按钮脉冲(M6 手感打磨)
		if _skill_prev_cd[slot - 1] > 0.0 and ratio <= 0.0:
			_pulse_button(btn)
		_skill_prev_cd[slot - 1] = ratio
		cd.value = ratio
		secs.text = ("%d" % int(ceil(comp.cd_left))) if ratio > 0.0 else ""
		if comp.delayed_left >= 0.0:
			# 吕布「不受令」延迟期间红闪(01 §10)
			btn.modulate = Color(1.0, 0.35 + 0.3 * absf(sin(Time.get_ticks_msec() * 0.012)), 0.3)
		elif ratio <= 0.0:
			btn.modulate = Color(1.08, 1.08, 1.02)
		else:
			btn.modulate = Color.WHITE

## 就绪脉冲:缩放 1→1.16→1(以格心为轴)
func _pulse_button(btn: Button) -> void:
	btn.pivot_offset = btn.size * 0.5
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2(1.16, 1.16), 0.09)
	tw.tween_property(btn, "scale", Vector2.ONE, 0.16)
