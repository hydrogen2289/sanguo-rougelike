class_name CsvLogger
extends RefCounted
## 波次 CSV 日志(02 §9):user://wave_log.csv
## 验收员据实测数据回填/修订 01 文档的平衡占位数值。

const PATH := "user://wave_log.csv"

static func ensure_header() -> void:
	if FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("wave,elapsed_s,enemies_left,team_hp,result")
	f.close()

static func append_row(cols: Array) -> void:
	var f := FileAccess.open(PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var parts := PackedStringArray()
	for c in cols:
		parts.append(str(c).replace(",", ";"))
	f.store_line(",".join(parts))
	f.close()
