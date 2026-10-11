# ADR 0001: Determinismo y semilla

- **Estado:** Propuesto
- **Fecha:** 2026-10-11
- **Origen:** issue #3

## Contexto
La simulación tiene que poder repetirse, probarse headless y, más adelante, reproducirse desde un registro de comandos.

## Decisión
La simulación es determinista. El `RandomNumberGenerator` con semilla es propiedad de la `Simulation`; el código de `src/sim/` no usa `randf()` ni otro generador global. Misma semilla y misma lista de comandos dan el mismo snapshot.

## Estado
Propuesto mientras el PR #99 está abierto; se marca Aceptado en un commit de ese PR cuando Cristian lo aprueba, antes del merge (ver `docs-vivos`). Registra lo ya decidido y construido; no introduce comportamiento nuevo.

## Consecuencias
- Hay un test de 900 ticks que compara dos corridas con la misma semilla y los mismos comandos.
- Toda aleatoriedad nueva (por ejemplo, el precio del trigo) sale del generador de la simulación.
- Los tests de la simulación no dependen de frames, tiempo real ni del árbol de escena.
