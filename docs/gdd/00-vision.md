# 00 — Vision

Status: draft (broad lines reworked; turn structure provisional) · Defines the pillars and broad lines every other section serves.

## Purpose
Voyn is a solarpunk-fantasy tactics game. You are a **Keeper**. In the overworld you play one character. In battle you field a small team of **creatures** on a hex arena, with Dofus-style tactics: AP, MP, range, line of sight, pushes.

The Land is the third player. Every cell carries **karma**, from Blighted to Thriving. Every action marks it, and between rounds the Land amplifies what the fighters did, like a living automaton. Win by defeating the Blightborn monsters, or by purifying the board into **Bloom**. Let the board sink into blight and the Land **Collapses**: everyone loses.

Pokémon's structure and Dofus's fights are both genres. Voyn takes mechanics from each and copies neither.

It is a side project, built for fun by one developer with AI help. It succeeds if it is fun to play **and** fun to build.

## Rules: pillars
Every system serves at least one pillar. A feature that serves none gets cut. When pillars conflict, the lower number wins.

1. **Every turn reads clearly.** While you plan, you see exactly what your plan does on the board as it stands, plus your allies' plans:
   - reach, range and LoS;
   - exact damage, and where a push lands;
   - the karma footprint and the Land's forecast.

   The other Side's plans stay hidden until the step resolves. That's the mind game, and enemy threat zones keep the guess informed. Everything then resolves in a fixed order you can follow. Big threats are Telegraphed steps ahead. When luck is involved, you see the odds before you commit and the result after. Nothing happens behind your back that you couldn't have read or guessed.
2. **The Land is the third player.** Every cell has karma, and every action marks it, monsters' actions included. Between rounds the Land amplifies: corruption feeds corruption, purity feeds purity. Push a board too far and it runs away on its own.
3. **Every fight has a cost.** Fights are negative-sum: you win or you lose, and the Land can make everyone lose.
   - Killing is quick but blights the ground; cleansing takes more work.
   - The best victory, Bloom, purifies the board. The worst ending, Collapse, takes everyone down.
4. **Roles that need each other.** Each creature does something no other can, with a small kit (2–4 abilities), and teams win by combining them. Voyn is PvM only, so balance comes from tuning monsters and encounters. Creatures are never sanded down until they lose their flavor. Different, never strictly better.

Pillar 1 comes first on purpose: a living battlefield you cannot read is just noise.

## Broad lines
| Line | Decision | Status |
|---|---|---|
| Tone and setting | Solarpunk fantasy. MVP Arena placeholder: a ruined cathedral reclaimed by nature | settled (setting brief to write) |
| Player fantasy | You are a Keeper restoring a blighted world, fighting through your creatures | settled |
| Structure | Overworld: one Keeper per player (quests, economy). Battle: the Keeper's creatures fight, and the Keeper makes a world interaction whenever it has recharged (`01` R12) | settled |
| Keeper | Classless, so one account can 100% the overworld. Battle interactions come from Arena interactables and tools every Keeper can unlock | settled |
| Classes | Creatures are the classes. A new playstyle is a new creature, with no story replay | settled |
| Collection | Creatures are recruited by Cleansing them, never by Killing them | proposed |
| Outcomes | Victory, Defeat, **Bloom** (board purified: remaining Monsters are Cleansed), **Collapse** (board blighted: everyone loses) | settled |
| Turn structure | **Discrete steps** (`01-combat.md` R3), adopted provisionally:<br>- a 16 s frozen window (doubled after round 1), solo included (solo should make you want friends);<br>- plans hidden from the other Side, visible to allies;<br>- one move + one ability per Creature per step;<br>- phased resolution;<br>- AP/MP recharge every few steps | provisional (validate in D3 paper test and M2a) |
| Randomness | Allowed when visible: odds shown before commit, result after. One seeded PRNG per fight, fixed seeds in tests | settled |
| Multiplayer | PvM only, no PvP. In groups, each player brings a Keeper and creatures | settled |
| Battle maps | Every battle starts from the map's authored karma; nothing carries over between battles, which prevents griefing. Zone-wide corruption may change maps later | settled |
| World | Persistent online world | north star, not committed |

## Rules: how we build it (budget)
- **Every session ends playable or testable.** No week ends with a half-built system that cannot run.
- **Every push to `debug` is playable on itch.io**, with the commit hash on screen (see `docs/architecture.md`).
- **Broad lines before content.** Creatures, monsters and spells stay placeholders until the broad lines they depend on are settled.
- **Placeholders until it is fun.** Primitive 3D shapes, flat colors, no rigged animation. Art waits for the M2b fun check.
- **Data, not code.** Numbers and content live in `data/` as JSON.
- **Headless, tested rules engine.** Golden replays and bot fights make changes cheap and safe.
- **Scope gate.** A feature enters the current milestone only if it serves a pillar and fits in one or two sessions.
- **Light process.** GDD sections stay short. Only combat-critical sections go through the `design-critic` loop.

## Audience
First the developer, then friends who like grid tactics and creature collecting. A fight lasts 5–10 minutes.

## Lineage: Jolar
Voyn grows out of Jolar, the developer's earlier Godot prototype (a creature-battle game). Jolar had:
- a shared pollution level ("alteration") that moves changed;
- a shared harvest pool ("fruits") that collecting depleted;
- "erosion", where damage lowered the target's healing cap.

Jolar tracked alteration but never made it matter. Voyn starts from the consequences: karma changes the board and decides the outcome. Harvest and Erosion are parked candidates.

## North star (not committed)
A persistent online world explored by Keepers. Group fights are PvM. Zones carry their own corruption, and a fallen zone may even change its battle maps. Harvesting the commons feeds crafting. Nothing in the MVP depends on this, except that the rules engine stays headless so a server can run it later.

## Interactions
- `01-combat.md` carries Pillars 1–3: previews, karma, the Land automaton, outcomes, Keeper interactions.
- `02-creatures.md` carries Pillar 4: creatures, kits, karma footprints.
- `03-world.md`: Arenas (starting karma, interactables), Monsters, Encounters.
- `04-economy.md`: post-MVP harvest and crafting.
- `05-progression.md`: Keeper progression and creature collection.

## Edge cases (pillar conflicts)
- A forecast or Telegraph too large or too hidden to read breaks Pillar 1. Shrink it until it reads.
- An action whose outcome, odds or footprint cannot be previewed exactly gets redesigned.
- If Collapse feels like a timer rather than a consequence, Pillar 3 is failing. Retune footprints before adding rules.
- If one creature is simply better than another at the same role, Pillar 4 is failing even in PvM. Make them different instead.

## MVP cut
An offline, single-player, combat-only slice. No overworld, collection, harvest, crafting, progression or online play. **All content below is placeholder** until the broad lines (turn structure especially) are settled.
- **1 Arena**: the ruined cathedral, with a starting karma pattern and 1–2 interactables.
- **1 Keeper** with one basic tool (e.g. purify a cell) plus the Arena's interactables.
- **3 creatures**, placeholder roles: a tank, a short-range glass cannon, a long-range one.
- **3 Monster placeholders**, all Blightborn: a nimble flier, a sturdy brute and a stationary boss (working names Bird, Gargoyle, Organ).
- **2 Encounters.**
- **Outcomes**: Victory, Defeat, Bloom, Collapse. The result screen shows Monsters Cleansed out of the total and the final board karma.
- **Fun check**: after M2a, M2b and M3, the developer plays the Encounters several times. If fights are not fun, fix that before adding anything else.

### Milestones
| # | Milestone | Proves |
|---|---|---|
| Broad lines | Turn structure (D3), collection and progression (D4), setting brief (D5) | The game's shape is settled |
| M0 | Godot project, test runner, data loading, git, `debug` → itch.io pipeline | The pipeline works |
| M1 | Complete headless rules engine (Land automaton, Keeper interactions, Telegraphs) + golden replays | Rules are correct and testable |
| M2a | Minimal 3D board, planning window, you vs scripted Monsters, basic previews, karma display | Steps, roles and the Land are fun (cheap first fun check) |
| M2b | AI, full previews and forecast, camera rotation, bot fights | The core loop is fun vs AI (fun check) |
| M3 | Boss, Encounter 2, Telegraph display | Living arena + negative-sum outcomes work (fun check) |
| M4+ | Experiments: height, rotating zones, harvest | The "crazy things" |

## Open questions
- **Turn structure**: discrete steps adopted provisionally. Validate on paper (D3) and in M2a; its open choices are in `01-combat.md`.
- **Collection**: recruit only Cleansed creatures? How many creatures does a Keeper field, solo and in groups?
- **Setting brief**: references, palette, what "solarpunk fantasy" means for Voyn. Names come after.
- Harvest (Jolar's fruits): in-fight, post-fight or world-only? Erosion: worth it?
- Final art style (decide after the M2b fun check).
