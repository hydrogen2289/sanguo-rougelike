extends Node
## SceneRouter —— 场景路由 autoload(M3;M7 扩展三层路由,02 §7/§13.2-M7)。
## 全链路(01 §10):主菜单 → 主城 →(战役/试炼塔)→ 战斗 → 结算 → 回主城/主菜单。
## 进战斗前由路由器负责 RunState.reset(seed) + 注入模式上下文(02 §8.1)。

signal city_enter_failed(reason: String)   # 坏档拒绝进主城(02 §3.2),主菜单横幅承接

const MAIN_SCENE := "res://scenes/main.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const PROLOGUE_SCENE := "res://scenes/ui/prologue.tscn"
const CITY_SCENE := "res://scenes/city/main_city.tscn"    # M7 主城(02 §6.2)

## 新档首次进主城:序章确认后改道主城(prologue.gd 零改动,goto_battle(false) 拦截)。
var _prologue_to_city := false

func _ready() -> void:
	call_deferred("_boot_route")

## M3:main.tscn 引导场景路由进主菜单(界面流程 01 §10)。
func _boot_route() -> void:
	var cs := get_tree().current_scene
	if cs != null and cs.scene_file_path == MAIN_SCENE:
		goto_menu()

## M3 旧路径(语义收窄为内部/冒烟沿用,02 §11):reset → 序章 → 战斗(默认塔模式)。
## 正式入口已移至「进入主城」(goto_city)与主菜单塔调试快捷键(goto_tower)。
func start_run() -> void:
	RunState.reset()
	_goto(PROLOGUE_SCENE)

## 「进入主城」(02 §7):有档 → 读档进主城;无档 → 新档 + 首次播序章
## (一次性 settings.prologue_seen);坏档校验失败 → 拒绝进入,横幅交主菜单。
func goto_city() -> void:
	var res: Dictionary = SaveState.load_game()
	if not bool(res.get("ok", false)):
		city_enter_failed.emit(str(res.get("reason", "存档损坏")))
		return                       # fail fast:不进主城,存档文件原样保留
	if bool(res.get("warned", false)):
		print("[SceneRouter] " + str(res.get("reason", "")))
	if not bool(SaveState.data.get("settings", {}).get("prologue_seen", false)):
		_prologue_to_city = true
		RunState.reset()
		_goto(PROLOGUE_SCENE)
		return
	_goto(CITY_SCENE)

## 序章确认改道(新档首进主城):prologue.confirm() 走 goto_battle(false),此处拦截。
func goto_battle(reset := true) -> void:
	if _prologue_to_city and not reset:
		_prologue_to_city = false
		SaveState.mark_prologue_seen()
		_goto(CITY_SCENE)
		return
	if reset:
		RunState.reset()
	_goto(BATTLE_SCENE)

## 战役入口(02 §7 / M9):读关卡表真实路由——坏 id 拒绝(不切场景,返回 false);
## 合法 id 注入模式上下文(stage_id + wave_total)后进战斗,波次由 wave_director 双源改造读取。
func goto_stage(stage_id: String) -> bool:
	if DataDB.stage_by_id(stage_id).is_empty():
		printerr("[SceneRouter] 闯关拒绝:关卡不存在 '%s'" % stage_id)
		return false
	prepare_campaign(stage_id)
	_goto(BATTLE_SCENE)
	return true

## 试炼塔入口(02 §7):自第 1 层;1~8 层沿用现剧本,M10 接塔层推进与随机波次。
func goto_tower() -> void:
	prepare_tower()
	_goto(BATTLE_SCENE)

## 模式上下文注入(02 §8.1):闯关 = {stage_id, wave_total}。
## wave_total 从关卡表带出(wave_director 闯关模式判定末波用);关卡不存在时为 0(路由层已拒绝)。
func prepare_campaign(stage_id: String) -> void:
	RunState.reset()
	RunState.mode = &"campaign"
	var stage: Dictionary = DataDB.stage_by_id(stage_id)
	var total := 0
	if not stage.is_empty():
		total = (stage.get("waves", []) as Array).size()
	RunState.context = {"stage_id": stage_id, "wave_total": total}

## 模式上下文注入(02 §8.1):塔 = {floor_start, endless}。
## 主城/主菜单「爬塔」入口为无尽模式(M10:杀 Boss 过层,1~8 层沿用 waves.json、
## 9+ 层由 tower_wave_gen 生成);难度一律按本局当前层算(02 §4.4 默认口径)。
func prepare_tower() -> void:
	RunState.reset()
	RunState.mode = &"tower"
	RunState.context = {"floor_start": 1, "endless": true}

## 「再来一局」:重置后直接进战斗,不重播序章(01 §10 一键重开)。
func restart_battle() -> void:
	goto_battle(true)

func goto_menu() -> void:
	SaveState.flush()                  # 退回主菜单落盘(02 §3.1 写盘时机)
	_goto(MENU_SCENE)

func _goto(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
