# Fuentes del mapa histórico (issue #60)

Cada carpeta `sources/<mapa>/` genera `data/maps/<mapa>.json` con `tools/map_import`. **No edites el JSON
generado a mano:** cambiá las fuentes o `overrides.json` y reimportá.

## Archivos
- `import.json`: la grilla. `origin` es la esquina noroeste en metros British National Grid (EPSG:27700),
  `cell_metres` el lado de la casilla (50 m, D-069), `width`/`height` en casillas, `samples_per_axis` cuántas
  muestras por eje se toman en cada casilla, y `priority` el orden de desempate entre clases. `roads_enabled`
  (opcional, `false` si falta) dice si el mapa se juega con calles (#67, D-080): `true` en la franja.
- Capas en GeoJSON, EPSG:27700 (todas opcionales). En la franja salen del export de OpenHistoricalMap (ver abajo):
  - `river.geojson`, `docks.geojson`, `marsh.geojson`, `existing.geojson`: polígonos (se admiten huecos y
    MultiPolygon). Cada casilla toma la clase que cubre la mayoría de sus muestras; lo que no cubre ningún
    polígono es tierra.
  - `roads.geojson`: líneas por el eje de cada calle principal (LineString o MultiLineString). Una calle marca
    cada casilla que cruza, así que una diagonal (D-058) queda en escalera unida por los lados.
- `overrides.json`: ajustes a mano que se aplican después de rasterizar, para que reimportar no los pise.
  `areas`: lista de `{"class": "river|dock|marsh|existing|land", "rects": [[x, y, ancho, alto]]}` (la última
  gana). `roads`: `{"add": [[x, y]], "remove": [[x, y]], "diagonals": [[x1, y1, x2, y2]]}`. Las diagonales (D-058) son
  aristas entre dos calles históricas que se tocan por la esquina; se listan una por una y nunca se deducen de las
  casillas. En la franja la lista está vacía: con las calles de OHM ninguna pasa de una casilla a otra solo por la esquina.
  `dense_housing_cells` (opcional):
  `[[x, y]]`, las casillas donde arranca la vivienda densa, en orden (#154, D-075, D-079); cada una tiene que ser
  edificación existente con una calle a un lado, y `startup.dense_housing_occupied` dice cuántas se ocupan.
  `anchors` (opcional, #152): anclas históricas leídas en las hojas,
  `{"name", "cell", "building", "source", "history"}`.
  `building` es el edificio que está desde el arranque (`""` si no tiene función). Un ancla en tierra es
  edificación existente; la de un `wharf` va sobre el río. Ningún ancla se demuele. `named_sites` (opcional):
  `{"name", "cell", "source", "history"}`, solo un nombre en una casilla; no bloquea nada. `history` abre con la
  etiqueta de Chronicler (`[FACT]`, `[FACT ±1]`, `[DEBATED]`, `[LEGEND]` o `[INVENTED]`) y dice qué es cierto y qué
  no. `history_notes` (opcional): las libertades del mapa entero, cada una con su etiqueta.
  Tierra de época (#176, D-083), todo opcional: `period_houses`, `{"name", "cell", "start_population", "source",
  "history"}`, son las casas de 1870. Van sobre tierra libre con una calle a un lado (D-079) y no llevan estilo de lote.
  La simulación las coloca como `dense_housing` no demolibles, con `start_population` habitantes (entero ≥ 0, opcional:
  si falta, 0) (#180, D-085). `damaged_wharves`,
  `{"name", "cell", "repair_cost_ratio", "source", "history"}`, son muelles dañados sobre el río. `repair_cost_ratio`
  es la parte del costo de un `wharf` nuevo que cuesta repararlo: mayor que 0 y como mucho 1 (la reparación es de #177).
  `lot_styles`, `{"<estilo>": [[x, y]]}`, es el estilo de cada lote libre y es solo dibujo (#178): toda casilla de tierra
  libre que no es una casa de época tiene uno y ninguna otra tiene. Todas estas listas pasan tal cual al JSON del mapa.

## Qué sale
`river_cells`, `dock_cells`, `road_cells`, `existing_cells`, `terrain` (`riverbank`: tierra junto al río o a
una dársena; `marsh`: lo calcado como marisma; el resto es tierra firme), `roads_enabled`, `road_diagonals` y, si
overrides lo trae, `dense_housing_cells`, `anchors`, `named_sites`, `history_notes`, `period_houses`,
`damaged_wharves` y `lot_styles`. Las reglas de calles son de #67 (en
`src/sim/road_network.gd`) y las de terreno de #88. La edificación existente no se puede edificar; la vivienda densa
inicial se pone sobre ella (D-075). Las dársenas no se pueden edificar (D-020).

## Reimportar
```
GODOT=/ruta/a/godot tools/map_import.sh riverside_strip      # o: all
GODOT=/ruta/a/godot tools/map_import.sh all --check          # solo compara, sale con 1 si algo quedó viejo
```
En Windows: `powershell -ExecutionPolicy Bypass -File tools\map_import.ps1 riverside_strip`.
El test `tests/tools/test_map_import.gd` falla si un mapa commiteado no coincide con sus fuentes.

## La franja de Wapping (`riverside_strip`, #152)
Opción A de Cristian (2026-10-18): el agua, las calles y las anclas históricas quedan fijas y el resto de la tierra
queda libre. `sources.json` dice de dónde sale cada cosa:
- **Calles, río y dársenas:** OpenHistoricalMap, CC0. `ohm_export.json` es la respuesta de Overpass a
  `ohm_1870.overpassql`, bajada el 2026-10-18; se guardan solo las vías en pie en 1870. **Hueco conocido de OHM:** no
  tiene Wapping High Street ni ninguna calle de la ribera, así que la franja no la trae (`sources.json`,
  `known_gaps`). Agregarla desde la hoja NLS es una decisión aparte: costaría unas 11 casillas libres.
- **Libertades** (`history_notes`): el Támesis de OHM no tiene fecha [DEBATED], y la esclusa de Wapping no entra a
  50 m por casilla, así que la Wapping Basin queda cerrada al río [INVENTED].
- **Anclas y sitios con nombre:** leídos en las hojas OS London 1:1056 VII.78, VII.87 y VII.88 (NLS, CC-BY, por
  IIIF, con la capa moderna apagada). Los recortes a 1/8 están en `nls_sheets/`; `sources.json` (`nls`) da sus
  puntos de control (esquinas de calles de OHM por id de nodo y esquinas de marco compartidas) y dónde está cada
  sitio en su hoja. `tools/map_sources --compare` (#170) escribe `nls_report.md` (el error de cada punto y la casilla
  de cada sitio según la hoja) y `docs/screenshots/riverside_strip_compare.png`; `--check` avisa si quedaron viejos.
  Cómo bajar y unir una hoja: `tools/map_sources/README.md`.
- **Esquina noroeste** (casillas x 0-5, y 0-3): cae en la hoja VII.77, que no tiene edición de 1862-74; ahí van
  solo las calles de OHM y la tierra queda libre.

Para bajar el export otra vez (no lo hace ningún test ni el CI):
```
curl -s --data-urlencode data@data/maps/sources/riverside_strip/ohm_1870.overpassql https://overpass-api.openhistoricalmap.org/api/interpreter > data/maps/sources/riverside_strip/ohm_export.json
```

## Fuentes y atribución
Base: OS London 1:1056 (1862–1874), National Library of Scotland, CC-BY: «Reproduced with the permission of the
National Library of Scotland» (https://maps.nls.uk/). Calles y agua de la franja: OpenHistoricalMap (CC0). Nombres
y calles del 8×8: Stanford's Library Map of London (1862). Créditos en `CREDITS.md` y en el juego.
