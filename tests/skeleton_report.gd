extends SceneTree
## Prints the skeleton bones and animation lengths of a character model.
## godot --headless --path . --script tests/skeleton_report.gd -- characters/character-i

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var scene: PackedScene = load("res://assets/kenney/%s.glb" % a)
		var inst: Node = scene.instantiate()
		print("== ", a)
		_dump(inst, 0)
		for n in inst.find_children("*", "Skeleton3D", true, false):
			var sk := n as Skeleton3D
			var names := []
			for i in range(sk.get_bone_count()):
				names.append("%s(parent %d)" % [sk.get_bone_name(i), sk.get_bone_parent(i)])
			print("bones: ", ", ".join(names))
		for n in inst.find_children("*", "AnimationPlayer", true, false):
			var ap := n as AnimationPlayer
			for name in ["idle", "walk", "sprint", "pick-up", "emote-yes", "interact-right", "sit"]:
				var anim := ap.get_animation(name)
				print("anim %s length=%.2f loop=%d" % [name, anim.length, anim.loop_mode])
		inst.free()
	quit()


func _dump(node: Node, depth: int) -> void:
	var extra := ""
	if node is MeshInstance3D:
		extra = " mesh aabb=" + str((node as MeshInstance3D).get_aabb().size)
	print("  ".repeat(depth), node.name, " [", node.get_class(), "]", extra)
	if depth < 8:
		for c in node.get_children():
			_dump(c, depth + 1)
