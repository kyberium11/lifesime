extends Node
## Autoload: loads data-driven game definitions (resources, foods, buildings), config and persona.

var game: Dictionary = {}
var config: Dictionary = {}
var persona: String = ""


func _ready() -> void:
	game = _load_json("res://data/game.json")
	config = _load_json("res://data/config.json")
	var f := FileAccess.open("res://data/persona.txt", FileAccess.READ)
	if f:
		persona = f.get_as_text()


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Bad JSON in %s" % path)
		return {}
	return parsed
