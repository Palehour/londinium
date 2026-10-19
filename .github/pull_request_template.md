Closes #

<!-- Base: `develop`. Only releases go develop → main. -->

## What changed
-

## How to verify (≤ 3 steps for Cristian)
1.

## Acceptance criteria → evidence
| Criterion | Test or manual step |
|---|---|
|  |  |

## Evidencia
<!-- Ver AGENTS.md, "Tests are guardrails". -->
- **Test que falla antes del arreglo y pasa después:** comando y salida (o link al run de CI), antes y después.
- **Archivos tocados:**
  -
  Ninguno está fuera del alcance del issue / Justificación: <motivo>
- **Tests modificados o borrados:** Ninguno / `<archivo>`: <motivo>

## Screenshots (if UI)

## Decisiones y docs
<!-- Doubts about GDD/DECISIONS, and the text you propose for them. If you edited GDD.md or DECISIONS.md,
     quote Cristian's authorization in a PR comment and say so here. Write "Ninguna" if nothing applies. -->
- Ninguna

## Checklist
- [ ] Base branch is `develop` (unless this is a release PR to `main`)
- [ ] `tools/run_tests` green locally, CI green, no new warnings in `.godot/import.log`
- [ ] No hardcoded balance values (all in `data/`, read via `Params`)
- [ ] No edits to `docs/GDD.md` / `docs/DECISIONS.md`, or Cristian's authorization is quoted in a PR comment and confirmed by Bailey with Cristian; no P-xxx implemented without approval
- [ ] No tests weakened/skipped; scope limited to the issue (sección "Evidencia" completa)
- [ ] Labels, milestone, assignee and project status are set (see the `abrir-pr` skill)
- [ ] Docs/ADR/skill actualizados en este PR, o No aplica: <motivo>
