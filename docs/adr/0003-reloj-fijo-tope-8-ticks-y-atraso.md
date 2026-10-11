# ADR 0003: Reloj fijo, tope de 8 ticks por frame y atraso conservado

- **Estado:** Aceptado
- **Fecha:** 2026-10-11
- **Origen:** issue #3; src/game/sim_clock.gd

## Contexto
El juego avanza por frames de duración variable, pero la simulación tiene que avanzar en pasos idénticos. Un frame muy largo no debe congelar el juego ejecutando cientos de ticks.

## Decisión
Un tick equivale a 1 segundo de juego a 1x. `SimClock` acumula `delta × velocidad` (pausa, 1x, 2x, 3x) y llama a `tick()` en pasos enteros, con un tope de 8 ticks por frame (`max_ticks_per_frame`). El tiempo que no entra por el tope queda en el acumulador: el atraso se conserva y se recupera en los frames siguientes, no se descarta.

## Estado
Aceptado. Registra lo ya decidido y construido; no introduce comportamiento nuevo.

## Consecuencias
- La velocidad real del juego puede quedar por detrás si el equipo no da abasto, pero el estado nunca salta ni pierde segundos.
- El tope es un límite de planificación, no un parámetro de balance; por eso no vive en `data/`.
- Los tests de `SimClock` cubren el tope y la conservación del atraso.
