class_name FurnitureDb
extends RefCounted
## The furniture catalogue: every Kenney furniture model we use, what it is for (role), what it costs, how
## comfortable it makes a home, whether it is a personal possession, and how big it is on the floor.
## Sizes come from data/furniture_sizes.json (made by tools/measure_furniture.gd).
##
## Conventions: a model's origin sits at one corner of its footprint; it extends +x and -z from there and its
## front faces +z. `scale` brings the kit's dollhouse proportions into line with a villager drawn at
## VILLAGER_SCALE, so counters reach roughly waist height and beds fit a sleeper.

const VILLAGER_SCALE := 0.18
## Every piece is drawn at its own `scale` times this, so people stand taller than tables and chair backs reach their shoulders.
const FURNITURE_FACTOR := 0.66
const WALL_HEIGHT := 1.29

## role: what the object is. actions: the activities a resident can do at it. price in coins, comfort adds to
## the home's comfort score, personal items belong to one resident (a bed, an armchair, a bedside table).
const ITEMS := {
	# beds and bedroom
	"bedSingle": {"label": "Bed", "role": "bed", "actions": ["sleep", "rest"], "price": 45, "comfort": 4, "personal": true, "scale": 0.9, "slots": 1},
	"bedDouble": {"label": "Double bed", "role": "bed", "actions": ["sleep", "rest"], "price": 70, "comfort": 5, "personal": true, "scale": 0.9, "slots": 2},
	"bedBunk": {"label": "Bunk bed", "role": "bed", "actions": ["sleep", "rest"], "price": 60, "comfort": 3, "personal": true, "scale": 0.9, "slots": 2},
	"cabinetBedDrawer": {"label": "Bedside table", "role": "storage", "actions": [], "price": 14, "comfort": 1, "personal": true, "scale": 1.4},
	"cabinetBed": {"label": "Bedside cabinet", "role": "storage", "actions": [], "price": 12, "comfort": 1, "personal": true, "scale": 1.4},
	"coatRack": {"label": "Coat rack", "role": "decor", "actions": [], "price": 10, "comfort": 1, "personal": true, "scale": 1.4},
	# seating
	"chair": {"label": "Chair", "role": "seat", "actions": ["eat"], "price": 10, "comfort": 1, "personal": false, "scale": 1.7},
	"chairCushion": {"label": "Cushioned chair", "role": "seat", "actions": ["eat"], "price": 16, "comfort": 1, "personal": false, "scale": 1.7},
	"chairRounded": {"label": "Round chair", "role": "seat", "actions": ["eat"], "price": 16, "comfort": 1, "personal": false, "scale": 1.7},
	"chairDesk": {"label": "Desk chair", "role": "seat", "actions": ["work", "study"], "price": 18, "comfort": 1, "personal": false, "scale": 1.7},
	"loungeChair": {"label": "Armchair", "role": "armchair", "actions": ["rest"], "price": 32, "comfort": 3, "personal": true, "scale": 1.6},
	"loungeChairRelax": {"label": "Reclining chair", "role": "armchair", "actions": ["rest"], "price": 48, "comfort": 4, "personal": true, "scale": 1.6},
	"loungeDesignChair": {"label": "Design chair", "role": "armchair", "actions": ["rest"], "price": 55, "comfort": 4, "personal": true, "scale": 1.6},
	"loungeSofa": {"label": "Sofa", "role": "sofa", "actions": ["rest", "socialize"], "price": 50, "comfort": 3, "personal": false, "scale": 1.6, "slots": 2},
	"loungeSofaLong": {"label": "Long sofa", "role": "sofa", "actions": ["rest", "socialize"], "price": 75, "comfort": 4, "personal": false, "scale": 1.5, "slots": 3},
	"loungeDesignSofa": {"label": "Design sofa", "role": "sofa", "actions": ["rest", "socialize"], "price": 90, "comfort": 5, "personal": false, "scale": 1.5, "slots": 2},
	"bench": {"label": "Bench", "role": "bench", "actions": ["rest", "socialize"], "price": 14, "comfort": 1, "personal": false, "scale": 2.0, "slots": 2},
	"benchCushion": {"label": "Cushioned bench", "role": "bench", "actions": ["rest", "socialize"], "price": 22, "comfort": 2, "personal": false, "scale": 2.0, "slots": 2},
	"stoolBar": {"label": "Bar stool", "role": "seat", "actions": ["eat"], "price": 8, "comfort": 0, "personal": false, "scale": 1.7},
	# tables and desks
	"table": {"label": "Table", "role": "table", "actions": ["eat"], "price": 30, "comfort": 2, "personal": false, "scale": 1.7},
	"tableCloth": {"label": "Table with cloth", "role": "table", "actions": ["eat"], "price": 38, "comfort": 2, "personal": false, "scale": 1.7},
	"tableRound": {"label": "Round table", "role": "table", "actions": ["eat"], "price": 34, "comfort": 2, "personal": false, "scale": 1.7},
	"tableCoffee": {"label": "Coffee table", "role": "decor", "actions": [], "price": 20, "comfort": 1, "personal": false, "scale": 1.6},
	"sideTable": {"label": "Side table", "role": "decor", "actions": [], "price": 12, "comfort": 1, "personal": false, "scale": 1.5},
	"desk": {"label": "Desk", "role": "desk", "actions": ["work", "study"], "price": 36, "comfort": 1, "personal": true, "scale": 1.7},
	"deskCorner": {"label": "Corner desk", "role": "desk", "actions": ["work", "study"], "price": 48, "comfort": 1, "personal": true, "scale": 1.7},
	"tableCross": {"label": "Workbench", "role": "bench_work", "actions": ["work"], "price": 55, "comfort": 1, "personal": true, "scale": 1.15},
	# kitchen
	"kitchenCabinet": {"label": "Kitchen cabinet", "role": "kitchen", "actions": [], "price": 24, "comfort": 1, "personal": false, "scale": 1.6},
	"kitchenCabinetDrawer": {"label": "Kitchen drawers", "role": "kitchen", "actions": [], "price": 26, "comfort": 1, "personal": false, "scale": 1.6},
	"kitchenSink": {"label": "Kitchen sink", "role": "kitchen", "actions": ["cook"], "price": 40, "comfort": 2, "personal": false, "scale": 1.6},
	"kitchenStove": {"label": "Stove", "role": "stove", "actions": ["cook"], "price": 60, "comfort": 3, "personal": false, "scale": 1.6},
	"kitchenStoveElectric": {"label": "Electric stove", "role": "stove", "actions": ["cook"], "price": 85, "comfort": 4, "personal": false, "scale": 1.6},
	"kitchenFridge": {"label": "Fridge", "role": "fridge", "actions": [], "price": 70, "comfort": 3, "personal": false, "scale": 1.6},
	"kitchenFridgeSmall": {"label": "Small fridge", "role": "fridge", "actions": [], "price": 45, "comfort": 2, "personal": false, "scale": 1.6},
	"kitchenBar": {"label": "Counter", "role": "counter", "actions": ["work", "eat"], "price": 35, "comfort": 1, "personal": true, "scale": 1.7},
	# bathroom
	"bathtub": {"label": "Bathtub", "role": "bath", "actions": ["wash"], "price": 70, "comfort": 3, "personal": false, "scale": 1.3},
	"shower": {"label": "Shower", "role": "bath", "actions": ["wash"], "price": 60, "comfort": 3, "personal": false, "scale": 1.3},
	"showerRound": {"label": "Round shower", "role": "bath", "actions": ["wash"], "price": 70, "comfort": 3, "personal": false, "scale": 1.3},
	"bathroomSink": {"label": "Washbasin", "role": "bath", "actions": ["wash"], "price": 30, "comfort": 1, "personal": false, "scale": 1.5},
	"toilet": {"label": "Toilet", "role": "toilet", "actions": [], "price": 35, "comfort": 1, "personal": false, "scale": 0.8},
	"bathroomCabinet": {"label": "Medicine cabinet", "role": "medical", "actions": ["treat"], "price": 30, "comfort": 1, "personal": false, "scale": 1.5},
	# storage and books
	"bookcaseClosed": {"label": "Bookcase", "role": "bookcase", "actions": ["study"], "price": 40, "comfort": 2, "personal": false, "scale": 1.6},
	"bookcaseClosedWide": {"label": "Wide bookcase", "role": "bookcase", "actions": ["study"], "price": 55, "comfort": 2, "personal": false, "scale": 1.6},
	"bookcaseOpen": {"label": "Open shelves", "role": "bookcase", "actions": ["study"], "price": 30, "comfort": 2, "personal": false, "scale": 1.6},
	"bookcaseOpenLow": {"label": "Low shelves", "role": "bookcase", "actions": ["study"], "price": 22, "comfort": 1, "personal": false, "scale": 1.6},
	"cabinetTelevision": {"label": "TV cabinet", "role": "tvstand", "actions": [], "price": 40, "comfort": 1, "personal": false, "scale": 1.6},
	"cardboardBoxClosed": {"label": "Crate", "role": "crate", "actions": [], "price": 6, "comfort": 0, "personal": false, "scale": 2.2},
	"cardboardBoxOpen": {"label": "Open crate", "role": "crate", "actions": [], "price": 6, "comfort": 0, "personal": false, "scale": 2.2},
	# tech
	"televisionModern": {"label": "Television", "role": "tv", "actions": ["rest"], "price": 90, "comfort": 3, "personal": false, "scale": 1.5},
	"televisionVintage": {"label": "Old television", "role": "tv", "actions": ["rest"], "price": 45, "comfort": 2, "personal": false, "scale": 1.5},
	"computerScreen": {"label": "Computer", "role": "computer", "actions": ["work"], "price": 120, "comfort": 1, "personal": true, "scale": 1.6},
	"laptop": {"label": "Laptop", "role": "computer", "actions": ["work"], "price": 100, "comfort": 1, "personal": true, "scale": 1.6},
	"radio": {"label": "Radio", "role": "decor", "actions": [], "price": 25, "comfort": 1, "personal": true, "scale": 1.6},
	# light and decoration
	"lampRoundFloor": {"label": "Floor lamp", "role": "lamp", "actions": [], "price": 18, "comfort": 1, "personal": false, "scale": 1.7},
	"lampSquareFloor": {"label": "Standing lamp", "role": "lamp", "actions": [], "price": 18, "comfort": 1, "personal": false, "scale": 1.7},
	"lampRoundTable": {"label": "Table lamp", "role": "lamp", "actions": [], "price": 10, "comfort": 1, "personal": true, "scale": 1.7},
	"lampWall": {"label": "Wall lamp", "role": "lamp", "actions": [], "price": 12, "comfort": 1, "personal": false, "scale": 1.5},
	"rugRectangle": {"label": "Rug", "role": "rug", "actions": [], "price": 24, "comfort": 1, "personal": false, "scale": 1.4},
	"rugRound": {"label": "Round rug", "role": "rug", "actions": [], "price": 24, "comfort": 1, "personal": false, "scale": 1.4},
	"rugDoormat": {"label": "Doormat", "role": "rug", "actions": [], "price": 6, "comfort": 0, "personal": false, "scale": 1.4},
	"pottedPlant": {"label": "Potted plant", "role": "plant", "actions": [], "price": 15, "comfort": 1, "personal": true, "scale": 1.6},
	"plantSmall1": {"label": "Small plant", "role": "plant", "actions": [], "price": 8, "comfort": 1, "personal": true, "scale": 1.8},
	"books": {"label": "Books", "role": "decor", "actions": [], "price": 8, "comfort": 1, "personal": true, "scale": 1.8},
	"trashcan": {"label": "Bin", "role": "decor", "actions": [], "price": 4, "comfort": 0, "personal": false, "scale": 1.6},
	"washer": {"label": "Washing machine", "role": "decor", "actions": [], "price": 55, "comfort": 2, "personal": false, "scale": 1.5},
}
## What the player can buy and place. Roles grouped for the furnish panel.
const SHOP := {
	"Beds": ["bedSingle", "bedDouble", "bedBunk", "cabinetBedDrawer"],
	"Seating": ["chair", "loungeChair", "loungeChairRelax", "loungeSofa", "loungeSofaLong", "loungeDesignSofa", "bench"],
	"Tables": ["table", "tableRound", "tableCoffee", "sideTable", "desk"],
	"Kitchen and bath": ["kitchenStove", "kitchenSink", "kitchenFridge", "kitchenCabinet", "bathtub", "shower", "bathroomSink", "toilet"],
	"Books and tech": ["bookcaseClosed", "bookcaseOpen", "cabinetTelevision", "televisionModern", "computerScreen", "radio"],
	"Decor": ["lampRoundFloor", "lampRoundTable", "rugRectangle", "rugRound", "pottedPlant", "plantSmall1", "books", "coatRack"],
}
## Items a new building starts with in the second lane (crates, plants...) are placed by the layouts.

static var _sizes: Dictionary = {}


static func sizes() -> Dictionary:
	if _sizes.is_empty():
		var file := FileAccess.open("res://data/furniture_sizes.json", FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_sizes = parsed
	return _sizes


static func spec(model: String) -> Dictionary:
	return ITEMS.get(model, {"label": model, "role": "decor", "actions": [], "price": 10, "comfort": 0, "personal": false, "scale": 1.5})


static func scale_of(model: String) -> float:
	return float(spec(model).get("scale", 1.5)) * FURNITURE_FACTOR


## Floor footprint (width along x, depth along z), already scaled.
static func footprint(model: String) -> Vector2:
	var s: Dictionary = sizes().get(model, {})
	var size: Array = s.get("size", [0.5, 0.5, 0.5])
	return Vector2(float(size[0]), float(size[2])) * scale_of(model)


static func height(model: String) -> float:
	var s: Dictionary = sizes().get(model, {})
	var size: Array = s.get("size", [0.5, 0.5, 0.5])
	return float(size[1]) * scale_of(model)


## Offset from the model origin to the middle of its footprint (unscaled model units).
static func center_offset(model: String) -> Vector2:
	var s: Dictionary = sizes().get(model, {})
	var c: Array = s.get("center", [0.25, -0.25])
	return Vector2(float(c[0]), float(c[1]))


static func role_of(model: String) -> String:
	return str(spec(model).role)


static func price_of(model: String) -> int:
	return int(spec(model).price)


static func is_personal(model: String) -> bool:
	return bool(spec(model).personal)


static func comfort_of(model: String) -> int:
	return int(spec(model).comfort)


static func label_of(model: String) -> String:
	return str(spec(model).label)


static func actions_of(model: String) -> Array:
	return spec(model).get("actions", [])
