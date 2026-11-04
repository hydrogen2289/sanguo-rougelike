extends RefCounted
## 测试基类:run() 收集断言结果(02 §9)。
## 任一 check 失败累计到 failed;run_all.gd 汇总,失败即非 0 退出码。

var passed := 0
var failed := 0
var skipped := false
var messages: PackedStringArray = PackedStringArray()

func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		messages.append("FAIL: " + msg)
		printerr("    [FAIL] " + msg)

func skip(reason: String) -> void:
	skipped = true
	print("    [SKIP] " + reason)

func run() -> Dictionary:
	passed = 0
	failed = 0
	skipped = false
	messages = PackedStringArray()
	# await 透传:_run() 为协程(含暂停/帧推进断言)时挂起续跑;普通套件直接透传返回。
	# 调用方(run_all.gd)需 await 本方法。
	await _run()
	return {"passed": passed, "failed": failed, "skipped": skipped, "messages": messages}

func _run() -> void:
	pass
