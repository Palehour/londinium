# Whitechapel completo: datos fuente (issue #61, tarea 1)

Autor: Chronicler. Sin código. Complementa D-086 (25 m) y D-091.
Versión 3: grilla rotada de 48×80 que eligió Cristian, a 25 m reales.
Tabla: `whitechapel_full_sources.csv`, una fila por elemento. Coordenadas en casillas: x 0–47 de oeste a este, y 0–79 de norte a sur, origen en el noroeste.
Etiquetas: [FACT] con fuente, [DEBATED], [LEGEND], [INVENTED]. Año de referencia: 1866 (EV-1866-OLDFORD, D-090).

## 1. Grilla y georreferencia
- Proyección British National Grid (EPSG:27700), como en `riverside_strip/import.json`.
- Esquina NO: **E 533500, N 181850**. Esquina SE: **E 534700, N 179850**. Son 1,2 km de oeste a este y 2 km de norte a sur.
- `x = floor((E − 533500) / 25)` y `y = floor((181850 − N) / 25)`. `build.py` comprueba que todas las coordenadas del CSV estén en x 0–47 e y 0–79.
- Conversión: los puntos de calles y escaleras salen de OpenStreetMap (ODbL, solo uso coordenadas derivadas). Támesis y dársenas salen del export OHM CC0 de `riverside_strip/`. Todo pasa a EPSG:27700 con pyproj, se recorta a la ventana con shapely y se redondea a la casilla. Las calles quedan como puntos cada ~120 m.
- Chequeo cruzado contra la OS London 1:1056 VII.78/87/88 (NLS, CC-BY), ya georreferenciada en `riverside_strip/nls_report.md` (≤ 3,6 m de error), y contra el mapa de Booth (booth.lse.ac.uk) como referencia visual. No copié imágenes.
- Error esperado: ±1 casilla.

## 2. Distritos (3)
Que cada parroquia existió, y cuándo, es [FACT]. La línea exacta la tracé yo siguiendo las calles que hacen de límite, con ±1–2 casillas de error, así que es [DEBATED].
- **Whitechapel** (St Mary Matfelon): parroquia medieval [FACT: VCH Middx xi; Survey of London vols. 54–55]. Abarca todo el ancho de la ventana al oeste de Back Church Lane (x 36), hasta Cable St / Royal Mint St (y 36). Al este de x 36 llega hasta Commercial Road (y 24).
- **St George in the East**: iglesia consagrada el 19/7/1729, parroquia separada de Stepney [FACT: stgitehistory.org.uk/history.html; VCH Middx xi]. Va de Cable St / Commercial Rd hasta el borde norte de los London Docks (y 51).
- **Wapping** (St John Wapping): parroquia desde 1694 [FACT: VCH Middx xi]. Va de los docks al Támesis.
- **No entran completos**. Con 1,2 km de ancho, St George y Wapping quedan cortados en E 534700 (x 47): sus partes del este, hasta New Gravel Lane / Shadwell (≈ E 535100), quedan afuera. Ver "Fuera del recorte".
- Pliegues [INVENTED]:
  - La punta sur de la parroquia de Spitalfields (al norte de Wentworth St, aprox. x 0–19, y 0–11) y la franja de la City en el borde oeste van a Whitechapel.
  - Wellclose y East Smithfield (libertades de la Torre) van a St George.
  - El precinto de St Katharine y la ribera de la Torre van a Wapping.

## 3. Támesis y escaleras
- `river.thames`: la fila donde empieza el río en cada x. De ahí a y 79, todo es río (como mínimo 4 filas de río por columna). Sale de OHM [DEBATED: el polígono de OHM no tiene fecha].
- Escaleras dentro de la ventana:
  - Alderman Stairs [DEBATED: el nombre sale de OSM moderno y no lo confirmé en la hoja].
  - Hermitage Stairs [FACT].
  - Wapping Old Stairs [FACT: leída en la hoja VII.88].
  - Fuente de la ubicación: las escaleras que sobreviven (OSM). Que existían en 1870 lo dicen la OS 1:1056 y Booth.

- **¿Las escaleras eran intocables?** La idea de que no se podían cerrar ni construir encima es [LEGEND]. Lo comprobado: eran *plying places* públicos de los watermen, registrados por la City (Registers of Plying Places, Guildhall) [FACT, vía rbhistory.org.uk/post/the-plying-game]. Pero se podían quitar por ley del Parlamento:
  - Las St Katharine's Stairs se eliminaron en 1827 para construir los St Katharine Docks [FACT: Harben, *Dictionary of London* (1918), https://www.grubstreetproject.net/places/4318/].
  - En 1868, sobre las escaleras que quitaba el Embankment, el MBW sostuvo que cuando se sacaban o se obstruían "existing stairs, pier, or landing-place" la ley solo lo obligaba a dar otro desembarcadero al público [FACT: Hansard, HC Deb 27/4/1868, https://api.parliament.uk/historic-hansard/commons/1868/apr/27/thames-embankment-steamboat-piers].
  - Los watermen pedían indemnización cuando una obra les cortaba el trabajo, como en 1818 por el puente de Rotherhithe [FACT: Hansard, HC Deb 6/4/1818, https://api.parliament.uk/historic-hansard/commons/1818/apr/06/thames-watermen].
  - Para el juego: las escaleras son fijas en 1866 y no se pueden demoler [INVENTED, es una regla de diseño, no una ley de la época]. Ninguna escalera de la ribera de Wapping que esté en el CSV se perdió con los London Docks [DEBATED: no encontré una lista primaria de escaleras eliminadas en 1800–05].

## 4. Dársenas (no edificables, D-020)
- St Katharine Docks: entera, abierta el 25/10/1828 [FACT: VCH Middx xi, BHO].
- London Docks, abiertos el 31/1/1805 [FACT: VCH Middx xi]:
  - Western Dock: entero [FACT].
  - Wapping Basin y Wapping Lock: enteros, 1805 [FACT].
  - Hermitage Basin: entera, 1821 [DEBATED].
  - Tobacco Dock: recortada, entran 406 de 4645 m² (es una astilla en x 46–47) [DEBATED, c. 1811–14].
- Los contornos salen de OHM (CC0).

## 5. Calles dentro de la ventana
| id | Calle | Dentro (m) | Año | Etiqueta | Fuente |
|---|---|---|---|---|---|
| street.whitechapel_high | Whitechapel High Street | 306 de 306 | en uso antes de 1086 | [FACT] (el origen romano es [DEBATED]) | VCH Middx xi pp. 7–13 (Stepney: Communications), BHO |
| street.whitechapel_road | Whitechapel Road | **749 de 1005, recortada** en x 47 | en uso antes de 1086 | [FACT] | VCH Middx xi pp. 7–13 |
| street.commercial_road_west | Commercial Road, extensión a Gardiner's Corner | 332 de 332 | 1865 o 1870 | [DEBATED] | Tower Hamlets CA appraisal (1865) contra una fuente secundaria (1870). En 1866 puede no existir todavía |
| street.commercial_road_east | Commercial Road, tramo de 1802–06 desde Back Church Lane | **345 de 1496, recortada** | 1806 | [FACT] | Survey of London vols. 43–44 pp. 120–126; THLHLA L/ABH |
| street.leman | Leman Street | 514 de 514 | 1682 | [FACT] | Survey of London, *Whitechapel* (vols. 54–55, 2022): la trazó Sir William Leman en los 1680; John Hooper tomó contratos de construcción en ago. 1682. surveyoflondon.org/map/feature/1457 y /1300 |
| street.cable | Cable Street | **548 de 1626, recortada** | 1703 (primer registro del nombre); el camino ya era Hachestreet en 1250 | [FACT] | VCH Middx xi pp. 7–13 |
| street.ratcliff_highway | Ratcliff Highway (hoy The Highway) | **466 de 1549, recortada** | 1272 ("vicum de Shadwell") | [FACT] | VCH Middx xi pp. 7–13 |
| street.cannon_street_road | Cannon Street Road | 568 de 568 (sobre el borde este, x 43–47) | 1754 | [FACT] | Ratcliff Highway Act 1754, 27 Geo. II c. 40 (ECCO); el nombre actual es de 1859 (stgitehistory.org.uk) |
| street.commercial_street | Commercial Street, tramo sur | 443 de 443 | 1845 | [FACT] | Survey of London vol. 27 cap. XIX, BHO. Entra porque la ventana llega a N 181850. Su punta norte cae en el pliegue de Spitalfields |
Las longitudes son de los ejes simplificados. Las calles recortadas terminan en el borde de la ventana.

## 5b. Fuera del recorte
Sin filas en el CSV.
| Elemento | Qué queda afuera | Etiqueta | Fuente |
|---|---|---|---|
| Whitechapel Road | 256 m al este de E 534700 (hacia Mile End) | [FACT] | VCH Middx xi pp. 7–13 |
| Commercial Road, tramo de 1806 | 1151 m al este | [FACT] | Survey of London vols. 43–44 |
| Cable Street | 1078 m al este (hacia Shadwell) | [FACT] | VCH Middx xi pp. 7–13 |
| Ratcliff Highway | 1083 m al este | [FACT] | VCH Middx xi pp. 7–13 |
| Commercial Street, tramo norte (1849–57/58) | Entero | [DEBATED] | Survey of London vol. 27 (la apertura en 1858 es secundaria) |
| St George in the East y Wapping | Las partes del este, de E 534700 a ≈ E 535100 (Old Gravel Lane a New Gravel Lane) | [FACT] (que existían) | VCH Middx xi |
| London Docks Eastern Dock (1820s) | Entero | [DEBATED] (fecha) | contorno OHM |
| Tobacco Dock | 91 % | [DEBATED] | contorno OHM |
| Escaleras | Tower Stairs (100 m al oeste del borde), Wapping New, King Henry's, Wapping Dock, New Crane y Pelican (todas al este) | [FACT] | OSM (posición), OS 1:1056 / Booth (en 1870) |
| La Torre | Su mitad oeste | [FACT] | |

## 6. water_source por distrito (1866)
Fuente: Farr, *Report on the Cholera Epidemic of 1866* (1868), https://archive.org/stream/b28067423/b28067423_djvu.txt. Uso el texto principal (pp. xix–xx), la nota al pie de p. xxix y las respuestas de los médicos oficiales de salud del apéndice "The Health Officers on the Water Supply" (p. ~171).
- **La nota de Farr ya está resuelta.** Su asterisco no habla del agua: va pegado a "were not supplied with gas by the Commercial Company". Lo que dice es que St George, Shadwell y Wapping no recibían *gas* de la Commercial Gas Company (p. xxix). El [DEBATED] que nacía de esa nota queda sin efecto.

| Distrito | water_source | Etiqueta | Evidencia |
|---|---|---|---|
| whitechapel | old_ford | [FACT] (mixto) | Farr la nombra entre los distritos de "the Old Ford pumps". John Liddle (MOH, 30/8/1866): la East London da agua a ~7914 casas y la New River a ~750 (≈ 1/12), estas en partes de los subdistritos Aldgate, Whitechapel North y Artillery, con caños por Upper East Smithfield y Petticoat Lane |
| st_george_east | old_ford | [FACT] | Farr (p. xix) la nombra entre los distritos abastecidos "by the Old Ford pumps", y en p. xx cita al capitán Tyler: Old Ford casi todos los días de semana y Lea Bridge de noche y los domingos. El MOH de St George no contestó la encuesta ("No replies were received") |
| wapping | old_ford | [FACT] para la compañía; [DEBATED] para las bombas | El MOH de Limehouse (cuyo distrito incluía Wapping) dice que está "wholly supplied by the East London Waterworks", salvo 15 casas en Green-yard y 4 en Brown Bear-alley, Wapping, que recibían de la New River. Ninguna fuente nombra a Wapping como Old Ford o Lea Bridge. Lo pongo en Old Ford por estar entre St George y Limehouse, que Farr sí pone en Old Ford |

Con la New River como excepción menor, para el juego los tres distritos son `old_ford`. Las casas de la New River (~9 % de Whitechapel, 19 en Wapping) quedan abstraídas [INVENTED].
Pozos: no pongo ninguno fijo. El MOH de Limehouse dice: "There are no public pumps or wells in the district in use". En Whitechapel, Liddle cuenta que la Junta de Obras cerró dos bombas por agua sucia y que los vecinos de Norton Folgate pidieron reabrirlas (p. ~171). Norton Folgate queda fuera del recorte, así que no se agrega ningún pozo.

## 7. Libertades
1. [INVENTED] **Ventana.** E 533500–534700 × N 181850–179850. Es la propuesta de Mason corrida 100 m al este para que entren Cannon Street Road (E 534580–534695) y el borde este del Western Dock (E 534681). El costo es perder Tower Stairs. El norte (N 181850) deja entera Whitechapel Road hasta E 534700, donde llega a N ≈ 181800. El sur (N 179850) deja como mínimo 4 filas de río.
2. [INVENTED] Los pliegues de distritos de la sección 2. Spitalfields como distrito sigue estacionado.
3. [INVENTED] Las calles son ejes simplificados. El ancho de 2 casillas (D-086) lo pone la tarea 3.
4. [DEBATED] Los límites de parroquia están trazados a mano con ±1–2 casillas de error.
5. [DEBATED] El río y las dársenas salen de OHM.

## 8. Parking (notas, sin filas en el CSV)
### Shadwell
- Shadwell Basin: la nueva entrada de los London Docks, 1854–58 [FACT: VCH Middx xi]. Queda al este de la ventana (E 535098–535448). Sus bordes exactos son [DEBATED].
- St Paul Shadwell: parroquia desde 1670 [DEBATED: es lo que dicen las fuentes secundarias, no lo chequeé en la VCH]. La iglesia está en E ≈ 535280, afuera. En 1866, Farr la nombra en la misma nota que St George y Wapping [DEBATED].
### Para la expansión 1888 (Spitalfields)
- Spitalfields (Christ Church), parroquia desde 1729 [FACT: Survey of London vol. 27]. Agua: `lea_bridge` [DEBATED]. Farr dice que las aguas de Old Ford y Lea Bridge se encontraban en una "fluctuating line ... onwards to Spitalfields".
- Hanbury Street: en el patio del n.º 29 se encontró a Annie Chapman el 8/9/1888 [DEBATED: hasta ahora solo lo vi en fuentes secundarias (casebook.org)]. El nombre unificado sería de 1876 [DEBATED].
- Dorset Street: calle de lodging houses. Mary Jane Kelly en Miller's Court, 9/11/1888 [DEBATED: solo secundarias]. La fama de "la peor calle de Londres" [LEGEND]. Su color en el mapa de Booth está [DEBATED] hasta que lo mire.

## Licencias
OHM CC0. OSM ODbL (coordenadas derivadas; si la tarea 3 las usa, atribuir "© OpenStreetMap contributors"). NLS CC-BY: "Reproduced with the permission of the National Library of Scotland". Booth/LSE solo como referencia visual.

## Liberty: corte este (aceptado por Mason, 2026-10-23)
- [INVENTED] El mapa corta en E534700. La parte este de St George in the East y de Wapping (de E534700 a unos E535100) queda afuera del juego.
- [INVENTED] El Eastern Dock de London Docks queda afuera.
- [INVENTED] Tobacco Dock aparece recortado: solo el 9 % (406 de 4645 m²).
- [INVENTED] Seis escaleras del este quedan afuera: Wapping New, King Henry's, Wapping Dock, New Crane, Pelican y Tower Stairs (esta última, en el oeste).
- Todo esto pasa al parking, junto con Shadwell.
