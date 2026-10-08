# Flujo de trabajo — Londinium

Un dev solo (Cristian) que no escribe código + agentes que sí. Simple a propósito.

## Ramas
- **`develop`** (rama por defecto): integración. Toda PR de agente va acá. Siempre con tests en verde.
- **`main`**: releases. Solo recibe PRs `develop` → `main` que abre Cristian, y cada release lleva un tag `v*`
  (`v0.1.0` = primer build jugable del hito 1), que dispara los builds.
- **Ramas cortas por issue**: `<tipo>/<issue>-<slug>` (`feat/`, `fix/`, `chore/`, `test/`), siempre desde
  `develop` y con PR a `develop`. Viven horas o pocos días; se borran al mergear.
- **Docs**: `docs/GDD.md` y `docs/DECISIONS.md` solo cambian en ramas `docs/<issue>-<slug>` que preparan Mason o
  Chronicler; Cristian las aprueba. Los agentes de código nunca los tocan.

### Protección de `main` y `develop`
- En GitHub, las dos ramas tienen protección clásica: PR obligatoria (0 aprobaciones), también para admins,
  sin force-push ni borrado. Más adelante se puede exigir el check `tests (headless GUT)` cuando el CI esté verde.
- Hook local `.githooks/pre-push`: bloquea `git push` directo a `main` y a `develop`
  (activar una vez por clon: `git config core.hooksPath .githooks`). Más la regla en AGENTS.md.

## Ciclo de una tarea
1. **Issue** en GitHub Issues con criterios de aceptación ligados a una sección del GDD, dentro del milestone
   "Hito 1" y de la épica #12 (las dependencias figuran como "bloqueado por"). Una cosa por issue.
   Tablero: GitHub Project "Londinium" (Status, Prioridad, Agente).
2. **Plan primero**: el agente lee AGENTS.md + la sección del GDD, propone un plan corto en la PR o el chat.
   Para tareas chicas, directo.
3. **Tests primero** en la simulación: test que falla → implementación → verde.
4. **PR chica** a `develop` con el template (qué cambió, cómo verificarlo en ≤ 3 pasos, dudas de docs).
5. **CI** (`ci.yml`, job `tests (headless GUT)`): importa el proyecto y corre GUT headless en Linux. Tiene que estar verde.
6. **Revisión de Cristian**: lee el resumen, prueba los 3 pasos en el PC si toca pantalla, mergea con
   *squash merge*. Opcional: pedirle a un segundo agente que revise la PR antes.
7. Un agente por issue a la vez; issues que tocan los mismos archivos, en serie.

## Release
1. Cristian abre una PR `develop` → `main` ("release: v0.x.y") y la mergea.
2. Crea el tag `v0.x.y` sobre `main` (`git tag v0.x.y origin/main && git push origin v0.x.y`).
3. `export.yml` genera los builds de Windows, macOS y Linux como artifacts.

## Tests: GUT (elegido) vs gdUnit4
- **GUT 9.7.x** (rama `godot_4_7`): el más veterano (desde 2016, ~2.7k ⭐), CLI simple con exit code 0/1,
  `.gutconfig.json`, salida JUnit. Lo corrés igual en Windows, Mac y CI con un solo comando, y los agentes
  lo conocen bien. Para una simulación de lógica pura no hace falta más.
- gdUnit4 (~1.25k ⭐, acción oficial de CI) es más completo (scene runner, mocks potentes, inspector), pero
  suma una pieza más y más superficie. Lo reconsideramos si en el hito 2 hay que testear mucha UI.

## CI y builds multiplataforma (gratis)
- **`ci.yml`** — en cada PR y push a `develop` o `main`: `chickensoft-games/setup-godot@v2` instala Godot 4.7.2 (sin .NET),
  `--import`, GUT headless. Solo Linux: es el runner más barato. Con el repo público los minutos de Actions son gratis
  (si pasa a privado: 2.000 min/mes en Free); una corrida debería rondar 2–4 min.
- **`export.yml`** — solo con tag `v*` o a mano: el mismo action con `include-templates: true` exporta
  **Windows, macOS y Linux desde un único runner Linux** (Godot exporta cruzado con las plantillas oficiales;
  no hace falta runner de macOS, que en repos privados consume ~10× más). Sube 3 artifacts por 14 días (límite Free: 500 MB).
  Alternativa equivalente: `firebelley/godot-export@v8.0.0`.
- **`export_presets.cfg`**: se commitea (desde Godot 4 las credenciales van a `.godot/export_credentials.cfg`,
  ignorado). Tres presets con nombres exactos `Windows Desktop`, `macOS`, `Linux`; rutas bajo `build/`.
  macOS: exportar como **.zip** (un `.app` exportado desde Windows pierde el bit de ejecución), binario
  Universal (Intel + Apple Silicon). Si el editor pide activar compresión de texturas ETC2/ASTC para macOS,
  activarla en Project Settings. Windows: sin firma (SmartScreen avisa "editor desconocido"; normal en builds de prueba).
- Antes del primer `git push` de arte o música: `git lfs install` en cada máquina. Los jobs de test no
  bajan LFS; el de export sí. Free = 10 GiB de almacenamiento + 10 GiB/mes de descarga LFS.

## macOS: firma y notarización
- Sin cuenta de Apple Developer: preset macOS con **Code Signing = "Built-in (ad-hoc only)"** y
  **Notarization = Disabled**. Godot firma ad-hoc incluso exportando desde Linux/Windows.
- En cualquier Mac: click derecho → Abrir → Abrir, o
  `xattr -dr com.apple.quarantine "Londinium.app"`. Gatekeeper bloquea apps no notarizadas bajadas de internet.
- La membresía paga de Apple Developer (Developer ID + notarytool) recién hace falta para **distribución
  pública** (itch.io/Steam/web) sin advertencias. No para el prototipo.

## Herramientas para agentes (gratis)
- AGENTS.md (Codex, Cursor, Grok Build lo leen; Claude Code vía `CLAUDE.md` → `@AGENTS.md`).
- Skill `godot-gdscript-patterns`: `npx skills add wshobson/agents --skill godot-gdscript-patterns`.
- MCP de Godot (`Coding-Solo/godot-mcp`): opcional, recién cuando haya escena jugable y queramos que el
  agente corra el juego y lea la salida de debug. No hace falta para la simulación.
- En el PC con Windows: el zip de Godot 4.7.2 trae `Godot_v4.7.2-stable_win64.exe` y `..._win64_console.exe`;
  los agentes usan el de consola para ver la salida. Definir la variable `GODOT` apuntando a ese.
