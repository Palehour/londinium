# ADR 0004: Contexto económico opcional

- **Estado:** Aceptado
- **Fecha:** 2026-10-11
- **Origen:** issues #3 y #4; src/sim/economy_context.gd

## Contexto
Algunos comandos y diagnósticos necesitan saber qué edificios y qué mapa existen, pero la simulación pura no debería depender de la carga de datos completa.

## Decisión
`EconomyContext` agrupa solo las definiciones estructurales (ids, etiquetas, entradas y salidas de recetas) y el mapa. Es opcional al crear la `Simulation`. Los números de balance no están en el contexto: se siguen leyendo con `Params.get_value()`.

## Estado
Aceptado. Registra lo ya decidido y construido; no introduce comportamiento nuevo.

## Consecuencias
- Las reglas de ubicación (por ejemplo, el campo de trigo solo en casillas cultivables) consultan el contexto.
- Una simulación sin contexto sigue funcionando para los sistemas que no lo necesitan.
- Agregar un dato estructural al contexto no autoriza a leer valores de balance fuera de `Params`.
