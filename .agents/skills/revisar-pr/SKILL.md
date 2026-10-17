---
name: revisar-pr
description: Revisa un PR de Londinium contra el issue y contra las reglas del repo. Usar cuando te pidan revisar o aprobar un PR.
---

# Revisar un PR

Revisá en **dos ejes separados** y citá siempre `archivo:línea`.

1. **El issue:** qué pedía (alcance, fuera de alcance, criterios de aceptación) y si cada criterio tiene
   su test o paso manual.
2. **El repo:** qué exigen `AGENTS.md`, `docs/ARCHITECTURE.md` y los ADR Aceptados (sim pura, determinismo,
   dinero en `int`, balance en `data/` vía `Params`, tipado estático, tests no debilitados).
   Si el PR trae ADR nuevos, pedí que pasen a Aceptado antes del merge (ver `docs-vivos`).

Clasificá cada hallazgo:
- **Bloqueante:** incumple un criterio o una regla. Incluye: cambió una convención y el doc, ADR o skill
  que la describe no se actualizó (casilla de docs de la plantilla).
- **Detalle menor:** estilo o mejora que no frena el merge.
- **Pregunta de diseño:** va a Cristian **sin resolverla vos**.

## `GDD.md` y `DECISIONS.md`
Aplicá la regla de `decision-diseno`: si el PR los edita sin la autorización de Cristian citada en un comentario
de la PR, es **bloqueante**. Si hay autorización, confirmala con Cristian antes de aprobar. Si propusieron el texto
en "Decisiones y docs", revisá la propuesta sin esperar que esté aplicada. Verificá también que no se hayan
implementado P-xxx sin aprobación.

**No mergees:** el merge lo hace Chief tras tu autorización (ver `AGENTS.md`, "GitHub tracking").

## Gotchas
- No marques "listo" sin ver la salida de tests y el CI en verde.
- Un comentario tuyo que cambia el diseño es una pregunta de diseño, no un pedido de cambio.
- Revisá el diff completo, también los archivos de datos y de docs.
