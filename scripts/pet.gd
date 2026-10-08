class_name Pet
extends Node2D
## Pip: a needs-driven creature whose decisions come from the LLM (see Brain).
## The game only validates and executes actions; the model chooses what to do.

enum State { IDLE, THINKING, MOVING, WORKING, SLEEPING }

signal spoke(text: String)
signal logged(kind: String, text: String)  # kind: thought | event | brain | speech | player

const SPEED := 3.0  # tiles per second
const SIGHT := 10

var world: World
var brain: Brain
var player: Node2D
var cell := Vector2i.ZERO

var hunger := 70.0
var energy := 90.0
var mood := 60.0
var bond := 10.0
var inventory: Dictionary = {}
var events: Array = []
var journal: Array = []

var state := State.IDLE
var status_text := "waking up"
var unanswered := ""

var _path: Array = []
var _on_arrive := Callable()
var _work_left := 0.0
var _on_work_done := Callable()
var _sleep_quality := 1.0
var _sleep_minutes := 0.0
var _cooldown := 0.0
var _bob := 0.0
var _sprite: Sprite2D


func setup(world_: World, brain_: Brain, player_: Node2D) -> void:
	world = world_
	brain = brain_
	player = player_
	brain.decided.connect(_on_decided)
	brain.failed.connect(_on_failed)
	_sprite = Sprite2D.new()
	_sprite.texture = Art.pet_texture()
	add_child(_sprite)


func place(c: Vector2i) -> void:
	cell = c
	position = world.cell_to_pos(c)


# --- main loop -------------------------------------------------------------

## dm: game minutes elapsed this frame; dt: real seconds (already speed-scaled).
func step(dm: float, dt: float) -> void:
	_tick_needs(dm)
	_cooldown = maxf(0.0, _cooldown - dt)
	match state:
		State.IDLE:
			if not brain.ready_to_think:
				status_text = "waking up (loading brain)..."
			elif _cooldown <= 0.0 and not brain.busy:
				_think()
		State.MOVING:
			_move(dt)
		State.WORKING:
			_work_left -= dm
			if _work_left <= 0.0:
				state = State.IDLE
				_on_work_done.call()
		State.SLEEPING:
			energy = minf(100.0, energy + 0.2 * _sleep_quality * dm)
			_sleep_minutes += dm
			if energy >= 95.0 or _sleep_minutes >= 600.0 or hunger <= 3.0:
				state = State.IDLE
				_event("Woke up feeling %s." % ("rested" if energy > 70.0 else "groggy"))
	_sprite.position.y = sin(_bob) * 1.0 if state == State.MOVING else 0.0
	_bob += dt * 14.0


func _tick_needs(dm: float) -> void:
	hunger = maxf(0.0, hunger - (0.025 if state == State.SLEEPING else 0.05) * dm)
	if state != State.SLEEPING:
		energy = maxf(0.0, energy - 0.04 * dm)
		if energy <= 0.0:
			_start_sleep(0.6)
			_event("Collapsed from exhaustion and fell asleep.")
	var target := 50.0
	if hunger < 25.0:
		target -= 20.0
	elif hunger > 60.0:
		target += 5.0
	if energy < 20.0:
		target -= 15.0
	var fire := _nearest_building("campfire", 5)
	if fire:
		target += 15.0 if GameClock.is_night() else 5.0
	if _nearest_building("shelter", 8):
		target += 8.0
	if player and world.pos_to_cell(player.position).distance_to(cell) < 5.0:
		target += 5.0 + bond * 0.1
	mood = move_toward(mood, clampf(target, 0.0, 100.0), 0.15 * dm)


func _nearest_building(kind: String, radius: int) -> bool:
	for c in world.find_all(kind, cell, radius):
		return true
	return false


# --- thinking --------------------------------------------------------------

func _think() -> void:
	state = State.THINKING
	status_text = "thinking..."
	brain.decide(Data.persona, _observation())


func _on_decided(action: Dictionary, raw: String, latency: float) -> void:
	if state != State.THINKING:
		return
	logged.emit("brain", "(%.1fs) %s" % [latency, raw.replace("\n", " ")])
	var thought := str(action.get("thought", "")).strip_edges()
	var say := str(action.get("say", "")).strip_edges()
	var note := str(action.get("note", "")).strip_edges()
	if thought != "":
		logged.emit("thought", thought)
	if say != "":
		spoke.emit(say)
		logged.emit("speech", say)
		unanswered = ""
	if note != "":
		journal.append("[D%d] %s" % [GameClock.day(), note])
		if journal.size() > 40:
			journal.pop_front()
	_execute(action)


func _on_failed(reason: String) -> void:
	logged.emit("brain", "Brain error: %s" % reason)
	state = State.IDLE
	status_text = "confused"
	_cooldown = 5.0


func _observation() -> String:
	var L: Array[String] = []
	L.append("Day %d, %s (%s)." % [GameClock.day(), GameClock.time_string(), GameClock.period()])
	L.append("You: hunger %d/100, energy %d/100, mood %d/100. Bond with caretaker: %d/100." % [hunger, energy, mood, bond])
	L.append("Inventory: %s." % _inventory_text())
	var seen := world.scan(cell, SIGHT, ["tree", "rock", "bush", "garden", "water"])
	if seen.is_empty():
		L.append("Within sight: nothing useful. Try exploring.")
	else:
		L.append("Within sight:")
		for k in seen:
			var info: Dictionary = seen[k]
			var label: String = k
			if k == "bush" or k == "garden":
				label = k + " with berries"
			L.append("- %s: %d, nearest %d tiles %s" % [label, info.count, info.dist, _compass(info.nearest)])
	var built := world.scan(cell, 60, ["campfire", "shelter", "garden"])
	var parts: Array[String] = []
	for k in ["campfire", "shelter"]:
		if built.has(k):
			parts.append("%s x%d (nearest %d tiles %s)" % [k, built[k].count, built[k].dist, _compass(built[k].nearest)])
	L.append("Your buildings: %s." % (", ".join(parts) if not parts.is_empty() else "none yet"))
	if player:
		var pc := world.pos_to_cell(player.position)
		var d := absi(pc.x - cell.x) + absi(pc.y - cell.y)
		L.append("Caretaker (human): %s." % ("%d tiles %s" % [d, _compass(pc)] if d <= SIGHT + 4 else "out of sight"))
	if unanswered != "":
		L.append('The caretaker said to you: "%s" (you have not replied yet).' % unanswered)
	L.append("Recipes:")
	for b in Data.game.buildings:
		var def: Dictionary = Data.game.buildings[b]
		var cost := []
		for item in def.cost:
			cost.append("%s %d" % [item, def.cost[item]])
		L.append("- %s: %s (%s)" % [b, ", ".join(cost), def.desc])
	if not events.is_empty():
		L.append("Recent events:")
		for e in events.slice(maxi(0, events.size() - 10)):
			L.append("- " + e)
	if not journal.is_empty():
		L.append("Your journal:")
		for j in journal.slice(maxi(0, journal.size() - 8)):
			L.append("- " + j)
	L.append("What do you do next?")
	return "\n".join(L)


func _inventory_text() -> String:
	var parts: Array[String] = []
	for k in inventory:
		if inventory[k] > 0:
			parts.append("%s x%d" % [k, inventory[k]])
	return ", ".join(parts) if not parts.is_empty() else "empty"


func _compass(to: Vector2i) -> String:
	var d := Vector2(to - cell)
	if d == Vector2.ZERO:
		return "here"
	var a := fposmod(rad_to_deg(atan2(-d.y, d.x)), 360.0)
	var names := ["east", "north-east", "north", "north-west", "west", "south-west", "south", "south-east"]
	return names[int(round(a / 45.0)) % 8]


# --- executing actions -----------------------------------------------------

## Models often pad targets ("bush with berries", "the campfire"); pick the known word inside.
func _normalize_target(raw: String, options: Array) -> String:
	for o in options:
		if raw == o:
			return o
	for o in options:
		if raw.contains(o):
			return o
	return raw


func _execute(a: Dictionary) -> void:
	var act := str(a.get("action", "")).to_lower().strip_edges()
	var target := str(a.get("target", "")).to_lower().strip_edges()
	match act:
		"gather":
			target = _normalize_target(target, Data.game.resources.keys())
		"eat":
			target = _normalize_target(target, Data.game.foods.keys())
		"build":
			target = _normalize_target(target, Data.game.buildings.keys())
		"explore":
			target = _normalize_target(target, ["north", "south", "east", "west"])
	match act:
		"gather":
			_do_gather(target)
		"eat":
			_do_eat(target)
		"sleep":
			_do_sleep()
		"build":
			_do_build(target)
		"explore":
			_do_explore(target)
		"rest":
			_begin_work(15.0, "resting", func() -> void:
				mood = minf(100.0, mood + 1.0))
		"talk":
			_begin_work(3.0, "chatting", func() -> void: pass)
		_:
			_fail("Unknown action '%s'." % act)


func _do_gather(kind: String) -> void:
	if not Data.game.resources.has(kind):
		_fail("Cannot gather '%s'. Options: tree, rock, bush, garden, water." % kind)
		return
	var targets := world.find_all(kind, cell, 45)
	if targets.is_empty():
		_fail("No %s%s found nearby. Explore to find some." % [kind, " with berries" if kind == "bush" or kind == "garden" else ""])
		return
	for t in targets.slice(0, 6):
		var path: Variant = world.path_to_adjacent(cell, t)
		if path == null:
			continue
		var def: Dictionary = Data.game.resources[kind]
		status_text = "heading to %s" % kind
		_go(path, func() -> void:
			status_text = "gathering %s" % kind
			_begin_work(float(def.minutes), status_text, func() -> void: _finish_gather(t, kind)))
		return
	_fail("Could not reach any %s." % kind)


func _finish_gather(c: Vector2i, kind: String) -> void:
	var got := world.harvest(c)
	if got.qty <= 0:
		_event("Tried to gather %s but there was nothing left." % kind)
		return
	inventory[got.item] = int(inventory.get(got.item, 0)) + int(got.qty)
	_event("Gathered %d %s from a %s." % [got.qty, got.item, kind])


func _do_eat(food: String) -> void:
	if not Data.game.foods.has(food):
		food = ""
		for f in Data.game.foods:
			if int(inventory.get(f, 0)) > 0:
				food = f
				break
	if food == "" or int(inventory.get(food, 0)) <= 0:
		_fail("You have no food to eat. Gather berries first.")
		return
	_begin_work(2.0, "eating " + food, func() -> void:
		if int(inventory.get(food, 0)) <= 0:
			return
		inventory[food] -= 1
		var def: Dictionary = Data.game.foods[food]
		hunger = minf(100.0, hunger + float(def.hunger))
		mood = minf(100.0, mood + float(def.mood))
		_event("Ate a %s. Hunger is now %d." % [food, hunger]))


func _do_sleep() -> void:
	if energy > 85.0:
		_fail("Not tired enough to sleep (energy %d). You can sleep when energy is below 85." % energy)
		return
	var q := 0.8
	var where := "on the grass"
	if _nearest_building("shelter", 4):
		q = 1.8
		where = "near the shelter"
	elif _nearest_building("campfire", 4):
		q = 1.2
		where = "by the campfire"
	_start_sleep(q)
	_event("Went to sleep %s." % where)


func _start_sleep(quality: float) -> void:
	state = State.SLEEPING
	status_text = "sleeping"
	_sleep_quality = quality
	_sleep_minutes = 0.0
	_path.clear()


func _do_build(kind: String) -> void:
	if not Data.game.buildings.has(kind):
		_fail("Cannot build '%s'. Options: campfire, shelter, garden." % kind)
		return
	var def: Dictionary = Data.game.buildings[kind]
	var missing := []
	for item in def.cost:
		var have := int(inventory.get(item, 0))
		if have < int(def.cost[item]):
			missing.append("%d more %s" % [int(def.cost[item]) - have, item])
	if not missing.is_empty():
		_fail("Not enough materials for a %s: need %s." % [kind, ", ".join(missing)])
		return
	if world.find_build_spot(cell, cell) == null:
		_fail("No room to build here. Move somewhere more open.")
		return
	_begin_work(float(def.minutes), "building a " + kind, func() -> void: _finish_build(kind))


func _finish_build(kind: String) -> void:
	var def: Dictionary = Data.game.buildings[kind]
	for item in def.cost:
		if int(inventory.get(item, 0)) < int(def.cost[item]):
			_event("Ran out of materials while building a %s." % kind)
			return
	var spot: Variant = world.find_build_spot(cell, cell)
	if spot == null:
		_event("No room left to build the %s." % kind)
		return
	for item in def.cost:
		inventory[item] -= int(def.cost[item])
	var amount := 1
	if Data.game.resources.has(kind):
		amount = int(Data.game.resources[kind].amount)
	world.set_object(spot, kind, amount)
	mood = minf(100.0, mood + 8.0)
	_event("Built a %s at (%d, %d)." % [kind, spot.x, spot.y])


func _do_explore(dir_name: String) -> void:
	var dirs := {
		"north": Vector2(0, -1), "south": Vector2(0, 1),
		"east": Vector2(1, 0), "west": Vector2(-1, 0),
	}
	var dir: Vector2 = dirs.get(dir_name, Vector2.from_angle(randf() * TAU))
	for i in range(12):
		var dist := randf_range(7.0, 12.0)
		var jitter := Vector2.from_angle(randf() * TAU) * 3.0
		var goal := cell + Vector2i((dir * dist + jitter).round())
		goal = Vector2i(clampi(goal.x, 2, World.W - 3), clampi(goal.y, 2, World.H - 3))
		var p := world.path_to(cell, goal)
		if not p.is_empty():
			status_text = "exploring"
			_go(p, func() -> void: _event("Explored %s and arrived at (%d, %d)." % [dir_name if dirs.has(dir_name) else "a bit", cell.x, cell.y]))
			return
	_fail("Could not find a way to explore that direction.")


# --- movement / work plumbing ---------------------------------------------

func _go(path: Array, on_arrive: Callable) -> void:
	_path = path
	_on_arrive = on_arrive
	if _path.is_empty():
		state = State.IDLE
		on_arrive.call()
		return
	state = State.MOVING


func _move(dt: float) -> void:
	if _path.is_empty():
		state = State.IDLE
		_on_arrive.call()
		return
	var goal: Vector2 = world.cell_to_pos(_path[0])
	position = position.move_toward(goal, SPEED * World.T * dt)
	if position.distance_to(goal) < 0.5:
		cell = _path[0]
		_path.pop_front()
		if _path.is_empty():
			state = State.IDLE
			_on_arrive.call()


func _begin_work(minutes: float, text: String, on_done: Callable) -> void:
	state = State.WORKING
	status_text = text
	_work_left = minutes
	_on_work_done = on_done


func _fail(msg: String) -> void:
	_event("Failed: " + msg)
	state = State.IDLE
	status_text = "puzzled"
	_cooldown = 1.0


func _event(text: String) -> void:
	events.append("[D%d %s] %s" % [GameClock.day(), GameClock.time_string(), text])
	if events.size() > 60:
		events.pop_front()
	logged.emit("event", text)


# --- player interaction ----------------------------------------------------

func hear(text: String) -> void:
	unanswered = text
	bond = minf(100.0, bond + 2.0)
	_event('The caretaker said: "%s"' % text)
	if state == State.SLEEPING and energy > 30.0:
		state = State.IDLE
		_event("Woke up because the caretaker spoke.")


func receive_gift(item: String, qty: int) -> void:
	inventory[item] = int(inventory.get(item, 0)) + qty
	bond = minf(100.0, bond + 3.0)
	mood = minf(100.0, mood + 3.0)
	_event("The caretaker gave you %d %s." % [qty, item])


# --- persistence -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"cell": [cell.x, cell.y], "hunger": hunger, "energy": energy, "mood": mood,
		"bond": bond, "inventory": inventory, "events": events.slice(maxi(0, events.size() - 40)),
		"journal": journal,
	}


func from_dict(d: Dictionary) -> void:
	place(Vector2i(int(d.cell[0]), int(d.cell[1])))
	hunger = float(d.hunger)
	energy = float(d.energy)
	mood = float(d.mood)
	bond = float(d.bond)
	inventory = {}
	for k in d.inventory:
		inventory[k] = int(d.inventory[k])
	events = d.events
	journal = d.journal
