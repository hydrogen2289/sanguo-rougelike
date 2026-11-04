extends Node
## SceneRouter —— 场景路由 autoload(M3)。
## 全链路(01 §10):主菜单 → 序章「桃园结义」→ 战斗 → 结算 → 再来一局 / 回主菜单。

const MAIN_SCENE := "res://scenes/main.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const PROLOGUE_SCENE := "res://scenes/ui/prologue.tscn"

func _ready() -> void:
	call_deferred("_boot_route")

## M3:main.tscn 引导场景路由进主菜单(界面流程 01 §10)。
func _boot_route() -> void:
	var cs := get_tree().current_scene
	if cs != null and cs.scene_file_path == MAIN_SCENE:
		goto_menu()

## 「开始游戏」:重置单局状态 → 序章(可跳过)。
func start_run() -> void:
	RunState.reset()
	_goto(PROLOGUE_SCENE)

## 进入战斗。reset=true 时重置 RunState(再来一局 / 调试直入);
## 序章确认后走 reset=false,保留 start_run 已建好的单局状态。
func goto_battle(reset := true) -> void:
	if reset:
		RunState.reset()
	_goto(BATTLE_SCENE)

## 「再来一局」:重置后直接进战斗,不重播序章(01 §10 一键重开)。
func restart_battle() -> void:
	goto_battle(true)

func goto_menu() -> void:
	_goto(MENU_SCENE)

func _goto(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
