# Backlog

Prioritized: top to bottom. Each task fits one session and leaves the game runnable with tests green. Take the first open task whose dependencies are done. Tick it here when it is done, in the same commit.

Who: **dev** = Sonnet session or `dev` agent · **grunt** = `grunt` agent (Haiku), spot-checked · **pilot** = Opus session · **you** = the developer.

**Build loop**: every push to `main` publishes a playable web build. Playtest rounds in `docs/playtest.md` feed this backlog. Getting to the first playable build comes before everything else.

## Waiting on you
- **Enable GitHub Pages**: repo Settings → Pages → Source: GitHub Actions. Then check the first workflow run.
- **T1c itch.io deploy** (optional, later): create the itch.io page and set `BUTLER_API_KEY` (secret), `ITCH_USERNAME` and `ITCH_GAME_ID` (variables) in GitHub. Then dev creates the `debug` branch and confirms a push shows the commit hash on itch.io.

## Now: Playable 1 (the first build you can play)
Placeholder content only (`docs/gdd/90-placeholder-content.md`). No Telegraphs, Keeper or AI yet.
- [x] **T7 Abilities + `targets`** (dev). Plan-time and resolution-time validation, Fizzle, `phase` tags (Prep/Dash/Strike), simultaneous Strike, cooldowns in steps, Areas, `damage`/`heal`/`shield`/`apply_status`, statuses, `chance`, and the `threat_zone` query (R6, R7.1–R7.4, R3.7). Define the ability, status and behavior JSON schemas (incl. `karma`, `phase`).
  *Done when:* there are tests for two fighters defeating each other in one Strike, and for a strike fizzling after its target walked away.
  *Notes for the pilot*: footprints are already applied by the ability resolver (T8 keeps the Monster cap, Upkeep Land effects and the Land phase). Reading choices to confirm or change in the GDD: cooldown N = usable again N steps later (so 1 never restricts); a fizzled ability still starts its cooldown; `chance` is rejected by the loader until R6.8 says per effect or per fighter; `allies` excludes the user, `include_user` adds it.
- [x] **T8 The Land in fights** (dev, needs T7). Footprints incl. the Monster cap in the loader, Upkeep blight/thrive on occupants, Cleansed / Killed / Downed, Renewal, the Land phase every `land_phase_every_steps`, board karma, Collapse and Bloom checkpoints (R11, R3.6, R3.8).
- [ ] **T9 Displacement** (dev, needs T7). Push, pull, Heavy, collision damage, farthest-first order, blight entered mid-push, Immovable/Stationary, Trail move cancelled after displacement (R7.5–R7.7, R3.6).
- [ ] **G1 Placeholder data** (grunt, needs T7). Turn `docs/gdd/90-placeholder-content.md` into JSON under `data/` (creatures, abilities, statuses, monsters, behaviors, arenas, encounters), following the T7 schemas. Dev spot-checks it with the loader and a load test.
- [ ] **T12 Minimal 3D board** (dev, needs T5, G1). Hex prism tiles from Arena data, tinted by karma; forecast chevrons; Land meter (R9.3); fixed orthographic camera; placeholder meshes by Side and creature; phase-by-phase animation from events (tweens only).
- [ ] **T13 Planning UI** (dev, needs T8, T9, T12).
  - The 8 s window timer with Ready, plus a dev-only "untimed" toggle (not a game rule).
  - Plan building per Creature (path + ability + order), and recharge pips.
  - Basic previews: reachable cells, valid targets, damage numbers, footprint.
  - Monsters use the `scripted_chase` behavior from the placeholder spec.
  - Local co-op on one screen, with allies' plans visible.
- [ ] **T13b Fight end + restart** (dev, needs T13). Outcome banner (Victory, Defeat, Bloom, Collapse), Monsters Cleansed k/n, final board karma, a Restart button. Push to `main`: this is **Playable 1**.
- [ ] **R1 Playtest round 1** (you). Play the Pages build and write the checklist in `docs/playtest.md`.

## Next (order set by playtest rounds)
- [ ] **T11 Golden replays** (dev, needs T9). Replay JSON format (seed + plans per step), a runner, and replays for what exists:
  - Engagement and LoS;
  - push-then-strike across two players in one step;
  - a dodge by a Lead move;
  - push through blight;
  - Cleanse vs Kill;
  - runaway into Collapse, and purification into Bloom;
  - a `chance` branch;
  - preview = result when every Side's plans are known.

  Add Telegraph and Keeper replays when T10/T10b land.
- [ ] **T10 Telegraphs + Mutations** (dev, needs T8, T9). `telegraph`, `mutate`, `shift_karma`, `cells([...])`, payload order, Crushed and Relocation (R6.5, R8).
- [ ] **T10b Keeper interactions** (dev, needs T10). Keeper plans, interactables in Arena data, the `purify` tool, `keeper_recharge_steps`, resolution in Prep (R12).
- [ ] **T14 Greedy AI** (dev, needs T11). R10.2: one plan per Monster at window start, integer weights, outcome overrides, the option to hold AP. Plus AI golden tests. Replaces `scripted_chase`.
- [ ] **T15 Full previews + forecast** (dev, needs T13). Everything in R9.1: Cleanse/Kill markers, threat zones, ghosted post-step state, Chance branches.
- [ ] **T16 Encounter flow** (dev, needs T14, T15). Placement UI, forfeit, camera rotation in 60° steps, best outcome per Encounter saved locally.
- [ ] **T17 Bot-fight runner** (dev, needs T14). Headless greedy Creatures vs Encounter, N fights with a harness-only step cap. Reports the outcome mix, steps per fight, and what drove each Collapse or Bloom.
- [ ] **T18 Boss + Encounter 2** (dev, needs T10, T16). Scripted pattern behavior (R10.3), Telegraph display (R8.4).

## Design track (parallel; replaces the placeholders)
- [ ] **D4 Collection and progression** (you + pilot). Recruit only Cleansed creatures? Creatures per Keeper, solo and in groups. What Keeper tools are, and how they unlock. Draft `05-progression.md`.
- [ ] **D5 Setting brief** (you + pilot). A page: what "solarpunk fantasy" means for Voyn, references, palette, tone. Names come after.
- [ ] **D1 `02-creatures.md`** (pilot, needs D4, D5, a few playtest rounds). Real creatures replacing the placeholders. Run `design-critic`.
- [ ] **D2 `03-world.md`** (pilot, needs D5). Real Arena, Monsters and Encounters replacing the placeholders.
- Dropped: the D3 paper test and the P1 sandbox. Steps are validated through playtest rounds instead.

## Done
- [x] **T1** Project setup: Godot 4.7.2, GUT, smoke test, commands in `CLAUDE.md`.
- [x] **T1b** Web build and GitHub Pages pipeline (`.github/workflows/build.yml`).
- [x] **T2** Rules loader. **T2b** Seeded PRNG (PCG32, golden outputs).
- [x] **T3** Hex math. **T4** LoS (golden table). **T4b** Karma automaton and forecast.
- [x] **T5** Fight state, step scheduler, events, plans, defeats. **T6** Simultaneous movement, `reachable`, default paths.
