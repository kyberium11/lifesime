extends Node3D
## Willowbrook: you are the village chief, seen from behind in third person. Walk the town with WASD,
## look around with the right mouse button, talk to residents (typing or by voice) and decide what the
## village builds. Residents talk to each other and to you out loud. Press Tab for the overview map.

const SAVE := "user://village3d.json"
const WALK_SPEED := 5.0
const RUN_SPEED := 9.5
## Flying: speed multiplier, climb rate, ceiling, and how high a wall or building reaches.
const FLY_SPEED_MUL := 2.2
const FLY_CLIMB := 9.0
const FLY_CEILING := 45.0
const WALL_TOP := 2.6
const BUILDING_TOP := 7.0
const INTERACT_RANGE := 9.0
const TALK_RANGE := 11.0
const PLAYER_LINES := {
	"chat": ["Hello %s, how are you?", "Got a moment, %s?"],
	"joke": ["Hey %s, want to hear a joke?"],
	"compliment": ["You're doing well, %s."],
	"gossip": ["Psst, %s, have you heard?"],
	"hug": ["Come here, %s."],
	"argue": ["%s, we need to talk."],
	"share_meal": ["I brought you something to eat, %s."],
}

var sim := LifeSim.new()
var art := CityArt.new()
var camera := Camera3D.new()
var hud := GameHud.new()
var overlay := WorldOverlay.new()
var pie := PieMenu.new()
var studio := PortraitStudio.new()
var voice := VoiceService.new()
var ai := AiClient.new()
var director := ConversationDirector.new()

var yaw := 0.4
var chase_pitch := 0.32
var chase_dist := 6.5
var overview := false
var overview_focus := Vector3(10, 0, 8)
var overview_dist := 70.0
var cam_target := Vector3.ZERO
var cam_dist := 6.5
var cam_pitch := 0.32
var speed := 1.0
var last_speed := 1.0
var selected := 0
var build_kind := ""
var ghost: MeshInstance3D
var look_drag := false
var chief_mode := ""
var chief_mode_time := 0.0
var voice_replies := true
var mic_devices: Array = []

var ai_enabled := true
var bridge_pid := -1
var decide_timer := 6.0
var decide_cursor := 0
var plans_cache: Array = []
var plans_timer := 0.0
var save_timer := 30.0
var ui_timer := 0.0
var fresh := false
var nosave := false
var shot := ""
var shot_after := 8.0
var advance_days := 0
var demo := ""
var demo_done := false
var mic_target := -1
var advice_panel := AdvicePanel.new()
var advice_polished := 0
var orders_panel := OrdersPanel.new()
var market_panel := MarketPanel.new()
var market_button := Button.new()
var furnish_panel := FurnishPanel.new()
var furnish_button := Button.new()
var journal_panel := JournalPanel.new()
var journal_button := Button.new()
var menu_panel := MenuPanel.new()
var tutorial_card := TutorialCard.new()
var photo := PhotoMode.new()
var ui_holder: Control
var menu_prev_speed := 1.0
var photo_pos := Vector3.ZERO
var photo_yaw := 0.0
var photo_pitch := 0.0
var tutorial_start := Vector3.ZERO
var flying := false
var demo_fight := false
var demo_fight_t := 0.0
var combat_hud: Control
var shake := 0.0
var hurt_flash: ColorRect
var dash_t := 0.0
var dash_dir := Vector3.ZERO
var _hp_bar: ProgressBar
var _stamina_bar: ProgressBar
var _combat_label: Label
var _down_label: Label
var fly_alt := 0.0
## While the chief is indoors: the room being shown, and where to put things back when leaving.
var interior: InteriorView = null
## While the chief is up a watchtower: {id, return position...}.
var lookout := {}
var fire_cooldown := 0.0
var outdoor := {}
const INTERIOR_WALK := 1.9
const INTERIOR_RUN := 3.4
const INTERIOR_CHIEF_SCALE := 0.2
var orders_button := Button.new()
var demo_at := 2.0
var muted_run := false
var verbose := false
var quit_after := 0.0
var _elapsed := 0.0


func _ready() -> void:
	GameSettings.load_from()
	ai_enabled = bool(GameSettings.value("ai"))
	voice_replies = bool(GameSettings.value("voice_replies"))
	for arg in OS.get_cmdline_user_args():
		if arg == "--fresh": fresh = true
		elif arg == "--nosave": nosave = true
		elif arg == "--offline": ai_enabled = false
		elif arg.begins_with("--speed="): speed = float(arg.substr(8))
		elif arg.begins_with("--shot="): shot = arg.substr(7); nosave = true
		elif arg.begins_with("--shot-after="): shot_after = float(arg.substr(13))
		elif arg.begins_with("--advance-days="): advance_days = int(arg.substr(15))
		elif arg.begins_with("--demo="): demo = arg.substr(7)
		elif arg.begins_with("--select="): selected = maxi(0, int(arg.substr(9)))
		elif arg.begins_with("--demo-at="): demo_at = float(arg.substr(10))
		elif arg == "--mute": muted_run = true
		elif arg == "--verbose": verbose = true
		elif arg.begins_with("--quit-after="): quit_after = float(arg.substr(13))
	if GameSettings.new_game:
		GameSettings.new_game = false
		fresh = true
	if not fresh:
		load_game()
	selected = clampi(selected, 0, sim.residents.size() - 1)
	for i in range(advance_days * 1440):
		sim.tick(1.0)
	sim.notices.clear()
	sim.drain_fx()
	sim.scripted_dialogue = true
	add_child(art)
	art.generate(sim)
	GameSettings.apply_quality(get_viewport(), art.sun)
	add_child(camera)
	camera.fov = 62.0
	camera.far = 600.0
	camera.current = true
	cam_target = art.chief.position + Vector3(0, 1.5, 0)
	ghost = art.box(art, Vector3(0, -10, 0), Vector3(3.8, 0.15, 3.8), Color("d1dba3"))
	var ghost_material := StandardMaterial3D.new()
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.material_override = ghost_material
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(voice)
	voice.tts_enabled = not muted_run
	add_child(ai)
	add_child(director)
	director.setup(sim, voice, ai)
	director.use_ai = ai_enabled
	ai.enabled = ai_enabled
	ai.completed.connect(_on_ai_completed)
	ai.failed.connect(_on_ai_failed)
	if ai_enabled:
		_start_bridge()
	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 2
	add_child(overlay_layer)
	overlay.camera = camera
	overlay.sim = sim
	overlay.art = art
	overlay_layer.add_child(overlay)
	add_child(studio)
	studio.setup(art)
	add_child(hud)
	hud.build(sim, studio)
	var advice_layer := CanvasLayer.new()
	advice_layer.layer = 5
	add_child(advice_layer)
	var advice_holder := Control.new()
	advice_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	advice_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	advice_holder.theme = UiKit.make_theme()
	advice_layer.add_child(advice_holder)
	advice_holder.add_child(advice_panel)
	advice_holder.add_child(orders_panel)
	furnish_panel.bought.connect(_furnish)
	advice_holder.add_child(furnish_panel)
	furnish_button.text = "Furnish  [G]"
	furnish_button.focus_mode = Control.FOCUS_NONE
	furnish_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	furnish_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	furnish_button.offset_left = 166
	furnish_button.offset_right = 266
	furnish_button.offset_top = 78
	furnish_button.visible = false
	furnish_button.pressed.connect(_toggle_furnish)
	advice_holder.add_child(furnish_button)
	market_panel.sim = sim
	advice_holder.add_child(market_panel)
	market_panel.traded.connect(_market_trade)
	market_button.text = "Market  [K]"
	market_button.focus_mode = Control.FOCUS_NONE
	market_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	market_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	market_button.offset_left = 58
	market_button.offset_right = 158
	market_button.offset_top = 78
	market_button.pressed.connect(_toggle_market)
	advice_holder.add_child(market_button)
	orders_button.text = "Orders  [O]"
	orders_button.focus_mode = Control.FOCUS_NONE
	orders_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	orders_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	orders_button.offset_left = -50
	orders_button.offset_right = 50
	orders_button.offset_top = 78
	orders_button.pressed.connect(_toggle_orders)
	advice_holder.add_child(orders_button)
	ui_holder = advice_holder
	journal_button.text = "Journal  [J]"
	journal_button.focus_mode = Control.FOCUS_NONE
	journal_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	journal_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	journal_button.offset_left = -158
	journal_button.offset_right = -58
	journal_button.offset_top = 78
	journal_button.pressed.connect(_toggle_journal)
	advice_holder.add_child(journal_button)
	journal_panel.sim = sim
	journal_panel.ai_available = ai_enabled
	advice_holder.add_child(journal_panel)
	advice_holder.add_child(menu_panel)
	tutorial_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tutorial_card.offset_left = 82
	tutorial_card.offset_top = -330
	tutorial_card.offset_right = 420
	tutorial_card.offset_bottom = -20
	tutorial_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	advice_holder.add_child(tutorial_card)
	_build_combat_ui(advice_holder)
	add_child(photo)
	tutorial_start = art.chief.position
	sim.ask_chief = true
	var pie_layer := CanvasLayer.new()
	pie_layer.layer = 8
	add_child(pie_layer)
	pie_layer.add_child(pie)
	pie.theme = UiKit.make_theme()
	mic_devices = voice.microphone_names()
	_connect_signals()
	_connect_extra()
	hud.set_voice_menu(voice_replies, _mic_name())
	_update_camera(1.0)
	_refresh_hud()


func _connect_signals() -> void:
	hud.resident_picked.connect(func(i: int) -> void: _select(i, true))
	hud.speed_picked.connect(func(v: float) -> void:
		if v > 0.0: last_speed = v
		speed = v)
	hud.save_requested.connect(func() -> void: hud.toast("Village saved." if save_game() else "Could not save (or saving is disabled).", "check", UiKit.GOOD))
	hud.ai_toggled.connect(_toggle_ai)
	hud.voice_replies_toggled.connect(func() -> void:
		voice_replies = not voice_replies
		voice.tts_enabled = voice_replies
		hud.set_voice_menu(voice_replies, _mic_name())
		hud.toast("Voice replies %s" % ("on" if voice_replies else "off"), "speaker" if voice_replies else "mute", UiKit.INK))
	hud.microphone_cycled.connect(_cycle_microphone)
	hud.interact_requested.connect(func(i: int) -> void: _open_resident_pie(i, _screen_of(art.actors[i].position + Vector3(0, 1.0, 0))))
	hud.chat_requested.connect(_open_chat)
	hud.mic_pressed.connect(_on_mic_pressed)
	orders_panel.ordered.connect(func(o: Dictionary) -> void: _execute_order(o, selected))
	advice_panel.mic_pressed.connect(_on_mic_pressed)
	advice_panel.chosen.connect(_answer_advice)
	advice_panel.closed.connect(func() -> void:
		if voice.listening:
			voice.stop_listening(true)
		_refresh_voice())
	hud.queue_cancelled.connect(func(i: int, slot: int) -> void: sim.cancel_queued(i, slot))
	hud.plan_approved.connect(_approve_plan)
	hud.autoplan_toggled.connect(func() -> void:
		sim.auto_plan = not sim.auto_plan
		hud.toast("The council now %s." % ("acts on its own" if sim.auto_plan else "waits for your decisions"), "town", UiKit.INK))
	hud.build_picked.connect(func(kind: String) -> void:
		build_kind = kind
		hud.set_hint("Click a free lot to place a %s  ·  right-click or Esc to cancel" % Catalog.label(kind).to_lower()))
	hud.chat_sent.connect(_on_chat_sent)
	hud.overview_toggled.connect(_toggle_overview)
	hud.chat.closed.connect(func() -> void: ai.cancel_all("chat"))
	director.overheard.connect(func(speaker: int, listener: int, text: String) -> void: hud.chat.add_overheard(str(sim.residents[speaker].name), str(sim.residents[listener].name), text))
	voice.listening_changed.connect(func(_on: bool) -> void: _refresh_voice())
	voice.transcribed.connect(_on_transcribed)
	voice.stt_failed.connect(func(reason: String) -> void:
		hud.toast(reason, "mic", UiKit.WARN)
		_refresh_voice())
	voice.stt_status_changed.connect(func(_t: String) -> void: _refresh_voice())
	if verbose:
		ai.failed.connect(func(_id: int, kind: String, reason: String, _tag: Variant) -> void: print("[ai failed] %s: %s" % [kind, reason]))
		ai.completed.connect(func(_id: int, kind: String, _data: Dictionary, _tag: Variant) -> void: print("[ai ok] %s" % kind))
		director.line_started.connect(func(speaker: int, text: String, _id: int) -> void: print("[%s] %s: %s" % [director.last_source, sim.residents[speaker].name, text]))
		director.scene_ended.connect(func(a: int, b: int, summary: String) -> void: print("[scene over] %s & %s: %s" % [sim.residents[a].name, sim.residents[b].name, summary]))
	director.line_started.connect(func(speaker: int, text: String, id: int) -> void: overlay.say_hold(speaker, text, id))
	director.line_ended.connect(func(_speaker: int, id: int) -> void: overlay.release(id))
	director.scene_started.connect(func(a: int, b: int) -> void:
		hud.set_hint("%s and %s are talking…" % [sim.residents[a].name, sim.residents[b].name])
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			if not director.in_scene(a):
				hud.set_hint("")))


# --- frame loop ----------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	_elapsed += dt
	_update_combat_state(dt)
	if demo_fight:
		demo_fight_t += dt
		if fmod(demo_fight_t, 0.55) < dt:
			_chief_attack(fmod(demo_fight_t, 3.3) < dt * 2.0)
		for fm in sim.mobs:
			if bool(fm.get("winding", false)) and Combat.fighter(sim).dodge_cd <= 0.0 and randf() < 0.5:
				_chief_dodge()
		Combat.fighter(sim).hp = maxf(Combat.fighter(sim).hp, 40.0)
	sim.tick(dt * 4.0 * speed)
	_handle_events(sim.drain_fx())
	while not sim.notices.is_empty():
		_toast_notice(str(sim.notices.pop_front()))
	_update_chief(dt)
	sim.chief_pos = _chief_tile()
	if interior == null:
		art.update_world(overview_focus if overview else art.chief.position)
	art.sync(selected, dt)
	_update_camera(dt)
	if not Tutorial.is_done("move") and art.chief.position.distance_to(tutorial_start) > 4.0:
		_tut("move")
	if sim.story_due > 0:
		var due := sim.story_due
		sim.story_due = 0
		_request_story(due, false)
	if interior == null:
		_update_hover()
		_update_ghost()
	else:
		overlay.interior = interior
		_check_interior_exit()
	if interior == null:
		overlay.interior = null
	overlay.lookout = not lookout.is_empty()
	fire_cooldown = maxf(0.0, fire_cooldown - dt)
	overlay.selected = selected
	ui_timer -= dt
	if ui_timer <= 0.0:
		ui_timer = 0.15
		_refresh_hud()
	_schedule_decisions(dt)
	_tick_advice_ui()
	save_timer -= dt
	if save_timer <= 0.0:
		save_timer = 30.0
		save_game()
	if demo != "" and not demo_done:
		_run_demo()
	if quit_after > 0.0 and _elapsed >= quit_after:
		_shutdown()
		get_tree().quit()
	if shot != "":
		shot_after -= dt
		if shot_after <= 0.0:
			get_viewport().get_texture().get_image().save_png(shot)
			_shutdown()
			get_tree().quit()


func _handle_events(events: Array) -> void:
	var visible_events: Array = []
	for e in events:
		if e.type == "advice_ready":
			hud.toast("%s has come to ask for your advice. Press E." % sim.residents[int(e.who)].name, "speech", UiKit.ACCENT)
		elif e.type == "conversation":
			if not director.begin_scene(e):
				# Too far away to stage: the town carries on quietly.
				sim.emote(int(e.a), "speech", 0.2)
		elif str(e.type) == "resident_removed":
			director.hush(2.0)
			art.remove_actor(int(e.index))
			overlay.clear_bubbles()
			selected = clampi(selected, 0, maxi(0, sim.residents.size() - 1))
			hud.chat.close()
		elif str(e.type) == "chief_hit":
			art.world_event(e)
			if not bool(e.dodged):
				hurt_flash.color.a = clampf(0.25 + float(e.amount) * 0.02, 0.0, 0.55) if not bool(e.blocked) else 0.12
				shake = maxf(shake, 0.2 + float(e.amount) * 0.02)
		elif str(e.type) in ["felled", "rock_chipped", "rock_gone", "hit", "strike", "mob_gone", "downed", "arrow", "wall_breach", "chief_drip", "swing"]:
			art.world_event(e)
		else:
			visible_events.append(e)
	overlay.feed(visible_events)


func _toast_notice(text: String) -> void:
	var icon := "star"
	var color := UiKit.ACCENT
	var lower := text.to_lower()
	if lower.contains("friend") or lower.contains("close") or lower.contains("best"):
		icon = "heart"
		color = UiKit.SOCIAL
	elif lower.contains("moved in") or lower.contains("now a"):
		icon = "town"
		color = UiKit.GOOD
	elif lower.contains("upgrad") or lower.contains("complet") or lower.contains("building"):
		icon = "build"
		color = UiKit.GOOD
	hud.toast(text, icon, color)


func _refresh_hud() -> void:
	plans_timer -= 0.15
	if hud.tab == 3 and plans_timer <= 0.0:
		plans_timer = 1.5
		plans_cache = CityPlanner.options(sim, 6, false)
	hud.refresh(selected, speed, build_kind, plans_cache)
	_refresh_voice()
	if hud.chat.chatting and not hud.chat.broadcast:
		var r: Dictionary = sim.residents[hud.chat.index]
		var emo := sim.emotion(r)
		hud.chat.set_subtitle("%s  ·  %s  ·  %s" % [r.trait, emo.capitalize(), Social.bond_label(float(r.bond))], UiKit.EMOTION_COLOR.get(emo, UiKit.INK))
	if build_kind == "" and not pie.is_open() and not voice.listening:
		_prompt_hint()


func _refresh_voice() -> void:
	var text := voice.stt_status
	if voice.listening:
		text = "Listening… speak, then pause." if voice.heard_speech else "Listening… go ahead and speak."
	elif voice.transcribing:
		text = "Understanding what you said…"
	hud.set_voice_state(text, voice.listening, voice.transcribing, voice.mic_level)
	advice_panel.set_voice_state(text, voice.listening, voice.transcribing, voice.mic_level)


## The "[E] Talk to ..." prompt near the chief.
func _prompt_hint() -> void:
	if interior != null:
		_interior_hint()
		return
	if not lookout.is_empty():
		var reach := _lookout_reach()
		var foe := Survival.nearest_mob(sim, lookout.tile, reach)
		hud.set_hint("On the watchtower  -  [F] fire at the nearest monster%s  -  [E] climb down" % (" (%d tiles away)" % int(Vector2(float(foe.pos[0]), float(foe.pos[1])).distance_to(lookout.tile)) if not foe.is_empty() else ", none in range"))
		return
	var near_tower := _tower_near(4.5)
	if not near_tower.is_empty() and sim.mobs.is_empty() and _nearest_resident_to_chief(5.0) < 0:
		hud.set_hint("[E] Climb the watchtower   -   shoot monsters by hand from the top")
		return
	if overview:
		hud.set_hint("Overview: click claimable land (blue) to expand, or a free lot to build  ·  Tab to return")
		return
	var chief_tile := Vector2(art.chief.position.x, art.chief.position.z) / CityMap.TILE
	for m in sim.mobs:
		if chief_tile.distance_to(Vector2(float(m.pos[0]), float(m.pos[1]))) < 5.0:
			hud.set_hint("%s  ·  [F] attack  [R] heavy  [Ctrl] dodge  hold [Y] block  ·  watch for the red !" % str(Survival.KINDS[str(m.kind)].label))
			return
	if sim.threat > 0 and not _advice_waiting():
		hud.set_hint("%d monsters about   ·   [O] orders: Defend / Take cover   ·   [F] attack when close" % sim.threat)
		return
	if _advice_waiting():
		hud.set_hint("[E] Hear out %s   ·   they are waiting for your advice" % sim.residents[int(sim.advice.resident)].name)
		return
	if Festivals.is_active(sim):
		var plaza := Festivals.plaza_spot(sim)
		var here := Vector2(art.chief.position.x, art.chief.position.z) / CityMap.TILE
		if here.distance_to(plaza) < 22.0 and _building_near_door(5.0).is_empty():
			hud.set_hint("The %s is on at the plaza   -   join the villagers" % str(sim.festival.name))
			return
	var door := _building_near_door(5.0)
	var near := _nearest_resident_to_chief(INTERACT_RANGE)
	if not door.is_empty() and (near < 0 or art.actors[near].position.distance_to(art.chief.position) > 5.0):
		hud.set_hint("[E] Enter the %s%s   ·   click it for more" % [Catalog.label(str(door.kind)).to_lower(), _owner_note(door)])
		return
	if near >= 0:
		hud.set_hint("[E] Talk to %s   ·   [V] speak with the microphone" % sim.residents[near].name)
	else:
		hud.set_hint("")


func _select(i: int, from_list: bool = false) -> void:
	selected = clampi(i, 0, sim.residents.size() - 1)
	if hud.chat.chatting:
		_open_chat(selected)
	if from_list and not overview:
		pass


func _mic_name() -> String:
	var current := AudioServer.input_device
	return current if current != "" else "default"


func _cycle_microphone() -> void:
	mic_devices = voice.microphone_names()
	if mic_devices.is_empty():
		hud.toast("No microphones found.", "mic", UiKit.WARN)
		return
	var at := mic_devices.find(AudioServer.input_device)
	var next := str(mic_devices[(at + 1) % mic_devices.size()])
	voice.set_microphone(next)
	hud.set_voice_menu(voice_replies, next)
	hud.toast("Microphone: %s" % next, "mic", UiKit.INK)


# --- chief (the player) ----------------------------------------------------------------------------------

func _blocked(p: Vector3) -> bool:
	for off in [Vector3(0.7, 0, 0), Vector3(-0.7, 0, 0), Vector3(0, 0, 0.7), Vector3(0, 0, -0.7)]:
		var t := CityMap.world_to_tile(p + off)
		if sim.map.solid_tiles.has(t) or sim.map.is_water(t):
			return true
	return false


## Buildings and walls only stop the chief below their roofs: fly high enough and they pass underneath.
func _move_blocked(from: Vector3, step: Vector3) -> bool:
	var height := art.chief.position.y
	if height < BUILDING_TOP and _blocked(from + step):
		return true
	return height < WALL_TOP and _wall_in_way(from, step)


## Climb, descend and lean while flying; settle back to the ground when it ends.
func _update_flight(dt: float, moving: bool) -> void:
	if flying:
		var up := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
		if get_viewport().gui_get_focus_owner() == null:
			fly_alt = clampf(fly_alt + up * FLY_CLIMB * dt, 0.0, FLY_CEILING)
	else:
		fly_alt = move_toward(fly_alt, 0.0, FLY_CLIMB * dt)
	art.chief.position.y = lerpf(art.chief.position.y, fly_alt, minf(1.0, dt * 6.0))
	if not flying and fly_alt <= 0.0 and art.chief.position.y < 0.05:
		art.chief.position.y = 0.0
	var lean := -0.5 if (flying and moving) else (-0.15 if flying else 0.0)
	var model: Node3D = art.chief.get_child(0)
	model.rotation.x = lerpf(model.rotation.x, lean, minf(1.0, dt * 8.0))


## Real-time upkeep of the chief's fighting state, and the bars that show it.
func _update_combat_state(dt: float) -> void:
	var f := Combat.fighter(sim)
	f.safe = interior != null or not lookout.is_empty() or photo.active
	f.air = art.chief.position.y > 1.5
	var wants_block := Input.is_physical_key_pressed(KEY_Y) and get_viewport().gui_get_focus_owner() == null and interior == null and not flying
	Combat.set_block(sim, wants_block)
	Combat.tick(sim, dt)
	var show := Combat.engaged(sim) and not photo.active
	combat_hud.visible = show
	if show:
		_hp_bar.value = float(f.hp) / float(f.max_hp) * 100.0
		_stamina_bar.value = Combat.stamina_fraction(sim) * 100.0
		_combat_label.text = ("Bleeding   " if Combat.is_bleeding(sim) else "") + ("Blocking" if bool(f.block) else "")
	_down_label.visible = Combat.is_down(sim)
	if _down_label.visible:
		_down_label.text = "KNOCKED OUT   %d" % int(ceil(float(f.down_t)))
	shake = maxf(0.0, shake - dt * 1.8)
	hurt_flash.color.a = maxf(0.0, hurt_flash.color.a - dt * 1.6)


func _build_combat_ui(holder: Control) -> void:
	combat_hud = PanelContainer.new()
	(combat_hud as PanelContainer).add_theme_stylebox_override("panel", UiKit.box(UiKit.GLASS, 12, 8))
	combat_hud.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	combat_hud.offset_left = -170
	combat_hud.offset_right = 170
	combat_hud.offset_top = -258
	combat_hud.offset_bottom = -196
	combat_hud.visible = false
	holder.add_child(combat_hud)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	combat_hud.add_child(col)
	_hp_bar = UiKit.bar(320.0, 12.0, UiKit.BAD)
	col.add_child(_hp_bar)
	_stamina_bar = UiKit.bar(320.0, 8.0, UiKit.GOOD)
	col.add_child(_stamina_bar)
	_combat_label = UiKit.label(col, "", 11, UiKit.WARN)
	_down_label = UiKit.label(holder, "", 44, UiKit.BAD)
	_down_label.set_anchors_preset(Control.PRESET_CENTER)
	_down_label.offset_left = -220
	_down_label.offset_right = 220
	_down_label.offset_top = -80
	_down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_down_label.visible = false
	hurt_flash = ColorRect.new()
	hurt_flash.color = Color(0.8, 0.05, 0.05, 0.0)
	hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(hurt_flash)


func _toggle_flight() -> void:
	if interior != null or not lookout.is_empty():
		return
	flying = not flying
	hud.toast("Flying on: W A S D to fly, E up, Q down. Press Z to land." if flying else "Landing...", "star", UiKit.INK)


## The gate closest to the chief within `reach` tiles ({} if none).
func _gate_near(reach: float) -> Dictionary:
	var here := Vector2(art.chief.position.x, art.chief.position.z) / CityMap.TILE
	var best := {}
	var best_d := reach
	for g in Walls.gates(sim):
		var d := here.distance_to(Walls.gate_points(g).mid)
		if d < best_d:
			best_d = d
			best = g
	return best


## Open or bar the gates (they all follow the chief's word for a few hours).
func _toggle_gates() -> void:
	var open_now := bool(Walls.gates(sim)[0].get("open", true)) if not Walls.gates(sim).is_empty() else true
	var msg := Walls.set_override(sim, "closed" if open_now else "open")
	hud.toast(msg, "star", UiKit.INK)


## Would this step carry the chief through a wall (or a shut gate)? Only an open gate lets anyone pass.
func _wall_in_way(from: Vector3, step: Vector3) -> bool:
	if step.length() < 0.0001:
		return false
	var reach := step + step.normalized() * 0.5
	var a := Vector2(from.x, from.z) / CityMap.TILE
	var b := Vector2(from.x + reach.x, from.z + reach.z) / CityMap.TILE
	return not Walls.blocks(sim, a, b).is_empty()


func _update_chief(dt: float) -> void:
	if photo.active:
		return
	if interior != null:
		_update_chief_inside(dt)
		return
	if not lookout.is_empty():
		_update_chief_lookout(dt)
		return
	# Never stay trapped: if a building went up under the chief, step out to the nearest open tile.
	var here := CityMap.world_to_tile(art.chief.position)
	if sim.map.solid_tiles.has(here):
		var free := sim.map.nearest_walkable(here)
		var spot := CityMap.tile_to_world(free)
		art.chief.position = Vector3(spot.x, art.chief.position.y, spot.z)
	var moving := false
	var running := false
	var face := Vector3.ZERO
	var typing := get_viewport().gui_get_focus_owner() != null
	var down := Combat.is_down(sim)
	if Combat.consume_respawn(sim):
		art.chief.position = CityMap.tile_pos_to_world(Vector2(2.5, 4.5))
		flying = false
		fly_alt = 0.0
		chief_mode = ""
	if down:
		chief_mode = "die"
		chief_mode_time = 0.2
	elif dash_t > 0.0:
		var dash_step := dash_dir * 17.0 * dt
		var dash_from := art.chief.position
		if not _move_blocked(dash_from, Vector3(dash_step.x, 0, 0)):
			art.chief.position.x += dash_step.x
		if not _move_blocked(art.chief.position, Vector3(0, 0, dash_step.z)):
			art.chief.position.z += dash_step.z
		dash_t -= dt
		moving = true
		face = dash_dir
		art.chief.get_child(0).rotation.x = -TAU * (1.0 - clampf(dash_t / Combat.DODGE_DASH, 0.0, 1.0))
		if dash_t <= 0.0:
			art.chief.get_child(0).rotation.x = 0.0
	elif not typing and not pie.is_open():
		var input := Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), 0, float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		var turn := float(Input.is_physical_key_pressed(KEY_Q)) - float(Input.is_physical_key_pressed(KEY_E))
		if overview:
			if input.length() > 0.0:
				overview_focus += input.rotated(Vector3.UP, yaw) * dt * (overview_dist * 0.55)
			yaw += turn * dt
		elif input.length() > 0.0:
			running = Input.is_physical_key_pressed(KEY_SHIFT)
			var dir := input.normalized().rotated(Vector3.UP, yaw)
			var step := dir * (RUN_SPEED if running else WALK_SPEED) * dt * (FLY_SPEED_MUL if flying else 1.0)
			var from := art.chief.position
			if not _move_blocked(from, Vector3(step.x, 0, 0)):
				art.chief.position.x += step.x
			if not _move_blocked(art.chief.position, Vector3(0, 0, step.z)):
				art.chief.position.z += step.z
			moving = from.distance_to(art.chief.position) > 0.001
			face = dir
	if chief_mode_time > 0.0:
		chief_mode_time -= dt
		if chief_mode_time <= 0.0:
			chief_mode = ""
	_update_flight(dt, moving)
	if not down and dash_t <= 0.0 and bool(Combat.fighter(sim).block) and not moving and chief_mode == "":
		chief_mode = "holding-both"
		chief_mode_time = 0.1
	art.animate_chief(face, moving, running, chief_mode, dt)
	Combat.set_facing(sim, Vector2(sin(art.chief.rotation.y), cos(art.chief.rotation.y)))


func _nearest_resident_to_chief(radius: float) -> int:
	if interior != null:
		var near := -1
		var near_d := radius * 0.25
		for i in interior.actor_indices():
			var d := _interior_actor_distance(int(i))
			if d < near_d:
				near_d = d
				near = int(i)
		return near
	var best := -1
	var best_d := radius
	for i in range(art.actors.size()):
		if not art.actors[i].visible:
			continue
		var d := art.actors[i].position.distance_to(art.chief.position)
		if d < best_d:
			best_d = d
			best = i
	return best


# --- camera ------------------------------------------------------------------------------------------------------

func _update_camera(dt: float) -> void:
	if photo.active:
		_photo_fly(dt)
		return
	var want_target := overview_focus if overview else art.chief.position + Vector3(0, 0.7 if interior != null else 1.5, 0)
	var want_dist := overview_dist if overview else chase_dist
	var want_pitch := 0.95 if overview else chase_pitch
	var k := 1.0 - exp(-dt * 7.0)
	cam_target = cam_target.lerp(want_target, k)
	cam_dist = lerpf(cam_dist, want_dist, k)
	cam_pitch = lerpf(cam_pitch, want_pitch, k)
	var offset := Vector3(0, sin(cam_pitch), cos(cam_pitch)) * cam_dist
	camera.position = cam_target + offset.rotated(Vector3.UP, yaw)
	camera.position.y = maxf(camera.position.y, 0.6)
	if shake > 0.0:
		camera.position += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * 0.35
	camera.look_at(cam_target)


func _toggle_overview() -> void:
	overview = not overview
	art.set_frontier_visible(overview)
	if overview:
		overview_focus = Vector3(art.chief.position.x, 0, art.chief.position.z)
		hud.toast("Overview: click land to claim it, or a free lot to build.", "town", UiKit.INK)
	else:
		build_kind = ""
	hud.set_hint("")


func _screen_of(p: Vector3) -> Vector2:
	return camera.unproject_position(p)


func ground_point(screen: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)


# --- picking and hover --------------------------------------------------------------------------------------------

func pick(screen: Vector2) -> Dictionary:
	var best := -1
	var best_d := 44.0
	for i in range(art.actors.size()):
		if not art.actors[i].visible:
			continue
		var anchor := art.actors[i].position + Vector3(0, 0.9, 0)
		if camera.is_position_behind(anchor):
			continue
		var d := _screen_of(anchor).distance_to(screen)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		return {"type": "resident", "index": best}
	var focal := get_viewport().get_visible_rect().size.y / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	var pick_building := {}
	var pick_d := 1e9
	for b in sim.buildings:
		var entry: Dictionary = art.building_nodes.get(int(b.id), {})
		var height := float(entry.get("height", 3.0))
		var center := CityMap.tile_to_world(sim.tile_of(b)) + Vector3(0, minf(height * 0.45, 2.2), 0)
		if camera.is_position_behind(center):
			continue
		var dist := camera.global_position.distance_to(center)
		var radius := 2.4 * focal / maxf(dist, 1.0)
		var d := _screen_of(center).distance_to(screen)
		if d < radius and dist < pick_d:
			pick_d = dist
			pick_building = b
	if not pick_building.is_empty():
		return {"type": "building", "id": int(pick_building.id)}
	var hit: Variant = ground_point(screen)
	if hit == null:
		return {"type": "none"}
	var g: Vector3 = hit
	var tile := CityMap.world_to_tile(g)
	var building := sim.building_at_tile(tile)
	if not building.is_empty():
		return {"type": "building", "id": int(building.id)}
	var district := CityMap.district_of(tile)
	if not sim.map.claimed.has(district) and sim.map.frontier().has(district):
		return {"type": "frontier", "district": district}
	if sim.map.is_buildable(tile):
		return {"type": "lot", "tile": tile}
	return {"type": "ground", "tile": tile}


func _update_hover() -> void:
	overlay.hover_text = ""
	art.clear_hover_zone()
	if pie.is_open() or build_kind != "" or not hud.root.visible:
		return
	var mouse := get_viewport().get_mouse_position()
	if get_viewport().gui_get_hovered_control() != null or look_drag:
		return
	var hit := pick(mouse)
	overlay.hover_pos = mouse
	match str(hit.type):
		"resident":
			var i: int = hit.index
			overlay.hover_text = "%s  ·  click to interact" % sim.residents[i].name
			art.set_hover_rect(art.actors[i].position, 1.6, 1.6)
		"building":
			var b := sim.building_by_id(int(hit.id))
			overlay.hover_text = "%s  ·  click" % Catalog.label(str(b.kind))
			art.set_hover_rect(CityMap.tile_to_world(sim.tile_of(b)), 3.9, 3.9)
		"frontier":
			var d: Vector2i = hit.district
			var why := sim.claim_blocker(d)
			overlay.hover_text = "Claim this land  ·  %d coins" % sim.claim_cost(d) if why == "" else why
			art.set_hover_rect(Vector3(d.x * CityArt.DISTRICT_UNITS + 6.0, 0, d.y * CityArt.DISTRICT_UNITS + 6.0), 15.0, 15.0)
		"lot":
			overlay.hover_text = "Free lot  ·  click to build"
			art.set_hover_rect(CityMap.tile_to_world(hit.tile), 3.9, 3.9)


## Build-mode preview: the lot turns green when the spot is valid, red (with the reason) when not.
func _update_ghost() -> void:
	if build_kind == "" or pie.is_open() or get_viewport().gui_get_hovered_control() != null:
		ghost.position.y = -10.0
		return
	var mouse := get_viewport().get_mouse_position()
	var hit: Variant = ground_point(mouse)
	if hit == null:
		ghost.position.y = -10.0
		return
	var tile := CityMap.world_to_tile(hit)
	var why := sim.build_blocker(build_kind, tile)
	ghost.position = CityMap.tile_to_world(tile) + Vector3(0, 0.2, 0)
	(ghost.material_override as StandardMaterial3D).albedo_color = Color(0.4, 0.85, 0.5, 0.5) if why == "" else Color(0.9, 0.3, 0.25, 0.5)
	overlay.hover_pos = mouse
	overlay.hover_text = "Click to place the %s" % Catalog.label(build_kind).to_lower() if why == "" else why


# --- input ---------------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if photo.active:
		_photo_input(event)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if build_kind != "":
					build_kind = ""
					hud.set_hint("")
				else:
					look_drag = true
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif look_drag:
				look_drag = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if overview:
				overview_dist = maxf(24.0, overview_dist - 6.0)
			else:
				chase_dist = maxf(2.8, chase_dist - 0.6)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if overview:
				overview_dist = minf(160.0, overview_dist + 6.0)
			else:
				chase_dist = minf(16.0, chase_dist + 0.6)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(mb)
	elif event is InputEventMouseMotion and look_drag:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * 0.0045
		chase_pitch = clampf(chase_pitch + motion.relative.y * 0.0035, 0.06, 1.25)
	elif event is InputEventKey and event.pressed and not event.echo:
		if advice_panel.visible and event.keycode >= KEY_1 and event.keycode <= KEY_4:
			_answer_advice_number(event.keycode - KEY_1)
			return
		match event.keycode:
			KEY_SPACE:
				if speed == 0.0:
					speed = last_speed
				else:
					last_speed = speed
					speed = 0.0
			KEY_1: speed = 1.0; last_speed = 1.0
			KEY_2: speed = 3.0; last_speed = 3.0
			KEY_3: speed = 8.0; last_speed = 8.0
			KEY_TAB: _toggle_overview()
			KEY_BRACKETRIGHT: _select((selected + 1) % sim.residents.size())
			KEY_BRACKETLEFT: _select((selected - 1 + sim.residents.size()) % sim.residents.size())
			KEY_H: hud.root.visible = not hud.root.visible
			KEY_BACKSLASH: hud.toggle_drawer()
			KEY_B: hud.show_tab(4)
			KEY_C: hud.show_tab(3)
			KEY_E: _interact_key()
			KEY_T: _open_chat(_conversation_target())
			KEY_V: _on_mic_pressed()
			KEY_O: _toggle_orders()
			KEY_G: _toggle_furnish()
			KEY_K: _toggle_market()
			KEY_J: _toggle_journal()
			KEY_Z: _toggle_flight()
			KEY_X: hud.toast(str(Weapons.chief_cycle(sim).message), "guard", UiKit.INK)
			KEY_P: _toggle_photo()
			KEY_F10: menu_panel.open() if not menu_panel.visible else menu_panel.close()
			KEY_F: _chief_attack()
			KEY_R: _chief_attack(true)
			KEY_CTRL: _chief_dodge()
			KEY_M: hud.voice_replies_toggled.emit()
			KEY_ESCAPE:
				if menu_panel.visible:
					menu_panel.close()
					return
				var busy := build_kind != "" or voice.listening or hud.chat.chatting or advice_panel.visible or orders_panel.visible or market_panel.visible or furnish_panel.visible or journal_panel.visible or pie.is_open()
				if not busy:
					menu_panel.open()
					return
				journal_panel.close()
				build_kind = ""
				hud.set_hint("")
				if voice.listening:
					voice.stop_listening(true)
				if hud.chat.chatting:
					hud.chat.close()
				advice_panel.close()
				orders_panel.close()
				market_panel.close()
				furnish_panel.close()
				pie.close()


## The chief swings at the nearest monster within reach.
func _chief_attack(heavy: bool = false) -> void:
	if not lookout.is_empty():
		_lookout_fire()
		return
	if interior != null or Combat.is_down(sim):
		return
	# Turn to the nearest foe in front of you so a swing finds it.
	var here := Vector2(art.chief.position.x, art.chief.position.z) / CityMap.TILE
	var nearest := Survival.nearest_mob(sim, here, Weapons.chief_reach(sim) + 1.5)
	if not nearest.is_empty():
		var to_foe := Vector2(float(nearest.pos[0]), float(nearest.pos[1])) - here
		art.chief.rotation.y = atan2(to_foe.x, to_foe.y)
	Combat.set_facing(sim, Vector2(sin(art.chief.rotation.y), cos(art.chief.rotation.y)))
	var res := Combat.attack(sim, heavy)
	if not bool(res.swung):
		if str(res.message) != "":
			hud.toast(str(res.message), "close", UiKit.WARN)
		return
	if sim.chief_weapon == "bow":
		chief_mode = "holding-right-shoot"
		chief_mode_time = 0.45
	elif heavy:
		chief_mode = "attack-kick-left"
		chief_mode_time = 0.75
	else:
		chief_mode = ["attack-melee-right", "attack-melee-left", "attack-kick-right"][clampi(int(res.combo) - 1, 0, 2)]
		chief_mode_time = 0.4
	if int(res.hits) > 0:
		shake = maxf(shake, 0.25 if heavy else 0.12)
	if int(res.kills) > 0:
		hud.toast("%d down." % int(res.kills) if int(res.kills) > 1 else "Down!", "guard", UiKit.GOOD)


func _chief_dodge() -> void:
	if interior != null or not lookout.is_empty() or flying or Combat.is_down(sim):
		return
	var input := Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), 0, float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var dir := input.normalized().rotated(Vector3.UP, yaw) if input.length() > 0.0 else -Vector3(sin(art.chief.rotation.y), 0, cos(art.chief.rotation.y))
	if Combat.dodge(sim):
		dash_t = Combat.DODGE_DASH
		dash_dir = dir.normalized()


func _interact_key() -> void:
	if interior != null:
		_interior_interact()
		return
	if not lookout.is_empty():
		_descend_tower()
		return
	if flying:
		return
	if not _gate_near(2.6).is_empty():
		_toggle_gates()
		return
	var tower := _tower_near(4.5)
	if not tower.is_empty() and _nearest_resident_to_chief(5.0) < 0:
		_climb_tower(int(tower.id))
		return
	if _advice_waiting() and _advice_in_range():
		_open_advice()
		return
	var near := _nearest_resident_to_chief(INTERACT_RANGE)
	if near >= 0:
		_select(near)
		_open_resident_pie(near, _screen_of(art.actors[near].position + Vector3(0, 1.0, 0)))


func _on_left_click(mb: InputEventMouseButton) -> void:
	if interior != null:
		_interior_click(mb.position)
		return
	if build_kind != "":
		var hit: Variant = ground_point(mb.position)
		if hit == null:
			return
		var tile := CityMap.world_to_tile(hit)
		var result := sim.place_building(build_kind, tile)
		var ok := result.begins_with("Started")
		hud.toast(result, "build" if ok else "close", UiKit.GOOD if ok else UiKit.BAD)
		return
	var picked := pick(mb.position)
	match str(picked.type):
		"resident":
			if _advice_waiting() and int(sim.advice.resident) == int(picked.index) and _advice_in_range():
				_open_advice()
				return
			_select(int(picked.index))
			_open_resident_pie(int(picked.index), mb.position)
		"building":
			_open_building_pie(int(picked.id), mb.position)
		"frontier":
			_open_frontier_pie(picked.district, mb.position)
		"lot":
			_open_lot_pie(picked.tile, mb.position)


# --- pie menus -------------------------------------------------------------------------------------------------------

func _command(i: int, action: String) -> void:
	var result := sim.command(i, action)
	var ok: bool = result.get("ok", false)
	hud.toast(str(result.message), "check" if ok else "close", UiKit.GOOD if ok else UiKit.WARN)


func _chief_near(i: int) -> bool:
	if interior != null:
		return _interior_actor_distance(i) <= TALK_RANGE * 0.25
	return art.actors[i].position.distance_to(art.chief.position) <= TALK_RANGE


func _social(i: int, kind: String) -> void:
	if not _chief_near(i):
		hud.toast("Walk closer to %s first." % sim.residents[i].name, "social", UiKit.WARN)
		return
	var r: Dictionary = sim.residents[i]
	var toward := art.actors[i].position - art.chief.position
	art.chief.rotation.y = atan2(toward.x, toward.z)
	chief_mode = "emote-yes" if kind != "hug" else "interact-right"
	chief_mode_time = 2.0
	var lines: Array = PLAYER_LINES.get(kind, ["Hello %s."])
	overlay.chief_say(str(lines[randi() % lines.size()]) % r.name)
	var result := sim.player_interact(i, kind)
	var ok: bool = result.get("ok", false) and result.get("success", true)
	hud.toast(str(result.message), "heart" if ok and kind != "argue" else "close", UiKit.SOCIAL if ok else UiKit.WARN)


func _open_resident_pie(i: int, at: Vector2) -> void:
	_select(i)
	var r: Dictionary = sim.residents[i]
	var social: Array = []
	for kind in ["chat", "joke", "compliment", "gossip", "hug", "argue"]:
		var k: String = kind
		var spec: Dictionary = Social.KINDS[k]
		var why := sim.social_blocker(i, -1, k)
		social.append({"label": spec.label, "icon": spec.icon, "color": UiKit.BAD if k == "argue" else UiKit.SOCIAL, "enabled": why == "", "hint": why if why != "" else "Bond %+d" % int(spec.bond), "action": func() -> void: _social(i, k)})
	social.append({"label": "Share a meal", "icon": "meal", "color": Color("e8955a"), "enabled": sim.meals > 0, "hint": "" if sim.meals > 0 else "No meals left", "action": func() -> void: _social(i, "share_meal")})
	var needs: Array = []
	for a in ["eat", "sleep", "wash", "rest"]:
		var act: String = a
		needs.append({"label": LifeSim.ACTION_VERBS[act], "icon": act, "color": UiKit.WARN, "enabled": sim.has_target(act), "hint": "" if sim.has_target(act) else "Nowhere yet", "action": func() -> void: _command(i, act)})
	var activities: Array = []
	for a in ["work", "study", "farm", "cook", "exercise", "play", "gather", "socialize"]:
		var act2: String = a
		activities.append({"label": LifeSim.ACTION_VERBS[act2], "icon": act2, "color": UiKit.GOOD, "enabled": sim.has_target(act2), "hint": "" if sim.has_target(act2) else "Nowhere yet", "action": func() -> void: _command(i, act2)})
	var items := [
		{"label": "Talk", "icon": "talk", "color": Color("8ed0e8"), "hint": "Chat or speak", "action": func() -> void: _open_chat(i)},
		{"label": "Social", "icon": "social", "color": UiKit.SOCIAL, "hint": "Interact", "children": social},
		{"label": "Needs", "icon": "hunger", "color": UiKit.WARN, "hint": "Eat, sleep...", "children": needs},
		{"label": "Activities", "icon": "work", "color": UiKit.GOOD, "hint": "Work, study...", "children": activities},
		{"label": "Wishes", "icon": "star", "color": UiKit.ACCENT, "hint": "Inspect", "action": func() -> void: hud.show_tab(1)},
	]
	pie.open(at, str(r.name), sim.emotion(r).capitalize(), items)


func _open_building_pie(id: int, at: Vector2) -> void:
	var b := sim.building_by_id(id)
	if b.is_empty():
		return
	var r: Dictionary = sim.residents[selected]
	var kind: String = b.kind
	var items: Array = []
	if int(b.level) >= 1:
		for a in LifeSim.KIND_ACTIONS.get(kind, []):
			var act: String = a
			items.append({"label": LifeSim.ACTION_VERBS[act], "icon": act, "color": UiKit.GOOD, "hint": "%s goes" % r.name, "action": func() -> void: _command(selected, act)})
		var blocker := sim.upgrade_blocker(id)
		if Catalog.max_level(kind) > 1:
			items.append({"label": "Upgrade", "icon": "upgrade", "color": UiKit.ACCENT, "enabled": blocker == "", "hint": blocker if blocker != "" else "Level %d" % (int(b.level) + 1), "action": func() -> void:
				var msg := sim.upgrade_building(id)
				hud.toast(msg, "build" if msg == "Upgrade started." else "close", UiKit.GOOD if msg == "Upgrade started." else UiKit.WARN)})
	else:
		items.append({"label": "Help build", "icon": "build", "color": UiKit.GOOD, "hint": "%s works on it" % r.name, "action": func() -> void: _command(selected, "work")})
	if str(kind) == "gate" and int(b.level) >= 1:
		var is_open := bool(b.get("open", true))
		items.append({"label": "Bar gates" if is_open else "Open gates", "icon": "guard", "color": UiKit.ACCENT, "hint": "All gates", "action": func() -> void: _toggle_gates()})
	if str(kind) == "watchtower" and int(b.level) >= 1:
		items.append({"label": "Climb", "icon": "guard", "color": UiKit.ACCENT, "hint": "Lookout", "action": func() -> void: _climb_tower(id)})
	if Interiors.enterable(b):
		items.append({"label": "Enter", "icon": "home", "color": UiKit.ACCENT, "hint": "Go inside", "action": func() -> void: _enter_building(id)})
	items.append({"label": "City", "icon": "town", "color": UiKit.INK, "hint": "Overview", "action": func() -> void: hud.show_tab(3)})
	var subtitle := "Level %d" % int(b.level) if int(b.level) >= 1 else "%d%% built" % int(float(b.progress))
	pie.open(at, Catalog.label(kind), subtitle, items)


func _open_lot_pie(tile: Vector2i, at: Vector2) -> void:
	var items: Array = []
	for kind in Catalog.BUILDABLE:
		var k: String = kind
		var why := sim.build_blocker(k, tile)
		var cost := Catalog.cost(k, 1)
		items.append({"label": Catalog.label(k), "icon": Catalog.spec(k).icon, "color": UiKit.ACCENT, "enabled": why == "", "hint": why if why != "" else "%d coins" % int(cost.coins), "action": func() -> void:
			var msg := sim.place_building(k, tile)
			var ok := msg.begins_with("Started")
			hud.toast(msg, "build" if ok else "close", UiKit.GOOD if ok else UiKit.BAD)})
	pie.open(at, "Free lot", "Build here", items)


func _open_frontier_pie(district: Vector2i, at: Vector2) -> void:
	var why := sim.claim_blocker(district)
	var items := [{"label": "Claim land", "icon": "town", "color": UiKit.ACCENT, "enabled": why == "", "hint": why if why != "" else "%d coins" % sim.claim_cost(district), "action": func() -> void:
		var msg := sim.claim_district(district)
		hud.toast(msg, "town" if msg == "District claimed." else "close", UiKit.GOOD if msg == "District claimed." else UiKit.WARN)}]
	# Wall or gate the border edge between this land and the village.
	for i in range(4):
		var inside: Vector2i = district + Walls.SIDES[i]
		if sim.map.claimed.has(inside):
			var side: int = [1, 0, 3, 2][i]
			var wall_why := Walls.place_blocker(sim, inside, side)
			items.append({"label": "Wall here", "icon": "guard", "color": UiKit.INK, "enabled": wall_why == "", "hint": wall_why if wall_why != "" else "%d coins" % int(Catalog.cost("wall", 1).coins), "action": func() -> void:
				var msg := Walls.place(sim, inside, side, false)
				hud.toast(msg, "build" if msg.begins_with("Started") else "close", UiKit.GOOD if msg.begins_with("Started") else UiKit.WARN)})
			items.append({"label": "Gate here", "icon": "guard", "color": UiKit.INK, "enabled": wall_why == "" or wall_why == "There is already a wall here.", "hint": "Opening for traffic", "action": func() -> void:
				var msg2 := Walls.place(sim, inside, side, true)
				hud.toast(msg2, "build" if msg2.begins_with("Started") else "close", UiKit.GOOD if msg2.begins_with("Started") else UiKit.WARN)})
			break
	pie.open(at, "New land", "%d trees to clear" % sim.map.district_trees(district), items)


func _approve_plan(option: Dictionary) -> void:
	var result := sim.apply_option(option, "The chief")
	var ok := result.begins_with("Started") or result == "Upgrade started." or result == "District claimed."
	hud.toast("Approved: %s" % str(option.label) if ok else result, "check" if ok else "close", UiKit.GOOD if ok else UiKit.WARN)
	plans_timer = 0.0


# --- talking: chat and voice ------------------------------------------------------------------------------------------

## Who you are talking to: the resident right in front of you, else the selected one.
func _conversation_target() -> int:
	var near := _nearest_resident_to_chief(TALK_RANGE)
	return near if near >= 0 else selected


func _open_chat(i: int) -> void:
	_tut("talk")
	selected = clampi(i, 0, sim.residents.size() - 1)
	var r: Dictionary = sim.residents[selected]
	var emo := sim.emotion(r)
	hud.chat.open_for(selected, str(r.name), "%s  ·  %s" % [r.trait, emo.capitalize()], hud._look_texture(r), UiKit.EMOTION_COLOR.get(emo, UiKit.INK))
	hud.chat.focus_input()


func _on_mic_pressed() -> void:
	if voice.transcribing:
		return
	if voice.listening:
		voice.stop_listening()
		return
	if advice_panel.visible:
		mic_target = int(sim.advice.resident)
	else:
		mic_target = _conversation_target()
		_open_chat(mic_target)
		hud.chat._input.release_focus()
	voice.stop_speaking()
	voice.start_listening()
	hud.toast("Listening to you, talking to %s." % sim.residents[mic_target].name, "mic", UiKit.BAD)
	_refresh_voice()


func _on_transcribed(text: String) -> void:
	var target := mic_target if mic_target >= 0 else selected
	overlay.chief_say(text)
	if advice_panel.visible and not sim.advice.is_empty():
		var choice := Advice.interpret(text, sim.advice.options)
		if choice == -2:
			hud.toast("I couldn't tell which option you meant. Try \"the first one\" or \"not now\".", "mic", UiKit.WARN)
			director.speak_to_chief(int(sim.advice.resident), "Sorry Chief, which did you mean?")
		else:
			_answer_advice(choice)
		_refresh_voice()
		return
	if hud.chat.index != target or not hud.chat.chatting:
		_open_chat(target)
	hud.chat.submit(text)
	_refresh_voice()


func _on_chat_sent(i: int, text: String) -> void:
	var order := Orders.parse(text, sim)
	if str(order.intent) != "chat":
		if i < 0 and str(order.scope) == "default":
			order.scope = "all"
		hud.chat.add_message(i, false, "Orders", _execute_order(order, i if i >= 0 else selected))
		return
	if i < 0:
		_broadcast_chat(text)
		return
	var r: Dictionary = sim.residents[i]
	sim.remember(r, "The chief said: " + text.left(300))
	sim.log_event("You to %s: %s" % [r.name, text.left(120)])
	r.bond = minf(100.0, float(r.bond) + 0.8)
	sim._check_wants(r)
	sim.talk_with[i] = -1
	if ai_enabled and ai.enabled:
		hud.chat.set_typing(true, str(r.name))
		var history := hud.chat.history(i)
		if not history.is_empty():
			history.pop_back()  # the current message is already in player_message
		ai.request("chat", sim.observation(i, text.left(600), history), {"i": i, "text": text}, 28.0)
	else:
		_local_reply(i, text)


func _local_reply(i: int, text: String, to_all: bool = false) -> void:
	var r: Dictionary = sim.residents[i]
	_deliver_reply(i, Social.chat_reply(str(r.name), str(r.trait), sim.emotion(r), text, sim.rng), to_all)


## Speaking to the whole village with no order in it: the two nearest residents answer.
func _broadcast_chat(text: String) -> void:
	var order: Array = range(sim.residents.size())
	order.sort_custom(func(a: int, b: int) -> bool: return art.actors[a].position.distance_squared_to(art.chief.position) < art.actors[b].position.distance_squared_to(art.chief.position))
	var replying := order.slice(0, mini(2, order.size()))
	for i in replying:
		var r: Dictionary = sim.residents[i]
		sim.remember(r, "The chief said to everyone: " + text.left(300))
		if ai_enabled and ai.enabled:
			hud.chat.set_typing(true, "The villagers")
			ai.request("chat", sim.observation(i, "(to everyone) " + text.left(600), []), {"i": i, "text": text, "all": true}, 28.0)
		else:
			_local_reply(i, text, true)


## Carry out an order. Returns the message shown to the chief.
func _execute_order(order: Dictionary, default_index: int) -> String:
	_tut("order")
	var result := Orders.execute(sim, order, default_index)
	var message := str(result.message)
	match str(result.ui):
		"hush":
			director.hush()
		"unhush":
			director.unhush()
		"pause":
			if speed > 0.0:
				last_speed = speed
			speed = 0.0
		"resume":
			speed = last_speed if last_speed > 0.0 else 1.0
		"faster":
			speed = 8.0 if speed >= 3.0 else 3.0
			last_speed = speed
		"slower":
			speed = 3.0 if speed > 3.0 else 1.0
			last_speed = speed
	var ack_text := str(result.ack_text)
	var ack_who := int(result.ack_who)
	if bool(result.ok) and ack_text != "" and ack_who >= 0 and ack_who < sim.residents.size() and str(result.ui) != "hush":
		sim.say(ack_who, ack_text)
		if voice_replies:
			director.speak_to_chief(ack_who, ack_text)
	hud.toast(message, "check" if bool(result.ok) else "close", UiKit.GOOD if bool(result.ok) else UiKit.WARN)
	sim.log_event("Order: " + message)
	plans_timer = 0.0
	return message


func _toggle_orders() -> void:
	if orders_panel.visible:
		orders_panel.close()
	else:
		advice_panel.close()
		market_panel.close()
		orders_panel.visible = true


func _toggle_market() -> void:
	_tut("market")
	if market_panel.visible:
		market_panel.close()
	else:
		advice_panel.close()
		orders_panel.close()
		market_panel.visible = true
		market_panel.refresh()


func _market_trade(action: String, item: String, amount: int) -> void:
	var result: Dictionary
	if action == "route":
		result = Caravans.open_route(sim)
	elif item.begins_with("c_"):
		result = Caravans.buy(sim, item, amount)
	elif Economy.is_animal_key(item):
		result = Economy.trade_animal(sim, action, item.substr(2), amount)
	else:
		result = Economy.trade(sim, action, item, amount)
	hud.toast(str(result.message), "coin" if bool(result.ok) else "close", UiKit.GOOD if bool(result.ok) else UiKit.WARN)
	if bool(result.ok):
		sim.log_event("Market: " + str(result.message))
	market_panel.refresh()


func _deliver_reply(i: int, text: String, to_all: bool = false) -> void:
	var r: Dictionary = sim.residents[i]
	if to_all:
		hud.chat.add_message(-1, false, str(r.name), text)
	else:
		hud.chat_reply(i, str(r.name), text)
	hud.chat.set_typing(false)
	sim.remember(r, "I told the chief: " + text.left(200))
	director.speak_to_chief(i, text)


# --- advice ----------------------------------------------------------------------------------------------------------

func _advice_waiting() -> bool:
	return not sim.advice.is_empty() and str(sim.advice.state) == "waiting"


func _advice_in_range() -> bool:
	var i := int(sim.advice.resident)
	return i < art.actors.size() and art.actors[i].position.distance_to(art.chief.position) <= INTERACT_RANGE


func _tick_advice_ui() -> void:
	var view := get_viewport().get_visible_rect().size
	if advice_panel.visible:
		advice_panel.reset_size()
		advice_panel.position = Vector2((view.x - advice_panel.size.x) * 0.5, view.y - 190.0 - advice_panel.size.y)
	furnish_button.visible = interior != null
	if furnish_panel.visible:
		furnish_panel.reset_size()
		furnish_panel.position = Vector2((view.x - furnish_panel.size.x) * 0.5, maxf(60.0, (view.y - furnish_panel.size.y) * 0.5 - 20.0))
	if market_panel.visible:
		market_panel.reset_size()
		market_panel.position = Vector2((view.x - market_panel.size.x) * 0.5, maxf(60.0, (view.y - market_panel.size.y) * 0.5 - 20.0))
	if orders_panel.visible:
		orders_panel.reset_size()
		orders_panel.position = Vector2((view.x - orders_panel.size.x) * 0.5, maxf(60.0, (view.y - orders_panel.size.y) * 0.5 - 20.0))
		orders_panel.set_selected_name(str(sim.residents[selected].name))
	if sim.advice.is_empty():
		advice_panel.close()
		return
	if int(sim.advice.id) != advice_polished:
		advice_polished = int(sim.advice.id)
		if ai_enabled and ai.enabled:
			ai.request("advise", Advice.payload(sim, sim.advice), {"advice": advice_polished}, 20.0)


func _open_advice() -> void:
	var i := int(sim.advice.resident)
	sim.advice.opened = true
	ai.cancel_all("advise")
	hud.chat.close()
	pie.close()
	var r: Dictionary = sim.residents[i]
	advice_panel.open_for(sim.advice, str(r.name), hud._look_texture(r))
	voice.stop_speaking()
	director.speak_to_chief(i, str(sim.advice.question))
	selected = i


func _answer_advice(option_id: int) -> void:
	if sim.advice.is_empty():
		return
	_tut("advice")
	var message := sim.resolve_advice(option_id)
	advice_panel.close()
	if message != "":
		hud.toast(message, "check", UiKit.GOOD)


func _answer_advice_number(n: int) -> void:
	var real: Array = sim.advice.options.filter(func(o: Dictionary) -> bool: return int(o.id) >= 0)
	if n < real.size():
		_answer_advice(int(real[n].id))


# --- the watchtower lookout --------------------------------------------------------------------------------------------

func _tower_near(radius: float) -> Dictionary:
	var best := {}
	var best_d := radius
	for b in sim.buildings:
		if str(b.kind) != "watchtower" or int(b.level) < 1:
			continue
		var at := CityMap.tile_to_world(sim.tile_of(b))
		var d := Vector2(at.x, at.z).distance_to(Vector2(art.chief.position.x, art.chief.position.z))
		if d < best_d:
			best_d = d
			best = b
	return best


func _lookout_reach() -> float:
	var tower := sim.building_by_id(int(lookout.id))
	return 16.0 + 3.0 * float(int(tower.level)) if not tower.is_empty() else 16.0


func _climb_tower(id: int) -> void:
	var b := sim.building_by_id(id)
	if b.is_empty() or str(b.kind) != "watchtower" or int(b.level) < 1 or not lookout.is_empty() or interior != null:
		return
	var at := CityMap.tile_to_world(sim.tile_of(b))
	var deck := 2.6 + float(int(b.level)) * 1.1 + 0.3
	lookout = {"id": id, "tile": Vector2(float(sim.tile_of(b).x), float(sim.tile_of(b).y)), "centre": Vector3(at.x, deck, at.z), "pos": art.chief.position, "rot": art.chief.rotation.y, "dist": chase_dist, "pitch": chase_pitch}
	if overview:
		_toggle_overview()
	pie.close()
	art.chief.position = lookout.centre
	chase_dist = 8.0
	chase_pitch = 0.42
	hud.toast("You climb the watchtower. Fire at monsters with F.", "guard", UiKit.INK)


func _descend_tower() -> void:
	if lookout.is_empty():
		return
	art.chief.position = lookout.pos
	art.chief.rotation.y = float(lookout.rot)
	chase_dist = float(lookout.dist)
	chase_pitch = float(lookout.pitch)
	lookout = {}
	hud.set_hint("")


func _update_chief_lookout(dt: float) -> void:
	var typing := get_viewport().gui_get_focus_owner() != null
	var face := Vector3.ZERO
	var moving := false
	if not typing and not pie.is_open():
		var input := Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), 0, float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		if input.length() > 0.0:
			var dir := input.normalized().rotated(Vector3.UP, yaw)
			var next := art.chief.position + dir * 1.6 * dt
			var off := Vector2(next.x - lookout.centre.x, next.z - lookout.centre.z)
			if off.length() > 0.9:
				off = off.normalized() * 0.9
			art.chief.position = Vector3(lookout.centre.x + off.x, lookout.centre.y, lookout.centre.z + off.y)
			moving = true
			face = dir
	if chief_mode_time > 0.0:
		chief_mode_time -= dt
		if chief_mode_time <= 0.0:
			chief_mode = ""
	art.animate_chief(face, moving, false, chief_mode, dt)


func _lookout_fire() -> void:
	if lookout.is_empty() or fire_cooldown > 0.0:
		return
	var tower := sim.building_by_id(int(lookout.id))
	if tower.is_empty():
		_descend_tower()
		return
	var foe := Survival.nearest_mob(sim, lookout.tile, _lookout_reach())
	chief_mode = "interact-right"
	chief_mode_time = 0.4
	if foe.is_empty():
		hud.toast("Nothing in range.", "guard", UiKit.MUTED)
		return
	fire_cooldown = 1.1
	if Survival.tower_fire(sim, tower, foe):
		hud.toast("Got it! The %s falls." % str(Survival.KINDS[str(foe.kind)].label).to_lower(), "guard", UiKit.GOOD)


# --- indoors ------------------------------------------------------------------------------------------------------------

## The chief's place in tile units, indoors counted as standing at the building's door.
func _chief_tile() -> Vector2:
	if not lookout.is_empty():
		return lookout.tile
	if interior != null and outdoor.has("tile"):
		return outdoor.tile
	return Vector2(art.chief.position.x, art.chief.position.z) / CityMap.TILE


func _building_near_door(radius: float) -> Dictionary:
	var best := {}
	var best_d := radius
	for b in sim.buildings:
		if not Interiors.enterable(b):
			continue
		var door := CityMap.tile_to_world(Vector2i(int(b.door[0]), int(b.door[1])))
		var d := Vector2(door.x, door.z).distance_to(Vector2(art.chief.position.x, art.chief.position.z))
		if d < best_d:
			best_d = d
			best = b
	return best


func _owner_note(b: Dictionary) -> String:
	if str(b.kind) != "home":
		return ""
	var names := Ownership.occupants(sim, b)
	if names.is_empty():
		return ""
	return " (%s's home)" % names[0] if names.size() == 1 else " (%s's family home)" % names[0]


func _enter_building(id: int) -> void:
	if interior != null:
		return
	var b := sim.building_by_id(id)
	if b.is_empty() or not Interiors.enterable(b):
		hud.toast("That building isn't finished yet.", "close", UiKit.WARN)
		return
	var door := CityMap.tile_to_world(Vector2i(int(b.door[0]), int(b.door[1])))
	if Vector2(door.x, door.z).distance_to(Vector2(art.chief.position.x, art.chief.position.z)) > 12.0:
		hud.toast("Walk to the building's door first.", "close", UiKit.WARN)
		return
	pie.close()
	hud.chat.close()
	advice_panel.close()
	orders_panel.close()
	market_panel.close()
	director.hush(1.0)
	var model: Node3D = art.chief.get_child(0)
	outdoor = {"pos": art.chief.position, "rot": art.chief.rotation.y, "scale": model.scale, "tile": Vector2(art.chief.position.x, art.chief.position.z) / CityMap.TILE, "dist": chase_dist, "pitch": chase_pitch, "yaw": yaw, "building": id, "overview": overview}
	if overview:
		_toggle_overview()
	interior = InteriorView.new()
	add_child(interior)
	interior.setup(sim, art, b)
	model.scale = Vector3.ONE * INTERIOR_CHIEF_SCALE
	art.chief.position = interior.to_world(Interiors.entrance(b))
	art.chief.rotation.y = PI
	chase_dist = 3.5
	chase_pitch = 0.72
	yaw = 0.0
	cam_target = art.chief.position + Vector3(0, 0.7, 0)
	cam_dist = chase_dist
	hud.set_hint("")
	_tut("enter")
	hud.toast("You step inside the %s%s." % [Catalog.label(str(b.kind)).to_lower(), _owner_note(b)], "home", UiKit.INK)


func _exit_building() -> void:
	if interior == null:
		return
	var b := interior.building
	var model: Node3D = art.chief.get_child(0)
	model.scale = outdoor.scale
	var door := CityMap.tile_to_world(Vector2i(int(b.door[0]), int(b.door[1])))
	art.chief.position = Vector3(door.x, outdoor.pos.y, door.z)
	art.chief.rotation.y = float(outdoor.rot)
	chase_dist = float(outdoor.dist)
	chase_pitch = float(outdoor.pitch)
	yaw = float(outdoor.yaw)
	cam_target = art.chief.position + Vector3(0, 1.5, 0)
	cam_dist = chase_dist
	overlay.interior = null
	interior.queue_free()
	interior = null
	outdoor = {}
	furnish_panel.close()
	hud.set_hint("")
	hud.toast("Back outside.", "town", UiKit.INK)


func _check_interior_exit() -> void:
	var room := interior.to_room(art.chief.position)
	if room.y > interior.size.y + 0.2:
		_exit_building()


func _update_chief_inside(dt: float) -> void:
	var moving := false
	var running := false
	var face := Vector3.ZERO
	var typing := get_viewport().gui_get_focus_owner() != null
	if not typing and not pie.is_open():
		var input := Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), 0, float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		if input.length() > 0.0:
			running = Input.is_physical_key_pressed(KEY_SHIFT)
			var dir := input.normalized().rotated(Vector3.UP, yaw)
			var step := dir * (INTERIOR_RUN if running else INTERIOR_WALK) * dt
			var from := interior.to_room(art.chief.position)
			var try_x := from + Vector2(step.x, 0)
			if not interior.blocked(try_x):
				from = try_x
			var try_z := from + Vector2(0, step.z)
			if not interior.blocked(try_z):
				from = try_z
			var before := art.chief.position
			art.chief.position = interior.to_world(from)
			moving = before.distance_to(art.chief.position) > 0.0005
			face = dir
	if chief_mode_time > 0.0:
		chief_mode_time -= dt
		if chief_mode_time <= 0.0:
			chief_mode = ""
	if moving:
		chief_mode = ""
		chief_mode_time = 0.0
	art.animate_chief(face, moving, running, chief_mode, dt)


func _interior_actor_distance(i: int) -> float:
	if interior == null:
		return 1.0e9
	var anchor := interior.actor_anchor(i)
	if anchor == Vector3.ZERO:
		return 1.0e9
	return Vector2(anchor.x, anchor.z).distance_to(Vector2(art.chief.position.x, art.chief.position.z))


func _item_label(it: Dictionary) -> String:
	var owners: Array = it.owners
	var label := FurnitureDb.label_of(str(it.model))
	if owners.is_empty():
		return label
	return "%s's %s" % [" & ".join(owners), label.to_lower()]


func _interior_hint() -> void:
	var room := interior.to_room(art.chief.position)
	var b := interior.building
	var talk := _nearest_resident_to_chief(INTERACT_RANGE)
	if talk >= 0:
		hud.set_hint("[E] Use  ·  [T] Talk to %s  ·  [G] Furnish" % sim.residents[talk].name)
		return
	var it := interior.nearest_item(room, 0.9)
	if not it.is_empty():
		hud.set_hint("[E] Use %s   ·   [G] furnish   ·   click furniture to give or remove it" % _item_label(it))
	elif interior.at_door(room):
		hud.set_hint("[E] Leave the %s" % Catalog.label(str(b.kind)).to_lower())
	else:
		hud.set_hint("%s%s   ·   [G] Furnish   ·   walk out the door to leave" % [Catalog.label(str(b.kind)), _owner_note(b)])


func _interior_interact() -> void:
	var room := interior.to_room(art.chief.position)
	var talk := _nearest_resident_to_chief(INTERACT_RANGE)
	if talk >= 0:
		_select(talk)
		_open_resident_pie(talk, get_viewport().get_visible_rect().size * 0.5)
		return
	var it := interior.nearest_item(room, 0.9)
	if it.is_empty():
		if interior.at_door(room):
			_exit_building()
		return
	var role := str(it.role)
	chief_mode = {"bed": "sit", "armchair": "sit", "sofa": "sit", "seat": "sit", "bench": "sit", "stove": "interact-right", "kitchen": "interact-right", "bath": "emote-yes", "bookcase": "pick-up", "desk": "interact-left", "bench_work": "interact-left", "counter": "interact-left"}.get(role, "interact-right")
	chief_mode_time = 3.0
	art.chief.rotation.y = deg_to_rad(float(it.rot) + 180.0)
	var reaction := Ownership.chief_uses(sim, interior.building, it)
	hud.toast("You use %s." % _item_label(it) if reaction == "" else "You use %s. %s" % [_item_label(it), reaction], "home", UiKit.INK if reaction == "" else UiKit.WARN)


func _interior_click(at: Vector2) -> void:
	for i in interior.actor_indices():
		var anchor := interior.actor_anchor(int(i))
		if anchor != Vector3.ZERO and not camera.is_position_behind(anchor) and _screen_of(anchor).distance_to(at) < 44.0:
			_select(int(i))
			_open_resident_pie(int(i), at)
			return
	var best := {}
	var best_d := 46.0
	for it in Interiors.furniture_of(interior.building):
		if str(it.role) == "rug":
			continue
		var p := interior.item_anchor(it) - Vector3(0, 0.15, 0)
		if camera.is_position_behind(p):
			continue
		var d := _screen_of(p).distance_to(at)
		if d < best_d:
			best_d = d
			best = it
	if not best.is_empty():
		_open_item_pie(best, at)


func _open_item_pie(it: Dictionary, at: Vector2) -> void:
	var b := interior.building
	var chosen: Dictionary = sim.residents[selected]
	var items: Array = []
	var id := int(it.id)
	if FurnitureDb.is_personal(str(it.model)):
		items.append({"label": "Give to %s" % chosen.name, "icon": "heart", "color": UiKit.SOCIAL, "hint": "Their own", "action": func() -> void:
			var target := Interiors.item_by_id(b, id)
			if not target.is_empty():
				target.owners = [str(chosen.name)]
				chosen.bond = minf(100.0, float(chosen.bond) + 1.5)
				hud.toast("%s now owns the %s." % [chosen.name, FurnitureDb.label_of(str(target.model)).to_lower()], "heart", UiKit.SOCIAL)})
	if not (it.owners as Array).is_empty():
		items.append({"label": "Make shared", "icon": "social", "color": UiKit.INK, "hint": "Everyone's", "action": func() -> void:
			var target2 := Interiors.item_by_id(b, id)
			if not target2.is_empty():
				target2.owners = []
				hud.toast("The %s is shared now." % FurnitureDb.label_of(str(target2.model)).to_lower(), "social", UiKit.INK)})
	var refund := int(float(it.get("price", 10)) * 0.5)
	items.append({"label": "Remove", "icon": "close", "color": UiKit.BAD, "hint": "Refund %d" % refund, "action": func() -> void:
		var gone := Interiors.remove(b, id)
		if not gone.is_empty():
			sim.money += refund
			hud.toast("Removed the %s (+%d coins)." % [FurnitureDb.label_of(str(gone.model)).to_lower(), refund], "coin", UiKit.GOOD)})
	pie.open(at, FurnitureDb.label_of(str(it.model)), "Belongs to %s" % " & ".join(it.owners) if not (it.owners as Array).is_empty() else "Shared", items)


func _toggle_furnish() -> void:
	if interior == null:
		hud.toast("Go inside a building to furnish it.", "home", UiKit.INK)
		return
	if furnish_panel.visible:
		furnish_panel.close()
		return
	orders_panel.close()
	market_panel.close()
	advice_panel.close()
	furnish_panel.visible = true
	_refresh_furnish_note()


func _refresh_furnish_note() -> void:
	if interior == null:
		return
	var b := interior.building
	var chosen: Dictionary = sim.residents[selected]
	var lives_here := int(chosen.home) == int(b.id)
	furnish_panel.set_context("%s. Personal pieces go to %s." % [Catalog.label(str(b.kind)), str(chosen.name) if lives_here or str(b.kind) != "home" else "nobody (%s lives elsewhere; select a resident of this home)" % chosen.name], sim.money)


func _furnish(model: String) -> void:
	if interior == null:
		return
	var b := interior.building
	var chosen: Dictionary = sim.residents[selected]
	var owner_name := ""
	if str(b.kind) == "home":
		owner_name = str(chosen.name) if int(chosen.home) == int(b.id) else ""
	else:
		owner_name = str(chosen.name)
	var result := Ownership.furnish(sim, b, model, owner_name)
	hud.toast(str(result.message), "home" if bool(result.ok) else "close", UiKit.GOOD if bool(result.ok) else UiKit.WARN)
	if bool(result.ok) and owner_name != "" and FurnitureDb.is_personal(model):
		chosen.bond = minf(100.0, float(chosen.bond) + 1.0)
	_refresh_furnish_note()


# --- AI ------------------------------------------------------------------------------------------------------------------

func _schedule_decisions(dt: float) -> void:
	if not ai_enabled or speed <= 0.0 or ai.queued_count("decide") > 0:
		return
	decide_timer -= dt
	if decide_timer > 0.0:
		return
	decide_timer = 22.0
	# Residents near the chief get their turn first, so the AI spends its effort where you can see it.
	var order: Array = range(sim.residents.size())
	order.sort_custom(func(a: int, b: int) -> bool: return art.actors[a].position.distance_squared_to(art.chief.position) < art.actors[b].position.distance_squared_to(art.chief.position))
	var pick_index: int = order[decide_cursor % mini(order.size(), 6)]
	decide_cursor += 1
	ai.request("decide", sim.observation(pick_index, ""), {"i": pick_index}, 60.0)


func _on_ai_completed(_id: int, kind: String, data: Dictionary, tag: Variant) -> void:
	if kind == "chronicle":
		var year := int(tag.year)
		var story := str(data.get("story", ""))
		if story != "":
			journal_panel.show_ai_story(year, story)
			if tag.get("asked", false):
				hud.toast("The storyteller has retold year %d." % year, "check", UiKit.GOOD)
		return
	if kind == "advise":
		if not sim.advice.is_empty() and int(sim.advice.id) == int(tag.advice):
			var texts := {}
			for o in data.get("options", []):
				texts[int(o.get("id", -9))] = str(o.get("text", ""))
			sim.refine_advice(str(data.get("question", "")), texts)
		return
	if kind != "chat" and kind != "decide":
		return
	var i := int(tag.i)
	if i >= sim.residents.size():
		return
	var r: Dictionary = sim.residents[i]
	r.thought = str(data.get("thought", "")).left(500)
	var say_text := str(data.get("say", "")).left(500)
	if str(data.get("note", "")) != "":
		sim.remember(r, str(data.note))
	if kind == "chat":
		_deliver_reply(i, say_text if say_text != "" else Social.chat_reply(str(r.name), str(r.trait), sim.emotion(r), str(tag.text), sim.rng), bool(tag.get("all", false)))
		return
	if say_text != "":
		r.say = say_text
		sim.log_event('%s: "%s"' % [r.name, say_text])
		if art.actors[i].position.distance_to(art.chief.position) < 30.0:
			sim.say(i, say_text)
	var action := str(data.action)
	if r.needs.hunger < 20 or r.needs.energy < 15:
		action = sim.choose_action(r)
	if not (bool(r.commanded) and float(r.remaining) > 0.0) and not sim.talking.has(i) and sim.has_target(action):
		sim.start_action(i, action)


func _on_ai_failed(_id: int, kind: String, _reason: String, tag: Variant) -> void:
	if kind == "chat":
		_local_reply(int(tag.i), str(tag.text), bool(tag.get("all", false)))


func _toggle_ai() -> void:
	ai_enabled = not ai_enabled
	ai.enabled = ai_enabled
	director.use_ai = ai_enabled
	if ai_enabled:
		if bridge_pid <= 0 or not OS.is_process_running(bridge_pid):
			_start_bridge()
		hud.toast("Claude AI on", "check", UiKit.GOOD)
	else:
		ai.clear()
		hud.toast("Local autonomy only", "check", UiKit.MUTED)


func _start_bridge() -> void:
	bridge_pid = OS.create_process("node", [ProjectSettings.globalize_path("res://bridge/server.mjs"), "--parent-pid=%d" % OS.get_process_id()], false)


# --- journal, menu, photos, tutorial ---------------------------------------------------------------------------------

func _tut(id: String) -> void:
	if Tutorial.mark(id):
		if not nosave:
			GameSettings.save_to()
		tutorial_card.refresh()
		hud.toast("First steps: %d left" % Tutorial.remaining(), "check", UiKit.GOOD)


func _toggle_journal() -> void:
	if journal_panel.visible:
		journal_panel.close()
		return
	_tut("journal")
	advice_panel.close()
	orders_panel.close()
	market_panel.close()
	journal_panel.ai_available = ai_enabled
	journal_panel.visible = true
	journal_panel.refresh()


func _request_story(year: int, asked: bool) -> void:
	if not ai_enabled or not ai.enabled:
		if asked:
			hud.toast("The AI is off, so the story stays as written.", "close", UiKit.WARN)
		return
	ai.request("chronicle", {"facts": Chronicle.facts(sim, year)}, {"year": year, "asked": asked}, 90.0)
	if asked:
		hud.toast("The storyteller is thinking...", "star", UiKit.INK)


func _toggle_photo() -> void:
	if photo.active:
		photo.exit()
		return
	_tut("photo")
	pie.close()
	for p in [advice_panel, orders_panel, market_panel, furnish_panel, journal_panel, menu_panel]:
		(p as Control).visible = false
	hud.root.visible = false
	overlay.visible = false
	ui_holder.visible = false
	photo_pos = camera.global_position
	photo_yaw = camera.rotation.y
	photo_pitch = camera.rotation.x
	photo.enter()


func _photo_exited() -> void:
	hud.root.visible = true
	overlay.visible = true
	ui_holder.visible = true
	look_drag = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _photo_fly(dt: float) -> void:
	var basis := Basis.from_euler(Vector3(photo_pitch, photo_yaw, 0.0))
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move -= basis.z
	if Input.is_key_pressed(KEY_S): move += basis.z
	if Input.is_key_pressed(KEY_A): move -= basis.x
	if Input.is_key_pressed(KEY_D): move += basis.x
	if Input.is_key_pressed(KEY_E): move += Vector3.UP
	if Input.is_key_pressed(KEY_Q): move -= Vector3.UP
	var pace := 7.0 * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	if move.length() > 0.0:
		photo_pos += move.normalized() * pace * dt
	photo_pos.y = maxf(photo_pos.y, 0.4)
	camera.position = photo_pos
	camera.basis = basis


func _photo_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			look_drag = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mb.pressed else Input.MOUSE_MODE_VISIBLE
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			photo_pos -= Basis.from_euler(Vector3(photo_pitch, photo_yaw, 0.0)).z * 1.5
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			photo_pos += Basis.from_euler(Vector3(photo_pitch, photo_yaw, 0.0)).z * 1.5
	elif event is InputEventMouseMotion and look_drag:
		var motion := event as InputEventMouseMotion
		photo_yaw -= motion.relative.x * 0.0045
		photo_pitch = clampf(photo_pitch - motion.relative.y * 0.0035, -1.45, 1.45)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_P, KEY_ESCAPE: photo.exit()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: photo.take_photo()
			KEY_LEFT: photo.cycle_filter(-1)
			KEY_RIGHT: photo.cycle_filter(1)


func _connect_extra() -> void:
	photo.exited.connect(_photo_exited)
	photo.captured.connect(func(path: String) -> void:
		hud.toast("Photo saved: %s" % ProjectSettings.globalize_path(path), "check", UiKit.GOOD))
	journal_panel.story_requested.connect(func(year: int) -> void: _request_story(year, true))
	hud.menu_requested.connect(menu_panel.open)
	menu_panel.resumed.connect(func() -> void: speed = menu_prev_speed)
	menu_panel.slot_saved.connect(func(slot: int) -> void:
		sim.chief_pos = _chief_tile()
		menu_panel.status("Saved to slot %d." % (slot + 1) if SaveSlots.save(sim, slot) else "Could not save to slot %d." % (slot + 1)))
	menu_panel.slot_loaded.connect(func(slot: int) -> void:
		if SaveSlots.activate(slot, SAVE):
			get_tree().reload_current_scene()
		else:
			menu_panel.status("That slot is empty."))
	menu_panel.slot_deleted.connect(func(slot: int) -> void:
		SaveSlots.delete(slot)
		menu_panel.status("Slot %d deleted." % (slot + 1)))
	menu_panel.new_village.connect(func() -> void:
		GameSettings.new_game = true
		get_tree().reload_current_scene())
	menu_panel.quit_game.connect(func() -> void:
		_shutdown()
		get_tree().quit())
	menu_panel.tutorial_reset.connect(func() -> void:
		Tutorial.reset()
		GameSettings.save_to()
		tutorial_card.refresh())
	menu_panel.setting_changed.connect(_setting_changed)
	voice.master_volume = int(GameSettings.value("voice_volume"))
	voice.tts_enabled = voice_replies and not muted_run
	menu_panel.visibility_changed.connect(func() -> void:
		if menu_panel.visible:
			menu_prev_speed = speed if speed > 0.0 else last_speed
			speed = 0.0)


func _setting_changed(key: String, value: Variant) -> void:
	match key:
		"voice_volume": voice.master_volume = int(value)
		"voice_replies":
			voice_replies = bool(value)
			voice.tts_enabled = voice_replies and not muted_run
			hud.set_voice_menu(voice_replies, _mic_name())
		"ai":
			if bool(value) != ai_enabled:
				_toggle_ai()
		"quality": GameSettings.apply_quality(get_viewport(), art.sun)
		"difficulty": hud.toast("Nights are now %s." % str(value), "star", UiKit.INK)
		"tutorial_hidden": tutorial_card.refresh()
	if not nosave:
		GameSettings.save_to()


# --- persistence ---------------------------------------------------------------------------------------------------------

func save_game(path: String = SAVE) -> bool:
	if nosave: return false
	sim.chief_pos = _chief_tile()
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(sim.to_dict()))
		file.flush()
		var write_error := file.get_error()
		file.close()
		if write_error != OK: return false
		if FileAccess.file_exists(path):
			if DirAccess.copy_absolute(path, path + ".bak") != OK: return false
		return DirAccess.rename_absolute(path + ".tmp", path) == OK
	return false


func load_game(save_path: String = SAVE) -> void:
	for path in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(path): continue
		var file := FileAccess.open(path, FileAccess.READ)
		if not file: continue
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) == OK:
			var data: Variant = parser.data
			if data is Dictionary:
				if data.get("version") == 2 and not nosave:
					# Keep the old fixed-layout village in case it is ever wanted back.
					DirAccess.copy_absolute(path, save_path.get_basename() + ".v2-backup.json")
				if sim.load_data(data):
					return


func _shutdown() -> void:
	save_game()
	ai.clear()
	voice.stop_speaking()
	# The bridge and the Whisper server watch this process and exit with it.


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown()


# --- scripted demos for screenshots ----------------------------------------------------------------------------------------

func _run_demo() -> void:
	if _elapsed < demo_at:
		return
	demo_done = true
	var centre := get_viewport().get_visible_rect().size * Vector2(0.45, 0.45)
	match demo:
		"pie":
			_open_resident_pie(selected, centre)
		"submenu":
			_open_resident_pie(selected, centre)
			pie._activate(pie._items[1])
		"building":
			_open_building_pie(int(sim.buildings_of("market")[0].id), centre)
		"lot":
			_open_lot_pie(sim.map.free_lots()[0], centre)
		"chat":
			_open_chat(selected)
			hud.chat.add_message(selected, true, "You", "Hello! How are you today?")
			hud.chat.add_message(selected, false, str(sim.residents[selected].name), "Hello, Chief! I'm doing well, thank you. The market smells wonderful this morning.")
		"overview":
			_toggle_overview()
		"build":
			hud.show_tab(4)
			build_kind = "home"
		"city":
			hud.show_tab(3)
		"chop", "mine", "water", "haul":
			var job_kind := "chop" if demo == "haul" else demo
			var worker := selected
			sim.command(worker, job_kind)
			var wanted_phase := "haul" if demo == "haul" else "work"
			var guard := 0
			while str((sim.residents[worker].job as Dictionary).get("phase", "")) != wanted_phase and guard < 6000:
				sim.tick(1.0)
				guard += 1
			var at: Vector2 = Vector2(sim.residents[worker].pos[0], sim.residents[worker].pos[1])
			art.chief.position = CityMap.tile_pos_to_world(at) + Vector3(2.5, 0, 6.0)
			art.sync(worker, 5.0)
			yaw = 0.2
			speed = 0.0
		"monsters":
			sim.minutes = 7.0 * 1440.0 + 22.0 * 60.0
			var base := Vector2(art.chief.position.x, art.chief.position.z) / CityMap.TILE
			Survival.spawn(sim, "zombie", base + Vector2(3.0, -2.0))
			Survival.spawn(sim, "slime", base + Vector2(-3.0, -3.0))
			Survival.spawn(sim, "wolf", base + Vector2(0.0, -5.0))
			sim.command(selected, "guard")
			art.sync(selected, 1.0)
			speed = 1.0
		"society":
			hud.show_tab(6)
		"mind":
			hud.show_tab(2)
		"defense":
			sim.money = 5000
			sim.wood = 200
			sim.stage_floor = 2
			sim.minutes = 6.0 * 1440.0 + 22.0 * 60.0
			for kind in ["watchtower", "clinic"]:
				var spot := Orders._spot_near_chief(sim, kind)
				sim.place_building(kind, spot)
				var nb: Dictionary = sim.buildings[sim.buildings.size() - 1]
				nb.level = 2
				nb.target = 0
				nb.progress = 100.0
			var chief_tile := Vector2(art.chief.position.x, art.chief.position.z) / CityMap.TILE
			Survival.spawn(sim, "zombie", chief_tile + Vector2(5.0, 2.0))
			art.sync(selected, 1.0)
			var tw: Dictionary = sim.buildings[sim.buildings.size() - 2]
			_toggle_overview()
			overview_focus = CityMap.tile_to_world(sim.tile_of(tw))
			overview_dist = 30.0
		"walls":
			sim.money = 9000
			sim.wood = 400
			sim.stage_floor = 3
			sim.claim_district(Vector2i(0, 1))
			Walls.build(sim, 99)
			for wb in sim.buildings:
				if Walls.is_wall(wb):
					wb.level = 2 if int(wb.id) % 2 == 0 else 1
					wb.target = 0
					wb.progress = 100.0
			sim.minutes = 5.0 * 1440.0 + 22.0 * 60.0
			Survival.spawn(sim, "zombie", Vector2(-4.0, 3.0))
			Survival.spawn(sim, "slime", Vector2(-3.5, 5.0))
			art.sync(selected, 1.0)
			_toggle_overview()
			overview_focus = CityMap.tile_pos_to_world(Vector2(-0.5, 2.0))
			overview_dist = 26.0
		"siege":
			# A ready-made night siege for playtesting: walls up, gates shut, a wave at the west wall.
			sim.money = maxi(sim.money, 6000)
			sim.wood = maxi(sim.wood, 300)
			sim.stage_floor = maxi(sim.stage_floor, 2)
			Walls.build(sim, 99)
			for sw in sim.buildings:
				if Walls.is_wall(sw):
					sw.level = maxi(1, int(sw.level))
					sw.target = 0
					sw.progress = 100.0
					sw.breached = false
					sw.condition = 100.0
			sim.minutes = floorf(sim.minutes / 1440.0) * 1440.0 + 22.0 * 60.0
			Walls.policy(sim)
			var rect := sim.map.bounds()
			var west_x := float(rect.position.x * CityMap.DISTRICT) - 3.0
			var mid_y := float(rect.position.y * CityMap.DISTRICT) + float(rect.size.y * CityMap.DISTRICT) * 0.5
			for k in range(5):
				Survival.spawn(sim, "zombie" if k % 3 != 2 else "slime", Vector2(west_x - float(k % 2) * 1.5, mid_y + float(k) * 1.2 - 2.0))
			art.chief.position = CityMap.tile_pos_to_world(Vector2(west_x + 6.0, mid_y))
			yaw = PI * 0.5
			speed = 1.0
			hud.toast("Night siege: five monsters at the west wall. Keep an eye on the wall's condition (Society tab).", "guard", UiKit.WARN)
		"rival":
			# Fly out to Redmarch, a short flight east, and look at the town from the road.
			var town := CityMap.tile_pos_to_world(Rival.position(sim))
			sim.minutes = floorf(sim.minutes / 1440.0) * 1440.0 + 12.0 * 60.0
			sim.armory["sword"] = 2
			sim.armory["shield"] = 2
			Weapons.chief_equip(sim, "sword")
			Weapons.chief_equip(sim, "shield")
			Rival.ensure(sim)
			sim.rival.known = true
			sim.rival.attitude = -60.0
			sim.rival.soldiers = max(int(sim.rival.soldiers), 30)
			art.chief.position = town + Vector3(-96.0, 0.0, 6.0)
			yaw = -PI * 0.5
			chase_dist = 16.0
			chase_pitch = 0.45
			demo_fight = true
			hud.toast("Redmarch lies %d metres beyond the village." % int(Rival.gap_units(sim)), "guard", UiKit.WARN)
		"raid":
			# A raid for playtesting: guards armed, a warband of Redmarch raiders at the east edge.
			sim.money = maxi(sim.money, 6000)
			sim.wood = maxi(sim.wood, 300)
			sim.stone = maxi(sim.stone, 300)
			Rival.ensure(sim)
			sim.rival.known = true
			sim.rival.soldiers = 40
			sim.armory["sword"] = 6
			sim.armory["spear"] = 2
			sim.armory["bow"] = 2
			sim.armory["shield"] = 4
			Weapons.arm_guards(sim, true)
			Weapons.chief_equip(sim, "sword")
			sim.minutes = floorf(sim.minutes / 1440.0) * 1440.0 + 15.0 * 60.0
			sim.rival.march = {"arrive": sim.minutes, "size": 7}
			Rival.tick(sim, 1.0)
			var east := Survival.village_centre(sim)
			art.chief.position = CityMap.tile_pos_to_world(east + Vector2(Survival.village_radius(sim) - 4.0, 0.0))
			yaw = -PI * 0.5
			speed = 1.0
			hud.toast("Redmarch raiders at the east edge! F attacks, X switches weapon, say \"arm the guards\".", "guard", UiKit.WARN)
		"fight":
			# Hands-on combat for a look at the blood and the moves: zombies and raiders close in on the chief.
			sim.money = maxi(sim.money, 6000)
			sim.armory["sword"] = 2
			sim.armory["shield"] = 2
			Weapons.chief_equip(sim, "sword")
			Weapons.chief_equip(sim, "shield")
			sim.minutes = floorf(sim.minutes / 1440.0) * 1440.0 + 21.5 * 60.0
			var spot := Vector2(2.5, 5.5)
			art.chief.position = CityMap.tile_pos_to_world(spot)
			yaw = 0.0
			_toggle_overview()
			overview_focus = CityMap.tile_pos_to_world(spot + Vector2(2.5, 0.5))
			overview_dist = 15.0
			for fk in range(4):
				var fm := Survival.spawn(sim, "zombie" if fk % 2 == 0 else "raider", spot + Vector2(1.6 + float(fk) * 0.5, -0.8 + float(fk % 2) * 1.6))
				fm.hp = 220.0
				fm.max_hp = 220.0
			Survival.spawn(sim, "raider_archer", spot + Vector2(5.5, 0.0))
			var cap := Survival.spawn(sim, "raider_captain", spot + Vector2(3.4, 1.0))
			cap.hp = 400.0
			cap.max_hp = 400.0
			demo_fight = true
		"farm":
			sim.money = 9000
			sim.food = 300
			for fb in sim.buildings:
				if str(fb.kind) == "farm":
					fb.level = 2
					fb.target = 0
					fb.growth = 70.0
			Farming.set_crop(sim, "pumpkin")
			for kind in ["chicken", "chicken", "chicken", "sheep", "cow"]:
				Farming.buy(sim, kind, 1)
			sim.minutes += 3.0 * 1440.0
			art.sync(selected, 1.0)
			var farm_tile: Vector2i = sim.tile_of(sim.buildings_of("farm")[0])
			_toggle_overview()
			overview_focus = CityMap.tile_to_world(farm_tile)
			overview_dist = 16.0
		"inside":
			var kind_name := OS.get_environment("INSIDE_KIND") if OS.get_environment("INSIDE_KIND") != "" else "home"
			var target_b: Dictionary = sim.buildings_of(kind_name)[0]
			sim.money = 5000
			Interiors.ensure(sim, target_b)
			var acts := {"home": ["sleep", "cook", "rest", "eat"], "market": ["work", "eat"], "workshop": ["work", "work"], "library": ["study", "study"], "bathhouse": ["wash", "wash"]}.get(kind_name, ["rest"]) as Array
			for ri in range(mini(sim.residents.size(), acts.size())):
				var rr: Dictionary = sim.residents[ri]
				if kind_name == "home":
					rr.home = int(target_b.id)
				rr.action = acts[ri]
				rr.target_id = int(target_b.id)
				rr.route = []
				rr.remaining = 900.0
			Ownership.refresh(sim, target_b)
			var dw := CityMap.tile_to_world(Vector2i(int(target_b.door[0]), int(target_b.door[1])))
			art.chief.position = Vector3(dw.x, 0, dw.z)
			_enter_building(int(target_b.id))
			art.chief.position = interior.to_world(Vector2(interior.size.x * 0.5, interior.size.y - 1.6))
			yaw = 0.0
		"pieclick":
			_open_resident_pie(selected, centre)
			await get_tree().create_timer(0.6).timeout
			var target: Vector2 = pie._slot_pos(0, pie._items.size())
			print("pie open=", pie.is_open(), " target=", target, " items=", pie._items.size())
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			ev.position = target
			ev.global_position = target
			Input.parse_input_event(ev)
			await get_tree().create_timer(0.3).timeout
			print("after click: open=", pie.is_open(), " stack=", pie._stack.size(), " title=", pie._title, " items=", pie._items.size())
			print("pie rect=", pie.get_global_rect(), " filter=", pie.mouse_filter, " visible=", pie.visible, " parent=", pie.get_parent())
		"market":
			_toggle_market()
		"orders":
			_toggle_orders()
			orders_panel._set_scope("all")
		"everyone":
			_open_chat(selected)
			hud.chat.set_broadcast(true)
			hud.chat.submit("everyone follow me")
			hud.chat.submit("how is everyone doing?")
		"advice":
			var request := Advice.city_request(sim)
			if request.is_empty():
				request = Advice.personal_request(sim)
			if request.is_empty():
				request = Advice._personal(0, "tired", "Chief, I'm completely worn out. Should I keep going?", [["Take the rest of the day off.", "rest"], ["Push through.", "push"]])
			sim.start_advice(request)
			var who := int(sim.advice.resident)
			sim.residents[who].pos = [sim.chief_pos.x + 1.0, sim.chief_pos.y + 0.5]
			sim.advice.state = "waiting"
			art.sync(selected, 1.0)
			_open_advice()
		"talk":
			# Stage a real two-person conversation right in front of the chief.
			var front := art.chief.position + Vector3(0, 0, -1).rotated(Vector3.UP, yaw) * 7.0
			for k in range(2):
				var r: Dictionary = sim.residents[k]
				var spot := CityMap.world_to_tile(front + Vector3((k - 0.5) * 3.2, 0, 0))
				r.pos = [float(spot.x), float(spot.y)]
				r.route = []
				r.action = "socialize"
				r.remaining = 25.0
			sim.residents[0].relations["Mira"] = 20.0
			sim.residents[1].relations["Pip"] = 20.0
			sim.resident_interact(0, 1, "chat")
		"voice":
			hud.set_voice_state("Listening… speak, then pause.", true, false, 0.6)
