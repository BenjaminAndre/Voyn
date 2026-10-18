# Architecture

Status: challenged · Owner: pilot (Opus). Changes here are architecture decisions; log them in `docs/gdd/README.md`.

## Stack
| Part | Choice | Notes |
|---|---|---|
| Client | Godot 4, latest stable (exact version pinned in `CLAUDE.md` by task T1), typed GDScript | 3D, orthographic camera, Compatibility renderer (keeps web export possible) |
| Rules engine | Pure GDScript module in `src/rules/` | Runs inside the client, and later inside Godot headless |
| AI | Pure GDScript module in `src/ai/` | Same constraints as the rules engine |
| Combat worker (post-MVP) | Godot headless export of this same project | Runs authoritative fights and Monster AI |
| Backend (post-MVP) | Go, in `server/` | Accounts, persistence, world, economy; routes fights to combat workers |
| Data | JSON in `data/` | Readable from GDScript and from Go |
| Tests | GUT (Godot Unit Test), run headless | Unit tests, golden replays, AI golden tests, bot fights |

Why not Rust: godot-rust could share one rules crate between client and server, but it front-loads a cargo + GDExtension pipeline and weak web export for a feature (online) that is not in the MVP. Go fits the low-compute backend, and the golden replays make a later port safe.

## Repo layout
```
project.godot   Godot project root = repo root, so res://data/ is reachable in exports
src/rules/      Rules engine: no Node, no scene tree, no rendering, no engine singletons
src/rules/turns/  The scheduler: the only code that knows the turn structure (GDD R3)
src/ai/         Behaviors; simulate through src/rules/ only
src/client/     Scenes, 3D board, camera, input, planning UI, window timer; reads state, sends plans, animates events
data/           JSON: combat/, creatures/, abilities/, statuses/, monsters/, behaviors/, arenas/, encounters/, keeper_tools/
tests/unit/     GUT tests, named after GDD rule IDs (test_R5_2_los_symmetric)
tests/golden/   Golden replays and the LoS table (JSON)
tests/fixtures/ Test-only creatures, abilities, monsters, arenas
docs/           Design docs (has a .gdignore)
server/         Go backend, later (has a .gdignore)
```
Export presets must include `data/**/*.json`, because Godot does not export non-resource files by default.

## Rules engine contract
- **Turn structure**: discrete steps (GDD R3, candidate G, provisional). The engine works one step at a time.
- **Setup actions**:
  - `place(creature, cell)`: any free Creature start cell from Arena data (`creature_start_cells`); re-placing a creature moves it;
  - `start_fight()`: errors unless every Creature is placed;
  - `forfeit()`.

  Monsters spawn from the Encounter's `[{monster, cell}]` list at setup.
- **Plans** (GDD R3.4): `{fighter, from_cell, move_path?, ability?, target_cell?, order: "move_first" | "ability_first"}`, plus `{keeper, interaction, target_cell}`.
  - `move_path` lists the cells to enter, in order; `from_cell` is where the fighter stood when it planned.
  - A plan with only a move uses `move_first`.
  - `validate_plan(state, plan) -> {ok, errors}` checks the plan against the board as it stands (GDD R3.4, R6.1). Allies' plans never affect validation; they only feed previews.
  - Errors are stable string codes (e.g. `not_your_fighter`, `path_not_contiguous`, `path_too_long`, `cell_not_walkable`, `cannot_move`, `not_enough_ap`, `out_of_range`, `no_los`, `not_on_axis`, `bad_target`, `on_cooldown`), the same shape as the rules loader.
  - A malformed plan is rejected at commit. A plan that becomes impossible later is not an error: it resolves into `move_blocked` or `fizzled` events.
- **`resolve_step(state, plans) -> result`**: takes every Side's plans for the step and returns the new state plus a list of events. It runs Lead moves → Prep → Dash → Strike → Trail moves → Upkeep (GDD R3.6). Fizzles are events, not errors. Only setup actions and malformed plans return errors.
- **Scheduler** (`src/rules/turns/`): the only module that knows the step structure (phase order, window, recharge cadence, Land cadence). If D3 changes, only this module and its tests move.
- **Time is the step counter**, an integer in the state. Durations, Telegraph delays, cooldowns and recharges are all in steps. The window length (`step_window_ms`) is a client and server concern, not a rules concern: the engine never reads a clock.
- **Simultaneous movement** (GDD R4.8): all movers of a phase advance one cell per sub-tick. Each sub-tick:
  1. Compute every mover's wanted cell.
  2. Mark vacated cells, iterating until nothing changes, so a mover can follow another out of a cell.
  3. Resolve conflicts by the GDD priority. Block swaps and cycles.
  4. Pay MP and Engagement per cell, against positions at the start of the sub-tick.
- **Queries** (read-only, so the client never computes a rule):
  - `reachable(state, fighter)` → for each cell: MP cost, default path (GDD R4.6), blight damage along it;
  - `targets(state, fighter, ability, from_cell)` → valid target cells from a planned position;
  - `threat_zone(state, fighter)` → the cells it could reach and hit this step;
  - `forecast(state)` → the cells the next Land phase would change, and the board karma after it.
- **Previews** (R9) and AI (R10) call `resolve_step` on a copy, with the player's and allies' plans and empty enemy plans. State is plain data, copyable in one call. For `chance` effects, the preview resolves each branch on its own copy.
- **Events** are the only thing the client animates: `step_started`, `phase_started` (with the phase name), `moved`, `move_blocked`, `ap_spent`, `fizzled`, `damaged`, `healed`, `shield_changed`, `displaced`, `relocated`, `collided`, `status_applied`, `status_ended`, `cell_mutated`, `karma_changed`, `chance_rolled`, `telegraph_placed`, `telegraph_resolved`, `interacted`, `refilled`, `land_phase`, `defeated` (with `cleansed`, `killed` or `downed`), `fight_ended` (with `collapse`, `bloom`, `victory` or `defeat`).
- `damaged` and `healed` carry a `cause`: `ability`, `blight`, `thrive`, `collision`, `crush` or `telegraph`. A `land_phase` event is followed by one `karma_changed` event per changed cell, in cell order.
- **Keep copies cheap**: AI and previews copy the state many times per step, so store per-cell data (karma, walkable, blocks_los) as packed int arrays indexed by cell, not as dictionaries of objects.
- **No undo**: plans are editable until the window closes, so the engine only ever sees final plans.

## Determinism and portability
Same state + same action gives the same events on every platform, and in a future Go port.
- **Integers only** in `src/rules/` and `src/ai/`: int64 range, no floats anywhere (LoS included), integer AI weights.
- **No negative division.** Clamp numerators to ≥ 0 before dividing (GDD R7.1). Where a signed floor is unavoidable (LoS), use the explicit `floor_div` below, never the language's `/`.
- **JSON numbers**: Godot's `JSON.parse` returns floats. The loader converts every number to int and rejects non-integers.
- **Order**: anything ordered (effects, payload entries, patterns, rosters, cell lists) is a JSON array, never object key order. Every iteration order comes from a GDD tie-break (turn order, cell order, direction order).
- **One seeded PRNG per fight, never the engine's RNG.** Use a hand-written integer generator (e.g. PCG32 or xorshift64*) in `src/rules/` that a Go port can reproduce bit for bit.
  - The seed is part of the fight state and of every golden replay. Tests fix their seeds; the game draws a fresh seed per fight and saves it with the replay, so any fight or bug report replays exactly.
  - Only `chance` effects (GDD R6.8) draw from it, at commit, in resolution order. Previews and AI simulations never advance the real generator; each branch is evaluated on its own copy.
- **Event encoding**:
  - fighter ID = roster index: Creatures in player order then party order (from data, never placement order), then Monsters in Encounter order. IDs are never reused; a defeated fighter keeps its ID;
  - cell = `[q, r]`;
  - each event is an object with `type`, `step` and `phase` (`setup`, `lead_move`, `prep`, `dash`, `strike`, `trail_move`, `upkeep`), plus a fixed set of integer/string fields. For example:
    - `moved`: fighter, from, to, mp_spent;
    - `move_blocked`: fighter, at, wanted, reason (`conflict`, `swap`, `cycle`, `occupied`, `no_mp`, `rooted`, `displaced`).

### Event schema (T5, T6)
Every event carries `type`, `step` (0 during placement) and `phase`. The phase is `setup` for events outside the six phases of a step: placement, `step_started`, forfeit. Events are plain dictionaries of ints, strings and `[q, r]` cells, in the order the rules produced them.

| type | fields | notes |
|---|---|---|
| `placed` | fighter, cell | a Creature put on a start cell |
| `fight_started` | | placement is over; step 1 begins |
| `step_started` | | first event of a step |
| `phase_started` | name | `lead_move`, `prep`, `dash`, `strike`, `trail_move` or `upkeep`; `phase` equals `name` |
| `moved` | fighter, from, to, mp_spent, mp_left | one cell entered in one sub-tick, with Engagement paid (`mp_left` feeds the MP pips) |
| `move_blocked` | fighter, at, wanted, reason | `at` = where it stands, `wanted` = the cell it could not enter |
| `damaged` | fighter, amount, absorbed, cause, hp | `amount` = damage dealt, `absorbed` = the part a Shield took, `hp` = HP left; `cause` as above |
| `healed` | fighter, amount, cause, hp | |
| `ability_used` | fighter, ability, cell | an ability started resolving; `cell` = its target |
| `fizzled` | fighter, ability, cell, reason | `reason` = the failed R6.1 check: `not_enough_ap`, `out_of_range`, `no_los`, `not_on_axis`, `bad_target`, `on_cooldown` |
| `ap_spent` | fighter, amount, ap | paid for every ability, fizzled or not; `ap` = left |
| `shield_changed` | fighter, shield | the Shield held now (0 = gone) |
| `status_applied` | fighter, status, magnitude, ends_step | |
| `status_ended` | fighter, status | expiry, a Shield used up, or the fighter or its source defeated |
| `defeated` | fighter, how | `cleansed`, `killed` or `downed`; followed by its `karma_changed` events |
| `karma_changed` | cell, from, to | in cell order within one cause |
| `refilled` | fighter, ap, mp | only if a pool actually changed |
| `fight_ended` | outcome | `collapse`, `bloom`, `victory` or `defeat` |

`move_blocked` reasons: `conflict`, `swap` (two movers exchanging cells), `cycle` (longer), `occupied`, `no_mp`, `rooted`, `displaced` (a Trail move cancelled because its fighter is not on the planned cell any more), plus `not_walkable` (terrain changed since planning) and `stationary`.

Order inside a move sub-tick: every `move_blocked` (ascending fighter ID), then every `moved` (ascending ID), then blight `damaged` events (ascending ID), then `defeated` events with their `karma_changed`.

Still to come with T8-T10b: `displaced`, `relocated`, `collided`, `cell_mutated`, `chance_rolled`, `telegraph_placed`, `telegraph_resolved`, `interacted`, `land_phase`. Each adds its row here with its task.

### Content schemas (T7)
Validated by `Defs` (`src/rules/defs.gd`): floats become ints, unknown and missing keys are errors, `_doc` is allowed and dropped. One JSON object per file under `data/abilities/`, `data/statuses/`, `data/behaviors/`.
- **Ability**: `{id, name?, phase: "prep" | "dash" | "strike", ap_cost, cooldown, target: "any_cell" | "empty_cell" | "any_fighter" | "enemy" | "ally" | "self", min_range, max_range, needs_los, line_only, area, affects: "enemies" | "allies" | "all", include_user?, effects: [], karma}`.
  - `area` = `{shape: "single"}`, `{shape: "burst", radius}` or `{shape: "line", length}` (a line needs `line_only`).
  - `effects` may be empty (a footprint-only ability such as Seed) and resolve in listed order. So far: `{type: "damage", base}`, `{type: "heal", amount}`, `{type: "shield", amount, duration}`, `{type: "apply_status", status, duration, magnitude}`. `push`/`pull` arrive with T9 and `mutate`/`telegraph` with T10; the loader rejects them until then. `chance` is rejected until GDD R6.8 says whether it rolls per effect or per fighter.
  - `affects`: `enemies` = the other Side, `allies` = the user's Side without the user, `all` = everyone in the Area but the user; `include_user` adds the user when it stands in the Area.
  - `cooldown` N: used in step s, usable again in step s + N (so 1 never restricts). A fizzled ability starts its cooldown too.
- **Status**: `{id, name?, effect: "shield" | "rooted" | "damage_taken_pct" | "damage_dealt_pct", sign: 1 | -1}`. An instance on a fighter is `{name, effect, sign, magnitude, ends_step, source}`; a duration N applied in step s ends in the Upkeep of step s + N. Shield is built in and needs no file.
- **Behavior**: `{id, kind: "scripted_chase"}` (`greedy` arrives with T14).
- **Fighter data** gains `abilities: [ability ID]`.

### Data shapes (provisional, until D2/G1 fix the content files)
- **Arena**: `{radius, obstacles: [[q, r]], karma: [[q, r, k]], creature_start_cells: [[q, r]], collapse_at, bloom_at}`.
- **Roster**: Creatures first (player order then party order), then Monsters in Encounter order; each entry `{side: "creature" | "monster", player, name, max_hp, max_ap, max_mp, power, recharge_steps, traits, cell (Monsters)}`. Stats are inline until creature and Monster data files exist.
- **State** (`FightState`): the grid and rules by shared reference; per-cell packed arrays (`karma`, `walkable`, `blocks_los`, `occupant`); fighters; `step`; `status` (`placement`, `fighting`, `ended`); `outcome`; the fight's PRNG. `clone()` copies it in one call.
- **Plan checks**: `Plans.shape_errors` (malformed or stale plans, refused by `resolve_step` with nothing changed) and `validate_plan(state, plan, player = -1)` (plan-time rules: `not_fighting`, `not_your_fighter`, `cannot_move`, `path_too_long`, `cell_not_walkable`, plus the shape codes: `missing_fighter`, `fighter_not_active`, `bad_order`, `missing_from_cell`, `bad_from_cell`, `stale_from_cell`, `bad_move_path`, `path_outside_arena`, `path_not_contiguous`, `path_repeats_cell`, `unknown_key:<key>`, `unknown_ability`, `ability_not_known`, `missing_target_cell`, `bad_target_cell`, `keeper_plans_unavailable`; for abilities also the R6.1 codes `not_enough_ap`, `out_of_range`, `no_los`, `not_on_axis`, `bad_target`, `on_cooldown`, checked from the cell the plan puts the user on).

### LoS algorithm (GDD R5)
Cube coordinates: `x = q`, `z = r`, `y = −q − r`. The algorithm samples the exact line, scaled by 12N, and adds a tiny integer nudge (`±(1, 2, −3)`). The nudge breaks exact ties without changing any non-tie result, and no ties remain after it. The nudged lines A→B and B→A visit the same cells, so LoS is symmetric.

```
los(A, B):
  if A == B or distance(A, B) == 1: return true
  return line_clear(A, B, +1) or line_clear(A, B, -1)

line_clear(A, B, s):
  N = distance(A, B); D = 12 * N
  a = cube(A); b = cube(B); e = (1, 2, -3) * s
  for i in 1 .. N-1:
    p = (a * N + (b - a) * i) * 12 + e        # componentwise, integers
    c = cube_round(p, D)
    if blocks_los(c) or occupied(c): return false
  return true

cube_round(p, D):                              # nearest cell to p / D
  r = (div_round(p.x, D), div_round(p.y, D), div_round(p.z, D))
  d = (abs(r.x * D - p.x), abs(r.y * D - p.y), abs(r.z * D - p.z))
  if d.x > d.y and d.x > d.z: r.x = -r.y - r.z
  elif d.y > d.z:             r.y = -r.x - r.z
  else:                       r.z = -r.x - r.y
  return r

div_round(n, D) = floor_div(2 * n + D, 2 * D)  # never a tie, thanks to the nudge
floor_div(n, m) = n / m if n >= 0 else -((-n + m - 1) / m)   # m > 0, '/' on non-negatives only
```
`tests/golden/los_table.json` lists every cell pair of a fixture Arena with its expected result. It is generated once from the GDScript implementation, after hand-checking a sample, and then becomes part of the port contract.

## Testing
- **Unit tests** per GDD rule, named with the rule ID.
- **Golden replays** (`tests/golden/*.json`): Arena + roster + seed + committed actions → expected event log. AI turns are recorded as plain actions, so the replays test rules, not AI. They are language-neutral: a Go port must pass the same files. Record a new one from real play whenever a bug is found.
- **AI golden tests**: state → the actions the behavior chooses.
- **Bot fights** (M2b+): headless runs of greedy Creatures vs an Encounter over many fights, with a harness-only round cap. They report the outcome mix and fight length (vision target: 5–10 minutes). Balance changes are checked against them. If greedy is too slow in GDScript, measure first, then prune candidates.

## Release pipeline: GitHub Pages, then itch.io
One workflow, `.github/workflows/build.yml`, adapted from the developer's double-cooked repo.
- **Trigger**: every push, plus manual `workflow_dispatch`. A newer push to the same ref cancels the older run.
- **Build job** (every branch), in order:
  1. checkout;
  2. restore or download the pinned Godot editor and web export templates (cached per version; the version is `GODOT_VERSION` in the workflow, the same as `CLAUDE.md`);
  3. write `build_info.txt` (short commit hash + UTC date);
  4. `--headless --import`, then the headless GUT tests (**a failing test means no deploy**);
  5. Godot web export with the `Web` preset to `build/web/`;
  6. upload `build/web` as a build artifact.
- **Pages** (`main` only): the build job uploads the Pages artifact and a `deploy-pages` job publishes it. The web preset has threads off, so no special headers are needed. One-time setup by the developer: repo Settings, Pages, Source: GitHub Actions.
- **itch.io** (`debug` branch only, not live yet): a last step of the build job pushes `build/web` to the itch.io channel `html5-debug` with butler. It skips itself until the developer has created the itch.io page and set `BUTLER_API_KEY` (secret), `ITCH_USERNAME` and `ITCH_GAME_ID` (variables) in GitHub. No AI session reads, writes or asks for the key.
- **Build info on screen**: `src/client/main.gd` shows the project version and `build_info.txt` in a corner. The preset's include filter lists `build_info.txt` and `data/**/*.json`, because Godot does not export non-resource files by default; it excludes `docs/`, `tests/`, `addons/gut/` and `.claude/`.
- **Web caveats**: run `test_prng` and the golden-replay tests in a web build once they exist (64-bit wraparound in the PRNG is verified on desktop only). Action versions in the workflow are copied from double-cooked; check them when they warn of deprecation.

## Online path (post-MVP, not committed)
The client sends an action, the Go backend authenticates and routes it, and a Godot headless worker runs `apply` and the Monster AI. The resulting events go back to every client in the fight. Clients keep the engine for queries and previews only; server events are authoritative. If Godot workers ever cost too much, port `src/rules/` and `src/ai/`, verified by the golden replays and AI golden tests.
