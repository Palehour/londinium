# ADR 0009: Movilidad entre clases

- **Estado:** Propuesto
- **Fecha:** 2026-10-13
- **Origen:** issue #53 (ascenso y descenso a artesano); D-061; amplía el ADR 0008

## Contexto
Desde #52 cada clase crece y se achica por su cuenta: llegan inmigrantes y se van emigrantes, pero nadie cambia de
clase. #53 pide que un trabajador ascienda a artesano si hay lugar, cerveza, pan y satisfacción, y que un artesano
vuelva a ser trabajador si le falta la cerveza durante un minuto. D-027 pide que el motor sea el mismo para todas las
eras, así que la regla no puede nombrar a "trabajador", "artesano" ni "cerveza".

## Decisión
- **La regla es de la clase destino y es datos.** En `classes.json`, la clase destino declara un bloque `mobility`
  opcional:
  - `from`: la clase de la que llega su gente.
  - `promotion.min_scores`: categoría → puntaje mínimo de la propia clase.
  - `promotion.source_satisfaction` y `promotion.per_minute`.
  - `demotion.category`, `demotion.below`, `demotion.seconds` y `demotion.per_minute`.

  Igual que en los demás bloques (ADR 0008), cada número es una clave de `Params` que ya existe o un número que el
  loader registra como `class.<clase>.mobility.*`. `ParameterRanges.PATTERNS` valida esas claves por forma. Los
  puntajes se miden sobre las categorías de la clase destino: la comunidad del artesano es la cerveza, mientras que
  la del trabajador es el té.
- **Umbrales enlazados.** El sustento del ascenso y el umbral del descenso apuntan a `needs.<categoría>.threshold`
  (D-032), no a números propios, así que se mueven con la categoría. Solo el 80 de comunidad es un número nuevo.
- **Estado.** `ClassState` de la clase destino suma `promotion_fraction`, `demotion_fraction` y
  `demotion_seconds_below`, que se guardan en `to_dict()` con valores por defecto para los guardados viejos.
  Mover gente solo cambia la población de la clase destino (y la de la clase origen si no es la base). El total no
  cambia y la clase base sigue siendo lo que dejan las otras.
- **Paso del tick.** `MobilitySystem` corre después de `GrowthSystem` y antes de `MoneySystem` (paso 8 de
  `docs/ARCHITECTURE.md`). Así lee los puntajes y la satisfacción del paso 7 de este mismo tick, la inmigración usa
  primero el lugar libre y el impuesto ya cobra a cada uno en su clase nueva. No usa números aleatorios.
- **Ritmo.** Las dos direcciones avanzan con una fracción por minuto, como el crecimiento. Si las condiciones se
  cortan, la fracción vuelve a 0 y no queda deuda.
  - El reloj del descenso cuenta segundos seguidos bajo el umbral, y solo mientras la clase tenga gente.
  - El descenso queda activo cuando ese reloj llega a los segundos pedidos.
  - Quien asciende deja su puesto por `WorkersSystem.trim_to_population`, así que ascienden primero los
    desempleados.
- **Diagnóstico.** `snapshot()["needs"]["classes"][<clase>]["mobility"]` dice de qué clase llega la gente, si el
  ascenso está activo, todos los bloqueos con sus ids, si el descenso está activo y cuántos segundos lleva. Los ids
  de bloqueo son `no_source_population`, `no_free_housing`, `category_below` (con la categoría y los bienes que
  faltan) y `source_satisfaction_low`. `Stats` cuenta los ascensos y los descensos del último minuto para el aviso
  del panel.

## Estado
Propuesto mientras el PR de #53 está abierto. Con la aprobación de Cristian, el autor lo cambia a Aceptado en un
commit del mismo PR, antes del merge.

## Consecuencias
- **Otra era puede tener sus propias movilidades sin tocar código.** Por ejemplo, de liberto a ciudadano en la
  romana. El aviso del panel nombra solo la primera clase con movilidad; con más de una habrá que separar los
  contadores por clase.
- **Sin vivienda de la clase destino, el sistema no cambia nada.** Por eso los escenarios sin vivienda de artesanos
  dan los mismos resultados que antes. Los que la tienen (`artisans_beer`) cambian y se vuelven a medir.
- **Cambiar el umbral de una categoría cambia también el ascenso y el descenso.** Si alguna vez tienen que ir por
  separado, alcanza con poner un número en vez de la clave en `classes.json`.
