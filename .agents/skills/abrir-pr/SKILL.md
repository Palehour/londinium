---
name: abrir-pr
description: Abre el PR de un issue de Londinium (plantilla, labels, milestone, tablero) y atiende la revisión. Usar al terminar de implementar o al recibir comentarios de revisión.
---

# Abrir el PR y atender la revisión

## Abrir
1. PR a **`develop`** (nunca a `main`), una rama por issue. Primera línea: `Closes #<n>`.
2. Usá la plantilla `.github/pull_request_template.md`. Cada criterio de aceptación va ligado a un test
   o a un paso manual. Pegá la salida de `tools/run_tests` (ver `implementar-issue`).
3. Sección **"Decisiones y docs"** obligatoria (si no hay nada: "Ninguna"). Ahí van las dudas sobre docs, el
   texto que proponés para `GDD.md`/`DECISIONS.md` si no tenés autorización, y la cita de la autorización de
   Cristian si los editaste (ver `decision-diseno`).
4. Casilla de docs: "Docs/ADR/skill actualizados en este PR" o "No aplica: <motivo>" (ver `docs-vivos`).
5. **Seguimiento en GitHub**, en el mismo paso que abrís el PR:
   - En el PR y en el issue: `hito-1`, un `tipo:*`, un `area:*`, uno de `p1`/`p2`/`p3`,
     `agente:codex` o `agente:claude` o `agente:grok`, y `en-revision`. Sacá `listo-para-agente` del issue.
   - Milestone: el hito actual. Assignee: `crisesarmiento`.
   - **Tablero** (https://github.com/orgs/Palehour/projects/2): tiene los campos **Status**, **Prioridad** y **Agente**.
     - Agregá PR e issue: `gh project item-add 2 --owner Palehour --url <url> --format json --jq .id`
     - Id del proyecto: `gh project view 2 --owner Palehour --format json --jq .id`
     - Ids de campos y opciones: `gh project field-list 2 --owner Palehour --format json`
     - Status = `En revisión`; Prioridad y Agente según las labels.
     - **Un campo por llamada:** `gh project item-edit --id <item-id> --project-id <project-id> --field-id <field-id> --single-select-option-id <option-id>` (así no se rompen los acentos).
   - Si falta el scope `project`: escribí `Tablero: pendiente (sin scope project)` en el PR. No ejecutes
     `gh auth login`; Cristian corre `gh auth refresh -h github.com -s project` una vez. No lo omitas en silencio.
6. **Merge:** quién y cuándo está en `AGENTS.md` ("GitHub tracking"). Los PR van con
   **squash merge a `develop`**. Después del merge, el Status pasa a `Hecho`.

## Atender la revisión
1. **Verificá cada comentario antes de aplicarlo.** Comprobalo en el código y en los docs; si es incorrecto o
   ambiguo, respondé con evidencia en vez de aplicarlo.
2. Aplicá los cambios en la misma rama.
3. **Después de cambiar el PR por una revisión, comentá en el mismo PR** qué cambió: cada pedido de la
   revisión y el commit o el archivo que lo cubre. El mensaje del commit no alcanza. El comentario lo publica
   la app con la que estás trabajando (Codex u otra), no un bot aparte.

## Gotchas
- Cuerpo del PR y comentarios largos: usá `--body-file`, no pases texto con acentos por la línea de comandos.
- Labels y campos del tablero son dos cosas distintas: actualizá ambos.
- Tests verdes en local no alcanzan: el PR no está listo hasta que el CI también lo esté.
- Si el PR toca la pantalla, describí cómo verlo en 3 pasos para Cristian.
