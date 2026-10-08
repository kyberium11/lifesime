extends SceneTree
## Measures every Kenney furniture model (and a villager) and writes data/furniture_sizes.json:
## {model: {size: [x, y, z], center: [x, z]}} in model units. Re-run after adding models.
## godot --headless --path . -s tools/measure_furniture.gd

func _aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var local := node.global_transform.affine_inverse() * m.global_transform
		var box := local * m.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


func _init() -> void:
	var result := {}
	var dir := DirAccess.open("res://assets/kenney/furniture")
	for f in dir.get_files():
		if not f.ends_with(".glb"):
			continue
		var scene: PackedScene = load("res://assets/kenney/furniture/" + f)
		var n: Node3D = scene.instantiate()
		root.add_child(n)
		var b := _aabb(n)
		result[f.get_basename()] = {"size": [snappedf(b.size.x, 0.001), snappedf(b.size.y, 0.001), snappedf(b.size.z, 0.001)], "center": [snappedf(b.get_center().x, 0.001), snappedf(b.get_center().z, 0.001)], "base": snappedf(b.position.y, 0.001)}
		n.queue_free()
	var villager: PackedScene = load("res://assets/kenney/characters/character-b.glb")
	var v: Node3D = villager.instantiate()
	root.add_child(v)
	var vb := _aabb(v)
	result["_villager"] = {"size": [vb.size.x, vb.size.y, vb.size.z], "center": [0, 0], "base": vb.position.y}
	DirAccess.make_dir_recursive_absolute("res://data")
	var file := FileAccess.open("res://data/furniture_sizes.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("measured ", result.size(), " models")
	quit()
