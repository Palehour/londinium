# ADR 0008: Población, satisfacción, crecimiento e impuesto por clase

- **Estado:** Aceptado
- **Fecha:** 2026-10-13
- **Origen:** issue #52 (clase artesano); D-027 y D-033; amplía el ADR 0007

## Contexto
Hasta #52 había una sola clase: la población, la satisfacción, la inmigración, la emigración y el impuesto eran
escalares del estado. El artesano es la segunda clase y tiene otras necesidades (pan y cerveza), otra vivienda, otros
pesos de satisfacción, otros umbrales de crecimiento y paga el impuesto por cabeza aunque no tenga empleo. D-027 pide
que el motor sea el mismo para todas las clases y las eras, sin "artesano" ni "trabajador" en el código.

## Decisión
- **Los números por clase son datos.** `classes.json` declara, por clase, los bloques `satisfaction`, `growth` y `tax`
  y, por necesidad, `satisfaction_key` y `consumption_key`. Cada campo es el nombre de una clave de `Params` que ya
  existe (el trabajador sigue apuntando a `population.*`, sin renombrar nada) o un número, que el loader registra como
  `class.<clase>.<bloque>.<campo>` (o `class.<clase>.need.<bien>.satisfaction_weight` y `.per_person_per_minute`).
  `ParameterRanges.PATTERNS` valida esas claves por forma (rangos en el issue #52) y `Params` generaliza la validación
  cruzada de la histéresis del hambre (`recovery >= threshold`) a las claves de clase.
- **Un solo camino del motor.** `SatisfactionSystem`, `GrowthSystem`, `ConsumptionSystem`, `WorkersSystem` y
  `MoneySystem` recorren `ClassStates.defs(context)` en el orden de `classes.json`. Sin contexto (fixtures de tests) la
  única clase es `ClassDef.legacy()`, con las claves de `population.*`.
- **Dónde vive el estado.** `EconomyState.population` sigue siendo el **total**. La clase base (`"base": true` en
  `classes.json`, una por era, que debe tomar puestos) conserva sus valores en los campos planos de `EconomyState`
  (`satisfaction`, `overcrowding`, fracciones de inmigración y emigración, bandera de hambre...), porque decenas de tests
  los leen y los asignan. Las demás clases viven en `EconomyState.class_states: Dictionary[StringName, ClassState]`.
  `ClassStates.checkout()`/`commit()` copian la clase base hacia y desde un `ClassState` para que los sistemas
  trabajen sobre una sola forma. La población de la clase base es el total menos la de las otras.
- **Vivienda por clase.** La capacidad de una clase es la de sus edificios (base más bono por categorías cumplidas); la
  vivienda que ninguna clase reclama cuenta para la base. `housing_capacity` es la suma de todas.
- **Puestos.** `takes_jobs: false` saca a la clase de los puestos (D-021 no cambia): `WorkersSystem` reparte solo a
  quienes buscan trabajo y `unemployed` no la cuenta.
- **Consumo.** La demanda de un bien es la suma, sobre las clases que lo tienen como necesidad, de residentes por consumo
  por persona. El té lo consumen solo las clases con té; la cerveza se consume como el té (saldo total: stock entero más
  fracción, ADR 0005), del almacén ya deteriorado por `MarketSystem`. Con demanda 0 un bien en el almacén cuenta como
  cubierto, para que los primeros artesanos lo encuentren.
- **Impuesto.** `tax.basis` es `employed` (por puesto ocupado) o `residents` (por residente). Cada clase suma a la
  misma `tax_fraction`; la tasa sigue siendo una sola.
- **Estabilidad.** `DefeatSystem.is_city_stable` mira a todas las clases: una clase con residentes que emigra por hambre
  o que perdió gente por baja satisfacción en la ventana hace inestable la ciudad. La despoblación sigue sobre el total.
- **Orden del tick.** No cambia: cada paso se vuelve genérico por clase.
- **Serialización.** `to_dict` agrega `class_states` y los campos de cerveza al final; `from_dict` los lee con valores
  por defecto, así que una partida guardada antes carga con cero artesanos. Una clase nueva en un estado viejo arranca
  en su satisfacción objetivo (`SatisfactionSystem.prime_class`), no en cero.

## Estado
Aceptado. Cristian lo aprobó en la PR #108 (issue #52) el 2026-10-13, confirmado por Bailey; el cambio a Aceptado
entra en un commit de esa misma PR, antes del merge. No reemplaza a ningún ADR: amplía el 0007 (las clases son
datos) y respeta el 0004 (contexto) y el 0005 (saldo total).

## Consecuencias
- Una clase más es solo datos (y una rama en `NeedsSystem.coverage` si trae un bien que nadie consume todavía).
- Sin viviendas de artesanos los escenarios existentes dan resultados idénticos a `develop` (`tools/balance_report`,
  `--summary --seeds 20` y CSV por minuto): la ruta del trabajador evalúa las mismas expresiones en el mismo orden y la
  clase sin residentes suma `0.0`.
- Límites conocidos: el pan y la cerveza se reparten sin prioridad entre clases; el consumo del pan de una ciudad vacía
  (`_empty_city_coverage`) usa las claves de `population.*`; si dos clases con `tax.basis = employed` tomaran puestos, los
  empleados se cobrarían una vez por clase (hoy solo hay una).
- La clase base por `"base": true` evita depender del orden del archivo; el orden solo define la suma de los términos.
- Tests: `tests/sim/test_artisan_class.gd`, `tests/sim/test_artisan_growth.gd`, `tests/data/test_artisan_data.gd` y el
  escenario `tests/scenarios/artisans_beer.json`.
