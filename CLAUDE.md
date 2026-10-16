# Voyn

Original solarpunk-fantasy tactics game on hex arenas. It mixes the *genres* of Dofus (grid combat, AP/MP, abilities, pushes) and creature collecting: you play a classless **Keeper** in the overworld, and your **Creatures** fight in battle. Not a copy of either: see IP rule.

Its own hook: the **Land is a third player**. Every cell has **karma** (Blighted ↔ Thriving), every action marks it, and a neighbor-sum automaton amplifies it between rounds. Fights are negative-sum: Victory or Defeat, **Bloom** if the board is purified, **Collapse** (everyone loses) if it sinks into blight. PvM only.

Grows out of the developer's earlier prototype, Jolar. Fun side project: one developer plus AI. Long-term north star is a persistent online world; the MVP is offline.

## Status
Pre-production, settling **broad lines** before content. The turn structure (D3) is open, with candidates in `01-combat.md` R3. Content (creatures, monsters, abilities) is placeholder. M0 setup is design-independent and can start any time (see `docs/tasks.md`).

**Stack (decided 2026-10-16, details in `docs/architecture.md`):**
- Client: Godot 4 (latest stable; pin the exact version here during M0), typed GDScript, 3D with orthographic camera, Compatibility renderer.
- Rules engine: pure, deterministic, headless GDScript in `src/rules/`, integer math only.
- Tests: GUT, run headless.
- Post-MVP: Godot headless combat workers + Go backend in `server/`. No server code before the MVP.

## IP rule (hard)
Dofus/Wakfu belong to Ankama. Reuse **mechanics and genre conventions only**. Never reuse names, art, lore, text, map layouts, or exact spell/class/item lists. Everything shipped must be original. For the Land, stay off Wakfu's vocabulary: no "Wakfu", "Stasis" or "Ecosystem" as feature names, and no plant-summoner cleansing class. The same rule applies to Pokémon (Nintendo / Game Freak / The Pokémon Company): creature collecting is a genre, but no names, creature designs, type charts or capture devices.

## Where things live
- `docs/gdd/` — the Game Design Document, one file per system. `docs/gdd/README.md` = index, glossary, decision log, open questions. **Source of truth for design.**
- `docs/architecture.md` — stack, repo layout, rules-engine contract, testing strategy, release pipeline.
- `docs/tasks.md` — prioritized backlog for implementation sessions.
- `.claude/skills/gdd-author/` — process for writing and challenging GDD sections.
- `.claude/agents/` — model-routed roles (below).
- `project.godot` at repo root. Code in `src/` (`rules/`, `rules/turns/`, `ai/`, `client/`); tests in `tests/` (`unit/`, `golden/`, `fixtures/`).
- Data (rules tuning, creatures, abilities, statuses, monsters, arenas, encounters, Keeper tools) lives in `data/` as JSON, never hardcoded.

## Model roles
| Role | Model | Use for |
|---|---|---|
| Pilot / `design-critic` | Opus | Design decisions, architecture, challenging assumptions, layout, adversarial review |
| `dev` (default session) | Sonnet | Implementation, GDD drafting from agreed decisions, refactors, tests |
| `grunt` | Haiku | Mechanical work: stat tables, bulk data entry, formatting, renames, boilerplate |

Rules: Opus decides, Sonnet builds, Haiku fills in. Don't use Opus for work with a clear spec; don't use Haiku for anything needing judgment. Haiku output that feeds balance or code gets spot-checked.

## Working rules
- Design changes go in the GDD first, then code. If code and GDD disagree, flag it; don't silently pick one.
- Use terms from the GDD glossary exactly. Add new terms there.
- Keep numbers (damage, costs, ranges) in `data/`, with the GDD referencing them.
- Every session ends with the game runnable and tests green. Pick tasks from `docs/tasks.md` that fit one session.
- **Godot 4 APIs only** (no Godot 3 syntax). Static typing on every GDScript variable, parameter and return.
- `src/rules/` never touches nodes, scenes, rendering, engine singletons, floats or engine RNG. Name tests after GDD rule IDs (`test_R5_2_los_symmetric`).
- Small commits, one concern each. No git repo yet: initialize before first code commit (task T1).
- State assumptions explicitly; list open questions in `docs/gdd/README.md` rather than guessing.

## Commands
Set during M0 (task T1). Expected entries: open the editor, run the game, run all tests headless, run golden replays. Godot is not on PATH yet on this machine.
