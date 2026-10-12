# ADR 0006: Fracciones acumuladas, con pozo compartido en los bienes con tope de almacén

- **Estado:** Propuesto
- **Fecha:** 2026-10-12
- **Origen:** issue #51, PR #105; src/sim/systems/production_system.gd. Reemplaza al ADR 0005.

## Contexto
El ADR 0005 fija que cada edificio acumula su propia fracción de producción (`output_fraction`) y solo entrega al stock las unidades enteras que completa. Con la malta y la cerveza (issue #51) aparece un almacén con tope y un bien que puede fabricar más de un edificio. Si cada productor descuenta solo su propia fracción del mismo espacio libre, varios pueden acumular más producción de la que cabe; y si el espacio libre se reparte entre ellos, dos productores con media unidad cada uno nunca entregarían la unidad entera.

## Decisión
Se mantiene lo del ADR 0005 y se agrega una regla para los bienes con tope de almacén.

- **Acumular (producción y merma del trigo):** cada edificio guarda `output_fraction` y solo entrega al stock las unidades enteras que completa; `wheat_decay_fraction` acumula la pérdida y solo la quita del stock al completar una unidad. Un conversor toma una unidad entera de insumo del stock, la reserva (`reserved_input`) y la va consumiendo según su ritmo; no toma otra hasta agotarla.
- **Saldo total (consumo y merma del pan, consumo del té):** el stock entero más la fracción (`bread_fraction`, `tea_fraction`) forman un único saldo. Cada tick se descuenta la demanda de ese saldo de inmediato y el resto se vuelve a separar en unidades enteras y fracción. El resto no espera a completar una unidad para descontarse.
- **Bienes con tope (nuevo):** un bien que un conversor produce y que tiene `market.<bien>.storage_capacity` en los datos (hoy la malta y la cerveza; se derivan de los datos, no de una lista) se frena en vez de tirar producción cuando el almacén se llena. El espacio libre es el tope menos el stock menos la fracción pendiente de **todos** los productores del bien, y el presupuesto de cada edificio se limita a ese espacio. Después de que corren todos los edificios de un conversor, las fracciones de ese bien forman un **pozo**: sus unidades enteras se entregan al stock y se descuentan de las fracciones de los productores en orden de construcción. Con un solo productor el resultado es el mismo que con la regla de acumular.

## Estado
Propuesto mientras el PR #105 está abierto. Con la aprobación de Cristian, el autor lo cambia a Aceptado en un commit del mismo PR, antes del merge. El ADR 0005 queda marcado como Reemplazado por este.

## Consecuencias
- Un bien con tope nunca pasa su capacidad ni deja producción oculta que no cabe; con varios productores, dos fracciones que suman una unidad la entregan.
- El resto de los bienes (harina, pan) sigue con la regla de acumular por edificio, sin cambios de comportamiento: los escenarios existentes dan idénticos resultados.
- Una implementación nueva elige la estrategia que corresponde: acumular si algo se entrega o se pierde de a unidades; saldo total si se consume de forma continua; pozo compartido si el bien tiene tope y puede fabricarlo más de un edificio. No se mezclan.
- El estado guardado incluye las fracciones y las reservas.
- Cuenta con una tolerancia de redondeo (`ROUNDING_EPSILON`) para que sumas de fracciones como sextos no demoren una unidad exacta.
- Los tests están en `tests/sim/test_malt_beer.gd` (`test_two_breweries_cannot_both_use_the_last_unit_of_room`).
