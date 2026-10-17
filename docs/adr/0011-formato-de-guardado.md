# ADR 0011: Formato de guardado

- **Estado:** Aceptado
- **Fecha:** 2026-10-16
- **Origen:** issue #57 (PR #142); D-037 (capítulos de 4 a 8 h con guardado en cualquier momento), D-065, D-066 y D-067

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
  números (`autosave_interval_seconds`: 600 y `autosave_slots`: 3) viven en `data/game/save.json`. No son economía:
  no pasan por `Params` ni por `ParameterRanges`, y los valida `SaveSettings` (enteros de al menos 1), igual que los
  tiempos del splash (`SplashTimings`). Cristian lo confirmó el 2026-10-17 (transmitido por Chief en la PR #142:
  https://github.com/Palehour/londinium/pull/142#issuecomment-6229249006).
- Los archivos van en `user://saves/` (`manual_<fecha>.sav`, `autosave_<n>.sav`, `stage_<etapa>.sav`).

## Estado
Aceptado el 2026-10-17 en la PR #142. Cristian aprobó la D-067 (transmitido por Chief, 2026-10-17 00:17 ART:
https://github.com/Palehour/londinium/pull/142#issuecomment-6228946725) y confirmó que los números del autoguardado se
validan fuera de `Params` (00:48 ART: https://github.com/Palehour/londinium/pull/142#issuecomment-6229249006), lo
último que la revisión de Bailey pedía resolver antes de aceptarlo.

## Consecuencias
- Cambiar la forma de lo guardado obliga a subir `SaveFile.VERSION`; una versión vieja se rechaza hasta que haya
  migración, que hoy no existe.
- Un campo nuevo de `EconomyState` tiene que viajar en `to_dict()`/`from_dict()`: el test de ida y vuelta
  (`tests/sim/test_save_round_trip.gd`) falla si no.
- Los mods se comparan solo por nombre y orden: un mod con el mismo nombre y otro contenido carga sin aviso.
  Es una limitación conocida; detectarlo pediría guardar una huella del contenido de cada mod.
- Leer un archivo no ejecuta código: sin objetos, y el estado se valida contra los campos de un estado nuevo antes
  de usarlo.
