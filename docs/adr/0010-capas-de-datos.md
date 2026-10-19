# ADR 0010: Capas de datos (dificultad y mods)

- **Estado:** Aceptado
- **Fecha:** 2026-10-15
- **Origen:** issue #70; D-044, D-049 y D-065

## Contexto
La dificultad (D-044) y los mods (D-049) cambian los mismos números de `data/` que lee la simulación, y #57 tiene
que poder guardar cuál se usó. D-014 exige que todo parámetro pase por una sola función (`Params.get_value`) que
aplica los modificadores del rol. D-065 fija el orden base → mods → preset → perillas → rol, los presets relativos a
Normal y las perillas absolutas.

## Decisión
- **Los mods se fusionan antes de validar (llega en la PR B, #132).** Cada archivo de un mod se fusiona en profundidad sobre el
  documento de `data/` con la misma ruta, en el orden de `load_order.json`. Lo que queda pasa por el mismo
  `DataLoader`, así que un mod se valida con los mismos esquemas y rangos que `data/`. Los valores base que ve el
  resto del juego ya incluyen los mods.
- **El preset y las perillas se resuelven una vez, en `DataLayers`.** El preset multiplica o suma sobre los valores
  base (con mods); las perillas fijan valores absolutos después. El resultado es una lista de modificadores `set`, con
  las claves enteras redondeadas al entero más cercano y las demás ajustadas a 0,000001 para que los factores
  escritos con decimales finitos (5/3 = 1,6666667) den el número aprobado.
- **`Params` aplica esa lista antes que la del rol.** El rol sigue último y sigue siendo la única función de
  modificadores; la validación de rangos y de las reglas cruzadas (política de trigo, fracciones de despoblación)
  cubre también lo que generan las capas.
- **Los presets y las perillas son datos** (`data/difficulty/`), y el loader verifica que cada valor posible de una
  perilla sea válido para sus claves. Una perilla fuera de rango o de paso es un error claro de `DataLayers.resolve`.
- **Normal no tiene modificadores**, así que sin preset el juego es idéntico a `data/`.

## Estado
Aceptado el 2026-10-15 en la PR #129. Aprobación de Cristian, confirmada por Bailey (2026-10-15 06:56 ART): «Sí, apruebo
en la #129 D-065, el resultado de Difícil tal como se midió con las corridas no jugadas documentadas, los guiones al
#128, el alcance sin mods (van en otra PR) y el test de defeat.* que saltea switches. Chief puede mergear con squash
cuando estén los arreglos.» La parte de mods llega en la PR B (#132).

## Consecuencias
- `GameSession.difficulty` dice en qué preset corre la partida, para #57.
- Un rol futuro que use `add` o `mul` actúa sobre el valor que dejó la dificultad, no sobre el de `data/`.
- Las perillas no pueden expresar algo que el rango de su clave no admita: el loader lo rechaza al cargar.
- `balance_report --preset` mide un preset sin tocar `data/`.
