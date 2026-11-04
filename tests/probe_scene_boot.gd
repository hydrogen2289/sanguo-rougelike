extends Node
func _ready() -> void:
	print("[probe] ready in_tree=", is_inside_tree(), " tree=", get_tree() != null)
	_probe()
func _probe() -> void:
	await get_tree().process_frame
	print("[probe] frame1 in_tree=", is_inside_tree(), " tree=", get_tree() != null, " cs=", get_tree().current_scene)
	await get_tree().process_frame
	print("[probe] frame2 in_tree=", is_inside_tree(), " cs=", get_tree().current_scene.name)
	get_tree().quit(0)
