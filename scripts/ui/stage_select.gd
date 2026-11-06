extends Control
## 选关页(M9,01 §3.1/§3.3/§3.4、02 §6.2/§7):章节卷轴 + 关卡节点列表。
## 每关显示:编号/名称/评星(历史最高)/已通关态/锁定态(通关前一关解锁,01 §3.4)/
## 未通关显示首通奖励预览,已通关显示重复奖励;Boss 关标注。
## 章节头显示总星数与评星宝箱(3/6/9 星档,01 §3.3 占位;领取走 CampaignSave → SaveState 钱包)。
## 点已解锁关卡 → 发 stage_chosen 信号,由 main_city 接编队确认(squad_edit 复用)→ 开战。
## 数据源:DataDB.campaign(表)+ CampaignSave(save 读写);音效走 UiTheme.button 按钮音(02 §10)。

signal stage_chosen(stage_id: String)

const PANEL_SIZE := Vector2(1280, 720)
const NAME_COLOR := Color(0.35, 0.27, 0.2)
const LOCK_COLOR := Color(0.55, 0.50, 0.44)
const GOLD_COLOR := Color(0.79, 0.66, 0.42)

var _list: VBoxContainer

func _ready() -> void:
	add_to_group("modal")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiTheme.dim_bg())
	var panel := UiTheme.scroll_panel(PANEL_SIZE)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -PANEL_SIZE * 0.5
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	vb.add_child(head)
	head.add_child(UiTheme.label("战 役", 32, UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23)), 5))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UiTheme.button("收 起", 19, Vector2(120, 46))
	close.pressed.connect(_on_close)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 580)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_rebuild()

func _on_close() -> void:
	queue_free()

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	CampaignSave.ensure_progress()
	for ch in DataDB.chapter_list():
		_build_chapter(ch)

# ---------------------------------------------------------------- 章节

func _build_chapter(ch: Dictionary) -> void:
	var cid := str(ch.get("id", ""))
	if not CampaignSave.chapter_unlocked(cid):
		# 未解锁章节(01 §3.4:通关整章解锁下一章):只给一行灰置预告
		_list.add_child(UiTheme.label(
			"第 %d 章 · %s(通关上一章解锁)" % [int(ch.get("order", 0)), str(ch.get("name", ""))],
			22, LOCK_COLOR, 3))
		return
	var stars := CampaignSave.chapter_stars(cid)
	var max_stars := 3 * (ch.get("stages", []) as Array).size()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_list.add_child(head)
	var title := UiTheme.label("第 %d 章 · %s    ★%d/%d" % [int(ch.get("order", 0)), str(ch.get("name", "")), stars, max_stars],
		24, UiTheme.col("deep_green", Color(0.31, 0.44, 0.32)), 3)
	head.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	# 评星宝箱(01 §3.3/§8.2 占位:3/6/9 星各 1 箱)
	var box_state := CampaignSave.box_state(cid)
	for t in CampaignSave.BOX_TIERS:
		var tier := int(t)
		var claimed := bool(box_state.get(tier, false))
		var reward := int(CampaignSave.BOX_REWARDS.get(tier, 0))
		var box := UiTheme.button("宝箱★%d(+%d)" % [tier, reward], 15, Vector2(150, 38))
		box.tooltip_text = "章节总星数达 %d 可领取" % tier
		if claimed:
			box.disabled = true
			box.text = "宝箱★%d 已领" % tier
		else:
			box.disabled = stars < tier
			box.pressed.connect(_on_claim_box.bind(cid, tier))
		head.add_child(box)
	# 关卡列表
	for st in ch.get("stages", []):
		_list.add_child(_stage_row(st))

func _on_claim_box(cid: String, tier: int) -> void:
	var r: Dictionary = CampaignSave.claim_box(cid, tier)
	if not bool(r.get("ok", false)):
		print("[StageSelect] 宝箱领取被拒: " + str(r.get("reason", "")))
		return
	SaveState.flush()                     # 领取即落盘(02 §3.1 写盘时机)
	Sfx.play("coin", -4.0)
	_rebuild()

# ---------------------------------------------------------------- 关卡行

func _stage_row(st: Dictionary) -> Control:
	var sid := str(st.get("id", ""))
	var unlocked := CampaignSave.is_unlocked(sid)
	var state: Dictionary = CampaignSave.stage_state(sid)
	var cleared := bool(state.get("cleared", false))
	var stars := int(state.get("stars", 0))
	var fc: Dictionary = st.get("first_clear", {})
	var rc: Dictionary = st.get("repeat_clear", {})
	var b := Button.new()
	b.add_to_group("stage_entry")
	b.set_meta("stage_id", sid)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 72)
	for kind in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(kind, UiTheme.panel_style())
	if not unlocked:
		b.disabled = true
		b.modulate = Color(1, 1, 1, 0.55)
		b.tooltip_text = "通关前一关解锁(01 §3.4 推图规则)"
	else:
		b.pressed.connect(_on_stage_pressed.bind(sid))
	var star_txt := ""
	for i in 3:
		star_txt += "★" if i < stars else "☆"
	var boss_tag := "【Boss关】" if bool(st.get("boss_stage", false)) else ""
	var status := ""
	if not unlocked:
		var ua := str(st.get("unlock_after", ""))
		var ua_name := str(DataDB.stage_by_id(ua).get("name", ua))
		status = "未解锁 · 通关「%s」开启" % ua_name
	elif cleared:
		status = "已通关 %s · 可重打(重复奖励 军资+%d)" % [star_txt, int(rc.get("junzi", 0))]
	else:
		status = "首通 军资+%d" % int(fc.get("junzi", 0))
		for hid in fc.get("fragments", {}):
			status += " %s碎片×%d" % [str(DataDB.hero_by_id(str(hid)).get("name", hid)), int(fc["fragments"][hid])]
		status += " · 推荐战力 %d" % int(st.get("rec_power", 0))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	b.add_child(row)
	var id_l := UiTheme.label(sid, 26, UiTheme.col("cinnabar", Color(0.71, 0.29, 0.23)), 3)
	id_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(id_l)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mid)
	var name_l := UiTheme.label(str(st.get("name", "")) + boss_tag, 22, NAME_COLOR, 3)
	mid.add_child(name_l)
	var status_l := UiTheme.label(status, 15, LOCK_COLOR, 2)
	mid.add_child(status_l)
	var right := UiTheme.label(star_txt if (unlocked and cleared) else ("已解锁" if unlocked else "锁"),
		24, UiTheme.col("gold", GOLD_COLOR), 3)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	return b

func _on_stage_pressed(stage_id: String) -> void:
	Sfx.play("horn", -10.0)               # 出征号角(沿用现有音色,02 §10 零新依赖)
	stage_chosen.emit(stage_id)
