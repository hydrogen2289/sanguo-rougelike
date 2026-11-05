extends Node3D
## Rig 挂载器:实例化时按父节点 unit_id 程序化拼装 Q 版 3D 低模小人。
## 场景里只留这个空 Node3D,网格全部运行时构建(02 §4 表现升级)。
## 颜色取 data/palette.json token;头/身/识别物语义见 unit_rig_3d.gd。

func _ready() -> void:
	var holder := get_parent()
	var uid := ""
	if holder != null and "unit_id" in holder:
		uid = str(holder.get("unit_id"))
	if uid.is_empty():
		uid = str(get_meta("unit_id", "huangjin_zu"))   # 兜底:场景内未设 id 时按黄巾卒
	add_child(UnitRig3D.build(uid, UnitRig3D.load_palette()))
