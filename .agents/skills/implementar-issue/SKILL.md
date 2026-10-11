---
name: implementar-issue
description: Implementa un issue de Londinium de punta a punta (rama, código, tests). Usar cuando te asignen un issue para programar.
---

# Implementar un issue

Las reglas de fondo están en `AGENTS.md`; acá solo el orden de trabajo.

1. **Estado local.** `git status` primero. Si hay cambios que no son tuyos, no los toques ni los incluyas
   (`git add` por archivo, nunca `git add -A`).
2. **Base.** `git switch develop` y `git pull --ff-only`. Rama `<tipo>/<n>-<slug>` desde ahí
   (`feat/`, `fix/`, `chore/`, `test/`).
3. **Leer.** El issue completo (alcance, fuera de alcance, criterios), la sección del GDD que cita,
   `docs/ARCHITECTURE.md` y los ADR en estado Aceptado de `docs/adr/`.
4. **Plan.** Si Cristian pidió modo plan, usá `planificar-issue` y esperá su aprobación.
5. **Decisiones.** Si falta un número de balance, una regla o un P-xxx, **detenete** y usá `decision-diseno`.
6. **Tests primero** en la simulación: test que falla, implementación, verde.
   - `src/sim/`: clases `RefCounted`, sin nodos.
   - Aleatoriedad solo con el `RandomNumberGenerator` con semilla de la simulación.
   - Dinero en peniques, `int`.
   - Todo valor de balance en `data/`, leído con `Params.get_value()`.
7. **Verificar.** Corré `tools/run_tests.ps1` (Windows) o `tools/run_tests.sh` con Godot 4.7.2 (consola).
   No digas "terminado" sin pegar la salida del comando, y mirá `.godot/import.log`.
8. **Entregar** con `abrir-pr`.

## Gotchas
- `GODOT` tiene que apuntar al ejecutable de **consola** (`..._win64_console.exe`); con el otro no hay salida.
- Archivos nuevos de Godot: correr `--import` y commitear los `*.uid` generados.
- No "arregles de paso" código fuera del issue: anotalo en la PR.
- Un cambio local ajeno en `data/` o `docs/` no es tuyo: dejalo sin stagear.
