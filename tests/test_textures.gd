extends "res://tests/test_base.gd"
## test_textures(M0):manifest 与 PNG 一一对应、尺寸正确、非全透明(02 §5/§9)。

const TEX_ROOT := "res://assets/textures/"

func _run() -> void:
	var mpath := TEX_ROOT + "manifest.json"
	check(FileAccess.file_exists(mpath), "manifest.json 存在")
	if not FileAccess.file_exists(mpath):
		return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(mpath))
	check(manifest != null and (manifest as Dictionary).has("files"), "manifest 可解析且有 files")
	if manifest == null or not (manifest as Dictionary).has("files"):
		return
	var files: Array = manifest["files"]
	check(files.size() >= 35, "manifest 记录 >= 35 张(实际 %d)" % files.size())
	var seen := {}
	for f in files:
		var rel := str(f["path"])
		seen[rel] = true
		var abs_path := ProjectSettings.globalize_path(TEX_ROOT + rel)
		check(FileAccess.file_exists(TEX_ROOT + rel), "文件存在: " + rel)
		if not FileAccess.file_exists(TEX_ROOT + rel):
			continue
		var img := Image.load_from_file(abs_path)
		check(img != null, "PNG 可解码: " + rel)
		if img == null:
			continue
		check(img.get_width() == int(f["w"]) and img.get_height() == int(f["h"]), "尺寸一致: " + rel)
		check(not _all_transparent(img), "非全透明: " + rel)
	# 反向对账:磁盘上的 PNG 全部登记在 manifest
	var disk: Array = []
	_walk_pngs(TEX_ROOT, disk)
	for rel in disk:
		check(seen.has(rel), "磁盘文件已登记 manifest: " + rel)
	# 工程图标
	check(FileAccess.file_exists("res://icon.png"), "icon.png 存在")
	check(manifest.has("icon"), "manifest 记录 icon")

func _all_transparent(img: Image) -> bool:
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			if img.get_pixel(x, y).a > 0.01:
				return false
	return true

func _walk_pngs(base: String, out: Array) -> void:
	var dir := DirAccess.open(base)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if dir.current_is_dir():
			_walk_pngs(base + f + "/", out)
		elif f.ends_with(".png"):
			out.append(base.substr(TEX_ROOT.length()) + f)
		f = dir.get_next()
	dir.list_dir_end()
