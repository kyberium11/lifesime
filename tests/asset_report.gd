extends SceneTree
## Prints size and animation info for the Kenney models. Run:
## godot --headless --path . --script tests/asset_report.gd -- suburban/building-type-a commercial/building-a ...

func aabb_of(node: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var local := mi.mesh.get_aabb()
			var xf := Transform3D.IDENTITY
			var cur: Node = mi
			while cur != node and cur != null:
				if cur is Node3D:
					xf = (cur as Node3D).transform * xf
				cur = cur.get_parent()
			var world := xf * local
			box = world if first else box.merge(world)
			first = false
		for c in n.get_children():
			stack.append(c)
	return box


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		var path := "res://assets/kenney/%s.glb" % a
		var scene: PackedScene = load(path)
		if scene == null:
			print("%-34s MISSING" % a)
			continue
		var inst := scene.instantiate()
		var box := aabb_of(inst)
		var anims := ""
		for n in inst.find_children("*", "AnimationPlayer", true, false):
			anims += " anims=" + ",".join((n as AnimationPlayer).get_animation_list())
		print("%-34s size=(%.2f, %.2f, %.2f) min=(%.2f, %.2f, %.2f)%s" % [a, box.size.x, box.size.y, box.size.z, box.position.x, box.position.y, box.position.z, anims])
		inst.free()
	quit()
