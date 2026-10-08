extends SceneTree
## Gate doors swing open and shut as the gate's state changes (renders the real CityArt, no UI).
## godot --headless --path . -s tests/gate_doors_test.gd

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _doors(art: CityArt, gate: Dictionary) -> Array:
	var entry: Dictionary = art.building_nodes.get(int(gate.id), {})
	var model: Node3D = entry.get("model", null)
	if model == null:
		return [null, null]
	return [model.get_node_or_null("door_l"), model.get_node_or_null("door_r")]


func _frames(art: CityArt, count: int) -> void:
	for i in range(count):
		art.sync(0, 0.016)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var sim := LifeSim.new()
	sim.rng.seed = 4
	sim.money = 9000
	sim.wood = 400
	sim.stage_floor = 1
	Walls.build(sim, 99)
	for b in sim.buildings:
		if Walls.is_wall(b):
			b.level = 1
			b.target = 0
			b.progress = 100.0
	var gates := Walls.gates(sim)
	check(gates.size() >= 2, "the layout has gates to look at (%d)" % gates.size())
	var art := CityArt.new()
	root.add_child(art)
	art.generate(sim)
	_frames(art, 5)
	for g in gates:
		var side := int(g.edge[2])
		var swing: float = [1.0, -1.0, -1.0, 1.0][side]
		var doors := _doors(art, g)
		var left: Node3D = doors[0]
		var right: Node3D = doors[1]
		check(left != null and right != null, "the %s gate has two door leaves" % Walls.SIDE_NAMES[side])
		if left == null or right == null:
			continue
		# Open: both leaves swing back, in opposite directions.
		g.open = true
		_frames(art, 400)
		check(absf(left.rotation.y - 1.5 * swing) < 0.05, "%s gate: the left leaf opens (%.2f)" % [Walls.SIDE_NAMES[side], left.rotation.y])
		check(absf(right.rotation.y + 1.5 * swing) < 0.05, "%s gate: the right leaf opens the other way (%.2f)" % [Walls.SIDE_NAMES[side], right.rotation.y])
		# Close: they swing back to lie across the opening, gradually rather than snapping.
		g.open = false
		_frames(art, 3)
		check(absf(left.rotation.y) > 0.3 and absf(left.rotation.y) < 1.5, "the door is part-way closed after a moment (%.2f)" % left.rotation.y)
		_frames(art, 400)
		check(absf(left.rotation.y) < 0.05 and absf(right.rotation.y) < 0.05, "%s gate: both leaves end up closed" % Walls.SIDE_NAMES[side])
		# Reopening works from closed.
		g.open = true
		_frames(art, 400)
		check(absf(left.rotation.y - 1.5 * swing) < 0.05, "%s gate: it can open again" % Walls.SIDE_NAMES[side])
	# The gate policy drives the doors: shut at night, open by day.
	var gate: Dictionary = gates[0]
	var doors0 := _doors(art, gate)
	sim.minutes = 6.0 * 1440.0 + 23.0 * 60.0
	Walls.policy(sim)
	_frames(art, 400)
	check(not bool(gate.open) and absf((doors0[0] as Node3D).rotation.y) < 0.05, "at night the gate policy shuts the doors")
	sim.minutes = 6.0 * 1440.0 + 12.0 * 60.0
	Walls.policy(sim)
	_frames(art, 400)
	check(bool(gate.open) and absf((doors0[0] as Node3D).rotation.y) > 1.0, "by day it opens them again")
	# A breached gate has no doors left to swing.
	gate.breached = true
	_frames(art, 5)
	var wrecked := _doors(art, gate)
	check(wrecked[0] == null and wrecked[1] == null, "a breached gate loses its doors")
	gate.breached = false
	_frames(art, 5)
	var mended := _doors(art, gate)
	check(mended[0] != null and mended[1] != null, "repairing it puts them back")
	print("GATE DOOR TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
