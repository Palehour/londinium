---
name: reflexionar
description: Convierte errores, correcciones de Cristian y comentarios de revisión de un PR en reglas que duran, en el lugar justo. Usar después de una revisión con cambios pedidos o cuando Cristian pida "reflexioná".
---

# Reflexionar

Después de un PR, juntá lo que salió mal y decidí si se vuelve regla. `docs-vivos` mantiene los docs al día con lo que
el PR cambia; esta skill se ocupa de las lecciones.

1. **Juntá.** Los comentarios de Bailey y de Cristian en el PR, lo que falló en el CI y lo que hubo que rehacer.
2. **Filtrá.** Es lección si es un error que puede repetir otro agente, si ya pasó dos veces, o si una sola vez costó
   caro (un merge roto, datos perdidos). Lo que pasa una sola vez y ya está cubierto por una regla no es lección.
3. **Primero la estructura.** Si un test, un chequeo de `tests/data/` (como `test_data_valid.gd` o
   `test_scripts_compile.gd`), un hook de `.githooks/` o el CI lo puede atajar, la lección es ese chequeo, no un texto.
4. **Si no, el texto va a un solo lugar:**
   - Regla de todo el repo: `AGENTS.md`.
   - Un paso del proceso: el Gotcha de la skill que lo cubre (`implementar-issue`, `abrir-pr`, `revisar-pr`, etc.).
   - Arquitectura o tick: `docs/ARCHITECTURE.md` o un ADR (ver `docs-vivos`).
   - `docs/GDD.md` y `docs/DECISIONS.md`: nunca desde acá; se propone en el PR (ver `decision-diseno`).

   Antes de escribir, buscá con grep si la regla ya existe. Si existe y no se cumplió, hacela más visible o sumale un
   ejemplo del error, no la copies.
5. **Proponé, no apliques.** Listá cada lección con su destino (archivo y sección) y el texto, en un comentario del PR o
   en el chat. Cristian decide. Lo aprobado va en el mismo PR si sigue abierto; si ya se mergeó, en uno nuevo
   `chore/<n>-<slug>`.

## Gotchas
- Una regla nueva se escribe como instrucción corta con el porqué, no como relato de lo que pasó.
- Si una lección contradice una regla existente, es una pregunta para Cristian, no una edición.
