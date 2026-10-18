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

## Round 1: Playable 1
- **Build**: `3e39997` (T13b). Play it at https://benjaminandre.github.io/Voyn/ (every push to `main` replaces it; the commit hash of the build you are on is in the bottom-right corner of the screen, so start your Inbox lines with it).
- **What it is**: PH Encounter 1 on PH Nave, placeholder content only (`docs/gdd/90-placeholder-content.md`). You control all three Creatures: PH Tank, PH Striker, PH Archer.
- **How to play**:
  - Click a Creature, then a blue cell to move. Pick an ability, then a yellow cell to aim it (a Guard-type ability needs no target). "Ability first, then move" flips the order. Right-click or Esc clears the selected Creature's plan.
  - Space or "Ready" ends the window early; the window is 8 s. Tick "Untimed (dev)" to think for as long as you like. "Threats" hatches the cells the Monsters could hit.
  - Floating numbers above fighters are the preview (the real resolution of your plans, with Monsters waiting). The Land meter shows board karma now and after the step.
- **Not in this build** (known gaps, not bugs): placement, Telegraphs, Keeper interactions, a smart Monster AI (they use the placeholder `scripted_chase`), co-op (T13c), sound. Standing still loses in about 16 steps.
- Things worth judging: is a step readable? Is 8 s enough? Do the Creatures feel different? Is the Land (karma) understandable without explanation? Is the fight too short or too long?
