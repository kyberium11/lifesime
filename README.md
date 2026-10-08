# Willowbrook — Pocket Village 3D

A playable Godot life simulation with a low-poly 3D village, four autonomous residents, and Claude-powered intentions, conversations and memories.

## Play

Run `./play.ps1` from PowerShell, or open `project.godot` in Godot 4.7 and press F5. Godot 4.7.2 was used for validation.

```powershell
./play.ps1
./play.ps1 -Offline       # Local simulation, no AI requests
./play.ps1 -Fresh         # New village; saves replace the current 3D village
```

The game starts its localhost Claude bridge automatically. Node.js and Claude Code must be installed for AI mode. Your existing Claude Code subscription login is used; no token is copied into this project. A live response was verified on this machine.

## Playing it

You are the caretaker: a small figure in a gold scarf who walks around Willowbrook. Everyone else is an AI-driven resident with needs, moods, wishes, friendships and memories.

**Interact like in The Sims.**

- **Click a resident** to open their pie menu. *Social* has Chat, Joke, Compliment, Gossip, Hug, Argue and Share a meal. *Needs* and *Activities* give orders. *Talk* opens a conversation window.
- Your avatar **walks over** before it interacts. Right-click the ground to walk anywhere.
- **Friendship gates what you can do.** Chat is open to strangers, a joke needs a little friendship, a hug needs real friendship. Everything has a cooldown, and arguing hurts.
- **Click a building** to send the selected resident there. Choose Eat at the Market, Work at the Workshop, Upgrade, and so on.
- **Orders queue.** The dock shows what each resident is doing and what is up next. Click a queued chip to cancel it. Residents **refuse** orders when exhausted or starving, and will not sleep when rested.
- Residents also talk to **each other** (chats, jokes, hugs, gossip, the odd argument), and you will see bubbles, emotes, friendship milestones and fulfilled wishes.
- **Wishes.** Each resident always has two goals (grow closer to someone, reach a skill level, do something three times, spend time with you). Fulfilling them earns aspiration points.
- In **Talk**, pick a quick reply or type anything. With Claude on, the resident replies in character within seconds. Offline, a local reply system answers.

**Controls**

| Input | Action |
|---|---|
| Left-click resident / building / site | Open its pie menu |
| Right-click ground | Walk the caretaker there (or cancel build mode) |
| Double-click a household card | Select and follow |
| Middle-drag, Q / E | Orbit camera |
| WASD | Pan camera |
| Mouse wheel | Zoom |
| Space | Pause / resume |
| 1 / 2 / 3 | 1x / 3x / 8x speed |
| Tab | Select next resident |
| I | Interact menu for the selected resident |
| T or Enter | Talk to the selected resident |
| F | Follow selected resident |
| B | Build tab; then click grass (green = valid, red shows why not) |
| H | Hide / show the interface |
| Escape | Close menu / chat / cancel building |

At 1x, one real second is four simulated minutes. Pausing stops time and new automatic AI requests; a reply already in flight can still arrive. The right-hand drawer has **People** (relationships), **Skills**, **Mind** (intentions and memories), **Town** (upgrades), **Build** and **Log**.

## Visible growth

The village changes as the residents live in it. Every visual is driven by real simulation state, so nothing is cosmetic.

- **Facility tiers (Lv 0-3).** Home, Market, Workshop, Library, Bathhouse and the Community Garden earn tiers from how often residents use them (6 / 18 / 40 visits). Tier 0 is a humble hut; Lv 1 is a cozy house; Lv 2 adds a porch, flower boxes and a dormer; Lv 3 adds a side wing, banner, lanterns and a red roof. The garden gains a fence, flower border, scarecrow and greenhouse. Tiers have gameplay effects (better meals, wages, sleep, study, health, harvests).
- **Upgrades are real projects.** Starting one costs coins and wood. The village council starts the most-used eligible upgrade each morning, or you can start one from the **Town** tab. The facility is wrapped in scaffolding with a live "UPGRADING 45%" label, and only residents' **work shifts** add progress.
- **Construction sites.** Anything you place from the **Build** tab starts as a site (stakes, frame, walls, roof) and is finished by work shifts, with a dust-puff pop when it completes.
- **Village stages.** Prosperity (tiers, finished buildings, orchard, skills) moves Willowbrook from Hamlet to Village, Town and Thriving Town. Each stage widens and re-paves the roads, adds curbs, street lamps and street trees, and expands the fountain. The entrance sign shows the current stage, and the header has a progress bar to the next one.
- **Living scenery.** Crops grow with the real harvest timer and turn gold when ready. Orchard saplings mature and bear fruit as residents gather. Windows glow and lamps light at dusk.

With default tuning a 28-day run reaches Village around day 4, Town around day 8 and Thriving Town around day 23 (`godot --headless --path . --script tests/growth_report.gd` prints the timeline; tune `TIER_*` and `STAGE_*` in `life_sim.gd`). Debug: `--advance-days=N` fast-forwards a fresh village N days before showing it. Reference screenshots live in `docs/progress/`.

## Simulation systems

- Four residents with personality preferences, independent routines and A* navigation around buildings.
- Hunger, energy, hygiene, social connection, fun and health; unmet needs affect health and mood.
- Shared produce, cooked meals, wood and coins; gathering and cooking use real resources.
- Workshop wages, five promotion ranks, and crafting, gardening, cooking, knowledge and fitness experience.
- Mutual relationships, invitations to the square, friendship milestones and individual memories.
- Crop growth, harvests, seven-day seasons, rain, night lighting, and birthdays every 28 game days. Rain accelerates crops; winter slows them.
- Construction costs, placement validation, cottage sleep benefits, garden yield bonuses, bench comfort, and lamps.
- Daily household bills and morale consequences for shortfalls.
- Autosave every 30 seconds and on normal close, atomic file replacement, and backup recovery.

This is an expanded playable foundation, not a finished Sims-scale game. Buildings currently have exterior interaction points, not furnished interiors. Romance, marriage, children, genetics, death/inheritance, individual property ownership, a full job market, and custom character creation are not implemented. Skill depth is strongest for careers and gardening; other skill tracks record progression alongside their related activities.

## Claude integration

The supplied reference was `E:\Projects\Coast\Q Digital Plugins\saas-platform\docs\claude_subscription_auth_token_playbook.md`. That document discusses **Claude Code OAuth**, which is distinct from extracting a Claude Desktop session. This game uses the authenticated Claude Code CLI through its [documented print mode](https://code.claude.com/docs/en/headless). Claude Code handles credentials and refresh itself; this implementation does not impersonate CLI request headers or read credential files.

```powershell
claude auth status
claude auth login         # Only if not already logged in
node bridge/server.mjs   # Optional manual bridge start
```

The bridge listens only on `127.0.0.1:18765`, rejects browser origins, disables Claude tools/customizations, runs in a temporary directory, and validates an action allowlist. Claude proposes actions and speech; it cannot directly change resources or execute commands. Prompts contain simulated resident state, recent village events and your in-game messages. AI activity uses the logged-in Claude account's allowance.

Default model: `haiku`. Override with the `LIFESIM_CLAUDE_MODEL` environment variable. If CLI detection fails, set `CLAUDE_CLI_PATH` to the native Claude executable or `cli.js`. Default cadence: one resident every 45 real seconds, configurable in `data/config.json` as `claude_interval_seconds`. The bridge enforces a 15-second minimum and one request at a time. Replies time out after 90 seconds. Local autonomy continues during requests and outages; the UI reports connection state. Queued chat receives priority at the next request.

## Saves and original game

3D save: `%APPDATA%\Godot\app_userdata\Pocket Village\village3d.json`, with `.bak` recovery. The original 2D `save.json` is preserved and is not migrated. To play the original prototype, launch `scenes/main.tscn`; its existing Ollama configuration and scripts remain available.

## Source map

- `scripts/life_sim.gd`: authoritative simulation: needs, commands and queues, social interactions, wishes, growth, navigation and the save schema.
- `scripts/social.gd`: interaction kinds, friendship levels, emotions, dialogue lines and offline chat replies.
- `scripts/village_art.gd`: procedural 3D world, articulated characters (faces, poses, animation), buildings, seasons, lighting.
- `scripts/village_main.gd`: camera, input and picking, pie menus, the caretaker avatar, chat routing, saves and the AI bridge client.
- `scripts/ui/`: the interface: `ui_kit` (design tokens and theme), `icon` (drawn icons), `game_hud`, `pie_menu`, `world_overlay` (bubbles, emotes, labels), `chat_panel`, `portrait` and `portrait_frame` (live 3D portraits).
- `bridge/server.mjs`: local Claude Code adapter and process lifecycle. Replies to your chat get a 3 s cooldown instead of 15 s.
- `bridge/decision.mjs`: action-response parsing.
- `scenes/village3d.tscn`: default scene.

## Verification

```powershell
godot --headless --path . --script tests/simulation_test.gd
godot --headless --path . --script tests/game_smoke.gd -- --fresh --nosave --offline
node --test tests/bridge.test.mjs
godot --headless --path . --script tests/growth_report.gd   # prints the development timeline
```

Tests cover a 28-day run, needs/economy bounds, construction, growth and stages, commands, queues and refusals, social interactions and cooldowns, wishes, save roundtrips and old-save compatibility, atomic replacement, corrupt-save recovery, and the real scene: HUD layout on screen, pie menus, avatar walk-and-interact, chat, picking, tabs, tiers, scaffolding and building entry.

Debug flags (after Godot's `--` separator): `--fresh`, `--nosave`, `--offline`, `--speed=8`, `--advance-days=N`, `--select=N`, `--shot=absolute/path.png`, `--shot-after=10`, and `--demo=pie|submenu|facility|chat|build|social|click|walk` to stage a screen (including injected real mouse clicks). Screenshot mode disables saving and exits after capture. Reference screenshots are in `docs/ui/` and `docs/progress/`.