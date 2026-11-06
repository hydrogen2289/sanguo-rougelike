extends SceneTree
## 自测入口(02 §9):godot.cmd --headless --path <工程> --script res://tests/run_all.gd
## 汇总执行全部测试套件;任一失败退出码非 0。
## 现 7 套件:原 5 套件 + test_rig(3D 立牌表现升级) + test_levels(关卡剧本 v0.2);0 跳过全绿。
## M7:增 SaveState autoload(第 6 个)与 test_save 存档套件(02 §12.2-1)。
## 注意:--script 模式下 ProjectSettings autoload 不自动实例化 ——
## 此处先手动把六个 autoload 挂到 /root(名称与注册名一致),
## 之后经 load() 加载的套件/场景脚本里全局标识符(RunState/DataDB/…)方可解析;
## 本入口自身不得直接引用 autoload 标识符(编译早于注册,会报 Identifier not found)。

const AUTOLOADS := [
	["DataDB", "res://scripts/autoload/data_db.gd"],
	["SaveState", "res://scripts/autoload/save_state.gd"],
	["RunState", "res://scripts/autoload/run_state.gd"],
	["EventBus", "res://scripts/autoload/event_bus.gd"],
	["SceneRouter", "res://scripts/autoload/scene_router.gd"],
	["Sfx", "res://scripts/autoload/sfx.gd"],
]

const TESTS := [
	"res://tests/test_data.gd",
	"res://tests/test_textures.gd",
	"res://tests/test_formulas.gd",
	"res://tests/test_rig.gd",
	"res://tests/test_flow.gd",
	"res://tests/test_balance_sim.gd",
	"res://tests/test_levels.gd",
	"res://tests/test_save.gd",
	"res://tests/test_meta.gd",
	"res://tests/test_campaign.gd",   # M9 组队闯关(表/评星/奖励入库/推图解锁/选关链路)
	"res://tests/test_tower_gen.gd",  # M10 试炼塔(随机波次生成器契约 + 塔层推进)
	"res://tests/test_tower_climb.gd",# M10 试炼塔端到端(真场景连爬 12 层 + 真实弹窗 + 撤退入库)
	"res://tests/test_reward.gd",     # M11 结算统一管道(奖励清单/局内军资不入库/经济闭环)
]

func _initialize() -> void:
	_register_autoloads()
	_run_suites()   # 协程:先等场景树激活(--script 模式首帧前树未就绪),再跑套件

func _run_suites() -> void:
	var total_p := 0
	var total_f := 0
	var skips := 0
	var failed_suites: PackedStringArray = PackedStringArray()
	# 等树激活:--script 模式下 _initialize 期间 add_child 的节点尚未入树,
	# _ready 推迟到首帧;用哨兵节点确认 is_inside_tree 后才执行场景级套件。
	var sentinel := Node.new()
	sentinel.name = "TreeSentinel"
	root.add_child(sentinel)
	var tries := 0
	while not sentinel.is_inside_tree() and tries < 10:
		await process_frame
		tries += 1
	sentinel.queue_free()
	if not sentinel.is_inside_tree() and tries >= 10:
		printerr("[run_all] 场景树未激活(--script 模式异常),中止")
		quit(1)
		return
	for path in TESTS:
		print("== %s ==" % path)
		if not FileAccess.file_exists(path):
			total_f += 1
			failed_suites.append(path)
			printerr("    测试文件缺失")
			continue
		var script = load(path)
		if script == null:
			# 编译失败会让 quit 永不执行、整个自测挂死;这里直接记为失败套件
			total_f += 1
			failed_suites.append(path)
			printerr("    套件脚本编译失败(见上方 Parse Error)")
			continue
		# 脚本解析失败时 load() 仍可能返回带错误的 GDScript 对象,new() 出来是个
		# 跑不动的空壳(_run 未编译 → 套件静默空跑、报 0 失败)。显式判一次:
		if script is GDScript and not (script as GDScript).can_instantiate():
			total_f += 1
			failed_suites.append(path)
			printerr("    套件脚本未通过编译(can_instantiate=false),计为失败套件")
			continue
		var inst = script.new()
		if inst == null:
			total_f += 1
			failed_suites.append(path)
			printerr("    套件实例化返回 null,计为失败套件")
			continue
		var r: Dictionary = await inst.run()   # 套件可为协程(test_base.run 内 await 透传)
		if inst is Node:
			inst.free()   # RefCounted 基类由引用计数释放,不能手动 free
		total_p += int(r.get("passed", 0))
		total_f += int(r.get("failed", 0))
		if bool(r.get("skipped", false)):
			skips += 1
		if int(r.get("failed", 0)) > 0:
			failed_suites.append(path)
		_purge_suite_residue()
	print("---- 自测汇总 ----")
	print("通过 %d / 失败 %d / 跳过套件 %d" % [total_p, total_f, skips])
	if total_f > 0:
		printerr("失败套件: " + ", ".join(failed_suites))
	quit(1 if total_f > 0 else 0)

## 套件间清理:上一条套件遗留的 UI/场景节点(主城、选关页、战斗)会留在 /root,
## 它们挂在全局 group(hub_entry / stage_entry / modal)里,下一条套件按 group 查找时
## 会抓到已释放实例的旧节点 —— 这是 test_campaign 串行跑时炸掉的根因。
## 每条套件跑完把遗留的场景根节点收掉并解除暂停,保证套件彼此独立。
func _purge_suite_residue() -> void:
	var autoload_names := {}
	for a in AUTOLOADS:
		autoload_names[str(a[0])] = true
	var doomed := {}
	for g in ["hub_entry", "stage_entry", "modal"]:
		for n in root.get_tree().get_nodes_in_group(g):
			if not is_instance_valid(n):
				continue
			var top: Node = n
			while top.get_parent() != null and top.get_parent() != root:
				top = top.get_parent()
			if top.get_parent() == root and not autoload_names.has(str(top.name)) \
					and str(top.name) != "TreeSentinel":
				doomed[top] = true
	for n in doomed:
		if is_instance_valid(n):
			n.free()
	root.get_tree().paused = false

func _register_autoloads() -> void:
	for a in AUTOLOADS:
		if root.has_node(a[0]):
			continue
		var s = load(a[1])
		if s == null:
			printerr("[run_all] autoload 脚本缺失: " + str(a[1]))
			continue
		var n = s.new()
		n.name = a[0]
		root.add_child(n)
	var db = root.get_node("DataDB")
	if db.heroes.is_empty():
		db.load_all()
