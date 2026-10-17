# AGENTS.md — Londinium

Rules for every coding agent (Codex, Claude Code, Grok Build, Cursor) working in this repo.
Short on purpose. If something here conflicts with a task description, this file wins; ask in the PR.

## Skills
Process lives in eight skills under `.agents/skills/<name>/SKILL.md`: `planificar-issue`, `implementar-issue`,
`tests-primero`, `decision-diseno`, `abrir-pr`, `revisar-pr`, `docs-vivos`, `reflexionar`. Codex and Cursor load
them on their own; if your agent does not (Claude Code does not read `.agents/`), read the matching `SKILL.md`
before starting.
A task prompt only needs the issue number, the skills that apply and, if wanted, plan mode.

## What this is
City builder prototype in **Godot 4.7.2 (stable), GDScript only**, no C#/.NET, no runtime AI.
Milestone 1 (M1) = the economy loop in `docs/GDD.md` ("Primer hito"). Colored squares, no art.
Cristian does not write code. He reviews PRs and plays builds. Make his review easy.

## Source of truth
- `docs/GDD.md` and `docs/DECISIONS.md` are canonical and drafted by the designer/historian bots; agents edit
  them only as the `decision-diseno` skill says. If you think a doc is wrong or ambiguous, write it under
  "Decisiones y docs" in your PR and implement the most conservative reading.
- Implement only **Decided** items (D-xxx). **Proposals (P-xxx) are not implemented** unless the issue
  says the proposal was approved.
- All balance numbers live in `data/`. Never hardcode a cost, rate, threshold or weight in code.
- Don't invent history. Names/dates in UI text come from the docs.

## Architecture (details in docs/ARCHITECTURE.md)
- `src/sim/` is the simulation: plain `RefCounted` classes, **no Node, no SceneTree, no UI, no
  `get_node`, no `_process`**. Deterministic: fixed tick, seeded `RandomNumberGenerator`, money as `int` pence.
- Every economic parameter is read through `Params.get_value(key)`, which applies the active role's
  modifiers (empty in M1). Never read raw data values from sim code.
- `src/game/` and `src/ui/` render state and send commands (`Simulation.apply_command()`). The UI never
  mutates sim state directly and contains no game rules.
- One autoload at most (`Game`), holding the running `Simulation`. No other singletons without approval.

## GDScript style
- Static typing everywhere: typed vars, params and returns (`var x: int`, `func f(a: float) -> void`).
  `:=` is fine when the type is obvious. Typed arrays/dicts (`Array[Building]`, `Dictionary[StringName, int]`).
  Untyped declarations are a compile error in this project (`untyped_declaration=2`). Never set
  `debug/gdscript/warnings/exclude_addons=false` (the default is true) so vendored addons aren't checked.
- Follow the official GDScript style guide: `snake_case` files/functions/vars, `PascalCase` `class_name`,
  `CONSTANT_CASE` constants, signals in past tense (`stock_changed`). One `class_name` per file, file name =
  snake_case of the class.
- Small functions, early returns, no magic numbers, comments explain *why*. Code and identifiers in English;
  player-facing strings live in `locale/ui.csv` and are read only through `src/ui/strings.gd`.

## Scenes and scripts
- One scene per folder with its script next to it (`src/ui/stats_panel/stats_panel.tscn` + `.gd`).
- Prefer building simple UI in code over large hand-written `.tscn` files. When you must write `.tscn`/`.tres`
  by hand: reference `ext_resource` by `path`, **never invent or copy `uid://` values**, then run the import
  command below and commit the generated `*.uid` files.
- Signals go up, calls go down. No `get_node("../../..")`.
- Never touch `addons/` (vendored GUT), `.godot/`, or `export_presets.cfg` unless the issue says so.

## Commands (run from repo root; `GODOT` = path to the Godot 4.7.2 *console* binary)
- First run / after adding files: `"$GODOT" --headless --path . --import`
- All tests: `tools/run_tests.sh` (Windows: `powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1`).
  Both save the import output to `.godot/import.log` and print it.
- One test file: `"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gexit -gtest=res://tests/sim/test_production.gd`
- Tests are GUT 9.7.x, in `tests/`, files `test_*.gd`, `extends GutTest`. Sim tests call `sim.tick()` N times
  directly (900 ticks = 15 game minutes); they must not depend on frames, real time or the scene tree.

## Tests are guardrails
- Every sim change ships with tests that would fail without it. Bug fix = failing test first.
- **Nunca modificar, saltear, borrar ni aflojar un test para que pase:** se cambia la implementación, no el
  resultado. Si un test parece mal, frenar y preguntar en el PR.
- **Máximo dos rondas de arreglo por la misma falla** (CI o revisión). Si falla dos veces igual, frenar y avisar a
  Cristian explicando qué se intentó.
- La evidencia (test que falla antes y pasa después, archivos tocados, tests cambiados) va en la sección
  "Evidencia" de la plantilla de PR.
- A passing build is not "done": if it touches the screen, describe how Cristian can see it in 3 steps.

## Git workflow
- Never push to `main` or `develop`. One issue = one branch = one PR into **`develop`** (the default branch).
  Releases (`develop` → `main` via PR + `v*` tag) are Cristian's.
- Branches: `<tipo>/<issue>-<slug>` for every type: `feat/`, `fix/`, `chore/`, `test/` (e.g. `feat/4-bakery-chain`,
  `chore/1-bootstrap`). `docs/<issue>-<slug>` is only for the designer/historian bots.
- Commits: Conventional Commits (`feat(sim): add bakery conversion`). Keep PRs small: aim for < 300 changed
  lines of non-test code; split otherwise.
- Don't add dependencies, addons, MCP servers or CI services without asking in the issue first.
- Don't refactor or "improve" code outside the issue's scope. Report it in the PR instead.
- **No tocar archivos fuera del alcance del issue** sin justificarlo en el PR (sección "Evidencia").
- **Rebasear solo ante conflictos reales** o cuando la rama necesita un arreglo de CI que ya entró en `develop`;
  estar atrasada respecto de `develop` no es motivo. Siempre rebase sobre `develop`, nunca mergear `develop` dentro
  de la rama.
- **Antes de pedir revisión a Bailey**, el PR necesita dos corridas de CI verdes seguidas sobre el mismo commit final,
  sin cambios en el medio (o una corrida verde y una re-verificación de que el tip no cambió). Si se pushea algo, se
  vuelve a esperar.
- Parallel work in Orca worktrees (setup, hot files, pitfalls): `docs/WORKFLOW.md` → "Trabajo en paralelo con Orca".

## GitHub tracking
Labels, milestone, assignee and the project board (Status, Prioridad, Agente) are set when you open the PR,
not later. Steps and commands: `abrir-pr`. PRs are squash-merged into `develop`.
- **`develop` está protegida:** no se mergea sin CI verde, y el merge solo lo hace Chief tras la autorización de
  Bailey (que confirma con Cristian a través de Chief).
- **Si quedás trabado** (falta info, permiso, falla repetida o una decisión de diseño): agregá la etiqueta
  `bloqueado` al issue o PR con un comentario de qué falta, y avisá. No sigas adivinando.

## Definition of done (every task)
1. All acceptance criteria of the linked issue are met, and each one is mapped to a test or a manual step in the PR.
2. `tools/run_tests` passes locally and CI is green. No new warnings or errors in the import log (`.godot/import.log`).
3. No hardcoded balance values; new parameters added to `data/` and read through `Params`.
4. `docs/GDD.md` / `docs/DECISIONS.md` untouched unless `decision-diseno` allows it; no P-xxx implemented without approval.
5. PR description uses the template: what changed, how to verify (≤ 3 steps), screenshots if UI, "Decisiones y docs".
