# Flujo de trabajo — Londinium

Un dev solo (Cristian) que no escribe código + agentes que sí. Simple a propósito.

## Ramas
- **`develop`** (rama por defecto): integración. Toda PR de agente va acá. Siempre con tests en verde.
- **`main`**: releases. Solo recibe PRs `develop` → `main` que abre Cristian, y cada release lleva un tag `v*`
  (`v0.1.0` = primer build jugable del hito 1), que dispara los builds.
- **Ramas cortas por issue**: `<tipo>/<issue>-<slug>` (`feat/`, `fix/`, `chore/`, `test/`), siempre desde
  `develop` y con PR a `develop`. Viven horas o pocos días; se borran al mergear.
- **Docs**: `docs/GDD.md` y `docs/DECISIONS.md` cambian en ramas `docs/<issue>-<slug>` que preparan Mason o
  Chronicler; Cristian las aprueba. Los agentes de código solo los editan en su rama de tarea, con la autorización
  de Cristian que describe la skill `decision-diseno`.

### Protección de `main` y `develop`
- En GitHub, las dos ramas tienen protección clásica: PR obligatoria (0 aprobaciones), también para admins,
  sin force-push ni borrado. En `develop` se exigen los checks `tests (unit)` y `tests (slow)` (#268).
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
5. **CI** (`ci.yml`, jobs `tests (unit)` y `tests (slow)`, en paralelo): cada uno corre el chequeo de APIs de Godot 3, importa el proyecto, chequea el parseo de GDScript y corre su parte de GUT headless en Linux. Los dos tienen que estar verdes.
6. **Revisión de Cristian**: lee el resumen, prueba los 3 pasos en el PC si toca pantalla, mergea con
   *squash merge* (él o Chief en su nombre). Bailey revisa la PR antes (ver la skill `revisar-pr`) y confirma con Cristian, a través de Chief, las autorizaciones de edición de
   `GDD.md`/`DECISIONS.md`. Opcional: pedirle además a un segundo agente que revise.
7. Un agente por issue a la vez; issues que tocan los mismos archivos, en serie (ver "Trabajo en paralelo con Orca").

## Trabajo en paralelo con Orca
Orca abre un worktree de git por tarea y corre un agente en cada uno. El `orca.yaml` de la raíz prepara cada
worktree con el import de Godot y hace que el agente espere a que termine (`setupAgentStartupPolicy: wait-for-setup`).

### Regla base
- Un issue = un worktree = una rama = un PR a `develop`. El worktree sale de `develop`, nunca de otra rama de
  feature, salvo pedido explícito.
- Las revisiones no se hacen en Orca: el PR va a Bailey y a Cristian como en "Ciclo de una tarea".

### Configuración, una vez por máquina
1. **`godot` en el PATH**, apuntando al binario *console* 4.7.2. El setup del `orca.yaml` lo llama así porque
   `$GODOT` (sh) y `%GODOT%` (cmd) no se escriben igual.
   - Windows: un `godot.cmd` en una carpeta del PATH de usuario con
     `@"C:\ruta\Godot_v4.7.2-stable_win64_console.exe" %*`. Después de cambiar el PATH, reiniciar Orca y abrir
     terminales nuevas: los procesos que ya estaban abiertos siguen con el PATH viejo.
   - Mac: `sudo mkdir -p /usr/local/bin && sudo ln -sf /Applications/Godot.app/Contents/MacOS/Godot /usr/local/bin/godot`
     (`/usr/local/bin` puede no existir en las Mac con Apple Silicon y pide `sudo`). Sin `sudo`: crear el symlink en
     `~/bin` y agregar `export PATH="$HOME/bin:$PATH"` a `~/.zprofile`. Una app de escritorio como Orca no siempre
     hereda el PATH de `~/.zshrc`.
   - Comprobar con `godot --version` **desde una terminal de Orca** (tiene que decir 4.7.2).
2. **Rama base:** `orca repo set-base-ref --repo id:<repoId> --ref origin/develop`, antes de crear worktrees.
3. **Hooks:** Settings → Repository → Hooks, fuente = `orca.yaml` only, así la PC y la Mac corren lo mismo.
4. **Skills de Orca:** `orca skills install --skill orca-cli --skill orchestration`. Las de jira, linear, emulator y
   per-workspace-env no aplican.

### Lanzar un worker
- Prompt de siempre: "Implementá el issue #N de Palehour/londinium. Leé el cuerpo y todos los comentarios, y usá las
  skills … Primero hacé el plan en modo plan y esperá mi aprobación." Cada agente arranca en modo plan y Cristian
  aprueba el plan de cada uno por separado.
- Desde la CLI: `orca worktree create --name issue-N --agent claude --setup run --prompt "<prompt>"`
  (otros agentes: `codex`, `grok`, entre otros). Para varios workers con seguimiento, usar Orchestration.

### Qué va en paralelo
- Solo issues independientes de verdad: no alcanza con que toquen archivos distintos si uno depende de algo que el
  otro cambia. Empezar con 2 o 3 workers.
- **Archivos calientes**, que dos issues no tocan a la vez: `docs/DECISIONS.md`, `docs/GDD.md`,
  `data/economy/*.json`, `src/ui/strings.gd` y `src/sim/simulation.gd`. Antes de lanzar, comparar el Alcance de cada
  issue: si comparten uno, van en serie.
- Los D-xxx nuevos se reservan en el issue antes de arrancar, para que dos PRs no tomen el mismo número.

### Integrar
- Se mergea un PR por vez. Cuándo rebasear un PR abierto después de un merge: `AGENTS.md` ("Git workflow").
- Un worker trabado se descarta; no se mergea trabajo parcial.

### Pitfalls
- Godot reformatea `data/economy/buildings.json` con tabs al abrir el proyecto o guardar en el editor (el `--import`
  por consola no lo toca). Ese cambio no se commitea nunca: `git checkout -- data/economy/buildings.json` antes de
  commitear.
- `tools/run_long_tests` y `balance_report --seeds 20` son CPU-bound: uno por vez, solo en el PR que va a mergearse.
  Los demás workers usan `tools/run_tests`.
- Cada worktree tiene su propio `.godot/` (está en `.gitignore`). El primer import tarda y no se comparte: no poner
  `.godot` en `worktree.sharedDirectories`, porque compartir el caché entre checkouts lo corrompe.
- En la app de escritorio el setup corre después de un prompt de confianza. Desde la CLI, solo con `--setup run`.
- Cada worktree lee el `orca.yaml` de **su** rama. Si el yaml cambia, mergearlo a `develop` y actualizar el checkout
  principal antes de crear worktrees; Orca vuelve a pedir confianza porque compara el contenido.
- En Windows el setup corre con `cmd.exe` y corta si una línea falla; en Mac, con `sh`. Por eso es una sola línea que
  vale en los dos.

## Release
1. Cristian abre una PR `develop` → `main` ("release: v0.x.y") y la mergea con *merge commit* (nunca squash),
   para que `main` y `develop` no se separen. Las PRs `feat/*` → `develop` siguen siendo squash.
2. Crea el tag `v0.x.y` sobre `main` (`git tag v0.x.y origin/main && git push origin v0.x.y`).
3. `export.yml` genera los builds de Windows, macOS y Linux como artifacts.

## Tests: GUT (elegido) vs gdUnit4
- **GUT 9.7.x** (rama `godot_4_7`): el más veterano (desde 2016, ~2.7k ⭐), CLI simple con exit code 0/1,
  `.gutconfig.json`, salida JUnit. Lo corrés igual en Windows, Mac y CI con un solo comando, y los agentes
  lo conocen bien. Para una simulación de lógica pura no hace falta más.
- gdUnit4 (~1.25k ⭐, acción oficial de CI) es más completo (scene runner, mocks potentes, inspector), pero
  suma una pieza más y más superficie. Lo reconsideramos si en el hito 2 hay que testear mucha UI.
- Los chequeos largos de 20 semillas (por ejemplo, la recuperación de inversión de los artesanos) no corren en CI; antes de mergear cambios de balance, ejecutarlos con `GODOT=/ruta/a/godot tools/run_long_tests.sh` (o `tools/run_long_tests.ps1` en Windows).

## CI y builds multiplataforma (gratis)
- **`ci.yml`** — en cada PR y push a `develop` o `main`: `chickensoft-games/setup-godot` v2.4.3 (fijado por SHA) instala Godot 4.7.2 (sin .NET),
  el chequeo de APIs de Godot 3, `--import`, el chequeo de parseo y GUT headless. Solo Linux: es el runner más barato. Con el repo público los minutos de Actions son gratis
  (si pasa a privado: 2.000 min/mes en Free).
  Son dos jobs en paralelo de 10 min como máximo cada uno (#268, D-132): **slow** corre `tests/slow/` (los juegos
  guionados de `tests/scenarios/`, casi la mitad del tiempo de GUT) y el balance report; **unit** corre todos los
  demás `test_*.gd` de `tests/`. Entre los dos corren los mismos tests que `tools/run_tests`. Un test que juega
  partidas enteras va en `tests/slow/`.
  En una PR que solo toca `docs/` (#226) los dos jobs corren igual y reportan el check, pero sin GUT entero ni balance
  report: unit corre solo los `test_*.gd` que leen `res://docs/`. Si toca cualquier otra cosa, corre todo.
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
- MCP de Godot (`Coding-Solo/godot-mcp`): opcional, recién cuando haya escena jugable y queramos que el
  agente corra el juego y lea la salida de debug. No hace falta para la simulación.
- En el PC con Windows: el zip de Godot 4.7.2 trae `Godot_v4.7.2-stable_win64.exe` y `..._win64_console.exe`;
  los agentes usan el de consola para ver la salida. Definir la variable `GODOT` apuntando a ese. Para Orca,
  además, `godot` en el PATH (ver "Trabajo en paralelo con Orca").
