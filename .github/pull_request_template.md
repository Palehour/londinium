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

## Screenshots (if UI)

## Doc questions (GDD/DECISIONS ambiguities; agents never edit docs)
- None

## Checklist
- [ ] Base branch is `develop` (unless this is a release PR to `main`)
- [ ] `tools/run_tests` green locally, CI green, no new warnings in `.godot/import.log`
- [ ] No hardcoded balance values (all in `data/`, read via `Params`)
- [ ] No edits to `docs/GDD.md` / `docs/DECISIONS.md`; no P-xxx implemented without approval
- [ ] No tests weakened/skipped; scope limited to the issue
