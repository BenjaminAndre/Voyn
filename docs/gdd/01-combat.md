# 01 — Combat

Status: draft (turn structure G, discrete steps, adopted provisionally) · Serves: Pillar 1 (Every turn reads clearly), Pillar 2 (The Land is the third player), Pillar 3 (Every fight has a cost), Pillar 4 (Roles that need each other)

## Purpose
A fight is a contest of position on a hex Arena, played in **steps**. Each step, time freezes for a short **window**, and every player plans what their Creatures will do. The Monsters plan too, in secret. Then everything resolves at once, in a fixed order you can read.

AP and MP don't come back every step. Each Creature recharges on its own rhythm, so *when* to act matters as much as *what* to do. Every ability marks the karma of the cells it touches, and the Land answers every step. Keepers stay off the board and make a world interaction when theirs has recharged.

Friends who plan together in the same window beat one player juggling every Creature. Solo is meant to feel like you could use help.

All Creatures, Monsters and abilities named here are placeholders.

## Rules
`code` names are keys in `data/combat/rules.json`, unless marked as Arena or fighter data. Tests reference rule IDs (R5.2…).

### R1 Grid
- **R1.1** The Arena is a set of hex Cells addressed by axial coordinates (q, r). Hex distance = `(|dq| + |dr| + |dq + dr|) / 2`.
- **R1.2** **Direction order**: D0 (+1, 0), D1 (+1, −1), D2 (0, −1), D3 (−1, 0), D4 (−1, +1), D5 (0, +1). A tie between directions goes to the lowest index.
- **R1.3** **Cell order**: ascending q, then ascending r. A tie between cells goes to the first in cell order.
- **R1.4** Each Cell has `walkable` (bool), `blocks_los` (bool), `height` (int; always 0 in MVP) and `karma` (R11.1). Every cell has karma, obstacles included. An **Obstacle** is a cell with `walkable = false` and `blocks_los = true`.
- **R1.5** A cell holds at most one Fighter. A fighter is never on a non-walkable cell.
- **R1.6** Cell properties change during a fight only through footprints (R11.2), defeats (R11.3), the Land phase (R11.4), Mutations (R8.5) and Keeper interactions (R12). Each battle starts from the Arena's authored state; nothing carries over between battles.

### R2 Fighters and Sides
- **R2.1** A **Fighter** is a **Creature** (fielded by a Keeper, player-controlled) or a **Monster** (AI-controlled). There are two Sides: the Keepers' Side and the Monsters' Side. Enemies are the fighters of the other Side. The Land is not a Side. **Keepers are not fighters**: they stay off the board (R12).
- **R2.2** Combat stats: `max_hp`, `max_ap`, `max_mp`, `power` (percent bonus to damage dealt), `recharge_steps` (R3.5). Values come from creature or Monster data. Recharge speed is a role axis: a fast skirmisher and a slow, heavy tank feel different (Pillar 4).
- **R2.3** **Traits** are permanent properties from creature or Monster data. MVP traits:
  - **Nimble**: ignores Engagement.
  - **Heavy**: Displacement against it moves 1 cell less (minimum 1).
  - **Immovable**: ignores Displacement.
  - **Stationary**: never moves by its own plan, and ignores Displacement.
  - **Blightborn**: ignores blight damage; +`blightborn_power_pct` to damage dealt while standing on a Corrupted or Blighted cell. All MVP Monsters are Blightborn.

### R3 Steps (turn structure G, provisional)
- **R3.1** **Placement phase**: Monsters spawn on the cells given by the Encounter. Each player places their Creatures on free start cells (`place`). The `start_fight` action ends placement, and step 1 begins.
- **R3.2** The fight is a sequence of **steps**. Each step is a **window**, then a **resolution**. The step number is always visible.
- **R3.3** **Window**: time is frozen for `step_window_ms` (8 s), solo included. The window ends early once every player is **Ready**.
  - Each player builds a **plan** for each of their Creatures. Each Keeper may plan its interaction if it has recharged (R12).
  - Plans can be edited freely until the window closes; nothing is final before that.
  - **Allies see each other's plans live. The other Side's plans stay hidden** until resolution: players don't see the Monsters' plans, and the AI doesn't see the players' plans.
  - The AI makes the Monsters' plans from the board as it stands when the window opens.
  - A fighter with no plan waits.
- **R3.4** **Plan**: at most **one movement segment** (a path within current MP) and at most **one ability**, in either order: move then ability ("close in and strike"), or ability then move ("hit and run"). A second ability or a second movement segment needs another step.
  - **Plan-time path check**: the path starts next to the cell the fighter stands on now, is contiguous, stays inside the Arena on walkable cells, and is no longer than current MP (1 MP per cell).
  - The path may cross cells that are occupied now, because their occupants may leave. Engagement and blocking are settled only at resolution (R4.8).
  - Stationary and Rooted fighters cannot plan a move.
- **R3.5** **Recharge**: AP and MP do not refill every step.
  - Every fighter starts the fight with full AP and MP.
  - A fighter's pool refills to its max in the Upkeep of every step whose number is a multiple of its `recharge_steps`. Step 1 is the first step.
  - Unspent points carry over until then, but a refill never overflows the max.
  - Spending now or holding for a better step is part of the decision.
- **R3.6** **Resolution**, in this fixed order every step. Each phase is animated in turn, with its name shown.
  1. **Lead moves**: movement segments of plans that start with a move (R4.8). A plan with only a move counts as a Lead move, so dodging by moving happens before Strike.
  2. **Abilities**, by their `phase` tag:
     - (a) **Prep**: buffs, Shields, purifies, and Keeper interactions;
     - (b) **Dash**: Displacement abilities, Creatures before Monsters, then roster order;
     - (c) **Strike**: damage and statuses, all computed from the state at the start of Strike and applied together. Then defeats are checked (R11.3), then footprints apply.
  3. **Trail moves**: movement segments of plans that end with a move (R4.8). A Trail move is cancelled (MP kept) if its fighter is no longer on the cell the path was planned from, e.g. after being displaced in Dash.
  4. **Upkeep**, in order:
     - due Telegraphs resolve, in placement order (R8);
     - Land effects on occupants: Blighted deals `blight_damage` (fixed; Blightborn ignore it), Thriving heals `thrive_heal`;
     - due status expiries (R6.6);
     - due refills (R3.5);
     - the Land phase, every `land_phase_every_steps` steps (currently every step, R11.4).
- **R3.7** **Fizzle**: an ability whose conditions (R6.1) no longer hold when it resolves fizzles. This happens when its user stopped short, LoS got blocked, or its target left the cell. A fizzled ability has no effect and no footprint, but its AP is still spent. You committed; the other Side read you.
- **R3.8** **Checkpoints and outcomes.**
  - **Elimination check**: after every phase and sub-phase in R3.6, and after each Telegraph payload entry. If a Side has no fighter left, the fight ends at once and the rest of the step is skipped.
  - **Land check** (R11.6): after every phase and sub-phase, and whenever an elimination check ends the fight.
  - When the fight ends, the outcome is the first of these that matches:
    1. **Collapse** (board karma ≤ `collapse_at`): everyone loses.
    2. **Bloom** (board karma ≥ `bloom_at`): the Keepers' Side wins, and every remaining Monster is Cleansed.
    3. No Monster left: **Victory**.
    4. No Creature left: **Defeat**.
    5. `forfeit`: **Defeat**.

  The result screen shows the outcome, Monsters Cleansed out of the total, and the final board karma. There is no step limit; stalemates are an open question. The bot-fight harness has its own cap (a test tool, not a rule).

#### Alternatives considered (D3)
- **A** Initiative line + pre-commit: the closest to Dofus, but waiting never disappears.
- **B** Side phases: whole-Side alpha strikes.
- **C** Untimed WE-GO.
- **D** Intents first: visible Monster plans; G's fallback if hidden plans read badly.
- **E** Alternating activations.
- **F** Slow real time with bullet time: parked, since G captures its co-op sync without real-time netcode.

The paper test (D3) can still compare G against A.

### R4 Movement
- **R4.1** A move enters an adjacent walkable cell for 1 MP. Fighters never pass through other fighters, allied or enemy.
- **R4.2** **Engagement**: leaving a cell costs `engagement_mp_per_enemy` extra MP per enemy adjacent to it. Nimble fighters ignore Engagement.
- **R4.3** A fighter that is not Blightborn takes `blight_damage` (fixed) for each Blighted cell it enters, by move, Displacement or Relocation (R8.6).
- **R4.4** Displacement (R7) is not movement: it costs no MP and ignores Engagement.
- **R4.5** A Rooted fighter cannot move.
- **R4.6** **Default path** (what the client suggests while planning): least blight damage, then least MP, then the lowest sequence of direction indices. The player may draw any path within MP.
- **R4.7** A mover defeated partway along its path stops there.
- **R4.8** **Simultaneous movement**: in a move phase, every mover advances one cell per **sub-tick**, in lockstep.
  - A mover enters its next cell if the cell is free, or is being vacated in that same sub-tick by a mover that does leave.
  - A cell held by a fighter that is not moving in this phase is never free.
  - **Conflict**: if several movers want the same cell, the one with fewer cells left in its path (counting the contested cell) wins, then Creatures before Monsters, then roster order. The others stop for good: they don't move again in this phase, even if a cell frees up later.
  - Two movers swapping cells, or any longer cycle, are all blocked and stop.
  - MP and Engagement are paid per cell, against positions at the start of the sub-tick. A mover that cannot pay stops.
  - A stopped mover keeps its unspent MP, and its plan's ability (if it comes after the move) may then fizzle (R3.7).

### R5 Line of sight
- **R5.1** LoS from cell A to cell B is checked along hex lines from A to B. Every cell on a line except A and B must be clear: not `blocks_los` and not occupied by a fighter.
- **R5.2** Two lines are tested, one with a positive nudge and one with a negative nudge. LoS is clear if either whole line is clear. The exact integer algorithm is in `docs/architecture.md`. LoS is symmetric: LoS(A, B) = LoS(B, A).
- **R5.3** A cell always has LoS to itself and to its neighbors.

### R6 Abilities
- **R6.1** An ability is checked twice:
  - when it is planned: against the board as it stands, from the cell the plan puts its user on. Allies' plans only feed the preview (R9), never validation;
  - when it resolves: against the board as it then is.

  Both times, it is valid only if all of these hold:
  1. the user's AP ≥ `ap_cost`;
  2. hex distance from the user to the target cell is within `[min_range, max_range]`;
  3. if `needs_los`: LoS from the user to the target cell;
  4. if `line_only`: the target cell lies on one of the six axes through the user;
  5. the target cell matches the `target` filter: `any_cell`, `empty_cell`, `any_fighter`, `enemy`, `ally` or `self`;
  6. the ability is off **cooldown** (cooldown N: usable again N steps later).

  Failing at resolution means it fizzles (R3.7).
- **R6.2** Abilities target **cells**, not fighters: an ability aimed at a cell hits whoever is there when it resolves. Its **Area** is computed from the target cell and ignores LoS and obstacles:
  - `single`: the target cell;
  - `burst(r)`: all cells within distance r;
  - `line(n)`: n cells starting at the target and continuing away from the user along the axis (needs `line_only`).

  The `affects` filter (`enemies`, `allies`, `all`, plus `include_user`) chooses which fighters in the Area are hit.
- **R6.3** The affected fighters are fixed when the ability starts resolving, by identity. Effects resolve in listed order, fighters in roster order within an effect. The exception is Displacement: farthest from the push origin first. The footprint (R11.2) applies after the effects (in Strike: after all Strike abilities, R3.6).
- **R6.4** Every ability has a `phase` tag (`prep`, `dash` or `strike`) that sets when it resolves (R3.6). MVP effect types: `damage`, `heal`, `shield`, `push`, `pull`, `apply_status`, `mutate`, `telegraph`. Every ability also has a `karma` footprint (R11.2), which may be 0.
- **R6.5** `mutate` applies a Mutation (R8.5) to the Area. Only Creature abilities and Keeper interactions may use it. Their `raise_obstacle` skips occupied cells. Monsters change cells only through `telegraph` and their limited footprints (R11.2).
- **R6.6** **Statuses** are named, timed bundles of modifiers defined in `data/statuses/`.
  - A status with duration N ends in the Upkeep of the Nth step after the step that applied it.
  - Reapplying a status replaces it (magnitude, duration, source): the newest wins, and Shield never stacks.
  - MVP statuses: **Vulnerable** (+% damage taken), **Guarded** (−% damage taken), **Rooted** (cannot move), **Shield** (R7.3).
- **R6.7** If the user is defeated while its own ability resolves, the rest of that ability still resolves.
- **R6.8** **Chance**: an effect may carry a `chance` (percent).
  - The plan preview shows the odds and both results.
  - The roll happens at resolution, from the fight's seeded PRNG.
  - No other randomness exists in combat.

### R7 Damage, healing, defeat, Displacement
- **R7.1** **Damage** = floor(max(0, base × (100 + user `power` + Σ user damage-dealt % + Σ target damage-taken %)) / 100). All modifiers add into one sum (the Blightborn bonus included); none multiply. **Fixed damage** ignores all modifiers. It covers collision, crush, blight and all Telegraph damage.
- **R7.2** **Heal** restores HP, capped at `max_hp`. `power` does not affect healing in MVP.
- **R7.3** **Shield** is a status that holds an amount. Any damage, fixed damage included, reduces Shield first and then HP. Shield is removed at 0 or when its duration ends.
- **R7.4** A fighter at 0 HP is **defeated** (R11.3).
  - It leaves the fight and its cell becomes free, and its remaining plan for this step is dropped.
  - Statuses on it are removed, and so are statuses it applied and Telegraphs it placed.
  - A defeated Creature is **Downed**: out for this fight only.
- **R7.5** **Push n** moves the target up to n cells, one at a time, away from the **push origin**.
  - The push origin is the user's cell, or the target cell if the ability sets `push_origin: target`.
  - The direction is computed once, before the first cell: the Dk closest to the vector from the origin to the pushed fighter's cell (largest dot product in cube coordinates; tie → lowest index).
  - A fighter on the origin is not pushed.
  - **Pull n** uses the opposite direction and stops once the target is adjacent to the origin.
  - Heavy reduces n by 1, to a minimum of 1.
- **R7.6** A push stops early when the next cell is non-walkable, occupied or outside the Arena. The pushed fighter then takes **collision damage**: `collision_damage_per_cell` × cells not travelled. The fighter or obstacle it hits takes nothing. A pull never deals collision damage. A fighter defeated mid-push stops there with no collision damage. A displaced fighter's Trail move in the same step is cancelled (R3.6).
- **R7.7** Immovable and Stationary fighters are never displaced and take no collision damage from a push aimed at them.

### R8 Telegraphs and Mutations
- **R8.1** A `telegraph` effect has its own Area (usually `cells([...])`, an absolute list from data, allowed only here). It marks those cells with a pending **payload**: an ordered list of entries, each holding effects and/or Mutations plus its own `affects` filter (relative to the source's Side).
- **R8.2** **Telegraphs are the exception to hidden plans.** Once placed, a Telegraph is visible to everyone. It resolves in the Upkeep of the Nth step after the one that placed it, with N ≥ `telegraph_min_delay` steps. It hits whoever stands on its cells at that moment, so a Trail move (or any later step) can dodge it.
- **R8.3** On resolution:
  - the affected fighters are those on the marked cells when resolution starts, fixed by identity;
  - entries resolve in listed order, and cells within an entry in cell order;
  - all Telegraph damage is fixed damage, so the number shown is exact.
- **R8.4** Every Telegraph shows its cells, its payload, its exact damage and the steps left.
- **R8.5** MVP **Mutations** (karma is never removed):
  - `raise_obstacle`: sets `walkable = false`, `blocks_los = true`;
  - `clear_obstacle`: sets `walkable = true`, `blocks_los = false`;
  - `shift_karma(n)`: adds n to the cell's karma.

  Several Mutations on one cell apply in order, and the last one wins.
- **R8.6** **Crushed**: when a Telegraph's `raise_obstacle` hits an occupied cell:
  - if no walkable, unoccupied cell exists outside the cells this payload raises, the Mutation is cancelled for that cell and no damage is dealt;
  - otherwise the occupant takes `crush_damage` (fixed). If that defeats it, the obstacle rises;
  - if it survives, it is relocated to the nearest such cell by hex distance (tie → cell order), and the obstacle rises.

  **Relocation** is not Displacement: it applies to every fighter, Immovable and Stationary included, and triggers blight entry damage (R4.3).

### R9 Previews (Pillar 1)
- **R9.1** While planning, a player sees exactly what their plan would do **on the board as it stands, plus their allies' current plans**:
  - path, MP cost, Engagement and blight damage;
  - ability validity, Area, exact damage, heal and Shield change;
  - Cleanse or Kill on a final blow;
  - Displacement end cells and collision damage;
  - odds and both results for any `chance` effect;
  - the footprint, and the karma, forecast and Land meter after the step.

  What the other Side plans is unknown. The preview shows each enemy's **threat zone** (the cells it could reach and hit this step, given its current AP/MP), so the guess is informed.
- **R9.2** Previews run the real resolution on a copy of the state with the player's and allies' plans; enemy plans are left empty. Golden tests check that, with the same plans on every Side, preview and result match exactly.
- **R9.3** **Visual grammar**, so the layers never compete:
  - karma = tile tint (two shades each way);
  - forecast = edge chevrons;
  - Telegraph = cell outline plus steps left;
  - planned paths = arrows (allies' in their own color);
  - reachable, target and Area = floor highlights;
  - threat zones = hatched overlay, on demand;
  - Cleanse/Kill = an icon over the fighter.

  Always on screen: the **window timer bar** with each player's Ready mark, each fighter's **recharge pips**, and the **Land meter** (one bar from `collapse_at` to `bloom_at`, marking board karma now and after this step's Land phase). During resolution, a banner names the current phase.

### R10 AI control
- **R10.1** Each Monster is played by the AI behavior named in its Monster data. In bot fights, Creatures are played by `greedy` with per-creature weights.
- **R10.2** At window start, the AI makes one plan per Monster from the visible board. It does not see the players' plans; it may consider their threat zones. Behavior `greedy` (integer weights from behavior data):
  1. Simulate every (path, ability, order) within the Monster's AP/MP on a copy of the state, assuming the other Side waits.
  2. **Outcomes override weights**: a result that ends the fight is scored by per-outcome weights. By default, Monsters treat Collapse as a loss, so they pollute up to the brink, never past it. A behavior may set `wants_collapse`: a boss that doesn't care to lose. For Creature bots: Bloom > Victory, and Collapse scores lowest.
  3. Otherwise, score damage dealt, defeats (Cleansed and Killed separately), board karma change, exposure, distance to preferred range, and the karma of the end cell.
  4. Holding AP for a later step is a valid plan, and is scored against acting now.
  - Ties: path end cell (cell order), then ability list order, then target cell (cell order).
  - **Exposure** of a cell = number of enemies whose threat zone contains it.
- **R10.3** Bosses may use a scripted pattern from their data instead.
- **R10.4** AI is deterministic given the fight seed, and integer-only. It has its own golden tests (state → chosen plans).

### R11 The Land
- **R11.1** **Karma**: every cell has a karma from −2 to +2 (names are working names):

  | Value | Name |
  |---|---|
  | −2 | Blighted |
  | −1 | Corrupted |
  | 0 | Neutral |
  | +1 | Pure |
  | +2 | Thriving |

  Arena data sets the starting pattern. Every change is clamped to this range.
- **R11.2** **Footprint**: every ability has an integer `karma` value.
  - After its effects, the value is added to every cell of its Area. Negative values corrupt; positive values purify. A fizzled ability leaves no footprint.
  - Telegraphs change karma only through `shift_karma` in their payload.
  - **Monster abilities** may only have `karma` 0 or −1 on a `single` Area (the loader rejects anything else). Larger Monster corruption must be Telegraphed.
  - A footprint is part of an ability's cost (priced in `02`).
- **R11.3** **Cleansed or Killed.** When a Monster is defeated, check its cell's karma at that moment:
  - **Pure or Thriving → Cleansed.** It leaves peacefully. **Renewal**: its cell and each adjacent cell gain +1.
  - **Otherwise → Killed.** Its cell becomes Blighted.

  A Downed Creature's cell becomes Blighted too. Violence pollutes.
- **R11.4** **Land phase** (in Upkeep, every `land_phase_every_steps` steps; currently every step). All cells update at once, each from the state before the update. Neighbor sums count the 6 neighbors; a missing neighbor (Arena edge) counts as 0.
  - **Corruption**:
    - a cell whose neighbors sum to ≤ −`land_sum_threshold` loses 1;
    - a Corrupted cell with at least one Blighted neighbor becomes Blighted.
  - **Purity**:
    - a cell whose neighbors sum to ≥ +`land_sum_threshold` gains 1;
    - a Pure cell with at least one Thriving neighbor becomes Thriving.
  - **Contested**: if a corruption rule and a purity rule both apply to a cell, it does not change.

  With `land_sum_threshold = 5`, a blighted blob on clean Neutral ground fills its own gaps and then stops: no cell outside a straight edge has more than 2 Blighted neighbors (−4). On ground that is already corrupted, it runs away. Purity behaves the same way. Land-phase changes cause no damage or healing by themselves.
- **R11.5** **Forecast**: the cells the next Land phase would change are always marked (R9.3) and recomputed after every change.
- **R11.6** **Board karma** = the sum of every cell's karma. Arena data sets `collapse_at` (negative) and `bloom_at` (positive). Reaching either one ends the fight (R3.8). Obstacles keep their karma, so walls never game the total.

### R12 Keeper interactions
- **R12.1** Each Keeper stays off the board. It can never be targeted or defeated.
- **R12.2** A Keeper may plan one interaction in a step's window once it has recharged (every `keeper_recharge_steps` steps). It resolves in Prep (R3.6) and is hidden from the other Side like any plan. A Keeper keeps planning even when all its own Creatures are Downed, as long as the fight goes on (e.g. allies in group play).
- **R12.3** Interactions come from two places:
  - the Arena: **interactables** placed in Arena data, such as a bell, a lever or a fountain;
  - Keeper **tools** unlocked in the overworld.

  Nothing is class-locked: every Keeper can unlock every tool.
- **R12.4** An interaction resolves like an ability with no user cell. It ignores range and LoS unless its data says otherwise, has a karma footprint, and goes through the same preview.
- **R12.5** MVP: one tool (`purify`: `shift_karma(+1)` on one cell, placeholder) plus the Arena's 1–2 interactables.

## Post-MVP rules (provisional, M4+)
- **Height**: integer levels 0–3.
  - Stepping up one level costs `height_step_mp` extra MP; stepping up two or more is impossible; stepping down is free.
  - Displacement down two or more levels deals `fall_damage_per_level` (fixed) per level beyond the first.
  - An attacker higher than its target deals +`height_advantage_pct` damage.
  - A cell between A and B blocks LoS if it is higher than both A and B.
- **Rotating zones**: a ring of cells turning in 60° steps around a center, carrying cell properties, karma, occupants and Telegraphs. Always telegraphed.
- **Arena events**: scripted Arena Telegraphs.
- **Biome**: a whole-battle modifier (e.g. "ash field: blight damage +5"), never per cell.
- **Harvest**: taking resources from Pure/Thriving cells at a karma cost (Jolar's fruits).

## Interactions
- `02-creatures.md` builds creature kits only from the targeting, Area, effect, phase and status types defined here. It prices each ability's karma footprint, push distance and cooldown, and each creature's `recharge_steps`. A new effect type is a combat change and lands here first. Constraints:
  - each MVP team can purify;
  - no MVP Creature ability combines `shift_karma` and `damage` on overlapping cells, so a Cleanse takes setup.
- `03-world.md` defines Arenas (cells, starting karma, `collapse_at`, `bloom_at`, interactables, start cells), Monsters (stats, traits, `recharge_steps`, behaviors) and Encounters. Constraints:
  - boss payloads hit enemies only;
  - every Monster has a Cleanse route the player can set up within a few steps from its preferred cell, proven by a scripted golden replay.
- `05-progression.md`: Keeper tools, creature collection (recruit by Cleansing, proposed).
- `docs/architecture.md`: engine contract, step scheduler, seeded PRNG, LoS algorithm, determinism, golden replays.

## Edge cases
- **Strike on a cell the target left in Lead moves**: it hits whoever is there now, possibly nobody. An `enemy`- or `ally`-filtered ability fizzles instead (R3.7).
- **Two fighters strike each other in the same step**: both hits land, since Strike is simultaneous. Both can be defeated.
- **Push in Dash, then an ally's strike on the push destination**: a same-step combo across players. It works because Dash comes before Strike.
- **Mover blocked by another mover** (conflict, swap or cycle): it stops (R4.8). A following ability may fizzle.
- **Telegraph dodge**: a Trail move off the marked cells avoids a Telegraph resolving in that step's Upkeep.
- **Finishing blow on Neutral ground**: the Monster is Killed. Footprints apply after defeats, so setting up a Cleanse takes an earlier step, an ally's Prep purify, a Keeper interaction, or a push onto Pure ground.
- **The last Monster's Kill tips the board into Collapse**: Collapse wins (R3.8).
- **A Renewal tips the board into Bloom**: Bloom. Every remaining Monster is Cleansed.
- **Contested cells** hold still. The forecast shows them as unchanged.
- **Blightborn fighter pushed or relocated into blight**: no damage (R4.3).
- **Push into a fighter**: the pushed fighter stops and takes collision damage. The fighter it hits takes nothing.
- **Push through blight**: blight damage per Blighted cell entered, plus collision damage if stopped later.
- **Obstacle raised under a fighter**: Crushed (R8.6). Creature and Keeper `mutate` never crushes (R6.5).
- **Source defeated**: its statuses and Telegraphs vanish (R7.4).
- **All my Creatures Downed in group play**: my Keeper keeps planning (R12.2).
- **Nobody plans anything for a step**: resolution still runs Upkeep, so the Land keeps moving.

## MVP cut
- **M1 (headless engine)**: R1–R12, height always 0.
- **M2a/M2b (client)**: planning UI, previews (R9), AI (R10), karma display, result screen.
- **M3**: the boss as the only Telegraph source, plus Telegraph display.
- **Out**: height, rotating zones, Arena events, biomes, harvest, summons, elements and resistances, range modifiers, movement footprints, invisibility, revival, fleeing, PvP (never), online.

## Open questions
- **Fizzle cost**: is spending the AP of a fizzled ability fun-frustrating or just frustrating?
- **Window length**: 8 s solo is meant to sting (bring friends). Offer a longer-window accessibility option?
- **Land phase every step**: likely too fast at 8 s steps. Tune `land_phase_every_steps` in M2a.
- **Plan order**: move→ability and ability→move both allowed (pilot addition to the user's "move then strike"). Keep both?
- **Threat zones**: always on, on demand, or not at all (pure mind game)?
- **Stalemates** without a step limit: what ends a fight nobody can win?
- **Group size**: how many Creatures per player, solo vs group, so 8 s stays playable?
- **Monster pollution**, **Thriving healing Monsters**, **Downed Creatures blighting**: keep or soften?
- **`land_sum_threshold` = 5**: tune with the forecast in M2a.
- **Engagement** costs MP only. Does a tank need a stronger hold?
