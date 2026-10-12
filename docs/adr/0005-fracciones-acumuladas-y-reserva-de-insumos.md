# ADR 0005: Fracciones acumuladas y reserva de insumos

- **Estado:** Reemplazado por ADR 0006
- **Fecha:** 2026-10-11
- **Origen:** issues #3 y #4; src/sim/systems/production_system.gd

## Contexto
Los stocks son unidades enteras, pero las recetas, el consumo y la merma ocurren por tick en cantidades fraccionarias. Redondear en cada tick perdería o crearía mercancía.

## Decisión
Los stocks son enteros y ninguna cantidad fraccionaria se redondea por tick. Hay dos estrategias, según el caso:

- **Acumular (producción y merma del trigo):** cada edificio guarda `output_fraction` y solo entrega al stock las unidades enteras que completa; `wheat_decay_fraction` acumula la pérdida y solo la quita del stock al completar una unidad. Un conversor toma una unidad entera de insumo del stock, la reserva (`reserved_input`) y la va consumiendo según su ritmo; no toma otra hasta agotarla.
- **Saldo total (consumo y merma del pan, consumo del té):** el stock entero más la fracción (`bread_fraction`, `tea_fraction`) forman un único saldo. Cada tick se descuenta la demanda de ese saldo de inmediato y el resto se vuelve a separar en unidades enteras y fracción. El resto no espera a completar una unidad para descontarse.

## Estado
Aceptado por Cristian el 2026-10-11 en el PR #99 (confirmado por Bailey). Registra lo ya decidido y construido; no introduce comportamiento nuevo.

## Consecuencias
- No se pierde ni se crea mercancía por redondeo; los tests de producción lo comprueban.
- Una implementación nueva elige la estrategia que corresponde: acumular si algo se entrega o se pierde de a unidades; saldo total si se consume de forma continua. No se mezclan.
- El estado guardado incluye las fracciones y las reservas.
- Cuenta con una tolerancia de redondeo (`ROUNDING_EPSILON`) para que sumas de fracciones como sextos no demoren una unidad exacta.
