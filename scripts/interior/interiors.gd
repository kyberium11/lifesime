class_name Interiors
extends RefCounted
## What is inside each building. A building's `furniture` is a list of items:
##   {id, model, x, z, rot, role, owners: [resident names], base: bool, price}
## x and z give the middle of the item's floor footprint in room units (one unit is one wall panel); rot is
## 0/90/180/270 degrees about the vertical axis (0 faces +z, towards the south wall). The room's door is in the
## middle of the south wall. Layouts are generated per kind and level, deterministically from the building's
## variant, then kept: gifts and purchases are added to the same list and survive upgrades.

const ENTERABLE := ["home", "market", "workshop", "library", "bathhouse", "office", "clinic", "farm"]
const MARGIN := 0.04
const DOOR_CLEAR := 0.95


static func enterable(b: Dictionary) -> bool:
	return str(b.kind) in ENTERABLE and int(b.level) >= 1


## Room width (x) and depth (z) in units.
static func dims(kind: String, level: int) -> Vector2:
	var lv := clampi(level, 1, 5)
	match kind:
		"home": return [Vector2(6, 5), Vector2(7, 5), Vector2(8, 6), Vector2(10, 7), Vector2(12, 8)][lv - 1]
		"market": return [Vector2(7, 5), Vector2(8, 6), Vector2(10, 6), Vector2(12, 7), Vector2(12, 7)][lv - 1]
		"workshop": return [Vector2(7, 6), Vector2(9, 6), Vector2(10, 7), Vector2(12, 8), Vector2(12, 8)][lv - 1]
		"library": return [Vector2(7, 6), Vector2(9, 7), Vector2(11, 8), Vector2(11, 8), Vector2(11, 8)][lv - 1]
		"bathhouse": return [Vector2(6, 5), Vector2(8, 6), Vector2(10, 6), Vector2(10, 6), Vector2(10, 6)][lv - 1]
		"office": return [Vector2(9, 6), Vector2(10, 7), Vector2(12, 8), Vector2(12, 8), Vector2(12, 8)][lv - 1]
		"clinic": return [Vector2(7, 5), Vector2(8, 6), Vector2(10, 6), Vector2(10, 6), Vector2(10, 6)][lv - 1]
		"farm": return [Vector2(8, 6), Vector2(9, 7), Vector2(11, 7), Vector2(11, 7), Vector2(11, 7)][lv - 1]
	return Vector2(6, 5)


static func door_x(size: Vector2) -> float:
	return floorf(size.x * 0.5) + 0.5


## Where a visitor stands just inside the door.
static func entrance(b: Dictionary) -> Vector2:
	var size := dims(str(b.kind), int(b.level))
	return Vector2(door_x(size), size.y - 0.75)


static func furniture_of(b: Dictionary) -> Array:
	return b.get("furniture", []) if b.get("furniture", []) is Array else []


static func item_by_id(b: Dictionary, id: int) -> Dictionary:
	for it in furniture_of(b):
		if int(it.id) == id:
			return it
	return {}


# --- geometry ------------------------------------------------------------------------------------------------------

static func rect_of(model: String, rot: int, x: float, z: float) -> Rect2:
	var fp := FurnitureDb.footprint(model)
	if rot % 180 != 0:
		fp = Vector2(fp.y, fp.x)
	return Rect2(Vector2(x - fp.x * 0.5, z - fp.y * 0.5), fp)


static func front_of(rot: int) -> Vector2:
	var a := deg_to_rad(float(rot))
	return Vector2(sin(a), cos(a))


static func _blocks_floor(role: String) -> bool:
	return role not in ["rug", "tv", "computer"]


static func fits(b: Dictionary, model: String, rot: int, x: float, z: float, ignore_id: int = -1) -> bool:
	var size := dims(str(b.kind), int(b.level))
	var r := rect_of(model, rot, x, z)
	if r.position.x < MARGIN or r.position.y < MARGIN or r.end.x > size.x - MARGIN or r.end.y > size.y - MARGIN:
		return false
	if not _blocks_floor(FurnitureDb.role_of(model)):
		return true
	# Keep the doorway clear.
	var door := Rect2(Vector2(door_x(size) - DOOR_CLEAR * 0.5, size.y - DOOR_CLEAR), Vector2(DOOR_CLEAR, DOOR_CLEAR))
	if r.intersects(door):
		return false
	for it in furniture_of(b):
		if int(it.id) == ignore_id or not _blocks_floor(str(it.role)):
			continue
		if r.grow(-0.02).intersects(rect_of(str(it.model), int(it.rot), float(it.x), float(it.z))):
			return false
	return true


static func _make_item(sim: LifeSim, model: String, x: float, z: float, rot: int, base: bool, owners: Array = []) -> Dictionary:
	sim.item_serial += 1
	return {"id": sim.item_serial, "model": model, "x": snappedf(x, 0.01), "z": snappedf(z, 0.01), "rot": rot, "role": FurnitureDb.role_of(model), "owners": owners.duplicate(), "base": base, "price": FurnitureDb.price_of(model), "y": 0.0}


## Put an item at an exact spot if it fits. Returns the item or {}.
static func add(sim: LifeSim, b: Dictionary, model: String, x: float, z: float, rot: int, base: bool = false, owners: Array = []) -> Dictionary:
	if not fits(b, model, rot, x, z):
		return {}
	if not b.get("furniture", []) is Array:
		b.furniture = []
	var it := _make_item(sim, model, x, z, rot, base, owners)
	b.furniture.append(it)
	return it


## Put an item wherever there is room, preferring spots against a wall. Returns the item or {}.
static func place_auto(sim: LifeSim, b: Dictionary, model: String, owners: Array = [], base: bool = false) -> Dictionary:
	var size := dims(str(b.kind), int(b.level))
	var best := {}
	var best_score := 1.0e9
	var steps_x := int(size.x / 0.25)
	var steps_z := int(size.y / 0.25)
	for rot in [0, 90, 180, 270]:
		var fp := rect_of(model, rot, 0.0, 0.0).size
		for ix in range(steps_x + 1):
			for iz in range(steps_z + 1):
				var x := float(ix) * 0.25
				var z := float(iz) * 0.25
				if not fits(b, model, rot, x, z):
					continue
				var wall_gap := minf(minf(x - fp.x * 0.5, size.x - x - fp.x * 0.5), minf(z - fp.y * 0.5, size.y - z - fp.y * 0.5))
				# Prefer facing into the room from a wall, and a centre-ish position along it.
				var facing_in := 0.0
				var f := front_of(rot)
				var centre := Vector2(size.x * 0.5, size.y * 0.5)
				if (centre - Vector2(x, z)).dot(f) < 0.0:
					facing_in = 1.5
				var score := wall_gap * 3.0 + facing_in + absf(x - size.x * 0.5) * 0.02
				if FurnitureDb.role_of(model) == "rug":
					score = Vector2(x, z).distance_to(centre)
				if score < best_score:
					best_score = score
					best = {"x": x, "z": z, "rot": rot}
	if best.is_empty():
		return {}
	return add(sim, b, model, float(best.x), float(best.z), int(best.rot), base, owners)


## An item standing on top of another (a television on its cabinet, a computer on a desk).
static func add_on(sim: LifeSim, b: Dictionary, model: String, base_item: Dictionary, base_owner: bool = true) -> Dictionary:
	if base_item.is_empty():
		return {}
	if not b.get("furniture", []) is Array:
		b.furniture = []
	var it := _make_item(sim, model, float(base_item.x), float(base_item.z), int(base_item.rot), true, [])
	it.y = FurnitureDb.height(str(base_item.model))
	b.furniture.append(it)
	return it


static func remove(b: Dictionary, id: int) -> Dictionary:
	for it in furniture_of(b):
		if int(it.id) == id:
			b.furniture.erase(it)
			return it
	return {}


# --- layouts ---------------------------------------------------------------------------------------------------------

## Items lined up along a wall, facing inward. wall: 0 west, 1 east, 2 north, 3 south.
static func _run(sim: LifeSim, b: Dictionary, wall: int, models: Array, start: float, gap: float = 0.04, owners_base: bool = true) -> float:
	var size := dims(str(b.kind), int(b.level))
	var cursor := start
	for model in models:
		var fp := FurnitureDb.footprint(model)
		var along := fp.x
		var depth := fp.y
		var rot := 0
		var x := 0.0
		var z := 0.0
		match wall:
			2:
				rot = 0
				x = cursor + along * 0.5
				z = depth * 0.5 + 0.06
			3:
				rot = 180
				x = cursor + along * 0.5
				z = size.y - depth * 0.5 - 0.06
			0:
				rot = 90
				x = depth * 0.5 + 0.06
				z = cursor + along * 0.5
			1:
				rot = 270
				x = size.x - depth * 0.5 - 0.06
				z = cursor + along * 0.5
		if add(sim, b, model, x, z, rot, owners_base).is_empty():
			cursor += 0.1
			continue
		cursor += along + gap
	return cursor


## Fill an empty building with its base furniture.
static func generate(sim: LifeSim, b: Dictionary) -> void:
	b.furniture = []
	var kind := str(b.kind)
	var level := clampi(int(b.level), 1, 5)
	var size := dims(kind, level)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b.id) * 977 + int(b.variant)
	match kind:
		"home": _layout_home(sim, b, size, level, rng)
		"market": _layout_market(sim, b, size, level, rng)
		"workshop": _layout_workshop(sim, b, size, level, rng)
		"library": _layout_library(sim, b, size, level, rng)
		"bathhouse": _layout_bathhouse(sim, b, size, level, rng)
		"office": _layout_office(sim, b, size, level, rng)
		"clinic": _layout_clinic(sim, b, size, level, rng)
		"farm": _layout_farm(sim, b, size, level, rng)
	b.layout_level = level


static func _layout_home(sim: LifeSim, b: Dictionary, size: Vector2, level: int, rng: RandomNumberGenerator) -> void:
	# Kitchen along the north wall.
	var kitchen: Array = ["kitchenFridge", "kitchenCabinet", "kitchenStove", "kitchenCabinetDrawer", "kitchenSink"]
	if level >= 3:
		kitchen.append("kitchenCabinet")
	_run(sim, b, 2, kitchen, 0.4)
	# Beds down the west wall: one per resident the house can hold (bunks when it is crowded).
	var capacity := Catalog.capacity("home", level)
	var beds: Array = []
	var left := capacity
	while left > 0 and beds.size() < 8:
		if left >= 2 and (capacity >= 5):
			beds.append("bedBunk")
			left -= 2
		elif left >= 2 and level >= 2 and rng.randf() < 0.4:
			beds.append("bedDouble")
			left -= 2
		else:
			beds.append("bedSingle")
			left -= 1
	var z_cursor := 1.2
	for model in beds:
		var fp := FurnitureDb.footprint(model)
		if z_cursor + fp.x > size.y - 0.5:
			# Second column of beds against the east wall.
			break
		if add(sim, b, model, fp.y * 0.5 + 0.06, z_cursor + fp.x * 0.5, 90, true).is_empty():
			z_cursor += 0.1
			continue
		z_cursor += fp.x + 0.15
	var placed_beds := 0
	for it in furniture_of(b):
		if str(it.role) == "bed":
			placed_beds += 1
	var east_cursor := 1.2
	while placed_beds < beds.size():
		var model2: String = beds[placed_beds]
		var fp2 := FurnitureDb.footprint(model2)
		if add(sim, b, model2, size.x - fp2.y * 0.5 - 0.06, east_cursor + fp2.x * 0.5, 270, true).is_empty():
			east_cursor += 0.15
			if east_cursor > size.y:
				break
			continue
		east_cursor += fp2.x + 0.15
		placed_beds += 1
	# Bedside tables next to the beds, and a lamp.
	for it in furniture_of(b).duplicate():
		if str(it.role) == "bed":
			var nightstand := "cabinetBedDrawer"
			place_auto(sim, b, nightstand, [], true)
			break
	# Dining table with chairs in the middle, on a rug.
	var cx := size.x * 0.5 + 0.4
	var cz := size.y * 0.5 + 0.1
	add(sim, b, "rugRectangle", cx, cz, 0, true)
	var table := add(sim, b, "table", cx, cz, 0, true)
	if not table.is_empty():
		var tfp := FurnitureDb.footprint("table")
		add(sim, b, "chair", cx - tfp.x * 0.3, cz - tfp.y * 0.5 - 0.22, 0, true)
		add(sim, b, "chair", cx + tfp.x * 0.3, cz - tfp.y * 0.5 - 0.22, 0, true)
		add(sim, b, "chair", cx - tfp.x * 0.3, cz + tfp.y * 0.5 + 0.22, 180, true)
		add(sim, b, "chair", cx + tfp.x * 0.3, cz + tfp.y * 0.5 + 0.22, 180, true)
	# Sofa, television and lamp along the east wall; an armchair in the corner.
	var lounge: Array = ["loungeSofa", "cabinetTelevision"]
	_run(sim, b, 1, lounge, 1.4)
	for it in furniture_of(b).duplicate():
		if str(it.model) == "cabinetTelevision":
			add_on(sim, b, "televisionModern", it)
	place_auto(sim, b, "loungeChair", [], true)
	place_auto(sim, b, "lampRoundFloor", [], true)
	if level >= 2:
		place_auto(sim, b, "bookcaseClosed", [], true)
		place_auto(sim, b, "pottedPlant", [], true)
	if level >= 3:
		# A bathroom corner.
		_run(sim, b, 3, ["bathtub", "bathroomSink", "toilet"], 0.3)
		place_auto(sim, b, "rugRound", [], true)
	if level >= 4:
		place_auto(sim, b, "loungeSofaLong", [], true)
		place_auto(sim, b, "bookcaseClosedWide", [], true)
		place_auto(sim, b, "plantSmall1", [], true)


static func _layout_market(sim: LifeSim, b: Dictionary, size: Vector2, level: int, rng: RandomNumberGenerator) -> void:
	# Shelves round the back and sides.
	var shelf_models: Array = []
	var shelf_count := int(size.x * 0.8)
	for i in range(shelf_count):
		shelf_models.append("bookcaseOpen" if i % 2 == 0 else "bookcaseClosed")
	_run(sim, b, 2, shelf_models, 0.4)
	_run(sim, b, 0, ["bookcaseOpen", "bookcaseOpen", "bookcaseClosed"], 1.2)
	_run(sim, b, 1, ["bookcaseClosed", "bookcaseOpen", "bookcaseOpen"], 1.2)
	# A counter with a stool for the stallholder, across the room towards the front.
	var counter_x := size.x * 0.5 - 1.2
	for i in range(1 + level / 2):
		add(sim, b, "kitchenBar", counter_x + float(i) * 0.75, size.y - 1.7, 180, true)
	add(sim, b, "stoolBar", counter_x + 0.4, size.y - 1.15, 180, true)
	# Display tables and crates of goods.
	# Display tables in the middle of the floor, each with a crate of goods on top.
	var table_fp := FurnitureDb.footprint("table")
	var tx := 1.6
	var tz := 2.0
	for i in range(2 + level):
		var table_item := add(sim, b, "table", tx + table_fp.x * 0.5, tz, 0, true)
		if not table_item.is_empty():
			add_on(sim, b, "cardboardBoxClosed" if i % 2 == 0 else "cardboardBoxOpen", table_item)
		tx += table_fp.x + 0.9
		if tx + table_fp.x > size.x - 1.2:
			tx = 1.6
			tz += 1.4
	for i in range(2 + level):
		place_auto(sim, b, "cardboardBoxClosed" if i % 2 == 0 else "cardboardBoxOpen", [], true)
	place_auto(sim, b, "pottedPlant", [], true)
	add(sim, b, "rugDoormat", door_x(size), size.y - 0.5, 0, true)


static func _layout_workshop(sim: LifeSim, b: Dictionary, size: Vector2, level: int, rng: RandomNumberGenerator) -> void:
	_run(sim, b, 2, ["bookcaseClosedWide", "kitchenCabinet", "kitchenStove", "kitchenCabinetDrawer", "bookcaseClosed", "bookcaseClosed"], 0.4)
	_run(sim, b, 0, ["bookcaseClosed", "cardboardBoxClosed", "bookcaseClosed"], 1.4)
	_run(sim, b, 1, ["cardboardBoxClosed", "cardboardBoxOpen", "bookcaseOpen"], 1.4)
	# Workbenches in columns down the middle, with a walkway on either side.
	var benches := 2 + level
	var bench_fp := FurnitureDb.footprint("tableCross")
	var usable := size.x - 3.6
	var columns := maxi(1, int((usable + 0.4) / (bench_fp.x + 0.4)))
	var start_x := (size.x - (float(columns) * bench_fp.x + float(columns - 1) * 0.4)) * 0.5
	for i in range(benches):
		var col := i % columns
		var row := i / columns
		var x := start_x + float(col) * (bench_fp.x + 0.4) + bench_fp.x * 0.5
		var z := 2.5 + float(row) * 1.6
		add(sim, b, "tableCross", x, z, 0, true)
	for i in range(1 + level / 2):
		place_auto(sim, b, "cardboardBoxClosed", [], true)
	place_auto(sim, b, "lampRoundFloor", [], true)
	place_auto(sim, b, "desk", [], true)
	place_auto(sim, b, "chairDesk", [], true)


static func _layout_library(sim: LifeSim, b: Dictionary, size: Vector2, level: int, rng: RandomNumberGenerator) -> void:
	var shelves: Array = []
	for i in range(int(size.x * 0.9)):
		shelves.append("bookcaseClosedWide" if i % 3 == 0 else "bookcaseClosed")
	_run(sim, b, 2, shelves, 0.4)
	_run(sim, b, 0, ["bookcaseOpen", "bookcaseClosed", "bookcaseOpen", "bookcaseClosed"], 1.3)
	_run(sim, b, 1, ["bookcaseOpen", "bookcaseClosed", "bookcaseOpen", "bookcaseClosed"], 1.3)
	# Reading tables with a chair each.
	var tables := 2 + level
	var x := 2.0
	var z := size.y * 0.5 - 0.2
	for i in range(tables):
		var tfp := FurnitureDb.footprint("desk")
		if add(sim, b, "desk", x + tfp.x * 0.5, z, 0, true).is_empty():
			z += 1.4
			x = 2.0
			continue
		var cfp := FurnitureDb.footprint("chairDesk")
		add(sim, b, "chairDesk", x + tfp.x * 0.5, z + tfp.y * 0.5 + cfp.y * 0.5 + 0.03, 180, true)
		x += tfp.x + 0.9
		if x + tfp.x > size.x - 1.5:
			x = 2.0
			z += 1.6
	place_auto(sim, b, "loungeSofa", [], true)
	place_auto(sim, b, "lampRoundFloor", [], true)
	place_auto(sim, b, "pottedPlant", [], true)
	add(sim, b, "rugRectangle", size.x * 0.5, size.y * 0.5 + 1.0, 0, true)


static func _layout_bathhouse(sim: LifeSim, b: Dictionary, size: Vector2, level: int, rng: RandomNumberGenerator) -> void:
	var tubs: Array = []
	for i in range(1 + level):
		tubs.append("bathtub")
	_run(sim, b, 2, tubs, 0.5, 0.3)
	_run(sim, b, 0, ["shower", "showerRound", "bathroomSink"], 1.6)
	_run(sim, b, 1, ["bathroomSink", "toilet", "bathroomCabinet"], 1.6)
	place_auto(sim, b, "benchCushion", [], true)
	place_auto(sim, b, "bench", [], true)
	place_auto(sim, b, "pottedPlant", [], true)
	place_auto(sim, b, "rugRound", [], true)
	add(sim, b, "rugDoormat", door_x(size), size.y - 0.5, 0, true)


static func _layout_office(sim: LifeSim, b: Dictionary, size: Vector2, level: int, rng: RandomNumberGenerator) -> void:
	_run(sim, b, 2, ["bookcaseClosedWide", "bookcaseClosed", "kitchenCabinet", "kitchenCabinet", "kitchenFridgeSmall", "bookcaseClosed"], 0.4)
	var desks := 3 + level * 2
	var x := 1.4
	var z := 2.2
	for i in range(desks):
		var dfp := FurnitureDb.footprint("desk")
		if add(sim, b, "desk", x + dfp.x * 0.5, z, 0, true).is_empty():
			z += 1.7
			x = 1.4
			continue
		var placed_desk: Dictionary = furniture_of(b).back() as Dictionary
		add_on(sim, b, "computerScreen", placed_desk)
		var chair_fp := FurnitureDb.footprint("chairDesk")
		add(sim, b, "chairDesk", x + dfp.x * 0.5, z + dfp.y * 0.5 + chair_fp.y * 0.5 + 0.03, 180, true)
		x += dfp.x + 0.8
		if x + dfp.x > size.x - 1.0:
			x = 1.4
			z += 1.7
	place_auto(sim, b, "loungeSofa", [], true)
	place_auto(sim, b, "pottedPlant", [], true)
	place_auto(sim, b, "lampRoundFloor", [], true)
	add(sim, b, "rugDoormat", door_x(size), size.y - 0.5, 0, true)


static func _layout_farm(sim: LifeSim, b: Dictionary, size: Vector2, level: int, rng: RandomNumberGenerator) -> void:
	# Hay racks and feed sacks along the back, tools and a workbench on the side, troughs where the animals feed.
	var racks: Array = []
	for i in range(int(size.x * 0.7)):
		racks.append("bookcaseOpenLow" if i % 2 == 0 else "cardboardBoxOpen")
	_run(sim, b, 2, racks, 0.5, 0.2)
	_run(sim, b, 0, ["bookcaseClosed", "tableCross", "bookcaseClosed"], 1.4, 0.2)
	_run(sim, b, 1, ["cardboardBoxClosed", "cardboardBoxClosed", "cardboardBoxOpen"], 1.6, 0.2)
	var troughs := 2 + level
	var tfp := FurnitureDb.footprint("bench")
	var x := size.x * 0.5 - float(troughs) * (tfp.x + 0.5) * 0.5 + tfp.x * 0.5 + 0.8
	for i in range(troughs):
		add(sim, b, "bench", x, size.y * 0.5 + 0.2, 0, true)
		x += tfp.x + 0.5
	add(sim, b, "stoolBar", 2.2, size.y - 1.5, 0, true)
	place_auto(sim, b, "lampRoundFloor", [], true)
	place_auto(sim, b, "coatRack", [], true)
	add(sim, b, "rugDoormat", door_x(size), size.y - 0.5, 0, true)


static func _layout_clinic(sim: LifeSim, b: Dictionary, size: Vector2, level: int, rng: RandomNumberGenerator) -> void:
	var beds := 2 + level
	var cursor := 0.4
	for i in range(beds):
		var fp := FurnitureDb.footprint("bedSingle")
		var x := cursor + fp.x * 0.5
		if x + fp.x * 0.5 > size.x - 0.4:
			break
		add(sim, b, "bedSingle", x, fp.y * 0.5 + 0.06, 0, true)
		cursor += fp.x + 0.3
	_run(sim, b, 0, ["bathroomCabinet", "bookcaseClosed"], 2.5)
	_run(sim, b, 1, ["bathroomCabinet", "kitchenFridgeSmall"], 2.5)
	place_auto(sim, b, "desk", [], true)
	place_auto(sim, b, "chairDesk", [], true)
	place_auto(sim, b, "benchCushion", [], true)
	place_auto(sim, b, "pottedPlant", [], true)
	add(sim, b, "rugDoormat", door_x(size), size.y - 0.5, 0, true)


## Make sure an enterable building has furniture matching its level. Gifts and purchases are kept across upgrades.
static func ensure(sim: LifeSim, b: Dictionary) -> void:
	if not enterable(b):
		return
	var level := clampi(int(b.level), 1, 5)
	var current := furniture_of(b)
	if not current.is_empty() and int(b.get("layout_level", 0)) == level:
		return
	var kept: Array = []
	for it in current:
		if not bool(it.get("base", false)):
			kept.append(it)
	generate(sim, b)
	for it in kept:
		var again := place_auto(sim, b, str(it.model), it.owners, false)
		if not again.is_empty():
			again.price = int(it.get("price", FurnitureDb.price_of(str(it.model))))
	Ownership.refresh(sim, b)


# --- smart objects: where a resident does what ---------------------------------------------------------------------------

## Where someone stands or lies to use an item: {pos: Vector2, face: float (degrees), pose: String}.
static func slot_of(it: Dictionary, index: int = 0) -> Dictionary:
	var model := str(it.model)
	var role := str(it.role)
	var rot := int(it.rot)
	var centre := Vector2(float(it.x), float(it.z))
	var front := front_of(rot)
	var fp := FurnitureDb.footprint(model)
	match role:
		"bed":
			var side := Vector2(front.y, -front.x)
			var offset := side * (0.0 if int(FurnitureDb.spec(model).get("slots", 1)) == 1 else (0.25 if index % 2 == 0 else -0.25))
			return {"pos": centre + offset, "face": float(rot), "pose": "lie"}
		"seat", "armchair":
			return {"pos": centre, "face": float(rot), "pose": "sit"}
		"sofa", "bench":
			var s2 := Vector2(front.y, -front.x)
			var o2 := s2 * (0.0 if int(FurnitureDb.spec(model).get("slots", 1)) <= 1 else (0.3 if index % 2 == 0 else -0.3))
			return {"pos": centre + o2, "face": float(rot), "pose": "sit"}
	var depth := fp.y if rot % 180 == 0 else fp.x
	return {"pos": centre + front * (depth * 0.5 + 0.32), "face": float(rot + 180), "pose": "stand"}


## Best item for an action (and a resident). Prefers the resident's own things, then free shared ones.
static func find_item(sim: LifeSim, b: Dictionary, action: String, who: String = "") -> Dictionary:
	var roles: Array = []
	match action:
		"sleep", "treat": roles = ["bed"]
		"rest": roles = ["armchair", "sofa", "bed", "bench"]
		"cook": roles = ["stove", "kitchen"]
		"eat": roles = ["seat", "table", "counter"]
		"wash": roles = ["bath"]
		"study": roles = ["desk", "bookcase"]
		"work": roles = ["bench_work", "desk", "counter", "computer"]
		"farm": roles = ["bench_work", "bench"]
		"socialize": roles = ["sofa", "bench"]
	var best := {}
	var best_rank := 1 << 20
	for role_rank in range(roles.size()):
		for it in furniture_of(b):
			if str(it.role) != roles[role_rank]:
				continue
			var owners: Array = it.owners
			var rank := role_rank * 10
			if who != "" and who in owners:
				rank -= 5
			elif not owners.is_empty() and not Ownership.may_use(sim, who, it):
				rank += 6
			if rank < best_rank:
				best_rank = rank
				best = it
	return best
