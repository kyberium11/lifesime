class_name Catalog
extends RefCounted
## Static city data: building kinds, per-level costs and models, city stages and the resident pools.
## Level arrays are indexed by level - 1. Models are "pack/name" paths under res://assets/kenney/.

const STAGES := ["Hamlet", "Village", "Town", "City", "Metropolis"]
## Population needed for each stage.
const STAGE_POP := [0, 8, 20, 45, 90]
## Work units a building needs to reach level n (index n - 1).
const WORK := [100.0, 140.0, 200.0, 280.0, 400.0]
## Visits a level-n building needs before it can be upgraded (index n).
const UPGRADE_VISITS := [0, 5, 14, 30, 55, 90]
const MAX_POPULATION := 120

const KINDS := {
	"home": {
		"label": "House", "icon": "home", "solid": true,
		"coins": [60, 140, 300, 620, 1300], "mats": [3, 6, 12, 22, 40],
		"stage": [0, 0, 1, 2, 3], "capacity": [2, 3, 5, 10, 20],
		"desc": "Homes. Residents sleep, cook and rest here.",
	},
	"market": {
		"label": "Market", "icon": "produce", "solid": true,
		"coins": [90, 200, 420, 880], "mats": [4, 8, 14, 24],
		"stage": [0, 1, 2, 3], "capacity": [0, 0, 0, 0],
		"desc": "Shops where residents buy meals. Higher levels feed more.",
	},
	"workshop": {
		"label": "Workshop", "icon": "work", "solid": true,
		"coins": [100, 220, 460, 950], "mats": [4, 8, 16, 28],
		"stage": [0, 1, 2, 3], "capacity": [0, 0, 0, 0],
		"desc": "Industry. Work shifts earn wages and build the city.",
	},
	"library": {
		"label": "Library", "icon": "study", "solid": true,
		"coins": [110, 260, 560], "mats": [4, 10, 18],
		"stage": [0, 1, 2], "capacity": [0, 0, 0],
		"desc": "Learning. Study here to raise knowledge faster.",
	},
	"bathhouse": {
		"label": "Bathhouse", "icon": "wash", "solid": true,
		"coins": [80, 190, 420], "mats": [3, 8, 14],
		"stage": [0, 1, 2], "capacity": [0, 0, 0],
		"desc": "Wash up and recover health.",
	},
	"farm": {
		"label": "Farm", "icon": "farm", "solid": false,
		"coins": [70, 160, 340], "mats": [3, 6, 10],
		"stage": [0, 0, 1], "capacity": [0, 0, 0],
		"desc": "Fields that feed the town. Bigger harvests with each level.",
	},
	"park": {
		"label": "Park", "icon": "play", "solid": false,
		"coins": [40, 110, 260], "mats": [2, 4, 8],
		"stage": [0, 0, 1], "capacity": [0, 0, 0],
		"desc": "Green space for play, exercise and calm.",
	},
	"office": {
		"label": "Offices", "icon": "town", "solid": true,
		"coins": [400, 800, 1500, 3000], "mats": [10, 20, 36, 60],
		"stage": [2, 3, 3, 4], "capacity": [0, 0, 0, 0],
		"desc": "Towers of commerce. High wages for city workers.",
	},
	"clinic": {
		"label": "Clinic", "icon": "health", "solid": true,
		"coins": [120, 280, 600], "mats": [5, 10, 18],
		"stage": [1, 2, 3], "capacity": [0, 0, 0],
		"desc": "Healing. The sick are treated here and recover fast.",
	},
	"watchtower": {
		"label": "Watchtower", "icon": "guard", "solid": true,
		"coins": [110, 260, 540], "mats": [6, 12, 20],
		"stage": [1, 2, 3], "capacity": [0, 0, 0],
		"desc": "Lookouts shoot at monsters that come near. Higher levels reach farther and hit harder.",
	},
	"wall": {
		"label": "Wall", "icon": "guard", "solid": false,
		"coins": [40, 120, 260], "mats": [6, 14, 26],
		"stage": [1, 2, 3], "capacity": [0, 0, 0],
		"desc": "A stretch of the village border wall: palisade, then stone, then fortified stone.",
	},
	"gate": {
		"label": "Gate", "icon": "guard", "solid": false,
		"coins": [90, 200, 420], "mats": [8, 16, 28],
		"stage": [1, 2, 3], "capacity": [0, 0, 0],
		"desc": "An opening in the wall. Residents pass; it shuts against monsters at night.",
	},
	"plaza": {
		"label": "Plaza", "icon": "star", "solid": false,
		"coins": [0, 300, 700], "mats": [0, 10, 22],
		"stage": [0, 1, 2], "capacity": [0, 0, 0],
		"desc": "The heart of town. A fountain and a place to gather.",
	},
}

## Walls and gates sit on district edges, not on lots.
const WALL_KINDS := ["wall", "gate"]

## Which kinds can be placed from the build menu (the plaza is the town centre).
const BUILDABLE := ["home", "market", "workshop", "library", "bathhouse", "farm", "park", "office", "clinic", "watchtower"]

const MODELS := {
	"home": [
		["suburban/building-type-h", "suburban/building-type-i", "suburban/building-type-a", "suburban/building-type-g"],
		["suburban/building-type-c", "suburban/building-type-j", "suburban/building-type-o", "suburban/building-type-m"],
		["suburban/building-type-b", "suburban/building-type-d", "suburban/building-type-k", "suburban/building-type-s", "suburban/building-type-u"],
		["suburban/building-type-e", "suburban/building-type-f", "suburban/building-type-n", "suburban/building-type-t", "suburban/building-type-r", "suburban/building-type-l"],
		["commercial/building-m", "commercial/building-n", "commercial/building-h"],
	],
	"market": [
		["commercial/building-a", "commercial/building-b", "commercial/building-c"],
		["commercial/building-d", "commercial/building-e", "commercial/building-f"],
		["commercial/building-g", "commercial/building-i", "commercial/building-j"],
		["commercial/building-k", "commercial/building-l"],
	],
	"workshop": [
		["industrial/building-i", "industrial/building-j", "industrial/building-s", "industrial/building-h", "industrial/building-k"],
		["industrial/building-p", "industrial/building-t", "industrial/building-g", "industrial/building-b"],
		["industrial/building-q", "industrial/building-r", "industrial/building-e", "industrial/building-d"],
		["industrial/building-l", "industrial/building-m", "industrial/building-f", "industrial/building-c", "industrial/building-n"],
	],
	"clinic": [
		["commercial/building-b"], ["commercial/building-e"], ["commercial/building-k"],
	],
	"library": [
		["suburban/building-type-q"], ["suburban/building-type-p"], ["commercial/building-n"],
	],
	"bathhouse": [
		["suburban/building-type-l"], ["commercial/building-b"], ["commercial/building-j"],
	],
	"office": [
		["commercial/building-skyscraper-c"], ["commercial/building-skyscraper-a"],
		["commercial/building-skyscraper-d"], ["commercial/building-skyscraper-e"],
	],
}

const RESIDENT_NAMES := [
	"Pip", "Mira", "Theo", "June", "Ada", "Bram", "Cora", "Dex", "Elia", "Finn", "Gwen", "Hugo", "Iris", "Jonas", "Kira", "Leo",
	"Maya", "Nico", "Opal", "Pax", "Quinn", "Rhea", "Soren", "Tess", "Uma", "Vic", "Wren", "Xavi", "Yara", "Zed", "Alma", "Bo",
	"Cleo", "Dana", "Eli", "Faye", "Gus", "Hana", "Ivo", "Jade", "Kai", "Lena", "Milo", "Nora", "Otto", "Pia", "Rex", "Sage",
]
const RESIDENT_TRAITS := [
	"Curious gardener", "Outgoing cook", "Ambitious maker", "Creative bookworm", "Quiet dreamer", "Cheerful helper",
	"Practical builder", "Gentle healer", "Restless explorer", "Thoughtful planner", "Playful joker", "Careful saver",
]
## Character models that read as ordinary villagers (the others are robots, orcs and the chief).
const LOOKS := ["character-b", "character-n", "character-k", "character-e", "character-f", "character-c", "character-m", "character-q", "character-a", "character-j", "character-p"]
const CHIEF_LOOK := "character-i"
## Looks that read as women, so the voice and pitch match.
const FEMALE_LOOKS := ["character-n", "character-e", "character-f"]


static func spec(kind: String) -> Dictionary:
	return KINDS.get(kind, {})


static func max_level(kind: String) -> int:
	return (KINDS[kind].coins as Array).size()


static func label(kind: String) -> String:
	return str(KINDS[kind].label)


static func cost(kind: String, level: int) -> Dictionary:
	var i := clampi(level - 1, 0, max_level(kind) - 1)
	return {"coins": int(KINDS[kind].coins[i]), "mats": int(KINDS[kind].mats[i])}


static func stage_needed(kind: String, level: int) -> int:
	return int(KINDS[kind].stage[clampi(level - 1, 0, max_level(kind) - 1)])


static func capacity(kind: String, level: int) -> int:
	if level < 1:
		return 0
	return int(KINDS[kind].capacity[clampi(level - 1, 0, max_level(kind) - 1)])


static func solid(kind: String) -> bool:
	return bool(KINDS[kind].solid)


static func stage_for_pop(pop: int) -> int:
	var s := 0
	for i in range(STAGE_POP.size()):
		if pop >= STAGE_POP[i]:
			s = i
	return s


## The Kenney model for a building ("" for kinds drawn from several parts, like farms and parks).
static func model(kind: String, level: int, variant: int) -> String:
	if not MODELS.has(kind):
		return ""
	var by_level: Array = MODELS[kind]
	var options: Array = by_level[clampi(level - 1, 0, by_level.size() - 1)]
	return str(options[absi(variant) % options.size()])
