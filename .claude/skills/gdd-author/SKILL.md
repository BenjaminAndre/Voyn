---
name: gdd-author
description: Write, extend, or challenge a section of the Voyn Game Design Document in docs/gdd/. Use when drafting a new system, revising a GDD file, or checking the GDD for consistency.
---

# GDD author

The GDD content lives in `docs/gdd/`; this skill is the process. Read `docs/gdd/README.md` (index, glossary, decisions, open questions) before anything else.

## Writing a section
1. **Scope it.** Name the system and which design pillar it serves. If no pillar, question whether it belongs.
2. **Ask first.** If key choices are open, list them as questions to the user (or the Opus pilot) instead of guessing. Record unresolved ones in Open questions.
3. **Draft** in the file for that system using this template:
   - **Purpose** — one paragraph, player-facing intent
   - **Rules** — precise, testable statements (numbers go in `data/`, referenced by name)
   - **Interactions** — links to other systems it touches
   - **Edge cases** — what happens when rules collide
   - **MVP cut** — the minimum version for the first playable
   - **Open questions**
4. **Glossary.** Add every new term to the README glossary; use existing terms verbatim.
5. **Decision log.** Record each non-obvious decision with the reason.

## Challenging a section
Delegate to the `design-critic` agent (Opus) with the file path. Resolve each blocker before marking the section "ready" in the README index. Status values: not started, draft, challenged, ready.

## Consistency check
Grep other GDD files for the terms and numbers the section touches; list contradictions explicitly.

## IP rule
Mechanics and genre conventions only. No Ankama names, lists, lore, or text.
