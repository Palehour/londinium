---
name: docs-vivos
description: Mantiene al día docs, ADRs y skills cuando un PR cambia algo que describen. Usar antes de abrir o aprobar un PR.
---

# Docs vivos

- Si el PR cambia algo que un doc o una skill describe, **se actualiza en el mismo PR**.
  La plantilla de PR tiene la casilla "Docs/ADR/skill actualizados en este PR" o "No aplica: <motivo>".
- **ADR (`docs/adr/`):** un ADR que revierte o cambia una decisión anterior la **reemplaza**: el viejo **no se
  borra**, se marca como Reemplazado por el nuevo. Los ADR sobre otros temas no se tocan y siguen vigentes.
  Un ADR está Propuesto mientras su PR está abierto. Cuando Cristian aprueba el PR, el autor lo cambia a
  Aceptado en un commit del mismo PR, **antes del merge** (el merge no reescribe archivos). El revisor no aprueba
  para mergear un ADR que quedó en Propuesto sin avisar.
- **`docs/GDD.md` y `docs/DECISIONS.md`:** la regla completa está en `decision-diseno`; no se repite acá.
- **Corregir dos veces por lo mismo:** si hubo que corregir a un agente dos veces por el mismo error,
  la corrección entra en la sección Gotchas de la skill que corresponda.

## Gotchas
- Cada regla vive en un solo lugar (`AGENTS.md` o una skill); en los demás sitios, apuntá a ella en vez de copiarla.
- Si renombrás una carpeta o un comando, buscá la ruta vieja con grep en `docs/`, `.agents/` y `AGENTS.md`.
- Cambiar una convención sin actualizar su doc es motivo de bloqueo en la revisión.
