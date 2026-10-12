# ADR 0004: Contexto económico opcional

- **Estado:** Aceptado
- **Fecha:** 2026-10-11
- **Origen:** issues #3 y #4; src/sim/economy_context.gd

## Contexto
Algunos comandos y diagnósticos necesitan saber qué edificios y qué mapa existen, pero la simulación pura no debería depender de la carga de datos completa.

## Decisión
`EconomyContext` agrupa solo las definiciones estructurales (ids, etiquetas, entradas y salidas de recetas) y el mapa. Es opcional al crear la `Simulation`, pero los sistemas económicos lo necesitan: sin contexto, `tick()` solo ejecuta los comandos en cola y avanza el contador de ticks. Los números de balance no están en el contexto: se siguen leyendo con `Params.get_value()`.

## Estado
Aceptado por Cristian el 2026-10-11 en el PR #99 (confirmado por Bailey). Registra lo ya decidido y construido; no introduce comportamiento nuevo.

## Consecuencias
- Las reglas de ubicación (por ejemplo, el campo de trigo solo en casillas cultivables) consultan el contexto.
- Una simulación sin contexto no corre ningún sistema económico (trabajadores, mercado, importaciones, producción, consumo, satisfacción, crecimiento, dinero, derrota ni estadísticas): con la cola de comandos vacía, el estado queda igual salvo el contador de ticks (`test_empty_ticks_only_advance_time`). Los comandos en cola sí se ejecutan y pueden cambiarlo, por ejemplo el dinero (`test_commands_wait_for_tick_run_in_fifo_order_and_only_once`).
- Agregar un dato estructural al contexto no autoriza a leer valores de balance fuera de `Params`.
