class_name SaveSlots
extends RefCounted
## Named save slots under user://slots/. Each file is a normal village save plus a small "meta" block so the
## picker can show day, population and when it was saved without loading the whole village.

const COUNT := 5
const DIR := "user://slots"


static func path(slot: int, dir: String = DIR) -> String:
	return "%s/slot_%d.json" % [dir, slot]


static func meta_of(sim: LifeSim) -> Dictionary:
	return {"day": sim.day(), "year": Chronicle.year_of(sim.day()), "season": Chronicle.season_of(sim.day()), "population": sim.residents.size(), "stage": sim.stage_name(), "money": sim.money, "saved": Time.get_datetime_string_from_system(false, true)}


static func save(sim: LifeSim, slot: int, dir: String = DIR) -> bool:
	if slot < 0 or slot >= COUNT:
		return false
	DirAccess.make_dir_recursive_absolute(dir)
	var data := sim.to_dict()
	data["meta"] = meta_of(sim)
	var file := FileAccess.open(path(slot, dir) + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return DirAccess.rename_absolute(path(slot, dir) + ".tmp", path(slot, dir)) == OK or FileAccess.file_exists(path(slot, dir))


static func read(slot: int, dir: String = DIR) -> Dictionary:
	if not FileAccess.file_exists(path(slot, dir)):
		return {}
	var file := FileAccess.open(path(slot, dir), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


## [{slot, exists, meta}] for every slot.
static func list(dir: String = DIR) -> Array:
	var out: Array = []
	for i in range(COUNT):
		var d := read(i, dir)
		out.append({"slot": i, "exists": not d.is_empty(), "meta": d.get("meta", {}) if d.get("meta", {}) is Dictionary else {}})
	return out


static func load_into(sim: LifeSim, slot: int, dir: String = DIR) -> bool:
	var d := read(slot, dir)
	return not d.is_empty() and sim.load_data(d)


## Make a slot the village that the next scene start loads: copies it over the main save.
static func activate(slot: int, target: String, dir: String = DIR) -> bool:
	if not FileAccess.file_exists(path(slot, dir)):
		return false
	return DirAccess.copy_absolute(path(slot, dir), target) == OK


static func delete(slot: int, dir: String = DIR) -> bool:
	return FileAccess.file_exists(path(slot, dir)) and DirAccess.remove_absolute(path(slot, dir)) == OK


static func describe(entry: Dictionary) -> String:
	if not bool(entry.exists):
		return "Empty"
	var m: Dictionary = entry.meta
	if m.is_empty():
		return "Saved village"
	return "%s · Year %d, day %d (%s) · %d people · %d coins · %s" % [m.get("stage", "Village"), int(m.get("year", 1)), int(m.get("day", 1)), m.get("season", ""), int(m.get("population", 0)), int(m.get("money", 0)), str(m.get("saved", "")).replace("T", " ")]
