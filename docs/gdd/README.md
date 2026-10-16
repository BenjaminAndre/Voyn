# Voyn — Game Design Document

## Index
| File | System | Status |
|---|---|---|
| `00-vision.md` | Pitch, pillars, broad lines, lineage, scope, milestones | draft (broad lines reworked) |
| `01-combat.md` | Grid, steps, AP/MP and recharge, LoS, abilities, Telegraphs, the Land, outcomes, Keeper interactions | draft (steps adopted provisionally) |
| `02-creatures.md` | Creatures, kits, karma footprints | not started (after broad lines) |
| `03-world.md` | Arenas, Monsters, Encounters, AI behaviors | not started (after broad lines) |
| `04-economy.md` | Harvest, crafting, trade | not started (post-MVP) |
| `05-progression.md` | Keeper progression, creature collection | not started (broad lines D4) |

Related: `docs/architecture.md` (stack, rules-engine contract, testing, release pipeline), `docs/tasks.md` (backlog).

## Glossary
Define every term here once; use it exactly everywhere. Names marked *working* may change.

| Term | Definition |
|---|---|
| Ability | An action a Creature or Monster uses, spending AP. Has a target cell, an Area, effects, a phase tag and a karma footprint. |
| AP (Action Points) | Pool spent on abilities. Refills to max every `recharge_steps` steps, never overflowing. |
| Area | The cells an ability affects around its target cell: `single`, `burst(r)`, `line(n)`, or `cells([...])` inside Telegraphs. |
| Arena | The hex board a fight happens on: cells, starting karma, `collapse_at`, `bloom_at`, interactables, start cells. Every battle starts from it unchanged. |
| Blighted | Karma −2. Deals blight damage (fixed) to non-Blightborn fighters who enter it or stand on it at Upkeep. |
| Blightborn | Trait: ignores blight damage; deals bonus damage from Corrupted or Blighted cells. All MVP Monsters have it. |
| Bloom | Outcome: board karma reaches `bloom_at`. The Keepers' Side wins, and every remaining Monster is Cleansed. |
| Board karma | The sum of every cell's karma. |
| Cell | One hex of an Arena, addressed by axial coordinates (q, r). |
| Cell order | Tie-break between cells: ascending q, then ascending r. |
| Chance | A visible random effect: odds shown before commit, rolled on commit from the fight's seeded PRNG. |
| Cleansed | A Monster defeated on a Pure or Thriving cell. It leaves peacefully and triggers a Renewal. |
| Collapse | Outcome: board karma falls to `collapse_at`. Everyone loses. |
| Collision damage | Fixed damage a pushed fighter takes for each push cell it could not travel. |
| Contested | A cell where a corruption rule and a purity rule both apply in the Land phase. It does not change. |
| Corrupted | Karma −1 *(working)*. |
| Creature | A fighter fielded by a Keeper, player-controlled. Creatures are Voyn's classes. |
| Crushed | What happens to a fighter on a cell where a Telegraph raises an obstacle: fixed damage, then Relocation. |
| Default path | The path the engine picks to a reachable cell: least blight damage, then least MP, then direction order. |
| Defeat | Outcome: no Creature left, or forfeit. |
| Defeated | A fighter at 0 HP. Monsters are Cleansed or Killed; Creatures are Downed. |
| Direction order | The fixed order D0–D5 of the six hex directions, used for tie-breaks. |
| Dash | Resolution sub-phase for Displacement abilities, after Prep and before Strike. |
| Displacement | Push or pull: moving a fighter without MP or Engagement. |
| Downed | A defeated Creature: out for this fight only. Its cell becomes Blighted. |
| Encounter | A set of Monsters and their spawn cells in an Arena. |
| Engagement | Extra MP a step costs for each enemy adjacent to the cell being left. |
| Event | A record emitted by the rules engine for one change. The client animates events and nothing else. |
| Fighter | Any unit on the board: Creature or Monster. Keepers are not fighters. |
| Fixed damage | Damage that ignores all modifiers: collision, crush, blight and all Telegraph damage. Shield still absorbs it. |
| Fizzle | An ability whose conditions no longer hold at resolution: no effect, no footprint, AP still spent. |
| Footprint | An ability's `karma` value, added to every cell of its Area after its effects. |
| Forecast | The always-visible marking of the cells the next Land phase would change. |
| Forfeit | Action that ends the fight at once as a Defeat. |
| Fun check | A deliberate play session at the end of a milestone. If it is not fun, fix that before adding anything. |
| Golden replay | A recorded fight (setup + seed + actions → expected events) used as a language-neutral regression test. |
| Guarded | Status: reduces damage taken by a percentage. |
| Heavy | Trait: Displacement against it moves 1 cell less (minimum 1). |
| Immovable | Trait: ignores Displacement. |
| Interactable | An Arena object a Keeper can use as its interaction (e.g. a bell, a lever, a fountain). |
| Karma | A cell's Land value, from −2 (Blighted) to +2 (Thriving). Every cell has one, obstacles included. |
| Keeper | The player's character. Classless, off the board in battle, cannot be targeted or defeated; plans an interaction whenever it has recharged (`keeper_recharge_steps`). |
| Keeper tool | A Keeper interaction unlocked in the overworld, available to every Keeper. |
| Killed | A Monster defeated on Neutral, Corrupted or Blighted ground. Its cell becomes Blighted. |
| Land | The third player: every cell's karma, and the rules that change it. |
| Land meter | One bar from `collapse_at` to `bloom_at`, showing board karma now and after this step's Land phase. |
| Land phase | In Upkeep, every `land_phase_every_steps` steps (currently every step): the karma automaton updates every cell at once. |
| Lead move | A plan's movement segment that comes before its ability. Resolves first in a step. |
| LoS (line of sight) | Whether the hex lines between two cells are free of blocking cells and fighters. |
| Monster | An AI-controlled fighter on the Monsters' Side. |
| MP (Movement Points) | Pool spent to move one cell at a time. Refills with AP. |
| Mutation | A cell change from a Telegraph, a Creature `mutate` effect or a Keeper interaction: `raise_obstacle`, `clear_obstacle`, `shift_karma`. |
| Neutral | Karma 0. |
| Nimble | Trait: ignores Engagement. |
| Obstacle | A cell that is not walkable and blocks LoS. It keeps its karma. |
| Payload | The ordered list of effects and Mutations a Telegraph applies when it resolves. |
| Pillar | One of the four design pillars in `00-vision.md`. Every system serves at least one. |
| Placement phase | Pre-fight stage where players put their Creatures on start cells. |
| Plan | What a fighter will do this step: at most one movement segment and one ability, in either order. Hidden from the other Side, visible to allies. |
| Power | Fighter stat: percentage bonus to damage dealt. |
| Prep | First ability sub-phase: buffs, Shields, purifies, Keeper interactions. |
| Pure | Karma +1 *(working)*. A Monster defeated here is Cleansed. |
| Ready | A player's signal that their plans are final; the window closes early when every player is Ready. |
| Recharge | AP and MP refilling to max every `recharge_steps` steps (a per-fighter role stat). |
| Relocation | Moving a Crushed fighter to the nearest free cell. Not Displacement: it affects every fighter. |
| Renewal | When a Monster is Cleansed: its cell and each adjacent cell gain +1 karma. |
| Rooted | Status: the fighter cannot take steps. |
| Rules engine | The headless, deterministic module in `src/rules/` that implements combat rules. |
| Shield | Status holding an amount that absorbs damage before HP. |
| Side | A team: the Keepers' Side (Creatures) or the Monsters' Side. The Land is not a Side. |
| Stationary | Trait: MP is always 0 and the fighter ignores Displacement. |
| Status | A named, timed bundle of modifiers on a fighter. Durations count in steps. |
| Step | The unit of fight time: a window, then a resolution (Lead moves, Prep, Dash, Strike, Trail moves, Upkeep). |
| Strike | Ability sub-phase where damage and statuses resolve simultaneously, then defeats, then footprints. |
| Sub-tick | One cell of lockstep progress in a simultaneous move phase. |
| Telegraph | A marker, visible to everyone, announcing a pending payload on cells and the step it resolves. The exception to hidden plans. |
| Threat zone | The cells an enemy could reach and hit this step with its current AP/MP. Shown to inform guesses about hidden plans. |
| Thriving | Karma +2. Heals fighters standing on it at Upkeep. |
| Trail move | A plan's movement segment that comes after its ability. Resolves after Strike. |
| Trait | A permanent fighter property from creature or Monster data. |
| Upkeep | Last part of a step: due Telegraphs, Land effects on occupants, status expiries, refills, Land phase. |
| Victory | Outcome: no Monster left. |
| Vulnerable | Status: increases damage taken by a percentage. |
| Window | The frozen planning time of a step: `step_window_ms` (8 s), solo included; ends early when every player is Ready. |

## Decision log
Current decisions. Replaced ones are listed under "Superseded".

| Date | Decision | Why | Decided by |
|---|---|---|---|
| 2026-10-16 | Client: Godot 4, typed GDScript, 3D with orthographic camera, Compatibility renderer | Free, strong 3D; height and rotation are far cheaper in 3D; typed GDScript limits AI mixing Godot 3/4 APIs | User + pilot |
| 2026-10-16 | Rules engine: pure, deterministic, headless GDScript, integer math, shared by client and future headless combat workers | One rules implementation for previews, AI, offline play and an authoritative server; cheap automated testing | Pilot, agreed by user |
| 2026-10-16 | Backend: Go, post-MVP only | Fits low-compute backend work; Rust's shared-crate advantage not worth its upfront cost | User + pilot |
| 2026-10-16 | Data in plain JSON under `data/`; golden replays as the port contract; Godot project root = repo root | Portable data; a future port must reproduce the same event logs | Pilot |
| 2026-10-16 | Every push to `debug` runs tests, then publishes a web build to itch.io with the commit hash on screen | Proven in Jolar; friends play the latest build, every build is traceable | User |
| 2026-10-16 | MVP is offline, single-player, combat-only; persistent online world is the uncommitted north star | Prove the fight is fun before paying for servers | User |
| 2026-10-16 | Hex grid | Uniform distances, 60° rotations, departure from square-grid genre conventions | User |
| 2026-10-16 | Placeholder art (3D primitives) until the M2b fun check | No art spend before combat is proven fun | User |
| 2026-10-16 | Project goal: fun side project; every session ends playable or testable; broad lines before content | Sets scope and process weight | User |
| 2026-10-16 | Pillars: Every turn reads clearly > The Land is the third player > Every fight has a cost > Roles that need each other | Coopetition reframed as negative-sum; class flavor over balance | User + pilot |
| 2026-10-16 | Structure: classless Keeper in the overworld; Creatures fight; Creatures are the classes | A new playstyle needs no story replay; one account can 100% the overworld | User + pilot |
| 2026-10-16 | PvM only, never PvP; balance by tuning Monsters and Encounters | Keeps creature flavor strong (what Dofus lost to class balancing) | User |
| 2026-10-16 | Karma −2..+2 on every cell; neighbor-sum automaton (≤ −5 corrupts, ≥ +5 purifies; Corrupted next to Blighted → Blighted, Pure next to Thriving → Thriving; contested holds) | User's rule: bounded on clean ground, runaway on corrupted ground, which supports "everybody loses" | User, formalized by pilot |
| 2026-10-16 | Outcomes: Collapse (board karma ≤ `collapse_at`, everyone loses) > Bloom (≥ `bloom_at`, remaining Monsters Cleansed) > Victory > Defeat; no round limit | Negative-sum with a purification win path | User + pilot |
| 2026-10-16 | Defeat on Pure/Thriving Cleanses a Monster (Renewal); elsewhere Kills it (cell → Blighted); Downed Creatures blight too | Position decides kill vs cleanse; violence pollutes | Pilot |
| 2026-10-16 | Battles always start from the map's authored karma; no carry-over between battles | Prevents griefing; zone-wide corruption may change maps later | User |
| 2026-10-16 | Randomness allowed only as visible Chance: odds before commit, result after; one seeded PRNG per fight, fixed seeds in tests | Fun of risk without hidden rolls (Pillar 1); exact replays | User + pilot |
| 2026-10-16 | Keeper: off-board, untargetable, one interaction whenever it has recharged, from Arena interactables and universal tools | Nobody waits with nothing to do; no class lock on the Keeper | User + pilot |
| 2026-10-16 | Monsters corrupt too, capped at −1 on one cell per instant ability; bigger corruption must be Telegraphed; AI treats Collapse as a loss unless `wants_collapse` | Everyone's violence pollutes, but fairly; nihilist bosses stay possible | Pilot, from user's idea |
| 2026-10-16 | Exact integer LoS algorithm; affected fighters fixed at use time; explicit elimination and Land checkpoints | Removes implementer guesswork before golden replays freeze it | Pilot, from design-critic |
| 2026-10-16 | All Telegraph damage is fixed damage; Creature/Keeper `raise_obstacle` skips occupied cells | Exact displayed numbers; no crush exploit | Pilot, from design-critic |
| 2026-10-16 | No MVP Creature ability combines `shift_karma` and `damage` on overlapping cells | A one-ability Cleanse would make cleansing free | Pilot, from design-critic |
| 2026-10-16 | M2 split into hot-seat M2a and AI M2b; kits of 2–4 abilities | Budget; cheap first fun check | Pilot, from design-critic |
| 2026-10-16 | Game time is an integer tick in the state from day one; one swappable scheduler module | Keeps every D3 candidate open, including real-time F, at almost no cost to the turn-based ones | Pilot |
| 2026-10-16 | **Turn structure G, discrete steps (provisional).** Each step is a frozen window (`step_window_ms` 8 s, solo included), then a resolution. | Co-op sync (friends beat one juggler), no waiting, turn-based networking, readable phases | User, formalized by pilot |
| 2026-10-16 | Plans are hidden from the other Side, visible to allies; Telegraphs stay visible | A mind game between Sides; co-op coordination inside a Side | User |
| 2026-10-16 | A plan holds one movement segment + one ability, in either order; another needs another step | User's rule; "either order" (hit-and-run) is a pilot addition | User + pilot |
| 2026-10-16 | Resolution order: Lead moves → Prep → Dash → Strike (simultaneous) → Trail moves → Upkeep; Fizzle when an ability's conditions fail at resolution (AP still spent) | Deterministic and readable simultaneous resolution | Pilot |
| 2026-10-16 | AP/MP refill to max every `recharge_steps` (per fighter); Land phase every step for now | Recharge speed as a role axis; tune the Land cadence in M2a | User |
| 2026-10-16 | Solo uses the same timed window | Solo should feel like you could use friends | User |
| 2026-10-16 | Pillar 1 restated: exact previews of your own and allies' plans; enemy plans are a guess informed by threat zones; big threats Telegraphed | Hidden simultaneous plans can't be previewed exactly | Pilot |

### Superseded
| Was | Replaced by |
|---|---|
| Three, then four pillars incl. "Win together, lose together" and "Small kits, deep combos" | Current pillars (negative-sum; Roles that need each other) |
| Fixed MVP content (Tank/Striker/Marksman, Bird/Gargoyle/Organ with traits) | All content is placeholder until broad lines settle |
| The player controls 3 Heroes | Keeper + Creatures |
| No randomness in combat | Visible Chance only |
| Round limit (Defeat) | No round limit; stalemates are an open question |
| Vitality, threshold-count spread, `collapse_cells` / `collapse_pct` | Karma, neighbor-sum automaton, board karma thresholds |
| Bloom = every Monster Cleansed (both Sides win) | Bloom = board purified (Keepers' Side wins) |
| Corrupted trait (Monsters) | Blightborn; "Corrupted" now names karma −1 |
| Land carried from Encounter 1 to Encounter 2 (proposal) | No carry-over between battles |
| Turn structure open, initiative-based draft rules, Rounds, undo of moves | Discrete steps (G); plans are editable until the window closes, so no undo is needed |
| Pillar 1 "see everything that decides the outcome" | Pillar 1 restated for hidden simultaneous plans |

## Open questions
Cross-cutting questions; per-system questions live in each file.
- **D3 Turn structure**: G (discrete steps) adopted provisionally. Validate it with a paper test (optionally against A) and in M2a. Its open choices are in `01-combat.md`: fizzle cost, window length, Land cadence, plan order, threat zones.
- **D4 Collection and progression**: recruit only Cleansed creatures? Team size solo vs group? Keeper tools.
- **D5 Setting brief**: what "solarpunk fantasy" means for Voyn; names come after.
- Stalemates without a round limit. (`01-combat.md`)
- Monster pollution pressure, Thriving healing Monsters, Downed Creatures blighting. (`01-combat.md`)
- Harvest and Erosion (from Jolar). (`00-vision.md`)
- Final art style, after the M2b fun check. (`00-vision.md`)
