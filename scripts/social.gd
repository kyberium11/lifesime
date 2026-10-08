class_name Social
extends RefCounted
## Social rules and dialogue: interaction kinds, friendship levels, emotions, barks and offline chat replies.
## Pure data + helpers, so the simulation, the UI and the tests all share one source of truth.

## `bond`: friendship change on success. `social`/`fun`: need changes. `min`: friendship needed to try it.
## `cool`: game minutes before the same pair can repeat it.
const KINDS := {
	"chat": {"label": "Chat", "bond": 5.0, "social": 14.0, "fun": 3.0, "min": 0.0, "cool": 25.0, "emote": "speech", "icon": "talk"},
	"joke": {"label": "Tell a joke", "bond": 6.0, "social": 10.0, "fun": 12.0, "min": 5.0, "cool": 45.0, "emote": "laugh", "icon": "laugh"},
	"compliment": {"label": "Compliment", "bond": 7.0, "social": 8.0, "fun": 4.0, "min": 10.0, "cool": 60.0, "emote": "star", "icon": "star"},
	"gossip": {"label": "Gossip", "bond": 6.0, "social": 12.0, "fun": 6.0, "min": 15.0, "cool": 60.0, "emote": "speech", "icon": "talk"},
	"hug": {"label": "Hug", "bond": 9.0, "social": 16.0, "fun": 6.0, "min": 30.0, "cool": 90.0, "emote": "heart", "icon": "heart"},
	"argue": {"label": "Argue", "bond": -12.0, "social": -6.0, "fun": -8.0, "min": 0.0, "cool": 60.0, "emote": "anger", "icon": "anger"},
}

const LEVELS := [[85.0, "Best friend"], [60.0, "Close friend"], [30.0, "Friend"], [10.0, "Acquaintance"], [0.0, "Stranger"]]

const LINES := {
	"chat": {
		"start": ["Hi {other}! How's your day going?", "Got a minute to chat, {other}?", "Lovely day in Willowbrook, isn't it?", "What have you been up to, {other}?"],
		"good": ["Oh, it's been good! Thanks for asking.", "Always happy to chat with you!", "You always brighten my day.", "Let me tell you about my morning..."],
		"meh": ["Mm. Sorry, my mind's elsewhere.", "Yeah... sure.", "Can we talk later?"],
	},
	"joke": {
		"start": ["Why did the scarecrow win an award? Outstanding in his field!", "Knock knock!", "What do you call a sleeping bull? A bulldozer!", "I'd tell a construction joke, but I'm still working on it."],
		"good": ["Ha! That's terrible. Do another!", "Hahaha, I needed that!", "Stop, my sides hurt!"],
		"meh": ["...I don't get it.", "Heh. Nice try.", "That one's a bit stale."],
	},
	"compliment": {
		"start": ["You do wonderful work around here, {other}.", "I really like your style, {other}.", "Have I told you how much I appreciate you?"],
		"good": ["Aww, that means a lot!", "You're too kind!", "Now I'm blushing."],
		"meh": ["Oh. Um, thanks?", "Are you trying to butter me up?"],
	},
	"gossip": {
		"start": ["Did you hear the orchard might bear fruit early?", "Psst... I think the market is getting a new look.", "Between us, the workshop is busier than ever."],
		"good": ["No way! Tell me more.", "Ha, I heard that too!", "Our little secret."],
		"meh": ["I'd rather not gossip.", "Hm, I wouldn't know."],
	},
	"hug": {
		"start": ["Come here, you.", "You look like you could use a hug.", "*opens arms*"],
		"good": ["Thank you, I needed that.", "Aww, warm and cozy.", "Best hug of the day!"],
		"meh": ["Oh! Um... personal space?", "*stiffly pats back*"],
	},
	"argue": {
		"start": ["I can't believe you did that!", "We need to talk. Seriously.", "You never listen to me!"],
		"good": ["Fine! Whatever.", "That's not fair!", "I'm not in the mood for this."],
		"meh": ["Fine! Whatever.", "That's not fair!", "I'm not in the mood for this."],
	},
}

const REFUSE_BOND := ["We barely know each other...", "Maybe when we're better friends.", "That's a bit forward."]

const BARKS := {
	"guard": ["I will keep watch.", "Nothing gets past me.", "Spears up, everyone."],
	"chop": ["Off to fell a tree!", "Where did I leave my axe?", "Timber!"],
	"mine": ["Time to break some rocks.", "I will fetch the pickaxe.", "Stone for the village!"],
	"water": ["I will fetch some water.", "The crops are thirsty.", "Bucket in hand!"],
	"eat": ["Lunch time!", "My stomach is growling.", "Something smells good."],
	"sleep": ["So sleepy...", "Time for bed.", "Zzz... almost."],
	"wash": ["A scrub is overdue.", "Bath time!"],
	"socialize": ["Let's see who's about.", "I could use some company."],
	"play": ["Time to have some fun!", "Race you to the swing!"],
	"work": ["Back to the workshop.", "Let's earn some coins."],
	"study": ["Time to learn something new.", "Off to the library."],
	"farm": ["The crops need tending.", "Time to get my hands dirty."],
	"gather": ["Let's see what the orchard gave us.", "Basket in hand."],
	"cook": ["Cooking something special.", "Dinner won't make itself."],
	"exercise": ["Time to stretch my legs.", "Let's get moving!"],
	"rest": ["A little break won't hurt.", "Ahh, a moment of peace."],
}

const REFUSALS := {
	"tired": ["I'm too exhausted for that right now.", "Can't. I can barely keep my eyes open."],
	"starving": ["I'm starving! Food first.", "Not on an empty stomach!"],
	"not_sleepy": ["I'm not sleepy at all.", "Too wired to sleep."],
	"full_queue": ["My hands are full right now.", "One thing at a time, please!"],
	"cooldown": ["Give me a moment.", "Later, maybe."],
}

const TRAIT_LINES := {
	"Pip": ["Have you seen how the garden is coming along?", "I love the smell of fresh soil.", "Plants don't judge. I like that."],
	"Mira": ["I'm planning a new recipe!", "Nothing beats a warm meal shared.", "Salt makes everything better."],
	"Theo": ["I want this village to be spectacular.", "Give me tools and a plan.", "One more building and we're a proper town."],
	"June": ["I found the best passage in the library.", "Books are quiet adventures.", "Did you know owls swallow prey whole?"],
}

const GENERIC_LINES := ["It is a good day to be in Willowbrook.", "I have been thinking about what this town could become.", "There is always something to do around here.", "I love seeing the town grow."]

const STATE_REPLY := {
	"happy": "I'm doing great, thanks for asking!",
	"content": "Can't complain, really.",
	"hungry": "Honestly, my stomach is rumbling.",
	"tired": "Pretty worn out, to be honest.",
	"dirty": "Could use a wash, haha.",
	"lonely": "A little lonely. Good thing you're here.",
	"bored": "Bored out of my mind.",
	"sick": "Not feeling my best.",
	"gloomy": "It's been a rough day.",
}


static func bond_label(score: float) -> String:
	for level in LEVELS:
		if score >= level[0]:
			return level[1]
	return "Stranger"


## A single word for how someone feels, driven by their lowest need and overall mood.
static func emotion(needs: Dictionary, mood: float) -> String:
	if float(needs.health) < 30.0:
		return "sick"
	if float(needs.energy) < 25.0:
		return "tired"
	if float(needs.hunger) < 30.0:
		return "hungry"
	if float(needs.hygiene) < 30.0:
		return "dirty"
	if float(needs.social) < 30.0:
		return "lonely"
	if float(needs.fun) < 30.0:
		return "bored"
	if mood > 75.0:
		return "happy"
	if mood > 52.0:
		return "content"
	return "gloomy"


static func pick(options: Array, rng: RandomNumberGenerator) -> String:
	return str(options[rng.randi() % options.size()])


## One line of dialogue. `role`: start (initiator), good / meh (responder).
static func line(kind: String, role: String, rng: RandomNumberGenerator, other: String = "") -> String:
	var table: Dictionary = LINES[kind]
	return pick(table[role], rng).replace("{other}", other)


static func bark(action: String, rng: RandomNumberGenerator) -> String:
	return pick(BARKS.get(action, ["Hmm."]), rng)


static func refusal(reason: String, rng: RandomNumberGenerator) -> String:
	return pick(REFUSALS[reason], rng)


## Offline reply to free-text chat, so conversation works even without the AI.
static func chat_reply(name: String, trait_: String, emotion_: String, text: String, rng: RandomNumberGenerator) -> String:
	var t := text.to_lower()
	for word in ["hello", "hi ", "hey", "good morning", "good evening", "howdy"]:
		if (t + " ").begins_with(word) or t.contains(" " + word):
			return "Hello! Nice to see you. %s" % STATE_REPLY.get(emotion_, "")
	if t.contains("how are you") or t.contains("how do you feel") or t.contains("how're you") or t.contains("how are things"):
		return STATE_REPLY.get(emotion_, "Doing alright.")
	if t.contains("who are you") or t.contains("your name"):
		return "I'm %s, %s of Willowbrook." % [name, trait_.to_lower()]
	if t.contains("hungry") or t.contains("food") or t.contains("eat"):
		return "Food sounds wonderful. The market always has something."
	if t.contains("tired") or t.contains("sleep") or t.contains("bed"):
		return "Sleep would be lovely. A shelter nearby helps a lot."
	if t.contains("thank"):
		return "Anytime!"
	if t.contains("love") or t.contains("friend"):
		return "That's sweet. I'm glad you're around."
	if t.contains("work") or t.contains("build") or t.contains("upgrade"):
		return "Every work shift helps the village grow. I'm in."
	if t.contains("sorry"):
		return "It's alright. Let's move on."
	if t.contains("?"):
		return pick(["Hmm, good question. Let me think...", "I'm not sure, but I'd love to find out."], rng)
	return pick(TRAIT_LINES.get(name, GENERIC_LINES), rng)
