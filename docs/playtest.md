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
Waiting for the first playable build (see "Now" in `docs/tasks.md`).
