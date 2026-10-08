class_name Orders
extends RefCounted
## Everything the chief can ask for, by voice, by typing, or from the Orders panel.
##
## parse(text) turns words into an order {intent, scope, names, ...}; execute() carries it out against the sim and
## returns {ok, message, ui, ack}. `ui` names a presentation-side effect the caller handles (hush, pause, ...).
## Anything that is not an order has intent "chat" and goes to the normal conversation.
##
## Intents: action (eat sleep wash socialize play work study farm gather cook exercise rest), build, upgrade, expand,
##   follow, unfollow, come, stay, free, home, stop (cancel everything), hush (stop talking), chatter (talk freely),
##   festival, report, suggest, approve, council_auto, council_ask, pause, resume, faster, slower.

const COUNT_WORDS := {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "1": 1, "2": 2, "3": 3, "4": 4}
const BUILD_WORDS := ["build", "construct", "make", "put up", "erect", "set up", "add", "raise", "start building", "we need", "we should have"]
const UPGRADE_WORDS := ["upgrade", "improve", "renovate", "level up", "expand the", "enlarge", "make the", "make it bigger"]
const KIND_WORDS := {
	"home": ["house", "houses", "home", "homes", "cottage", "cottages", "housing"],
	"market": ["market", "markets", "shop", "shops", "store", "stall"],
	"workshop": ["workshop", "workshops", "forge", "factory", "mill"],
	"library": ["library", "libraries", "school"],
	"bathhouse": ["bathhouse", "bathhouses", "bath house", "spa"],
	"farm": ["farm", "farms", "field", "fields"],
	"park": ["park", "parks", "garden", "gardens", "playground"],
	"office": ["office", "offices", "town hall"],
	"clinic": ["clinic", "hospital", "infirmary"],
	"watchtower": ["watchtower", "watchtowers", "lookout", "guard tower"],
	"wall": ["wall", "walls", "palisade", "rampart", "ramparts", "fortification"],
	"gate": ["gate", "gates"],
}
const ACTION_WORDS := {
	"sleep": ["sleep", "nap", "go to bed", "bedtime", "get some sleep", "turn in"],
	"eat": ["eat", "have a meal", "lunch", "dinner", "breakfast", "get something to eat", "grab some food", "have some food"],
	"wash": ["wash", "bathe", "shower", "clean up", "freshen up", "take a bath", "bathhouse"],
	"cook": ["cook", "bake", "prepare food", "make dinner", "make meals", "prepare meals"],
	"farm": ["farm", "harvest", "plant", "crops", "tend the", "water the"],
	"gather": ["gather", "forage", "collect", "supplies", "materials", "bring food", "pick fruit", "pick berries"],
	"study": ["study", "read", "learn", "library", "books"],
	"exercise": ["exercise", "workout", "work out", "jog", "run laps", "train", "stretch", "fitness"],
	"play": ["play", "have fun", "enjoy yourself", "enjoy yourselves", "relax at the park", "go to the park"],
	"socialize": ["socialize", "socialise", "chat", "mingle", "hang out", "make friends", "talk to each other", "talk with each other", "mix"],
	"work": ["work", "help build", "help out", "help with", "construction", "lend a hand", "get to work", "back to work", "workshop shift"],
	"rest": ["rest", "relax", "take a break", "take it easy", "sit down", "put your feet up", "recover"],
}
## Outdoor jobs are matched first: "gather wood" must mean chopping, not foraging.
const JOB_WORDS := {
	"farm": ["feed the animals", "feed the chickens", "feed the cows", "feed the livestock", "milk the cows", "milk the cow", "milk", "collect eggs", "collect the eggs", "gather eggs", "gather the eggs", "get the eggs", "get eggs", "shear", "tend the animals", "tend the farm", "tend the livestock", "look after the animals", "herd"],
	"treat": ["treat", "heal", "cure", "doctor", "see a doctor", "clinic", "medicine", "get better", "get treated", "get checked"],
	"repair": ["repair", "fix", "mend", "maintain", "maintenance", "patch up", "restore the", "fix up"],
	"guard": ["guard", "defend", "protect", "fight", "attack", "patrol", "stand watch", "keep watch", "hunt monsters", "kill monsters", "fight monsters", "kill the zombies", "monsters", "zombies", "slimes", "wolves", "wolf", "hunt"],
	"chop": ["chop", "cut wood", "cut down", "cut the trees", "cut trees", "cut some trees", "fell a tree", "fell trees", "lumber", "timber", "gather wood", "collect wood", "get wood", "bring wood", "fetch wood", "wood", "logs", "firewood", "woodcutting", "lumberjack", "axe"],
	"mine": ["mine", "quarry", "gather stone", "gather stones", "collect stone", "collect stones", "get stone", "get stones", "bring stone", "bring stones", "fetch stone", "stones", "stone", "rocks", "break rocks", "smash rocks", "pickaxe", "ore"],
	"water": ["fetch water", "carry water", "get water", "bring water", "draw water", "collect water", "water the crops", "water the farm", "water the fields", "water the plants", "water the garden", "water", "bucket", "buckets"],
}
const ACTION_ORDER := ["sleep", "eat", "wash", "cook", "farm", "study", "exercise", "play", "socialize", "gather", "work", "rest"]
const COMMAND_CUES := ["go ", "please", "let's", "lets ", "time to", "start", "begin", "head ", "can you", "could you", "will you", "would you", "get ", "do some", "you should", "you need", "you must", "i want you", "i need you", "back to", "now", "everyone", "everybody", "all of you", "you all", "off you go", "go and", "go on", "take ", "have a", "get on"]
const ALL_WORDS := ["everyone", "everybody", "all of you", "you all", "all villagers", "the villagers", "villagers", "all of them", "the whole village", "everyone here", "guys", "folks", "team", "all hands", "residents", "citizens", "people"]
const NEAR_WORDS := ["nearby", "around me", "near me", "everyone here", "those here", "people here", "people around"]
const QUESTION_STARTS := ["how", "what", "why", "did", "have", "are", "is", "who", "when", "where", "does", "do you", "tell me", "was", "were", "which"]
const ACTION_ICON := {"eat": "eat", "sleep": "sleep", "wash": "wash", "socialize": "socialize", "play": "play", "work": "work", "study": "study", "farm": "farm", "gather": "gather", "cook": "cook", "exercise": "exercise", "rest": "rest"}
const NEAR_TILES := 6.0


static func _clean(text: String) -> String:
	var t := text.to_lower()
	for ch in [",", ".", "!", "?", ";", ":", "\"", "(", ")"]:
		t = t.replace(ch, " ")
	t = t.replace("’", "'")
	return " " + " ".join(t.split(" ", false)) + " "


static func _has(t: String, phrase: String) -> bool:
	var p := phrase.strip_edges()
	if phrase.ends_with(" ") and not phrase.begins_with(" "):
		return t.contains(" " + p + " ") or t.contains(" " + p)
	return t.contains(" " + p + " ") or t.contains(" " + p + "s ") or t.contains(" " + p + "ing ")


static func _any(t: String, phrases: Array) -> bool:
	for p in phrases:
		if _has(t, str(p)):
			return true
	return false


static func _mentions_building(t: String) -> bool:
	for k in KIND_WORDS:
		if _any(t, KIND_WORDS[k]):
			return true
	return false


static func names_in(text: String, sim: LifeSim) -> Array:
	var t := _clean(text)
	var out: Array = []
	for i in range(sim.residents.size()):
		if t.contains(" " + str(sim.residents[i].name).to_lower() + " ") or t.contains(" " + str(sim.residents[i].name).to_lower() + "'s "):
			out.append(i)
	return out


## Words into an order. `sim` is only used to recognise residents' names.
static func parse(text: String, sim: LifeSim) -> Dictionary:
	var t := _clean(text)
	var order := {"intent": "chat", "scope": "default", "names": names_in(text, sim), "text": text}
	var words := t.strip_edges().split(" ", false)
	if not (order.names as Array).is_empty():
		order.scope = "names"
	elif _any(t, NEAR_WORDS):
		order.scope = "near"
	elif _any(t, ALL_WORDS) or _has(t, "all"):
		order.scope = "all"
	var is_question := text.strip_edges().ends_with("?")
	var first := words[0] if not words.is_empty() else ""
	var polite := t.contains(" can you ") or t.contains(" could you ") or t.contains(" will you ") or t.contains(" would you ") or t.contains(" please ")
	if is_question and not polite and (first in QUESTION_STARTS or t.contains(" do you ")):
		if _any(t, ["how are the animals", "how is the farm", "how are the crops", "how many animals", "the herd", "the livestock"]):
			order.intent = "farm_report"
		elif _any(t, ["status", "report", "how is everyone", "how are everyone", "how are they", "how is the village", "how are things", "how's the village", "how is everything", "what's going on", "whats going on", "what is going on"]):
			order.intent = "report"
		elif _any(t, ["what should we do", "what should we build", "what should we","what do we need", "what does the village need", "what's next", "what is next", "any suggestions", "what do you suggest", "what plans"]):
			order.intent = "suggest"
		return order
	# --- weapons and the rival town ---------------------------------------------------------------------------------------
	var weapon_words := {"sword": "sword", "swords": "sword", "spear": "spear", "spears": "spear", "club": "club", "clubs": "club", "bow": "bow", "bows": "bow", "shield": "shield", "shields": "shield", "arrow": "arrow", "arrows": "arrow"}
	var weapon := ""
	for w in words:
		if weapon_words.has(w):
			weapon = str(weapon_words[w])
			break
	if _any(t, ["armory", "armoury", "what weapons", "weapon report", "how many weapons", "weapons report", "our weapons"]):
		order.intent = "weapons_report"
		return order
	if weapon != "" and _any(t, ["forge", "craft", "make", "smith", "build me", "produce", "get me"]):
		var wqty := 1
		for ww in words:
			if ww.is_valid_int():
				wqty = int(ww)
				break
			if COUNT_WORDS.has(ww) and ww not in ["a", "an"]:
				wqty = int(COUNT_WORDS[ww])
		order.intent = "craft"
		order.kind = weapon
		order.amount = clampi(wqty, 1, 20)
		return order
	if weapon != "" and _any(t, ["equip", "wield", "take up", "pick up", "hold the", "use the", "draw the", "carry the"]):
		order.intent = "chief_equip"
		order.kind = weapon
		return order
	if _any(t, ["put away your weapon", "unequip", "sheathe", "bare hands", "put your weapon away", "lower your weapon"]):
		order.intent = "chief_equip"
		order.kind = ""
		return order
	if _any(t, ["arm the guards", "arm everyone", "arm all", "arm the village", "arm the villagers", "arm up", "hand out weapons", "give out weapons", "hand out arms", "give weapons", "equip the guards", "equip everyone"]):
		order.intent = "arm"
		order.everyone = _any(t, ["everyone", "all", "village", "villagers"])
		return order
	if _any(t, ["redmarch", "the rival", "rival town", "the enemy", "enemy town", "our neighbour", "our neighbor"]):
		if _any(t, ["attack", "march on", "invade", "raid ", "go to war", "wage war", "send the army", "strike"]):
			order.intent = "attack_rival"
			return order
		if _any(t, ["envoy", "ambassador", "emissary", "diplomat", "send a gift", "send gifts"]):
			order.intent = "envoy"
			return order
		if _any(t, ["tribute", "pay off", "bribe"]):
			order.intent = "tribute"
			return order
		if _any(t, ["peace", "truce", "ceasefire", "make terms", "treaty"]):
			order.intent = "peace"
			return order
		order.intent = "rival_report"
		return order
	if _any(t, ["send an envoy", "send envoy", "send an ambassador", "send an emissary"]):
		order.intent = "envoy"
		return order
	if _any(t, ["pay tribute", "pay the tribute"]):
		order.intent = "tribute"
		return order
	if _any(t, ["ask for peace", "propose peace", "make peace", "offer peace", "sue for peace", "call a truce", "ask for a truce"]):
		order.intent = "peace"
		return order
	if _any(t, ["attack the rival", "attack the enemy", "send the army", "march on redmarch", "go to war", "declare war", "attack redmarch"]):
		order.intent = "attack_rival"
		return order
	# --- being quiet -------------------------------------------------------------------------------------
	if _any(t, ["stop talking", "stop chatting", "stop speaking", "be quiet", "quiet", "silence", "shut up", "hush", "enough talking", "enough chatter", "no more talking", "stop the conversation", "stop conversations", "stop the chatter", "stop gossiping", "stop chat", "stop yapping", "pipe down", "keep it down", "not talking"]):
		order.intent = "hush"
		return order
	if _any(t, ["keep talking", "talk freely", "chat freely", "carry on talking", "feel free to talk", "you can talk", "talk to each other again", "chat away", "gossip", "start talking", "resume talking", "talk again"]):
		order.intent = "chatter"
		return order
	# --- game flow ------------------------------------------------------------------------------------------
	if _any(t, ["pause", "freeze time", "stop time"]) and not _has(t, "resume"):
		order.intent = "pause"
		return order
	if _any(t, ["resume", "unpause", "continue the game", "play on", "start time", "normal speed"]):
		order.intent = "resume"
		return order
	if _any(t, ["speed up", "faster", "fast forward", "hurry up time"]):
		order.intent = "faster"
		return order
	if _any(t, ["slow down", "slower", "slow time"]):
		order.intent = "slower"
		return order
	# --- council ------------------------------------------------------------------------------------------------
	if _any(t, ["let the council", "council decide", "council handle", "council can decide", "you decide", "decide for yourselves", "turn on auto", "autopilot", "plan on your own", "handle it yourselves", "run the village", "run things"]):
		order.intent = "council_auto"
		return order
	if _any(t, ["ask me first", "i decide", "i will decide", "i'll decide", "stop the council", "manual", "wait for my approval", "ask me before", "let me decide", "let me choose"]):
		order.intent = "council_ask"
		return order
	if _any(t, ["approve", "go ahead with the plan", "approve the plan", "do the plan", "follow the plan", "do the council", "do what the council", "yes to the plan"]):
		order.intent = "approve"
		return order
	if _any(t, ["suggestions", "any ideas for the village", "what should we build", "what do we need", "what does the village need", "make a plan", "what is the plan", "what's the plan", "show the plan", "propose"]):
		order.intent = "suggest"
		return order
	if _any(t, ["farm report", "livestock report", "how are the animals", "how is the farm", "how many animals", "the herd"]):
		order.intent = "farm_report"
		return order
	if _any(t, ["report", "status", "how is everyone", "how are everyone", "how are they all", "how are things", "how is the village", "how's the village", "sitrep", "update me", "give me an update", "roll call", "state of the village"]):
		order.intent = "report"
		return order
	# --- festival ------------------------------------------------------------------------------------------------
	if _any(t, ["festival", "party", "celebrate", "celebration", "feast", "throw a", "have a party"]):
		order.intent = "festival"
		return order
	# --- following, staying, regrouping -----------------------------------------------------------------------------
	if _any(t, ["stop following", "don't follow", "do not follow", "no need to follow", "quit following", "stop trailing", "unfollow", "you can go", "you may go", "dismissed", "you're free", "you are free", "go about your", "go on your way"]):
		order.intent = "unfollow"
		return order
	if _any(t, ["follow me", "follow", "come with me", "come along", "walk with me", "stick with me", "stay with me", "stay close", "tag along", "accompany me", "with me"]) and not _any(t, ["stay here", "stay put"]):
		order.intent = "follow"
		return order
	if _any(t, ["stay here", "stay put", "stay there", "wait here", "wait there", "hold position", "hold still", "stand still", "don't move", "do not move", "freeze", "stay where you are", "stay", "wait"]):
		order.intent = "stay"
		return order
	if _any(t, ["come here", "come to me", "come over", "over here", "gather round", "gather around", "gather here", "gather together", "gather up", "gather everyone", "gather everybody", "gather the villagers", "assemble", "meet me", "meet here", "come together", "form up", "line up", "huddle", "come back", "to me", "get over here", "everyone here", "regroup", "muster"]):
		order.intent = "come"
		order.spot = "chief"
		return order
	if _any(t, ["meet at the plaza", "meet in the plaza", "go to the plaza", "gather at the plaza", "gather in the plaza", "to the plaza", "at the plaza", "the town square", "to the square", "village square", "to the center", "to the centre", "to the town centre", "to the town center"]):
		order.intent = "come"
		order.spot = "plaza"
		return order
	if _any(t, ["hide", "take cover", "shelter", "get inside", "go inside", "run for cover", "get to safety", "lock the doors", "barricade", "stay inside", "everyone inside"]):
		order.intent = "shelter"
		return order
	if _any(t, ["go home", "head home", "go to your house", "go back home", "return home", "back home", "go to your homes", "get home", "to your homes", "to your house"]):
		order.intent = "home"
		return order
	if _any(t, ["stop", "cancel", "never mind", "nevermind", "carry on", "as you were", "free time", "do what you want", "do what you like", "do as you please", "go about", "resume your", "forget it", "abort", "at ease", "stand down", "relax everyone", "normal life", "business as usual"]) and not _mentions_building(t):
		order.intent = "stop"
		return order
	if _any(t, ["dreams", "aspirations", "ambitions", "what does everyone want", "what do they want", "their hopes", "what are their goals"]):
		order.intent = "dreams"
		return order
	# --- jobs ------------------------------------------------------------------------------------------------------------------------
	var job_titles := {"doctor": "doctor", "physician": "doctor", "healer": "doctor", "shopkeeper": "shopkeeper", "storekeeper": "shopkeeper", "merchant": "shopkeeper", "farmer": "farmer", "gardener": "farmer", "guard": "guard", "soldier": "guard", "watchman": "guard", "gatekeeper": "gatekeeper", "lumberjack": "lumberjack", "woodcutter": "lumberjack", "miner": "miner", "builder": "builder", "librarian": "librarian"}
	var asked_title := ""
	for w in words:
		if job_titles.has(w):
			asked_title = str(job_titles[w])
			break
	if asked_title != "" and _any(t, ["make", "hire", "appoint", "assign", "employ", "name", "promote", "put"]) and (not (order.names as Array).is_empty() or order.scope in ["default", "all"]):
		order.intent = "assign_job"
		order.title = asked_title
		return order
	if _any(t, ["find everyone a job", "give everyone a job", "give everyone jobs", "find jobs", "fill the jobs", "fill all the jobs", "put everyone to work", "assign jobs", "hire people"]):
		order.intent = "fill_jobs"
		return order
	if (_any(t, ["fire", "sack", "lay off"]) or _any(t, ["dismiss from"])) and not (order.names as Array).is_empty():
		order.intent = "dismiss_job"
		return order
	# --- gates and fortifications ---------------------------------------------------------------------------------------
	if _has(t, "gate") or _has(t, "gates"):
		if _any(t, ["open", "unlock", "unbar", "let people in"]):
			order.intent = "gates_open"
			return order
		if _any(t, ["close", "shut", "lock", "bar", "seal"]):
			order.intent = "gates_close"
			return order
		if _any(t, ["auto", "automatic", "normal", "as usual", "routine", "default"]):
			order.intent = "gates_auto"
			return order
	if _any(t, ["fortify", "fortifications", "defences", "defenses", "wall off", "wall in", "wall around", "walls around", "surround the village", "palisade"]):
		order.intent = "build"
		order.kind = "wall"
		order.count = 99
		return order
	# --- farm: crops and livestock ---------------------------------------------------------------------------------------
	var caravan_words := {"spice": "c_spice", "spices": "c_spice", "seeds": "c_seeds", "melon seeds": "c_seeds", "prize cow": "c_cow", "steel tools": "c_tools", "tools": "c_tools", "rare books": "c_books", "books": "c_books", "medicine": "c_medicine"}
	if _any(t, ["trade route", "trade routes", "open a route", "new route"]) and _any(t, ["open", "build", "pay", "start", "buy", "new"]):
		order.intent = "route"
		return order
	if _any(t, ["merchant", "caravan", "trader", "peddler"]) and _any(t, ["selling", "sells", "wares", "what", "stock", "offer", "report", "here", "in town"]):
		order.intent = "caravan_report"
		return order
	if Caravans.present(sim) and _any(t, ["buy", "get", "purchase", "take"]):
		for phrase in caravan_words:
			if _has(t, str(phrase)):
				var cqty := 1
				for cw in words:
					if cw.is_valid_int():
						cqty = int(cw)
						break
				order.intent = "caravan_buy"
				order.ware = str(caravan_words[phrase])
				order.amount = clampi(cqty, 1, 9)
				return order
	var animal_kinds := {"chicken": "chicken", "chickens": "chicken", "hen": "chicken", "hens": "chicken", "sheep": "sheep", "lamb": "sheep", "lambs": "sheep", "cow": "cow", "cows": "cow", "cattle": "cow", "pig": "pig", "pigs": "pig", "hog": "pig", "hogs": "pig"}
	var animal := ""
	for w in words:
		if animal_kinds.has(w):
			animal = str(animal_kinds[w])
			break
	if animal != "":
		var herd_qty := 1
		for w2 in words:
			if w2.is_valid_int():
				herd_qty = int(w2)
				break
			if COUNT_WORDS.has(w2) and w2 not in ["a", "an"]:
				herd_qty = int(COUNT_WORDS[w2])
				break
		if _any(t, ["slaughter", "butcher", "cull", "eat the", "kill the", "for meat"]):
			order.intent = "slaughter"
			order.animal = animal
			order.amount = clampi(herd_qty, 1, 50)
			return order
		if _any(t, ["sell"]):
			order.intent = "sell_animal"
			order.animal = animal
			order.amount = clampi(herd_qty, 1, 50)
			return order
		if _any(t, ["buy", "get", "raise", "breed", "add", "purchase", "stock", "more", "some", "need"]) and not _any(t, ["feed", "milk", "shear", "eggs", "tend"]):
			order.intent = "buy_animal"
			order.animal = animal
			order.amount = clampi(herd_qty, 1, 20)
			return order
	var crop_words := {"wheat": "wheat", "carrot": "carrot", "carrots": "carrot", "corn": "corn", "maize": "corn", "pumpkin": "pumpkin", "pumpkins": "pumpkin", "melon": "melon", "melons": "melon"}
	if (_any(t, ["plant", "sow", "switch to", "grow", "replant", "farm only", "raise crops of"]) or _any(t, ["crop"])) and first not in ["i", "we", "my", "it", "they", "you"]:
		for w3 in words:
			if crop_words.has(w3):
				order.intent = "crop"
				order.crop = str(crop_words[w3])
				return order
	if _any(t, ["livestock report", "how are the animals", "how is the farm", "farm report", "how many animals", "the herd"]):
		order.intent = "farm_report"
		return order
	# --- furniture as gifts -------------------------------------------------------------------------------------------------------
	var gifts := [["double bed", "bedDouble"], ["bunk bed", "bedBunk"], ["bed", "bedSingle"], ["armchair", "loungeChair"], ["recliner", "loungeChairRelax"], ["sofa", "loungeSofa"], ["couch", "loungeSofa"], ["chair", "loungeChair"], ["dining table", "table"], ["desk", "desk"], ["table", "table"], ["lamp", "lampRoundFloor"], ["rug", "rugRectangle"], ["carpet", "rugRectangle"], ["plant", "pottedPlant"], ["bookcase", "bookcaseClosed"], ["bookshelf", "bookcaseClosed"], ["shelf", "bookcaseOpen"], ["television", "televisionModern"], ["tv", "televisionModern"], ["radio", "radio"], ["stove", "kitchenStove"], ["fridge", "kitchenFridge"], ["bathtub", "bathtub"]]
	if _any(t, ["give", "gift", "buy", "get", "furnish", "bring"]) and not _any(t, ["wall", "gate"]):
		for g in gifts:
			if _has(t, str(g[0])):
				order.intent = "gift"
				order.furniture = str(g[1])
				return order
	# --- the market --------------------------------------------------------------------------------------------------
	if _any(t, ["market prices", "what are prices", "how much is", "the prices", "price of", "prices"]):
		order.intent = "market"
		return order
	if _any(t, ["sell", "buy", "trade"]) and not _mentions_building(t):
		var item := ""
		for pair in [["food", "food"], ["produce", "food"], ["wood", "wood"], ["timber", "wood"], ["stone", "stone"], ["stones", "stone"], ["wheat", "wheat"], ["carrots", "carrot"], ["carrot", "carrot"], ["corn", "corn"], ["pumpkins", "pumpkin"], ["pumpkin", "pumpkin"], ["melons", "melon"], ["melon", "melon"], ["surplus", "surplus"], ["extra", "surplus"]]:
			if _has(t, str(pair[0])):
				item = str(pair[1])
				break
		var qty := 10
		for w in words:
			if w.is_valid_int():
				qty = int(w)
				break
		order.intent = "trade"
		order.trade_action = "buy" if _has(t, "buy") else "sell"
		order.item = item
		order.amount = clampi(qty, 1, 500)
		return order
	# --- the village itself: expand, upgrade, build ------------------------------------------------------------------------
	if _any(t, ["claim land", "claim more land", "claim the land", "claim a district", "more land", "new district", "new land", "grow the village", "extend the village", "expand the village", "expand the town", "expand the city", "expand our", "expansion", "annex", "expand", "claim", "widen the village", "enlarge the village"]):
		order.intent = "expand"
		return order
	var kind := ""
	var at := 1 << 30
	for k in KIND_WORDS:
		for w in KIND_WORDS[k]:
			var pos := t.find(" " + str(w) + " ")
			if pos < 0:
				pos = t.find(" " + str(w) + "s ")
			if pos >= 0 and pos < at:
				at = pos
				kind = str(k)
	var count := 1
	for w in words:
		if COUNT_WORDS.has(w) and w not in ["a", "an"]:
			count = int(COUNT_WORDS[w])
			break
	if kind in Catalog.WALL_KINDS and _any(t, BUILD_WORDS) and not (_any(t, UPGRADE_WORDS) or _has(t, "upgrade")):
		order.intent = "build"
		order.kind = kind
		order.count = 99 if (_any(t, ["walls", "all", "around", "whole", "entire", "every"]) or kind == "wall" and _has(t, "walls")) else 1
		return order
	if _any(t, UPGRADE_WORDS) or (_has(t, "upgrade")):
		order.intent = "upgrade"
		order.kind = kind
		return order
	if _any(t, BUILD_WORDS) and not _any(t, ["help build", "help with building", "keep building", "building work"]):
		order.intent = "build"
		order.kind = kind
		order.count = clampi(count, 1, 4)
		return order
	# --- plain activities --------------------------------------------------------------------------------------------------
	var action := ""
	var best := 1 << 30
	for job in JOB_WORDS:
		for w in JOB_WORDS[job]:
			var jp := t.find(" " + str(w) + " ")
			if jp < 0:
				jp = t.find(" " + str(w) + "s ")
			if jp < 0:
				jp = t.find(" " + str(w) + "ing ")
			if jp >= 0 and jp < best:
				best = jp
				action = job
	for a in ACTION_ORDER:
		if action != "":
			break
		for w in ACTION_WORDS[a]:
			var pos2 := t.find(" " + str(w) + " ")
			if pos2 < 0:
				pos2 = t.find(" " + str(w) + "s ")
			if pos2 < 0:
				pos2 = t.find(" " + str(w) + "ing ")
			if pos2 >= 0 and pos2 < best:
				best = pos2
				action = a
	if action == "" and kind != "":
		action = {"home": "rest", "market": "socialize", "workshop": "work", "library": "study", "bathhouse": "wash", "farm": "farm", "park": "play", "office": "work", "clinic": "treat", "watchtower": "guard", "wall": "repair", "gate": "repair"}.get(kind, "")
	if action != "":
		var imperative := false
		for cue in COMMAND_CUES:
			if t.contains(" " + str(cue).strip_edges()):
				imperative = true
				break
		var stripped := t
		for i in order.names:
			stripped = stripped.replace(" " + str(sim.residents[i].name).to_lower() + " ", " ")
		var bare := stripped.strip_edges().split(" ", false)
		if bare.size() <= 4 and not bare.is_empty() and bare[0] not in ["i", "we", "my", "it", "its", "you", "he", "she", "they", "that", "this", "the", "so", "and", "but"] and not _any(t, ["love", "like", "hate", "enjoy", "miss", "wish"]):
			imperative = true
		if imperative:
			order.intent = "action"
			order.action = action
	return order


# --- executing ----------------------------------------------------------------------------------------------------------

## Which residents an order applies to. `default_index` is who the chief is talking to (-1 for nobody).
static func targets(sim: LifeSim, order: Dictionary, default_index: int) -> Array:
	var out: Array = []
	match str(order.scope):
		"all":
			for i in range(sim.residents.size()):
				out.append(i)
		"near":
			for i in range(sim.residents.size()):
				if Vector2(sim.residents[i].pos[0], sim.residents[i].pos[1]).distance_to(sim.chief_pos) <= NEAR_TILES:
					out.append(i)
		"names":
			out = (order.names as Array).duplicate()
		_:
			if default_index >= 0 and default_index < sim.residents.size():
				out.append(default_index)
	return out


static func _who(sim: LifeSim, who: Array) -> String:
	if who.size() == sim.residents.size() and who.size() > 1:
		return "Everyone"
	if who.size() == 1:
		return str(sim.residents[who[0]].name)
	if who.size() <= 3:
		var names: Array = []
		for i in who:
			names.append(str(sim.residents[i].name))
		return ", ".join(names)
	return "%d residents" % who.size()


static func _nearest_first(sim: LifeSim, who: Array) -> Array:
	var sorted := who.duplicate()
	sorted.sort_custom(func(a: int, b: int) -> bool:
		return Vector2(sim.residents[a].pos[0], sim.residents[a].pos[1]).distance_squared_to(sim.chief_pos) < Vector2(sim.residents[b].pos[0], sim.residents[b].pos[1]).distance_squared_to(sim.chief_pos))
	return sorted


static func _result(ok: bool, message: String, ui: String = "", ack_who: int = -1, ack_text: String = "") -> Dictionary:
	return {"ok": ok, "message": message, "ui": ui, "ack_who": ack_who, "ack_text": ack_text}


static func _chief_tile(sim: LifeSim) -> Vector2i:
	return Vector2i(roundi(sim.chief_pos.x), roundi(sim.chief_pos.y))


static func execute(sim: LifeSim, order: Dictionary, default_index: int = -1) -> Dictionary:
	var who := targets(sim, order, default_index)
	var intent := str(order.intent)
	match intent:
		"hush":
			return _result(true, "The village falls quiet.", "hush")
		"chatter":
			return _result(true, "The villagers may chat again.", "unhush")
		"pause", "resume", "faster", "slower":
			return _result(true, {"pause": "Paused.", "resume": "Time runs again.", "faster": "Faster.", "slower": "Slower."}[intent], intent)
		"council_auto":
			sim.auto_plan = true
			return _result(true, "The council will plan on its own.")
		"council_ask":
			sim.auto_plan = false
			return _result(true, "The council waits for your decisions.")
		"report":
			return _result(true, report(sim))
		"suggest":
			return _suggest(sim)
		"approve":
			return _approve(sim)
		"expand":
			return _expand(sim)
		"build":
			return _build(sim, order, who)
		"upgrade":
			return _upgrade(sim, order)
		"festival":
			return _festival(sim)
		"gates_open":
			var open_msg := Walls.set_override(sim, "open")
			return _result(not sim.buildings.filter(func(b: Dictionary) -> bool: return str(b.kind) == "gate").is_empty(), open_msg)
		"gates_close":
			var close_msg := Walls.set_override(sim, "closed")
			return _result(not sim.buildings.filter(func(b: Dictionary) -> bool: return str(b.kind) == "gate").is_empty(), close_msg)
		"gates_auto":
			return _result(true, Walls.set_override(sim, "auto"))
		"buy_animal":
			var bought := Farming.buy(sim, str(order.animal), int(order.get("amount", 1)))
			return _result(bool(bought.ok), str(bought.message))
		"sell_animal":
			var sold_beasts := Economy.trade_animal(sim, "sell", str(order.animal), int(order.get("amount", 1)))
			return _result(bool(sold_beasts.ok), str(sold_beasts.message))
		"slaughter":
			var butchered := Farming.slaughter(sim, str(order.animal), int(order.get("amount", 1)))
			return _result(bool(butchered.ok), str(butchered.message))
		"crop":
			var planted := Farming.set_crop(sim, str(order.crop))
			return _result(bool(planted.ok), str(planted.message))
		"farm_report":
			return _result(true, farm_report(sim))
		"dreams":
			var lines: Array = []
			var pool: Array = who if not who.is_empty() and str(order.scope) != "default" else range(sim.residents.size())
			for i in pool:
				var d := Quests.text_of(sim.residents[int(i)])
				if d != "":
					lines.append("%s: %s" % [sim.residents[int(i)].name, d.to_lower()])
			return _result(not lines.is_empty(), ("; ".join(lines.slice(0, 5)) + ".") if not lines.is_empty() else "Nobody has shared a dream yet.")
		"assign_job":
			if who.is_empty():
				return _result(false, "Who should get the job? Name them or select someone.")
			var results: Array = []
			var any_ok := false
			for i in who:
				var res := Jobs.assign(sim, int(i), str(order.title))
				results.append(str(res.message))
				any_ok = any_ok or bool(res.ok)
				if not bool(res.ok) and who.size() > 1:
					break
			return _result(any_ok, " ".join(results.slice(0, 2)))
		"fill_jobs":
			var filled := Jobs.fill_vacancies(sim)
			return _result(filled > 0, "%d post%s filled." % [filled, "" if filled == 1 else "s"] if filled > 0 else "Every opening is staffed, or nobody suitable is free.")
		"dismiss_job":
			if who.is_empty():
				return _result(false, "Who?")
			var gone := Jobs.dismiss(sim, int(who[0]))
			return _result(bool(gone.ok), str(gone.message))
		"gift":
			if who.is_empty():
				return _result(false, "Who is the gift for? Say a name, or select someone.")
			var gift_result := Ownership.gift(sim, str(order.furniture), int(who[0]))
			return _result(bool(gift_result.ok), str(gift_result.message), "", int(who[0]), "")
		"weapons_report":
			return _result(true, Weapons.report(sim))
		"craft":
			var forged := Weapons.craft(sim, str(order.kind), int(order.get("amount", 1)))
			return _result(bool(forged.ok), str(forged.message))
		"chief_equip":
			var held := Weapons.chief_equip(sim, str(order.kind))
			return _result(bool(held.ok), str(held.message))
		"arm":
			var given := Weapons.arm_guards(sim, bool(order.get("everyone", false)))
			if int(given.armed) + int(given.shields) == 0:
				return _result(false, "Nobody was armed: the armory is empty or everyone already has what they need. %s" % Weapons.report(sim))
			return _result(true, "Armed %d resident%s and gave out %d shield%s." % [int(given.armed), "" if int(given.armed) == 1 else "s", int(given.shields), "" if int(given.shields) == 1 else "s"])
		"rival_report":
			return _result(true, Rival.report(sim))
		"envoy":
			var sent := Rival.envoy(sim)
			return _result(bool(sent.ok), str(sent.message))
		"tribute":
			var paid := Rival.tribute(sim)
			return _result(bool(paid.ok), str(paid.message))
		"peace":
			var talks := Rival.peace(sim)
			return _result(bool(talks.ok), str(talks.message))
		"attack_rival":
			var battle := Rival.attack(sim)
			return _result(bool(battle.ok), str(battle.message))
		"route":
			var opened := Caravans.open_route(sim)
			return _result(bool(opened.ok), str(opened.message))
		"caravan_report":
			return _result(true, Caravans.report(sim))
		"caravan_buy":
			var deal := Caravans.buy(sim, str(order.ware), int(order.get("amount", 1)))
			return _result(bool(deal.ok), str(deal.message))
		"market":
			return _result(true, _market_report(sim))
		"trade":
			return _trade(sim, order)
	if who.is_empty():
		return _result(false, "Who should do that? Select someone, name them, or say \"everyone\".")
	var near := _nearest_first(sim, who)
	var label := _who(sim, who)
	match intent:
		"follow":
			for i in who:
				sim.follow(i)
			return _result(true, "%s will follow you." % label, "", near[0], "Right behind you, Chief." if who.size() == 1 else "We're with you, Chief!")
		"unfollow":
			var n := 0
			for i in who:
				if sim.following.has(i) or sim.holding.has(i):
					n += 1
				sim.free_resident(i)
			return _result(true, "%s is free to go." % label if n > 0 else "%s wasn't following you." % label, "", near[0], "Thanks, Chief. Back to it." if n > 0 else "")
		"stay":
			for i in who:
				sim.hold(i)
			return _result(true, "%s will stay put." % label, "", near[0], "I'll wait right here.")
		"stop":
			for i in who:
				sim.free_resident(i)
			return _result(true, "%s carries on as usual." % label, "", near[0], "All right, Chief.")
		"come":
			var spot := sim.chief_pos
			var where := "you"
			if str(order.get("spot", "chief")) == "plaza":
				var plazas := sim.buildings_of("plaza")
				if not plazas.is_empty():
					var t := sim.tile_of(plazas[0])
					spot = Vector2(t.x, t.y)
					where = "the plaza"
			var n2 := sim.gather_at(who, spot, "the chief" if where == "you" else "the plaza")
			return _result(n2 > 0, "%s is gathering at %s." % [label, where], "", near[0], "On my way, Chief!")
		"shelter":
			for i in who:
				sim.flee(i, true)
			return _result(true, "%s took cover indoors." % label, "", near[0], "Taking cover, Chief!")
		"home":
			var started := 0
			for i in who:
				sim.free_resident(i)
				if sim.start_action(i, "rest"):
					sim.residents[i].commanded = true
					started += 1
			return _result(started > 0, "%s is heading home." % label, "", near[0], "Home we go.")
		"action":
			return _action(sim, str(order.action), who, label, near)
	return _result(false, "I'm not sure what you want done.")


static func _action(sim: LifeSim, action: String, who: Array, label: String, near: Array) -> Dictionary:
	var done := 0
	var queued := 0
	var refused := 0
	var first_message := ""
	for i in who:
		var res := sim.command(i, action)
		if first_message == "":
			first_message = str(res.message)
		if bool(res.get("ok", false)):
			if bool(res.get("queued", false)):
				queued += 1
			else:
				done += 1
		else:
			refused += 1
	var verb: String = LifeSim.ACTION_VERBS[action].to_lower()
	if who.size() == 1:
		return _result(done + queued > 0, first_message, "", -1, "")
	var parts: Array = []
	if done > 0:
		parts.append("%d now" % done)
	if queued > 0:
		parts.append("%d next" % queued)
	if refused > 0:
		parts.append("%d can't" % refused)
	var ok := done + queued > 0
	var message := "%s: %s (%s)." % [label, verb, ", ".join(parts)] if ok else first_message
	return _result(ok, message, "", near[0] if ok else -1, Social.bark(action, sim.rng) if ok else "")


static func _spot_near_chief(sim: LifeSim, kind: String) -> Vector2i:
	for t in sim.map.free_lots(_chief_tile(sim)):
		if sim.build_blocker(kind, t) == "":
			return t
	return Vector2i(-9999, -9999)


static func _build(sim: LifeSim, order: Dictionary, who: Array) -> Dictionary:
	var kind := str(order.get("kind", ""))
	if kind in Catalog.WALL_KINDS:
		var res := Walls.build(sim, int(order.get("count", 1)), kind == "gate")
		if int(res.placed) > 0:
			sim.record_decision("The chief", "Build walls", "Ordered by the chief")
			if not who.is_empty():
				for i in who:
					sim.command(i, "work")
		return _result(int(res.placed) > 0, str(res.message))
	if kind == "":
		# "Build something": do the council's best construction plan.
		for o in CityPlanner.options(sim, 6, false):
			if str(o.type) == "build":
				var r := sim.apply_option(o, "The chief")
				return _result(r.begins_with("Started"), "You ordered: %s." % Advice.plain(o) if r.begins_with("Started") else r)
		return _result(false, "Nothing worth building right now. Try naming it, like \"build a farm\", or claim more land.")
	var made := 0
	var last := ""
	for k in range(int(order.get("count", 1))):
		var spot := _spot_near_chief(sim, kind)
		if spot.x < -9000:
			last = sim.build_blocker(kind, Vector2i(2, 2))
			if sim.map.free_lots(_chief_tile(sim)).is_empty():
				last = "There are no free lots. Claim more land first."
			elif last == "" or last.begins_with("That lot"):
				last = "No room or means for another %s." % Catalog.label(kind).to_lower()
			break
		last = sim.place_building(kind, spot)
		if last.begins_with("Started"):
			made += 1
			sim.record_decision("The chief", "Build a %s" % Catalog.label(kind).to_lower(), "Ordered by the chief")
		else:
			break
	if made == 0:
		return _result(false, last)
	var message := "Building %s%s." % ["%d " % made if made > 1 else "a ", Catalog.label(kind).to_lower() + ("s" if made > 1 else "")]
	var ack := -1
	if not who.is_empty():
		for i in who:
			sim.command(i, "work")
		message += " %s will help." % _who(sim, who)
		ack = _nearest_first(sim, who)[0]
	return _result(true, message, "", ack, "We'll get it built, Chief." if ack >= 0 else "")


static func _upgrade(sim: LifeSim, order: Dictionary) -> Dictionary:
	var kind := str(order.get("kind", ""))
	var best := {}
	var reason := ""
	for b in sim.buildings:
		if kind != "" and str(b.kind) != kind:
			continue
		var why := sim.upgrade_blocker(int(b.id))
		if why == "":
			if best.is_empty() or int(b.visits) > int(best.visits):
				best = b
		elif reason == "":
			reason = why
	if best.is_empty():
		if kind == "":
			for o in CityPlanner.options(sim, 6, false):
				if str(o.type) == "upgrade":
					var r := sim.apply_option(o, "The chief")
					return _result(r == "Upgrade started.", "You ordered: %s." % Advice.plain(o) if r == "Upgrade started." else r)
		var noun := Catalog.label(kind).to_lower() if kind != "" else "building"
		return _result(false, "Can't upgrade a %s yet: %s" % [noun, reason if reason != "" else "none are ready."])
	var result := sim.upgrade_building(int(best.id))
	if result == "Upgrade started.":
		sim.record_decision("The chief", "Upgrade the %s" % Catalog.label(str(best.kind)).to_lower(), "Ordered by the chief")
		return _result(true, "Upgrading the %s." % Catalog.label(str(best.kind)).to_lower())
	return _result(false, result)


static func _expand(sim: LifeSim) -> Dictionary:
	var here := Vector2i(floori(sim.chief_pos.x / CityMap.DISTRICT), floori(sim.chief_pos.y / CityMap.DISTRICT))
	var best := Vector2i.ZERO
	var best_d := 1 << 30
	var found := false
	for d in sim.map.frontier():
		var dist := (d.x - here.x) * (d.x - here.x) + (d.y - here.y) * (d.y - here.y)
		if dist < best_d:
			best_d = dist
			best = d
			found = true
	if not found:
		return _result(false, "There is no land to claim next to the village.")
	var why := sim.claim_blocker(best)
	if why != "":
		return _result(false, why)
	var result := sim.claim_district(best)
	if result == "District claimed.":
		sim.record_decision("The chief", "Claim new land", "Ordered by the chief")
		return _result(true, "New land claimed near you.")
	return _result(false, result)


static func _festival(sim: LifeSim) -> Dictionary:
	if sim.residents.is_empty():
		return _result(false, "There is nobody to celebrate with.")
	if not sim.festival.is_empty():
		return _result(false, "The %s is already under way." % str(sim.festival.name))
	if sim.money < 40:
		return _result(false, "A feast costs 40 coins.")
	Festivals.call_feast(sim)
	return _result(true, "The villagers gather for a feast at the plaza.", "", 0, "A feast! Wonderful idea, Chief!")


static func _old_festival(sim: LifeSim) -> Dictionary:
	var message := Advice._apply_personal(sim, 0, "festival")
	var plazas := sim.buildings_of("plaza")
	var spot := sim.chief_pos
	if not plazas.is_empty():
		var t := sim.tile_of(plazas[0])
		spot = Vector2(t.x, t.y)
	var all: Array = range(sim.residents.size())
	sim.gather_at(all, spot, "the festival")
	return _result(true, message, "", _nearest_first(sim, all)[0], "A festival! Wonderful idea, Chief!")


static func _suggest(sim: LifeSim) -> Dictionary:
	var options := CityPlanner.options(sim, 3, false)
	if options.is_empty():
		return _result(true, "The council has nothing pressing. The village is doing fine.")
	var lines: Array = []
	for o in options:
		lines.append(Advice.plain(o))
	return _result(true, "The council suggests: " + "; ".join(lines) + ".")


static func _approve(sim: LifeSim) -> Dictionary:
	var options := CityPlanner.options(sim, 3, false)
	if options.is_empty():
		return _result(false, "There is no plan waiting for approval.")
	var o: Dictionary = options[0]
	var r := sim.apply_option(o, "The chief")
	var ok := r.begins_with("Started") or r == "Upgrade started." or r == "District claimed."
	return _result(ok, "Approved: %s." % Advice.plain(o) if ok else r)


static func report(sim: LifeSim) -> String:
	var hungry: Array = []
	var tired: Array = []
	var sad: Array = []
	for r in sim.residents:
		if float(r.needs.hunger) < 30.0:
			hungry.append(str(r.name))
		if float(r.needs.energy) < 25.0:
			tired.append(str(r.name))
		if sim.mood(r) < 40.0:
			sad.append(str(r.name))
	var parts: Array = ["%d residents, mood %d%%, %d coins, %d food" % [sim.residents.size(), int(sim.average_mood()), sim.money, sim.food + sim.meals]]
	if not hungry.is_empty():
		parts.append("hungry: " + ", ".join(hungry.slice(0, 3)))
	if not tired.is_empty():
		parts.append("exhausted: " + ", ".join(tired.slice(0, 3)))
	if not sad.is_empty():
		parts.append("low spirits: " + ", ".join(sad.slice(0, 3)))
	var project := sim.active_project()
	if not project.is_empty():
		parts.append("building the %s" % str(project.get("label", "project")).to_lower())
	return "The %s: %s." % [sim.stage_name().to_lower(), "; ".join(parts)]


static func _market_report(sim: LifeSim) -> String:
	var parts: Array = []
	for item in ["food", "wood", "stone"]:
		parts.append("%s %.2f" % [item, Economy.price(sim, item)])
	var text := "Market: %s coins each." % ", ".join(parts)
	if not sim.events.is_empty():
		text += " " + str(sim.events[sim.events.size() - 1].text)
	return text


static func _trade(sim: LifeSim, order: Dictionary) -> Dictionary:
	var action := str(order.get("trade_action", "sell"))
	var item := str(order.get("item", ""))
	if item == "surplus" or (item == "" and action == "sell"):
		var messages: Array = []
		var wood_extra := sim.wood - 30
		var stone_extra := sim.stone - 20
		if wood_extra > 0:
			messages.append(str(Economy.trade(sim, "sell", "wood", wood_extra).message))
		if stone_extra > 0:
			messages.append(str(Economy.trade(sim, "sell", "stone", stone_extra).message))
		if messages.is_empty():
			return _result(false, "There is no surplus to sell (the village keeps 30 timber and 20 stone).")
		return _result(true, " ".join(messages))
	if item == "":
		return _result(false, "Say what to trade: food, wood or stone.")
	var res := Economy.trade(sim, action, item, int(order.get("amount", 10)))
	return _result(bool(res.ok), str(res.message))


static func farm_report(sim: LifeSim) -> String:
	var parts: Array = []
	for b in sim.buildings:
		if str(b.kind) != "farm" or int(b.level) < 1:
			continue
		var herd: Array = []
		for kind in Farming.ANIMALS:
			var n := Farming.count(b, kind)
			if n > 0:
				herd.append("%d %s" % [n, Farming.ANIMALS[kind].plural if n != 1 else str(Farming.ANIMALS[kind].label).to_lower()])
		parts.append("%s %d%%%s" % [str(Farming.CROPS[Farming.crop_of(b)].label).to_lower(), int(float(b.get("growth", 0.0))), (" with " + ", ".join(herd)) if not herd.is_empty() else ""])
	if parts.is_empty():
		return "There are no farms yet."
	return "Farms: " + "; ".join(parts) + "."
