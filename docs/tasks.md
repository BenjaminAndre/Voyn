# Backlog

Prioritized: top to bottom. Each task fits one session and leaves the game runnable with tests green. Take the first open task whose dependencies are done. Tick it here when it is done, in the same commit.

Who: **dev** = Sonnet session or `dev` agent · **grunt** = `grunt` agent (Haiku), spot-checked · **pilot** = Opus session · **you** = the developer.

## Broad lines (before content and before T5)
- [ ] **D3 Validate discrete steps** (you + pilot). G is adopted provisionally and `01-combat.md` R3 is written for it.
  - Paper-test it, ideally with a friend: a printed hex mat, tokens, face-down plan cards revealed together, an 8 s sand timer, and phases resolved by hand (Lead moves → Prep → Dash → Strike → Trail moves → Upkeep).
  - Optionally play the same fight with A (initiative + pre-commit) for contrast.
  - Settle the open choices in `01-combat.md`: fizzle cost, plan order, threat zones, Land cadence.
- [ ] **P1 Step sandbox** (dev, needs T3, T4; optional). Only if paper leaves the feel undecided: real timing pressure is the one thing paper can't fake.
  - A 2D top-down debug board with circles for fighters and 2–3 fixture abilities each.
  - A real 8 s window, Ready, recharge pips, simultaneous resolution.
  - Throwaway code outside `src/rules/`, so it never blocks M1.

  *Done when:* the user can play a 3-vs-3 skirmish solo, and with a friend on one machine.
- [ ] **D4 Collection and progression** (you + pilot). Recruit only Cleansed creatures? Creatures per Keeper, solo and in groups. What Keeper tools are, and how they unlock. Draft `05-progression.md`.
- [ ] **D5 Setting brief** (you + pilot). A page: what "solarpunk fantasy" means for Voyn, references, palette, tone. Names come after.

## M0 — Setup (design-independent, can run any time)
- [x] **T1 Project setup** (dev). `git init` with a Godot `.gitignore`; commit the existing docs first. Ask the user to install the latest Godot 4 stable; don't download it yourself. Create `project.godot` at repo root (Compatibility renderer). Add `.gdignore` to `docs/`. Install GUT and add one smoke test. Write the exact Godot version and the commands (open editor, run game, run tests headless) into `CLAUDE.md`.
  *Done when:* the documented headless test command passes from a fresh clone.
- [ ] **T1b `debug` → itch.io pipeline** (dev, needs T1). First, **you**: create the GitHub repo and the itch.io page, and set `BUTLER_API_KEY` (secret), `ITCH_USERNAME` and `ITCH_GAME_ID` (variables) in GitHub. Then dev:
  - add a minimal main scene that shows `build_info.txt` in a corner;
  - add a web export preset whose include filter lists `build_info.txt` and `data/**/*.json`;
  - write the workflow described in `docs/architecture.md` (tests, then export, then publish).

  *Done when:* a push to `debug` shows the new commit hash on itch.io.
- [ ] **T2 Data loader** (dev, needs T1). `src/rules/` loader for `data/combat/rules.json`. It converts JSON numbers to int, rejects non-integers, missing keys and unknown keys, and asserts `telegraph_min_delay ≥ 1`.
  *Done when:* tests cover a valid file and each rejection.
- [ ] **T2b Seeded PRNG** (dev, needs T1). Hand-written integer generator in `src/rules/` (`docs/architecture.md`). A test pins the first 1,000 outputs for a fixed seed; that list becomes part of the port contract.

## M1 — Complete headless rules engine
Tests use fixture creatures, abilities, Monsters and Arenas in `tests/fixtures/`, not real content, so M1 does not wait on `02`/`03`.
- [ ] **T3 Hex math** (dev, needs T1). Axial and cube coords, distance, neighbors, direction order, cell order, push-direction pick, `floor_div` (R1.1–R1.3, R7.5). Integer only.
- [ ] **T4 LoS** (dev, needs T3). Implement the algorithm in `docs/architecture.md` exactly. Generate `tests/golden/los_table.json` for a fixture Arena after hand-checking a sample.
  *Done when:* a symmetry test over every cell pair passes.
- [ ] **T4b Karma automaton** (dev, needs T3). Pure function: karma grid → next karma grid (R11.4), plus `forecast`. It does not depend on the turn structure.
  *Done when:* tests on an all-Neutral fixture show that a blight pair, a blight triangle and a hexagonal blob each stay bounded over 20 phases, a corrupted field runs away, the purity mirror holds, contested cells hold, and edge cells treat missing neighbors as 0.
- [ ] **T5 State, step scheduler, events** (dev, needs T2, T2b, T3). Copyable plain-data state with a step counter. Plan format and `validate_plan`. A `resolve_step` skeleton with the phase order. Recharge refills, placement, `start_fight`, elimination checkpoints, Victory, Defeat, `forfeit` (R2, R3). Write the event schema into `docs/architecture.md`.
- [ ] **T6 Movement + `reachable`** (dev, needs T5). Simultaneous lockstep movement with conflicts, swaps and cycles (R4.8, the algorithm in `docs/architecture.md`). Also Engagement, Rooted, blight entry damage, Blightborn, default path, defeat mid-path (R4).
  *Done when:* there are tests for a same-cell conflict, a swap, a 3-cycle, and a follow-the-leader chain.
- [ ] **T7 Abilities + `targets`** (dev, needs T4, T6). Plan-time and resolution-time validation, Fizzle, `phase` tags (Prep/Dash/Strike), simultaneous Strike, cooldowns in steps, Areas, `damage`/`heal`/`shield`/`apply_status`, statuses, `chance` (R6, R7.1–R7.4, R3.7). Define the ability, status and behavior JSON schemas (incl. `karma`, `phase`).
  *Done when:* there are tests for two fighters defeating each other in one Strike, and for a strike fizzling after its target walked away.
- [ ] **T8 The Land in fights** (dev, needs T4b, T7). Footprints incl. the Monster cap in the loader, Upkeep blight/thrive on occupants, Cleansed / Killed / Downed, Renewal, the Land phase every `land_phase_every_steps`, board karma, Collapse and Bloom checkpoints (R11, R3.6, R3.8).
- [ ] **T9 Displacement** (dev, needs T7). Push, pull, Heavy, collision damage, farthest-first order, blight entered mid-push, Immovable/Stationary (R7.5–R7.7).
- [ ] **T10 Telegraphs + Mutations** (dev, needs T8, T9). `telegraph`, `mutate`, `shift_karma`, `cells([...])`, payload order, Crushed and Relocation (R6.5, R8).
- [ ] **T10b Keeper interactions** (dev, needs T10). Keeper plans, interactables in Arena data, the `purify` tool, `keeper_recharge_steps`, resolution in Prep (R12).
- [ ] **T11 Golden replays** (dev, needs T10b). Replay JSON format (seed + plans per step), a runner, and the first replays:
  - Engagement and LoS;
  - push-then-strike across two players in one step;
  - a dodge by a Lead move, and a Telegraph dodge by a Trail move;
  - push through blight;
  - Cleanse vs Kill;
  - corruption runaway into Collapse, and purification into Bloom;
  - Crushed;
  - a `chance` branch;
  - preview = result when every Side's plans are known.

## Content (after broad lines)
- [ ] **D1 `02-creatures.md` MVP** (pilot, needs D3, D4, D5). 3 creatures × 2–4 abilities with priced footprints, meeting the constraints in `01-combat.md` Interactions. Run `design-critic`.
- [ ] **D2 `03-world.md` MVP** (pilot, needs D3, D5). Arena layout, starting karma, `collapse_at`/`bloom_at`, interactables; 3 Monsters with stats, traits, behaviors and weights; 2 Encounters. Meet the constraints in `01-combat.md` Interactions.
- [ ] **G1 Content data entry** (grunt, needs D1, D2, T7). Turn the numbers from D1/D2 into JSON under `data/`, following the T7 schemas. Dev spot-checks it with the loader.

## M2a — Planning window vs scripted Monsters
- [ ] **T12 Minimal 3D board** (dev, needs T5, T1b). Hex prism tiles from Arena data, tinted by karma; forecast chevrons; Land meter (R9.3); fixed orthographic camera; placeholder meshes by Side and creature; phase-by-phase animation from events (tweens only).
- [ ] **T13 Planning UI** (dev, needs T11, T12, G1).
  - The 8 s window timer with Ready, and plan building per Creature (path + ability + order).
  - The Keeper interaction, and recharge pips.
  - Basic previews: reachable cells, valid targets, damage numbers, footprint, odds.
  - Monsters play scripted plans until T14.
  - Local co-op on one screen, with allies' plans visible.
- [ ] **F1 Fun check** (you). Play Encounter 1 solo, then with a friend. Do steps, roles and the Land feel fun? Is solo frustrating in the good way?

## M2b — Fight vs AI
- [ ] **T14 Greedy AI** (dev, needs T11). R10.2: one plan per Monster at window start, integer weights, outcome overrides, the option to hold AP. Plus AI golden tests.
- [ ] **T15 Full previews + forecast** (dev, needs T13). Everything in R9.1: Cleanse/Kill markers, threat zones, ghosted post-step state, Chance branches.
- [ ] **T16 Encounter flow** (dev, needs T14, T15). Placement UI, Encounter 1 vs AI, the four outcomes, result screen (Cleansed k/n, final board karma), forfeit, restart, camera rotation in 60° steps.
- [ ] **T17 Bot-fight runner** (dev, needs T14, G1). Headless greedy Creatures vs Encounter, N fights with a harness-only step cap. Reports the outcome mix, steps per fight, and what drove each Collapse or Bloom.
- [ ] **F2 Fun check** (you).

## M3 — The arena fights back
- [ ] **T18 Boss + Encounter 2** (dev, needs T16). Scripted pattern behavior (R10.3), Telegraph display (R8.4).
- [ ] **F3 Fun check** (you).
