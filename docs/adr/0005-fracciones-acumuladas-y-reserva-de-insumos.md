# ADR 0005: Fracciones acumuladas y reserva de insumos

- **Estado:** Aceptado
- **Fecha:** 2026-10-11
- **Origen:** issues #3 y #4; src/sim/systems/production_system.gd

## Contexto
Los stocks son unidades enteras, pero las recetas, el consumo y la merma ocurren por tick en cantidades fraccionarias. Redondear en cada tick perdería o crearía mercancía.

## Decisión
Los stocks son enteros. La parte fraccionaria se acumula aparte (`output_fraction` en cada edificio, `bread_fraction`, `tea_fraction` y `wheat_decay_fraction` en el estado) y solo se entrega o se descuenta cuando completa una unidad entera. Un conversor toma una unidad entera de insumo del stock, la reserva (`reserved_input`) y la va consumiendo según su ritmo; no toma otra hasta agotarla.

## Estado
Aceptado. Registra lo ya decidido y construido; no introduce comportamiento nuevo.

## Consecuencias
- No se pierde ni se crea mercancía por redondeo; los tests de producción lo comprueban.
- El estado guardado incluye las fracciones y las reservas.
- Cuenta con una tolerancia de redondeo (`ROUNDING_EPSILON`) para que sumas de fracciones como sextos no demoren una unidad exacta.
