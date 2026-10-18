# Playtest checklist

The build loop: agents build in the background, every push to `main` becomes a playable web build, you play it and write a checklist, and agents work through it.

## How a round works
1. **Build.** A push to `main` runs the tests, then publishes the web build to GitHub Pages. The commit hash shows in a corner of the screen. (Later, the `debug` branch also goes to itch.io: task T1c.)
2. **Play and write.** Add items under **Inbox** below: one line each, prefixed with the build hash you played. Start a line with `!` if it must be fixed before anything else. Raw notes are fine: "brute feels unkillable", "can't tell whose turn it is".
3. **Triage (pilot).** The pilot moves each Inbox item into the next round and tags it:
   - `[dev]`: a clear fix; the implementation is obvious;
   - `[design]`: needs a decision. The pilot proposes one in the item; you approve or redirect. Rule changes go to the GDD before code;
   - `[later]`: real, but not this round (it moves to `docs/tasks.md`);
   - `[no]`: not doing it, with the reason.
4. **Build the round (dev).** Work top to bottom: small commits, tests green, push to `main`. Mark each item `→ <hash>` when it's fixed.
5. **Verify (you).** Play the new build, then tick `[x]` or reopen with a note.

To start a round, tell any session "playtest round ready" (the pilot triages) or "build the round" (the dev starts).

## Inbox
*(You write here. Format: `- <hash> <note>`)*


## Round 3 (ready to play): build `4c676e6`
- **Build**: `4c676e6`, all of round 2. Play it at https://benjaminandre.github.io/Voyn/. The corner of the screen shows the hash of the build you are on; later pushes that only touch docs change the hash but not the game.
- **What changed since round 1**:
  - **Clicking works.** The scene's root Control used to swallow every click that was not on a button (2.11); real clicks now reach the board, and clicking a figure (body or name) selects it (2.1).
  - **Selecting a Creature shows where it can go** (a nobody-selected start, 2.2). **Move is a button next to the abilities** (2.6): pick Move or an ability, see its light-blue zone, click a cell. The order you pick them in is the plan order, so there is no toggle. Picking one again replaces it. Esc or right-click cancels the aim, then clears the plan, then deselects.
  - **Four blues for your plan** (2.7): the usable zone, the chosen path, the predicted position (with a translucent ghost of the Creature), and the ability's target and Area, darkest, with damage numbers on who it hits.
  - **Colours** (2.10): terrain is purple (corruption, Blighted darker) and green (purity, Thriving darker) on stone; every Creature is blue and every Monster red, told apart by shape only.
  - **You can plan while the step plays** (2.8): select and plan the next step during the animation; the plans carry into the next window, which still closes on time. The window is now **16 s** (2.3).
  - **A log on the right** (2.5) lists each phase and its effects as they play; collapse it with the Log button.
  - **No stuck aiming** (2.4): opening or closing a window cancels any aim.
- **What to judge** (round 1's questions carry over):
  - Is a step readable? Is 16 s about right, or is the animation what feels fast?
  - Do the three Creatures feel different now that colour no longer tells them apart? Is the shape enough?
  - Is the Land (purple and green) understandable without explanation?
  - Do the four blues read as one plan, light to dark? Is the ghost clear?
  - Is planning during playback useful, or confusing?
  - Is the fight too short or too long?
- Write notes under **Inbox**, each starting with the build hash.

## Round 2 (built, waiting for you to verify): triaged from your notes on `cd4fef9`
Your notes are kept in quotes. Every item below is built and pushed; each `→` points at the commit. Play Round 3 and tick them, or reopen with a note.

### `[dev]`: build now
- [ ] **2.1 Click a figure to select it.** *"I should be able to select a creature by clicking on it."* → `9eac364` (the pick column was narrowed in `fcffbd3`, so the tile behind a figure stays clickable at its center)
  - **Cause**: a click is traced straight down to the floor (`BoardView.cell_at_screen`). A fighter's body is drawn above and in front of its tile, so clicking the body lands on the cell behind it.
  - **Fix**: a click or hover on a fighter's figure (body or label) counts as a click on that fighter's cell, for selecting, aiming and Area hover. Figures win over the tile behind them; empty tiles work as now.
  - **Test**: a click at the projected center of each fighter's body resolves to that fighter's cell.
- [ ] **2.2 Start each window with no Creature selected.** → `4d44953` *"so that when we select one, we get feedback by seeing its movement range."* Today the first Creature is preselected (`main.gd _begin_window`).
- [ ] **2.3 Double the window: `step_window_ms` 8000 → 16000.** → `a63deaa` *"A step goes by too fast. Double the length."* I read this as the planning window. If you meant the resolution animation, say so, and we'll slow that instead.
- [ ] **2.4 Never leave the UI stuck.** → `da710a7` *"I got stuck on 'select yellow case for target' when the turn ended while I was planning."* Opening or closing a window cancels any aiming in progress and clears stale hints. No input state may survive into a mode where it can't be finished.
- [ ] **2.5 Resolution log on the right.** → `9cdd00b` *"The phases and effects that happen could be in a box on the right, which is kinda hidden."* A panel at the right edge lists each phase and its events as they play ("Lead moves: Tank 2 cells", "Strike: Brute takes 22"). It is out of the way, can be collapsed, and holds the last step until the next one plays.

- [ ] **2.11 Clicks never reached the board** (your follow-up: "the raycasting to select a tile fails"). → `d0c72ae`
  - **Cause**: the scene root is a full-screen Control with the default mouse filter (Stop), so the GUI swallowed every click that wasn't on a button. Selecting, moving and aiming all failed in the web build. The tests passed only because they call `click_cell` directly.
  - **Fix**: the root Control ignores the mouse. A new `test_input_routing.gd` pushes real mouse events through a viewport, so this can't come back silently.
  - **Known trade-off**: a fighter's figure wins clicks over the tile just behind it (2.1), so that tile is only clickable on its far half. Say so if it gets in the way.

### `[design]`: approved by you, with your changes (build after 2.5)
- [ ] **2.6 Move is chosen like an ability; no order toggle.** → `fcffbd3` *"Move command just fails."* · *"The toggle 'move after action' is unnecessary."* · *"show 'movement' as an ability"*
  - **Cause of the failed moves**: once an ability was chosen, every click was read as an aim, so clicking a blue cell did nothing.
  - **Build** (GDD R9.4):
    - "Move" is a button next to the abilities.
    - Pick Move or an ability, see its zone, then click a cell. The order you choose them in is the plan order: Move first is "close in and strike", ability first is "hit and run".
    - After the Move is set, the ability's zone is computed from the predicted position. Picking one again replaces it. Right-click or Esc clears the step in progress.
- [ ] **2.7 Ghost preview in shades of the team colour.** → `4eab3f6` *"A confirmed command should be shown in a darker hue."* · *"see a 'ghost preview'"* · *"highlighting the area in different shades of a team"*
  - **Build** (GDD R9.3), with your shades, light to dark:
    1. the zone you can use now (Move reach, or the ability's valid targets);
    2. the chosen path, slightly darker;
    3. the predicted position, a second tone darker, with a translucent ghost of the Creature on it;
    4. the ability's target and Area, darkest, with damage numbers on the fighters hit.
  - The shades don't depend on plan order: if you act first, the ability stays darkest and the new position stays at shade 3.
- [ ] **2.8 Plan at any time.** → `4c676e6` *"I should be able to plan during all phases…"*
  - **Build** (GDD R3.3): while a step's resolution plays, you can already plan the next step, against the step's final state, so those plans are exact. The window still closes on time.
- [ ] **2.10 New colour scheme.** → `99be769` *"Green/purple (and later orange) should be to the terrain… blue is us, red is them, yellow is neutral."*
  - **Build** (GDD R9.3):
    - Karma tints: purple for corruption, green for purity, stone for Neutral. The forecast chevrons and the Land meter use the same purple and green.
    - Every Creature is blue and every Monster is red, told apart by shape. Today the Archer is violet and the Flier orange, which clashes with the terrain colours.
    - Monster threat zones and Telegraphs are red; yellow is only for neutral things (Arena interactables later).
    - Plan overlays use shades of blue (2.7). No other colour may be used for a Side or the terrain.

### `[later]`
- [ ] **2.9 Judge the rest after these fixes.** *"Everything else is hard to judge due to being unable to move nor use spells correctly."* The questions from round 1 (readability, window length, Creature identity, karma, fight length) carry over to round 3.

## Round 1: Playable 1 (played; notes triaged into Round 2)
- **Build**: `3e39997` (T13b). Play it at https://benjaminandre.github.io/Voyn/ (every push to `main` replaces it; the commit hash of the build you are on is in the bottom-right corner of the screen, so start your Inbox lines with it).
- **What it is**: PH Encounter 1 on PH Nave, placeholder content only (`docs/gdd/90-placeholder-content.md`). You control all three Creatures: PH Tank, PH Striker, PH Archer.
- **How to play**:
  - Click a Creature, then a blue cell to move. Pick an ability, then a yellow cell to aim it (a Guard-type ability needs no target). "Ability first, then move" flips the order. Right-click or Esc clears the selected Creature's plan.
  - Space or "Ready" ends the window early; the window is 8 s. Tick "Untimed (dev)" to think for as long as you like. "Threats" hatches the cells the Monsters could hit.
  - Floating numbers above fighters are the preview (the real resolution of your plans, with Monsters waiting). The Land meter shows board karma now and after the step.
- **Not in this build** (known gaps, not bugs): placement, Telegraphs, Keeper interactions, a smart Monster AI (they use the placeholder `scripted_chase`), co-op (T13c), sound. Standing still loses in about 16 steps.
- Things worth judging: is a step readable? Is 8 s enough? Do the Creatures feel different? Is the Land (karma) understandable without explanation? Is the fight too short or too long?
