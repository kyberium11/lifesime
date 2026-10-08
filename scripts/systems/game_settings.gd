class_name GameSettings
extends RefCounted
## Player settings kept between sessions in user://settings.json: voice volume, AI on/off, graphics quality,
## how dangerous the nights are, and which tutorial steps have been done.

const PATH := "user://settings.json"
const DEFAULTS := {"voice_volume": 80, "voice_replies": true, "ai": true, "quality": "high", "difficulty": "normal", "blood": true, "tutorial_hidden": false, "tutorial_done": []}
const DIFFICULTY := {"peaceful": 0.0, "calm": 0.6, "normal": 1.0, "harsh": 1.6}
const QUALITY := ["low", "medium", "high"]

static var data: Dictionary = DEFAULTS.duplicate(true)
## Set by the menu so the next scene start begins a brand new village.
static var new_game := false


static func value(key: String) -> Variant:
	return data.get(key, DEFAULTS.get(key))


static func set_value(key: String, v: Variant) -> void:
	data[key] = v


static func monster_factor() -> float:
	return float(DIFFICULTY.get(str(data.get("difficulty", "normal")), 1.0))


static func load_from(path: String = PATH) -> void:
	data = DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		for k in DEFAULTS:
			if parsed.has(k) and (typeof(parsed[k]) == typeof(DEFAULTS[k]) or (parsed[k] is float and DEFAULTS[k] is int)):
				data[k] = int(parsed[k]) if DEFAULTS[k] is int else parsed[k]
		if not DIFFICULTY.has(str(data.difficulty)):
			data.difficulty = "normal"
		if not QUALITY.has(str(data.quality)):
			data.quality = "high"
		data.voice_volume = clampi(int(data.voice_volume), 0, 150)


static func save_to(path: String = PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	return true


## Graphics quality: shadows and antialiasing on the given viewport.
static func apply_quality(viewport: Viewport, light: DirectionalLight3D) -> void:
	var q := str(data.quality)
	viewport.msaa_3d = Viewport.MSAA_DISABLED if q == "low" else (Viewport.MSAA_2X if q == "medium" else Viewport.MSAA_4X)
	if light != null:
		light.shadow_enabled = q != "low"
