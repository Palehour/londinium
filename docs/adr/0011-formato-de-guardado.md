# ADR 0011: Formato de guardado

- **Estado:** Propuesto
- **Fecha:** 2026-10-16
- **Origen:** issue #57; D-037 (capítulos de 4 a 8 h con guardado en cualquier momento), D-065 y D-066

## Contexto
Las partidas del Hito 2 duran horas, así que hay que poder guardar y seguir. La simulación es determinista
(ADR 0001): una partida cargada tiene que seguir exactamente como si no se hubiera cortado. La historia de
estadísticas de #82 se guarda en arreglos empaquetados, la dificultad y los mods cambian los números (ADR 0010) y
los números del autoguardado los aprobó Cristian el 2026-10-13.

## Decisión
- Un guardado es un único `Variant` escrito con `store_var` en un archivo comprimido con ZSTD
  (`FileAccess.open_compressed`), **sin objetos** (`get_var(false)` al leer). Los arreglos empaquetados de la
  historia viajan tal cual.
- El contenido es un sobre versionado: `format` (`"londinium-save"`), `version` (entero), `saved_at`, `scenario`,
  `difficulty`, `knobs`, `mods` (en orden de carga) y `simulation`, que es `Simulation.to_save()`: el estado
  (`EconomyState.to_dict()`), la ventana de estadísticas, la historia de #82, el tick, la semilla y el punto de los
  dos generadores (trigo y cebada).
- `Simulation.from_save()` arma la simulación con ese estado y restaura el tick y los dos generadores; no cambia
  `tick()` ni el orden del tick.
- Se guarda el estado **al cierre del último tick**. Los comandos todavía en cola no entran en el archivo; si hay
  alguno al guardar a mano, el panel lo avisa. El autoguardado siempre corre justo después de un tick.
- Al cargar se rechaza, con un mensaje de `Strings`, un archivo que no es un guardado o está dañado, uno de otra
  versión y uno jugado con **otros mods** (otro conjunto u otro orden). La partida en curso sigue.
  Una historia que falta o está rota no impide cargar (D-066).
- Autoguardado cada `autosave_interval_seconds` de juego en `autosave_slots` ranuras rotativas, más un archivo
  aparte por cada etapa del capítulo cumplida, fuera de la rotación. Los guardados manuales no tienen tope. Los
  números viven en `data/game/save.json`; no son economía, así que no pasan por `Params`.
- Los archivos van en `user://saves/` (`manual_<fecha>.sav`, `autosave_<n>.sav`, `stage_<etapa>.sav`).

## Estado
Propuesto mientras el PR del #57 está abierto.

## Consecuencias
- Cambiar la forma de lo guardado obliga a subir `SaveFile.VERSION`; una versión vieja se rechaza hasta que haya
  migración, que hoy no existe.
- Un campo nuevo de `EconomyState` tiene que viajar en `to_dict()`/`from_dict()`: el test de ida y vuelta
  (`tests/sim/test_save_round_trip.gd`) falla si no.
- Leer un archivo no ejecuta código: sin objetos, y el estado se valida contra los campos de un estado nuevo antes
  de usarlo.
