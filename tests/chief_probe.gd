extends SceneTree
func _initialize() -> void:
	var scene: PackedScene = load("res://assets/kenney/characters/character-i.glb")
	var inst: Node3D = scene.instantiate()
	root.add_child(inst)
	for n in ["character-i2", "character-i", "root", "torso", "head", "arm-left", "arm-right", "leg-left"]:
		var node: Node3D = inst if n == "character-i2" else inst.find_child(n, true, false)
		print("%-12s pos=%s scale=%s rot=%s" % [n, str(node.position), str(node.scale), str(node.rotation_degrees)])
	var head: Node3D = inst.find_child("head", true, false)
	print("head global pos=", head.global_position, " global basis scale=", head.global_transform.basis.get_scale())
	var arm: Node3D = inst.find_child("arm-right", true, false)
	print("arm-right global pos=", arm.global_position, " scale=", arm.global_transform.basis.get_scale())
	var hm := head as MeshInstance3D
	print("head mesh aabb=", hm.mesh.get_aabb())
	var am := arm as MeshInstance3D
	print("arm mesh aabb=", am.mesh.get_aabb())
	quit()
