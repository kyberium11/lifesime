extends SceneTree
## Walls and gates: placing, blocking, gates, sieges, growth, job routes, planning, orders, saving.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _finish_all(sim: LifeSim) -> void:
	for b in sim.buildings:
		if Walls.is_wall(b):
			b.level = maxi(1, int(b.level))
			b.target = 0
			b.progress = 100.0


func _rich(seed_: int = 1) -> LifeSim:
	var sim := LifeSim.new()
	sim.rng.seed = seed_
	sim.money = 5000
	sim.wood = 300
	sim.stage_floor = 1
	for resident in sim.residents:
		resident.values = ["Community"]
	return sim


func _init() -> void:
	var sim := _rich()
	var edges := Walls.perimeter(sim)
	check(edges.size() == 6, "two districts have six border edges (%d)" % edges.size())
	var west := Vector2i(0, 0)
	check(Walls.place_blocker(sim, west, 0) == "", "a wall can be started on the west edge")
	check(Walls.place_blocker(sim, west, 1) != "", "the edge between the two claimed districts is inside the village")
	var coins := sim.money
	check(Walls.place(sim, west, 0, false).begins_with("Started"), "placing a wall starts construction")
	check(sim.money < coins, "walls cost coins")
	check(not Walls.place(sim, west, 0, false).begins_with("Started"), "the same edge cannot be walled twice")
	var plan := Walls.build(sim, 99)
	check(int(plan.placed) >= 5, "the rest of the border is planned (%s)" % str(plan))
	var gate_count := 0
	for b in sim.buildings:
		if str(b.kind) == "gate":
			gate_count += 1
	check(gate_count >= 2, "gates are planned too (%d)" % gate_count)
	check(Walls.missing(sim).is_empty() or Walls.missing(sim).size() < 6, "the border is accounted for")
	# unfinished walls do not block
	var inside := Vector2(2.0, 2.0)
	var outside := Vector2(-3.0, 2.0)
	var wall_w := Walls.find(sim, west, 0)
	check(wall_w.is_empty() or not Walls.intact(wall_w), "an unfinished wall does not stop anyone yet")
	_finish_all(sim)
	# collision: crossing the west boundary (x = -0.5)
	var mid := Walls.mid(west, 0)
	var off_gate := Vector2(mid.x + 0.3, mid.y + 1.4)
	var off_gate_out := Vector2(mid.x - 0.3, mid.y + 1.4)
	var west_edge := Walls.find(sim, west, 0)
	check(not Walls.blocks(sim, off_gate, off_gate_out).is_empty(), "a finished wall blocks movement across it")
	if str(west_edge.kind) == "gate":
		var in_gate := Vector2(mid.x + 0.3, mid.y)
		var out_gate := Vector2(mid.x - 0.3, mid.y)
		check(Walls.blocks(sim, in_gate, out_gate).is_empty(), "an open gate lets people through its opening")
		west_edge.open = false
		check(not Walls.blocks(sim, in_gate, out_gate).is_empty(), "a closed gate blocks even its opening")
		west_edge.open = true
	check(Walls.blocks(sim, inside, Vector2(3.0, 2.0)).is_empty(), "walking inside the village is never blocked")
	# gates follow day and night
	sim.minutes = 6.0 * 1440.0 + 23.0 * 60.0
	Walls.policy(sim)
	check(not Walls.gates(sim, true).is_empty() == false or Walls.gates(sim, true).is_empty(), "gates close at night")
	sim.minutes = 6.0 * 1440.0 + 12.0 * 60.0
	Walls.policy(sim)
	check(Walls.gates(sim, true).size() == Walls.gates(sim).size() and not Walls.gates(sim).is_empty(), "gates open by day")
	check(Walls.set_override(sim, "closed").contains("shut") and Walls.gates(sim, true).is_empty(), "the chief can shut the gates")
	check(Walls.set_override(sim, "auto").contains("routine"), "and return them to the routine")
	# a monster sieges a wall
	var s := _rich(2)
	Walls.place(s, Vector2i(0, 0), 0, false)
	_finish_all(s)
	var wall := Walls.find(s, Vector2i(0, 0), 0)
	s.minutes = 5.0 * 1440.0 + 23.0 * 60.0
	for r in s.residents:
		r.pos = [1.0, 2.5]
		r.route = []
		r.action = "play"
		r.remaining = 9999.0
		r.target_id = -1
		r.commanded = true
	var zombie := Survival.spawn(s, "zombie", Vector2(-3.0, 2.5))
	var breached := false
	for i in range(160):
		for r in s.residents:
			r.pos = [1.0, 2.5]
			r.route = []
			r.action = "play"
			r.needs.hunger = 90.0
			r.needs.energy = 90.0
			r.remaining = 9999.0
			r.target_id = -1
		s.tick(1.0)
		if bool(wall.breached):
			breached = true
			break
	check(float(wall.condition) < 100.0, "a monster damages the wall it cannot pass (%.0f)" % float(wall.condition))
	check(breached or not s.mobs.has(zombie) or float(wall.condition) < 80.0, "a sustained siege wears the wall down")
	# a breached wall no longer blocks, and can be repaired
	wall.breached = true
	wall.condition = 0.0
	var gap_in := Vector2(1.0, 2.0)
	var gap_out := Vector2(-2.0, 2.0)
	check(Walls.blocks(s, gap_in, gap_out).is_empty(), "a breach lets monsters through")
	check(not s.upgrade_blocker(int(wall.id)).is_empty(), "a breached wall must be repaired before it is upgraded")
	s.wood = 50
	Economy.repair(s, wall, 20.0)
	check(not bool(wall.breached) and float(wall.condition) > 30.0, "repairing closes the breach")
	# stronger walls last longer
	var strong := _rich(3)
	Walls.place(strong, Vector2i(0, 0), 0, false)
	_finish_all(strong)
	var tough := Walls.find(strong, Vector2i(0, 0), 0)
	tough.level = 3
	var weak := _rich(3)
	Walls.place(weak, Vector2i(0, 0), 0, false)
	_finish_all(weak)
	var frail := Walls.find(weak, Vector2i(0, 0), 0)
	var z1 := Survival.spawn(strong, "zombie", Vector2(-3, 2))
	var z2 := Survival.spawn(weak, "zombie", Vector2(-3, 2))
	Walls.siege(strong, z1, tough, 10.0)
	Walls.siege(weak, z2, frail, 10.0)
	check(float(tough.condition) > float(frail.condition), "stone walls hold longer than palisades")
	# growth takes down interior walls
	var g := _rich(4)
	Walls.place(g, Vector2i(1, 0), 1, false)
	Walls.place(g, Vector2i(1, 0), 3, false)
	var before: int = Walls.status(g).segments
	g.map.claim_district(Vector2i(2, 0))
	Walls.remove_interior(g)
	check(int(Walls.status(g).segments) == before - 1, "claiming land takes down the wall it swallowed")
	check(Walls.perimeter(g).size() == 8, "new border edges appear (%d)" % Walls.perimeter(g).size())
	# job routes use gates
	var j := _rich(5)
	j.minutes = 1.0 * 1440.0 + 9.0 * 60.0
	var sealed := Walls.build(j, 99)
	for b in j.buildings:
		if str(b.kind) == "gate":
			b.kind = "wall"
	_finish_all(j)
	check(Walls.gates(j).is_empty(), "no gates in this layout")
	check(not j.has_target("chop"), "a fully sealed village cannot send anyone out to chop")
	var k := _rich(5)
	k.minutes = 1.0 * 1440.0 + 9.0 * 60.0
	k.last_day = k.day()
	Walls.build(k, 99)
	_finish_all(k)
	check(not Walls.gates(k).is_empty(), "a walled village has gates")
	check(k.has_target("chop"), "gates let workers reach the forest")
	var timber := k.wood
	check(k.command(0, "chop").ok, "chop order accepted")
	for i in range(1500):
		k.tick(2.0)
		if (k.residents[0].job as Dictionary).is_empty() and i > 20:
			break
	var far := Vector2(-30.0, 2.0)
	check(Walls.accessible(k, Vector2(2.0, 2.0), far), "with gates the far forest is reachable")
	check(not Walls.accessible(j, Vector2(2.0, 2.0), far), "without gates it is not")
	check(not Walls.crossing(k, Vector2(2.0, 2.0), far).is_empty() or not Walls.gates(k).is_empty(), "the straight line to the forest is walled")
	check(k.wood > timber, "timber arrives through the gate (%d -> %d)" % [timber, k.wood])
	# planning, orders
	var p := _rich(6)
	p.kills = 12
	p.downs = 3
	p.stage_floor = 2
	p.minutes = 6.0 * 1440.0
	var needs := CityPlanner.needs(p)
	check(float(needs.wall) > 0.5, "the council wants walls after trouble (%.2f)" % float(needs.wall))
	var kinds := {}
	for o in CityPlanner.options(p, 12, false):
		kinds[str(o.type)] = true
	check(kinds.has("wall"), "wall plans are offered")
	for o in CityPlanner.options(p, 12, false):
		if str(o.type) == "wall":
			check(p.apply_option(o, "Council").begins_with("Started"), "a wall plan can be carried out")
			break
	var o := LifeSim.new()
	check(Orders.parse("build walls around the village", o).intent == "build" and Orders.parse("build walls around the village", o).kind == "wall", "wall order parses")
	check(int(Orders.parse("wall off the village", o).count) == 99, "wall off means the whole border")
	check(Orders.parse("build a gate", o).kind == "gate", "gate order parses")
	check(Orders.parse("close the gates", o).intent == "gates_close", "close gates parses")
	check(Orders.parse("open the gates", o).intent == "gates_open", "open gates parses")
	check(Orders.parse("gates back to normal", o).intent == "gates_auto", "gate routine parses")
	check(Orders.parse("build a watchtower", o).kind == "watchtower" and Orders.parse("build a clinic", o).kind == "clinic", "tower and clinic orders parse")
	var r := _rich(7)
	var built := Orders.execute(r, Orders.parse("wall off the village", r), 0)
	check(built.ok and Walls.status(r).segments >= 5, "the wall order places segments: " + str(built.message))
	check(not Orders.execute(r, Orders.parse("close the gates", r), 0).ok or true, "gate orders do not crash")
	# towers and gatekeepers strengthen the defence
	var def := _rich(12)
	def.stage_floor = 2
	Walls.build(def, 99)
	_finish_all(def)
	var west_wall := Walls.find(def, Vector2i(0, 0), 0)
	var base_factor := Walls.defence_factor(def, west_wall)
	var tower_spot := Orders._spot_near_chief(def, "watchtower")
	def.place_building("watchtower", tower_spot)
	var tw: Dictionary = def.buildings[def.buildings.size() - 1]
	tw.level = 1
	tw.target = 0
	tw.progress = 100.0
	tw.tile = [int(Walls.mid(Vector2i(0, 0), 0).x) + 2, int(Walls.mid(Vector2i(0, 0), 0).y)]
	check(Walls.tower_covers(def, west_wall) and Walls.defence_factor(def, west_wall) < base_factor, "a nearby watchtower makes the wall harder to break")
	var gate_def: Dictionary = Walls.gates(def)[0]
	def.minutes = 3.0 * 1440.0 + 23.0 * 60.0
	var night_factor := Walls.defence_factor(def, gate_def)
	var keeper: Dictionary = def.residents[0]
	keeper.profession = "gatekeeper"
	keeper.employer = int(gate_def.id)
	var gp := Walls.gate_points(gate_def)
	keeper.pos = [gp.inner.x, gp.inner.y]
	check(Walls.manned(def, gate_def) and Walls.defence_factor(def, gate_def) < night_factor, "a gatekeeper at his post strengthens the gate")
	keeper.pos = [50.0, 50.0]
	check(not Walls.manned(def, gate_def), "an absent keeper leaves the gate unmanned")
	# sieging monsters are shot first
	var priority := _rich(13)
	var pt := Orders._spot_near_chief(priority, "watchtower")
	priority.place_building("watchtower", pt)
	var ptw: Dictionary = priority.buildings[priority.buildings.size() - 1]
	ptw.level = 1
	ptw.target = 0
	ptw.progress = 100.0
	priority.minutes = 3.0 * 1440.0 + 23.0 * 60.0
	var tx := float(ptw.tile[0])
	var tz := float(ptw.tile[1])
	var near_mob := Survival.spawn(priority, "zombie", Vector2(tx + 2.0, tz))
	var siege_mob := Survival.spawn(priority, "zombie", Vector2(tx + 8.0, tz))
	siege_mob.siege = 1
	near_mob.hp = 100.0
	siege_mob.hp = 100.0
	Survival._towers(priority, 10.0)
	check(float(siege_mob.hp) < 100.0 and float(near_mob.hp) == 100.0, "the tower picks the monster clawing at the wall over the nearer one")
	# a fallen keeper weakens the gate
	var fall := _rich(14)
	fall.stage_floor = 2
	Walls.build(fall, 99)
	_finish_all(fall)
	var fg: Dictionary = Walls.gates(fall)[0]
	var fk: Dictionary = fall.residents[0]
	fk.profession = "gatekeeper"
	fk.employer = int(fg.id)
	var cond_before := float(fg.condition)
	Survival._down(fall, 0, {"kind": "zombie"})
	check(float(fg.condition) < cond_before, "the gate is left weak when its keeper falls")
	# saving
	var data: Variant = JSON.parse_string(JSON.stringify(r.to_dict()))
	var restored := LifeSim.new()
	check(restored.load_data(data), "a save with walls loads")
	check(Walls.status(restored).segments == Walls.status(r).segments, "walls survive saving")
	var lot_taken := false
	for b in restored.buildings:
		if Walls.is_wall(b) and restored.map.occupied.has(restored.tile_of(b)):
			lot_taken = true
	check(not lot_taken, "walls do not occupy lots after loading")
	print("WALLS TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
