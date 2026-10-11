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
7. **Verificar.** Corré la suite con Godot 4.7.2 y la variable `GODOT` apuntando al binario. No digas
   "terminado" sin pegar la salida del comando, y mirá `.godot/import.log`.
   - Windows (PowerShell): `$env:GODOT = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"` y
     `powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1`.
   - Linux: `GODOT=/ruta/a/Godot_v4.7.2-stable_linux.x86_64 tools/run_tests.sh`.
   - macOS: `GODOT=/Applications/Godot.app/Contents/MacOS/Godot tools/run_tests.sh`.
   - Un solo archivo: agregá `-gtest=res://tests/sim/test_production.gd` al final del comando.
8. **Entregar** con `abrir-pr`.

## Gotchas
- `GODOT` tiene que apuntar al ejecutable de **consola** (`..._win64_console.exe`); con el otro no hay salida.
- Archivos nuevos de Godot: correr `--import` y commitear los `*.uid` generados.
- No "arregles de paso" código fuera del issue: anotalo en la PR.
- Un cambio local ajeno en `data/` o `docs/` no es tuyo: dejalo sin stagear.
