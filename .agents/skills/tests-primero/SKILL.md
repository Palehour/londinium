---
name: tests-primero
description: Escribe primero un test GUT que falla y después el arreglo o la feature. Usar al corregir un bug o al agregar una regla a la simulación o a los datos.
---

# Tests primero

La regla está en `AGENTS.md` ("Tests are guardrails"); acá, cómo cumplirla.

1. **Reproducí.** Escribí qué debería pasar, qué pasa hoy y el caso más chico que lo muestra
   (un edificio, una receta, N ticks).
2. **Elegí el test más cercano** que ya cubra ese código y sumale un caso:
   - Simulación: `tests/sim/test_*.gd`. Armá la `Simulation` como los tests vecinos
     (`SimTestParams.isolated_params()` aísla una regla de necesidades y finanzas) y llamá `sim.tick()` N veces
     (900 = 15 minutos de juego). Nada de frames, tiempo real ni árbol de escenas.
   - Datos y mods: `tests/data/`. Escenas y paneles: `tests/game/`.
   - Balance de varias horas: un escenario JSON en `tests/scenarios/` (ver `tests/slow/test_scenarios.gd`).
3. **Escribí el test y corrélo antes de tocar el código.** Tiene que fallar por el motivo del bug, no por un error
   de compilación o de setup. Un solo archivo:
   `"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gexit -gtest=res://tests/sim/test_<x>.gd`.
4. **Arreglá** con el cambio más chico que cumpla el comportamiento esperado.
5. **Corré otra vez** el test y después la suite entera (`tools/run_tests`, ver `implementar-issue`).

## Qué se testea
- Lo que se observa: stock, peniques, población, eventos, el estado que devuelve la simulación. No helpers privados
  ni el orden interno de llamadas.
- El valor esperado sale del issue, del GDD o de `data/` vía `Params`, no de una corrida del código.
- Probá el test con dos ediciones imaginarias: si rompés el comportamiento, tiene que fallar; si reescribís el
  código por dentro sin cambiar el resultado, tiene que seguir pasando.

## En el PR
En la tabla "Acceptance criteria → evidence", nombrá el test, cómo falló antes del arreglo (una línea de la
salida de GUT) y que pasa después.

## Gotchas
- Si un test cuesta más que el arreglo (pantalla, input, timing), usá un paso manual o un escenario, y explicá por
  qué en el PR. Mejor ningún test nuevo que uno frágil.
- Archivo de test nuevo: corré `--import` y commiteá su `.uid`.
- Nunca cambies un test para que coincida con un código equivocado (ver `AGENTS.md`).
