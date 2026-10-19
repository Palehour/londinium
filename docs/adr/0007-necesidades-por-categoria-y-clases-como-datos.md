# ADR 0007: Necesidades por categoría y clases como datos por era

- **Estado:** Aceptado
- **Fecha:** 2026-10-12
- **Origen:** issue #86; D-027 (clases y necesidades como datos, sin era fija) y D-032

## Contexto
Hasta #86 la única clase tenía sus necesidades cableadas: el pan y el té entraban en la satisfacción con claves fijas y la vivienda sumaba una capacidad fija. #52 (artesano) y #53 (ascenso) necesitan más clases con otras necesidades, y D-027 pide que el motor sea el mismo para todas las eras y que las clases y las necesidades sean datos.

## Decisión
- Las categorías de necesidades (sustento, abrigo, salud, comunidad o fe, estatus) y las clases se declaran en `data/eras/<era>/needs.json` y `classes.json`. Hoy se carga una sola era, `victorian` (`DataLoader.DEFAULT_ERA`).
- La estructura (qué bien cuenta en qué categoría, qué edificio es la vivienda de la clase) vive en defs del `DataCatalog` (`ClassDef`, `NeedDef`) y llega a la simulación por `EconomyContext`, como los edificios (ADR 0004). Los números se leen con `Params.get_value()`: `needs.<categoría>.threshold`, `needs.housing_bonus_per_category`, `class.<clase>.housing_max_bonus` y `class.<clase>.need.<bien>.value`.
- `NeedsSystem` calcula, para cada clase y categoría, `Σ cobertura × valor` (sin tope) y si alcanza el umbral. Corre dentro del paso 7 del tick (`SatisfactionSystem.update_target`), así que el orden del tick no cambia.
- La capacidad de cada vivienda de una clase es su base (`building.<id>.capacity`) más `min(housing_bonus_per_category × categorías cumplidas, housing_max_bonus)`. Una vivienda que ninguna clase reclama queda en su base. El tope se guarda como bono máximo sobre la base, no como número absoluto.
- Cada necesidad apunta con `satisfaction_key` a la clave de `Params` que dice cuánta satisfacción aporta; el trabajador reutiliza `population.satisfaction.bread_weight` y `population.tea.satisfaction_bonus`.
- Los rangos de las claves con ids dinámicos se validan por forma (`ParameterRanges.PATTERNS`), así que una era nueva no toca código.
- `EconomyState.class_needs` guarda el resultado y `from_dict` acepta estados sin esa clave.
- Los textos salen de ids estables (clase, categoría, bien, motivo) traducidos en `src/ui/strings.gd`.

## Estado
Aceptado al confirmarse la aprobación de Cristian del PR #107 (12/10/2026), en un commit del mismo PR y antes del merge. No reemplaza a ningún ADR; amplía el contexto del ADR 0004 con las clases.

## Consecuencias
- Una clase o una categoría nueva (por ejemplo el artesano en #52) es solo datos, más una rama en `NeedsSystem.coverage` si trae un bien que todavía nadie consume.
- Con `housing_max_bonus = 0` el trabajador conserva su capacidad y su satisfacción: la migración no cambia ningún resultado (`tools/balance_report` idéntico a `develop`).
- La población y la satisfacción siguen siendo únicas hasta #52, que las parte por clase.
- Cada categoría tiene un solo umbral para todas las clases.
