extends Node
## SaveState —— 跨局持久状态唯一入口(M7,02 §3)。
## schema v1 见 02 §3.2:wallet / roster / squad / campaign / tower / stats / settings。
## 落盘 user://save_v1.json(Windows:%APPDATA%\Godot\app_userdata\桃源乱武\)。
## 原子写:先写 .tmp 再 rename 覆盖;覆盖前旧文件复制为 .bak(单级回滚);
## 加载:JSON 解析失败 → 尝试 .bak → 再失败按新档处理并横幅告警;
## 校验:_validate() 拦截非法值(id 合法性 / level-star 区间 / 军资非负 / 席位约束),
## 坏档 fail fast 拒绝进入主城(与 DataDB fail fast 风格一致,02 §3.2)。
## 版本迁移:根字段 version,逐级升级;当前只有 v1,迁移骨架(_steps 注册点)先建。
## 不存局内态:局内 build(遗物/强化/军资/临时武将)只存在于 RunState,不入存档(02 §8.4)。

signal wallet_changed                 # TopBar 订阅(M7)
signal save_flushed                   # 存档落盘完成(TopBar「已存档」提示)
signal save_load_failed(reason: String)   # 坏档校验失败(拒绝进主城)

const CURRENT_VERSION := 1
const LEVEL_CAP := 30                 # 等级域 [1,30](02 §5.1,占位锚点)
const STAR_CAP := 5                   # 星级域 [1,5](02 §5.2,占位锚点)
const MAX_SLOT_CAP := 7               # 席位上限锚点(塔 7 = RunState.MAX_TEAM)
const INITIAL_SLOT_CAP := 3           # 闯关初始 3 席(主公 + 2,提案,01 §13-1)
const CHAPTER1_STAGES := 8            # 第一章 8 关(占位,01 §3.5;M9 由 campaign.json 驱动)

## 存档文件名(测试/冒烟可改用隔离文件,结束恢复默认;不改 product 路径语义)
var save_file := "save_v1.json"
var data: Dictionary = {}             # 当前会话存档(空 = 未初始化)
var last_note := ""                   # 最近一次加载的提示(备份恢复/坏档重开,主城横幅用)

## 迁移注册点:from_version -> Callable(data)->Dictionary(失败返回 {})。
## 未来版本在发布时登记 _steps[旧版本],migrate 逐级走梯子(02 §3.1)。
var _steps: Dictionary = {}

var _session_writable := false        # 校验失败的坏档会话禁止 flush(防误覆盖好档)
var _last_errors: PackedStringArray = PackedStringArray()

# ---------------------------------------------------------------- 路径

func _path() -> String:
	return "user://" + save_file

func _path_tmp() -> String:
	return _path() + ".tmp"

func _path_bak() -> String:
	return _path() + ".bak"

func has_save() -> bool:
	return FileAccess.file_exists(_path())

# ---------------------------------------------------------------- 生命周期

## 不在 _ready 自动读档:主菜单「进入主城」经 SceneRouter.goto_city() 显式读档(02 §7)。
## 退出游戏落盘(02 §3.1 写盘时机:……退回主菜单、退出游戏;回主菜单的 flush 在 SceneRouter.goto_menu)。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()

# ---------------------------------------------------------------- 默认档(02 §3.2 schema)

func default_save() -> Dictionary:
	var roster := {}
	for h in DataDB.heroes:
		var id := str(h.get("id", ""))
		if id.is_empty():
			continue
		var owned: bool = RunState.INITIAL_TEAM.has(id)   # 桃园三人组开局即有(01 §2.2)
		roster[id] = {
			"owned": owned,
			"level": 1 if owned else 0,
			"star": 1 if owned else 0,
			"source": "initial" if owned else "",
		}
	return {
		"version": CURRENT_VERSION,
		"updated_at": _now_iso(),
		"wallet": {"junzi": 0, "fragments": {}},
		"roster": roster,
		"squad": {"slots": RunState.INITIAL_TEAM.duplicate(), "slot_cap": INITIAL_SLOT_CAP},
		"campaign": {
			"chapters": {"ch1": {"unlocked": true, "stages": _default_ch1_stages()}},
			"boxes": {"ch1": {"3": false, "6": false, "9": false}},
		},
		"tower": {"highest_floor": 0},
		"stats": {"total_runs": 0, "total_kills": 0, "tower_best_kill": 0},
		"settings": {"master_volume": 1.0, "prologue_seen": false},
	}

## 第一章占位(01 §3.5:8 关);M9 campaign.json 落地后改为表驱动生成。
func _default_ch1_stages() -> Dictionary:
	var stages := {}
	for i in range(1, CHAPTER1_STAGES + 1):
		stages["1-%d" % i] = {"cleared": false, "stars": 0}
	return stages

func _now_iso() -> String:
	return Time.get_datetime_string_from_system(false, false)   # YYYY-MM-DDTHH:MM:SS(02 §3.2)

# ---------------------------------------------------------------- 读取

## 读档入口(02 §7「进入主城」)。返回 {ok, created, warned, reason}:
## ok=false → 校验失败/版本不可识别,拒绝进入主城(横幅交主菜单,存档文件原样保留);
## created=true → 无档(或坏档重开)已建内存新档;warned=true → 有横幅级提示(last_note)。
func load_game() -> Dictionary:
	_last_errors = PackedStringArray()
	last_note = ""
	if not has_save():
		data = default_save()
		_session_writable = true
		return {"ok": true, "created": true, "warned": false, "reason": ""}
	var parsed = JSON.parse_string(_read_text(_path()))
	var used_bak := false
	if parsed == null:
		parsed = JSON.parse_string(_read_text(_path_bak()))   # .bak 单级回滚(02 §3.1)
		used_bak = parsed != null
	if parsed == null:
		# 主档 + 备份均不可解析 → 按新档处理并横幅告警(02 §3.1)
		data = default_save()
		_session_writable = true
		last_note = "存档损坏且无有效备份,已重开新档"
		return {"ok": true, "created": true, "warned": true, "reason": last_note}
	var migrated := migrate(parsed)
	if migrated.is_empty():
		_session_writable = false
		last_note = "存档版本无法识别(可能来自更新版本的游戏)"
		return {"ok": false, "created": false, "warned": false, "reason": last_note}
	var fixed := normalize(migrated)
	var errs := validate(fixed)
	if not errs.is_empty():
		_session_writable = false
		_last_errors = errs
		last_note = errs[0]
		var reason := "存档校验失败,拒绝进入主城: " + errs[0]
		save_load_failed.emit(reason)
		return {"ok": false, "created": false, "warned": false, "reason": reason}
	data = fixed
	_session_writable = true
	if used_bak:
		last_note = "主存档损坏,已从备份 .bak 恢复"
		return {"ok": true, "created": false, "warned": true, "reason": last_note}
	return {"ok": true, "created": false, "warned": false, "reason": ""}

func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

# ---------------------------------------------------------------- 写盘(原子写,02 §3.1)

## 唯一写盘入口:结算入库 / 招募合成 / 升级升星 / 评星宝箱 / 退回主菜单 / 退出游戏均调本函数。
func flush() -> void:
	if data.is_empty():
		return                       # 未初始化(从未进过主城)不落盘
	if not _session_writable:
		return                       # 坏档会话:拒绝覆盖磁盘上的原档
	data["updated_at"] = _now_iso()
	var dir := DirAccess.open("user://")
	if dir == null:
		printerr("[SaveState] user:// 目录不可达,存档未落盘")
		return
	if dir.file_exists(save_file):
		# DirAccess.copy 对相对路径解析不稳(实测 err=7),备份走 user:// 全路径
		var cerr := dir.copy(_path(), _path_bak())   # 写前备份(单级回滚)
		if cerr != OK:
			printerr("[SaveState] .bak 备份失败 err=%d(继续写入)" % cerr)
	var f := FileAccess.open(_path_tmp(), FileAccess.WRITE)
	if f == null:
		printerr("[SaveState] 临时档打开失败:%s" % _path_tmp())
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	if dir.file_exists(save_file + ".tmp"):
		var rerr := dir.rename(save_file + ".tmp", save_file)   # 原子覆盖
		if rerr != OK:
			# rename 偶发被占用(Windows 杀软扫描等)→ 直接覆写兜底
			printerr("[SaveState] rename 失败 err=%d,退化为直接覆写" % rerr)
			var f2 := FileAccess.open(_path(), FileAccess.WRITE)
			if f2 != null:
				f2.store_string(JSON.stringify(data, "  "))
				f2.close()
	save_flushed.emit()

## 删档(save + tmp + bak),回到「无档」状态;删档重开验收(验收项 5)与测试用。
func delete_save() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		for p in [save_file, save_file + ".tmp", save_file + ".bak"]:
			if dir.file_exists(p):
				dir.remove(p)
	data = {}
	_session_writable = false
	last_note = ""

# ---------------------------------------------------------------- 版本迁移(02 §3.1)

## 逐级升级:while version < CURRENT_VERSION 走 _steps[version];
## 版本 <1 或 >CURRENT(过新)→ 返回 {} 由调用方按不可识别处理(拒绝覆盖)。
func migrate(d: Dictionary) -> Dictionary:
	if d == null:
		return {}
	var v := int(d.get("version", -1))
	if v < 1 or v > CURRENT_VERSION:
		return {}
	while v < CURRENT_VERSION or _steps.has(v):
		# 梯子推进:版本落后走既定步骤;CURRENT 之上仅当显式登记了步骤才继续(测试可观测,防缺步死档)
		var step = _steps.get(v)
		if step == null:
			return {}                # 缺迁移步骤 = 迁移骨架未覆盖,按不可识别处理
		var out = step.call(d)
		if out == null or (out as Dictionary).is_empty():
			return {}
		d = out
		var nv := int(d.get("version", -1))
		if nv <= v:
			return {}                # 迁移步骤未推进版本号,防死循环
		v = nv
	return d

## 结构修复:缺失/类型不符的段落按默认档回填(版本内字段增补),再交 validate 硬校验。
func normalize(d: Dictionary) -> Dictionary:
	var base := default_save()
	for k in base:
		if not d.has(k):
			d[k] = base[k]
	# wallet
	var w: Dictionary = d["wallet"] if d["wallet"] is Dictionary else base["wallet"]
	if not (w.get("junzi") is int) and not (w.get("junzi") is float):
		w["junzi"] = 0
	if not (w.get("fragments") is Dictionary):
		w["fragments"] = {}
	d["wallet"] = w
	# roster:逐 id 回填(覆盖 DataDB 全部 id,含未拥有)
	var r: Dictionary = d["roster"] if d["roster"] is Dictionary else base["roster"]
	var fixed_roster := {}
	for id in base["roster"]:
		var e = r.get(id)
		if not (e is Dictionary):
			fixed_roster[id] = base["roster"][id]
			continue
		var good: Dictionary = base["roster"][id]
		var entry := {}
		entry["owned"] = bool(e.get("owned", good["owned"]))
		entry["level"] = int(e.get("level", good["level"]))
		entry["star"] = int(e.get("star", good["star"]))
		entry["source"] = str(e.get("source", good["source"]))
		fixed_roster[id] = entry
	d["roster"] = fixed_roster
	# squad
	var sq: Dictionary = d["squad"] if d["squad"] is Dictionary else base["squad"]
	if not (sq.get("slots") is Array):
		sq["slots"] = base["squad"]["slots"]
	sq["slot_cap"] = int(sq.get("slot_cap", base["squad"]["slot_cap"]))
	d["squad"] = sq
	# campaign / boxes(结构存在即可,关卡合法性归 M9 表校验)
	if not (d["campaign"] is Dictionary):
		d["campaign"] = base["campaign"]
	var cp: Dictionary = d["campaign"]
	if not (cp.get("chapters") is Dictionary):
		cp["chapters"] = {}
	if not (cp.get("boxes") is Dictionary):
		cp["boxes"] = {}
	# tower / stats / settings 标量回填
	if not (d["tower"] is Dictionary):
		d["tower"] = base["tower"]
	d["tower"]["highest_floor"] = int(d["tower"].get("highest_floor", 0))
	if not (d["stats"] is Dictionary):
		d["stats"] = base["stats"]
	if not (d["settings"] is Dictionary):
		d["settings"] = base["settings"]
	d["settings"]["master_volume"] = float(d["settings"].get("master_volume", 1.0))
	d["settings"]["prologue_seen"] = bool(d["settings"].get("prologue_seen", false))
	d["version"] = int(d.get("version", CURRENT_VERSION))
	return d

# ---------------------------------------------------------------- 校验(02 §3.2)

## 硬校验:返回错误列表,空 = 通过。坏档 → load_game 拒绝进入主城(fail fast)。
func validate(d: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	if int(d.get("version", -1)) != CURRENT_VERSION:
		errs.append("version=%s 应为 %d" % [str(d.get("version")), CURRENT_VERSION])
	# wallet:军资非负、碎片非负
	var w: Dictionary = d.get("wallet", {})
	if float(w.get("junzi", -1)) < 0.0:
		errs.append("军资为负(%s)" % str(w.get("junzi")))
	for hid in w.get("fragments", {}):
		if float(w["fragments"][hid]) < 0.0:
			errs.append("碎片为负:%s" % str(hid))
	# roster:id 合法 + 区间
	var legal_ids := {}
	for h in DataDB.heroes:
		legal_ids[str(h.get("id", ""))] = true
	var roster: Dictionary = d.get("roster", {})
	for id in roster:
		if not legal_ids.has(str(id)):
			errs.append("roster 含非法武将 id: %s" % str(id))
			continue
		var e: Dictionary = roster[id]
		var owned := bool(e.get("owned", false))
		var lv := int(e.get("level", 0))
		var st := int(e.get("star", 0))
		if not owned:
			if lv != 0 or st != 0:
				errs.append("%s 未拥有但 level=%d star=%d" % [str(id), lv, st])
		else:
			if lv < 1 or lv > LEVEL_CAP:
				errs.append("%s level=%d 越出 [1,%d]" % [str(id), lv, LEVEL_CAP])
			if st < 1 or st > STAR_CAP:
				errs.append("%s star=%d 越出 [1,%d]" % [str(id), st, STAR_CAP])
	# squad:slots[0] 恒为主公、唯一、合法且已拥有、数量 ≤ 席位
	var sq: Dictionary = d.get("squad", {})
	var slots: Array = sq.get("slots", [])
	var slot_cap := int(sq.get("slot_cap", INITIAL_SLOT_CAP))
	if slot_cap < 1 or slot_cap > MAX_SLOT_CAP:
		errs.append("slot_cap=%d 越出 [1,%d]" % [slot_cap, MAX_SLOT_CAP])
	if slots.is_empty():
		errs.append("squad.slots 为空(主公必须上阵)")
	else:
		if str(slots[0]) != "liubei":
			errs.append("slots[0]=%s 应为主公 liubei" % str(slots[0]))
		var seen := {}
		for s in slots:
			var sid := str(s)
			if not legal_ids.has(sid) or not roster.has(sid) \
					or not bool(roster[sid].get("owned", false)):
				errs.append("席位含非法/未拥有武将: %s" % sid)
			if seen.has(sid):
				errs.append("席位重复: %s" % sid)
			seen[sid] = true
		if slots.size() > slot_cap:
			errs.append("上阵 %d 超出席位 %d" % [slots.size(), slot_cap])
	# campaign:章节结构 + 评星区间
	var chapters: Dictionary = d.get("campaign", {}).get("chapters", {})
	for cid in chapters:
		var ch: Dictionary = chapters[cid]
		if not (ch.get("stages") is Dictionary):
			errs.append("章节 %s 缺 stages" % str(cid))
			continue
		for sid in ch["stages"]:
			var stg: Dictionary = ch["stages"][sid]
			var stars := int(stg.get("stars", 0))
			if stars < 0 or stars > 3:
				errs.append("关卡 %s 评星 %d 越出 [0,3]" % [str(sid), stars])
	# tower / stats 非负
	if int(d.get("tower", {}).get("highest_floor", -1)) < 0:
		errs.append("最高层为负")
	for k in d.get("stats", {}):
		if float(d["stats"][k]) < 0.0:
			errs.append("统计 %s 为负" % str(k))
	var sv := float(d.get("settings", {}).get("master_volume", 1.0))
	if sv < 0.0 or sv > 1.0:
		errs.append("master_volume=%.2f 越出 [0,1]" % sv)
	return errs

# ---------------------------------------------------------------- 钱库 API(TopBar / M8 养成共用)

func _wallet() -> Dictionary:
	if not (data.get("wallet") is Dictionary):
		data["wallet"] = {"junzi": 0, "fragments": {}}
	return data["wallet"]

func junzi() -> int:
	return int(_wallet().get("junzi", 0))

func add_junzi(v: int) -> void:
	_wallet()["junzi"] = maxi(0, junzi() + v)
	wallet_changed.emit()

func try_spend_junzi(v: int) -> bool:
	if junzi() < v:
		return false
	_wallet()["junzi"] = junzi() - v
	wallet_changed.emit()
	return true

func _fragments() -> Dictionary:
	if not (_wallet().get("fragments") is Dictionary):
		_wallet()["fragments"] = {}
	return _wallet()["fragments"]

func fragments_of(hero_id: String) -> int:
	return int(_fragments().get(hero_id, 0))

## 定向碎片:按武将分别记账(提案:货币仅军资 + 定向武将碎片两种,01 §13-2)
func add_fragments(hero_id: String, v: int) -> void:
	var fr := _fragments()
	fr[hero_id] = maxi(0, fragments_of(hero_id) + v)
	wallet_changed.emit()

func fragments_total() -> int:
	var total := 0
	for k in _fragments():
		total += int(_fragments()[k])
	return total

## 序章一次性标记(02 §7:settings.prologue_seen;新档首进主城播完即置)
func mark_prologue_seen() -> void:
	if data.get("settings") is Dictionary:
		data["settings"]["prologue_seen"] = true
