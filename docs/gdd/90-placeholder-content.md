# 90 — Placeholder content (throwaway)

Status: placeholder, for Playable 1 only · Owner: pilot

Everything here is **throwaway**. It exists so the first web build is playable, and it will be replaced by `02-creatures.md` and `03-world.md` after D4/D5.
- Names are role labels on purpose, so nobody grows attached to them.
- Numbers are first guesses, to be tuned through playtest rounds.
- Once G1 has turned this page into JSON under `data/`, **the JSON is the source of truth**: tune `data/`, not this page.

All rules referenced are in `01-combat.md`. Coordinates are axial `(q, r)`.

## Arena: PH Nave
- **Shape**: a regular hexagon of radius 5 around (0, 0), 91 cells.
- **Obstacles** (pillars): (−2, 0), (2, 0), (1, −2), (−1, 2).
- **Starting karma**: everything Neutral (0), except:

  | Cells | Karma | Why |
  |---|---|---|
  | (1, −4) and its 6 neighbors | −1 Corrupted | The Monster spawn sits in dirty ground: Blightborn bonus from step 1 |
  | (−1, 4) and its 6 neighbors | +1 Pure | Creature start: a Monster finished there is Cleansed |
  | (−4, 1), (−4, 2) | −2 Blighted | A stable hazard pair on clean ground |
  | (4, −1), (4, −2) | +1 Pure | A purity foothold on the far side |

  Starting board karma: −2.
- `collapse_at`: −40. `bloom_at`: +40.
- `creature_start_cells`: (−1, 4), (0, 4), (1, 3), (−2, 5), (−1, 5), (0, 5).

## Encounter: PH Encounter 1
Roster order:

| # | Monster | Spawn |
|---|---|---|
| 1 | PH Brute | (0, −4) |
| 2 | PH Brute | (1, −4) |
| 3 | PH Flier | (2, −5) |
| 4 | PH Flier | (−1, −3) |

Party order: PH Tank, PH Striker, PH Archer.

## Creatures
| Creature | max_hp | max_ap | max_mp | power | recharge_steps | Traits |
|---|---|---|---|---|---|---|
| PH Tank | 160 | 6 | 3 | 0 | 4 | — |
| PH Striker | 100 | 6 | 4 | 10 | 3 | — |
| PH Archer | 90 | 6 | 3 | 0 | 3 | — |

## Monsters
| Monster | max_hp | max_ap | max_mp | power | recharge_steps | Traits | Behavior |
|---|---|---|---|---|---|---|---|
| PH Brute | 160 | 6 | 2 | 0 | 4 | Heavy, Blightborn | `scripted_chase` |
| PH Flier | 70 | 4 | 4 | 0 | 2 | Nimble, Blightborn | `scripted_chase` |

## Abilities
Range is `min–max` in hex distance. "—" means none. Cooldown is in steps; 0 means none.

| Ability | Owner | phase | ap | target | range | LoS | line_only | Area | affects | Effects | karma | cooldown |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Shove | PH Tank | dash | 2 | enemy | 1–1 | no | no | single | enemies | push 2, then damage 6 | 0 | 1 |
| Bash | PH Tank | strike | 3 | enemy | 1–1 | no | no | single | enemies | damage 18 | −1 | 0 |
| Guard | PH Tank | prep | 3 | self | 0–0 | no | no | burst(1) | allies + user | Shield 20 for 2 steps | +1 | 2 |
| Lunge | PH Striker | strike | 3 | enemy | 1–2 | no | yes | single | enemies | damage 22 | −1 | 0 |
| Whirl | PH Striker | strike | 4 | self | 0–0 | no | no | burst(1) | enemies | damage 16 | −1 | 2 |
| Shot | PH Archer | strike | 3 | enemy | 2–6 | yes | no | single | enemies | damage 16 | 0 | 0 |
| Seed | PH Archer | prep | 3 | any_cell | 1–5 | yes | no | burst(1) | — | (no effects) | +1 | 2 |
| Pin | PH Archer | strike | 2 | enemy | 2–4 | yes | no | single | enemies | damage 6, then Rooted for 1 step | 0 | 2 |
| Slam | PH Brute | strike | 3 | enemy | 1–1 | no | no | single | enemies | damage 22 | −1 | 0 |
| Peck | PH Flier | strike | 2 | enemy | 1–2 | no | no | single | enemies | damage 10 | −1 | 0 |

What the kits test:
- **Tank**: hold, shove into pillars, and purify around itself.
- **Striker**: big damage, paid for in karma. Whirl corrupts 7 cells.
- **Archer**: clean damage at range, plus Seed. Seed is the setup tool for a Cleanse: purify the ground under a Monster, then finish it there (R11.3). It also meets the "each team can purify" constraint without the Keeper, who comes in T10b.

Both Monster abilities respect the Monster footprint cap (R11.2: −1 on a single cell).

## Statuses
| Status | Effect | Notes |
|---|---|---|
| Shield | Absorbs `amount` damage before HP (R7.3) | Guard grants 20 for 2 steps |
| Rooted | Cannot move (R4.5) | Pin applies it for 1 step |

## Behavior: `scripted_chase` (until T14)
Deterministic and dumb on purpose. At window start, for each Monster in roster order:
1. **Target**: the nearest Creature by hex distance (tie → roster order).
2. **Strike from here**: if one of its abilities can hit the target's current cell from where it stands (AP, range, LoS, cooldown), plan that ability with no move.
3. **Otherwise, close in**:
   - Find the reachable cells from which an ability could hit the target's current cell.
   - Move along the default path (R4.6) to the cheapest one by MP (tie → cell order).
   - Plan `move_first` with that ability if it is in range from the end cell. Otherwise move as far as MP allows toward the target, with no ability.
4. **Low on AP**: if it can't afford any ability, it only moves.

It aims at where Creatures stand *now* and never predicts movement, so dodging by moving works against it. That is fine for Playable 1.
