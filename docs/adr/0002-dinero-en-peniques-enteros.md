# ADR 0002: Dinero en peniques enteros

- **Estado:** Aceptado
- **Fecha:** 2026-10-11
- **Origen:** issues #3 y #4; docs/ARCHITECTURE.md (Conventions)

## Contexto
El dinero con decimales binarios acumula error y rompe el determinismo y las comparaciones exactas en los tests.

## Decisión
El dinero es un `int` en peniques en toda la simulación. La conversión a libras, chelines y peniques es solo de presentación (UI). Los parámetros monetarios se redondean una sola vez, al final de toda la lista de modificadores, al penique más cercano y con los empates alejándose de cero.

## Estado
Aceptado. Registra lo ya decidido y construido; no introduce comportamiento nuevo.

## Consecuencias
- Ningún `float` guarda dinero en `EconomyState`.
- `Params.get_value()` aplica ese redondeo único a las claves monetarias.
- Los datos de `data/` expresan costos y precios en peniques enteros.
