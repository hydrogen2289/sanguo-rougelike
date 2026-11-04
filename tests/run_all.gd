extends SceneTree
## 自测入口(02 §9):godot.cmd --headless --path <工程> --script res://tests/run_all.gd
## 汇总执行全部测试套件;任一失败退出码非 0。
## M3/M4:原 5 套件转正;关卡设计 v0.2 增 test_levels(第 6 套件),0 跳过全绿。
## 注意:--script 模式下 ProjectSettings autoload 不自动实例化 ——
## 此处先手动把五个 autoload 挂到 /root(名称与注册名一致),
## 之后经 load() 加载的套件/场景脚本里全局标识符(RunState/DataDB/…)方可解析;
## 本入口自身不得直接引用 autoload 标识符(编译早于注册,会报 Identifier not found)。

const AUTOLOADS := [
	["DataDB", "res://scripts/autoload/data_db.gd"],
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
		var inst = script.new()
		var r: Dictionary = await inst.run()   # 套件可为协程(test_base.run 内 await 透传)
		if inst is Node:
			inst.free()   # RefCounted 基类由引用计数释放,不能手动 free
		total_p += int(r.get("passed", 0))
		total_f += int(r.get("failed", 0))
		if bool(r.get("skipped", false)):
			skips += 1
		if int(r.get("failed", 0)) > 0:
			failed_suites.append(path)
	print("---- 自测汇总 ----")
	print("通过 %d / 失败 %d / 跳过套件 %d" % [total_p, total_f, skips])
	if total_f > 0:
		printerr("失败套件: " + ", ".join(failed_suites))
	quit(1 if total_f > 0 else 0)

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
