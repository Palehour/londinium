# Fuentes del mapa histórico (issue #60)

Cada carpeta `sources/<mapa>/` genera `data/maps/<mapa>.json` con `tools/map_import`. **No edites el JSON
generado a mano:** cambiá las fuentes o `overrides.json` y reimportá.

## Archivos
- `import.json`: la grilla. `origin` es la esquina noroeste en metros British National Grid (EPSG:27700),
  `cell_metres` el lado de la casilla (50 m, D-069), `width`/`height` en casillas, `samples_per_axis` cuántas
  muestras por eje se toman en cada casilla, y `priority` el orden de desempate entre clases.
- Capas calcadas en QGIS, exportadas como GeoJSON en EPSG:27700 (todas opcionales):
  - `river.geojson`, `docks.geojson`, `marsh.geojson`, `existing.geojson`: polígonos (se admiten huecos y
    MultiPolygon). Cada casilla toma la clase que cubre la mayoría de sus muestras; lo que no cubre ningún
    polígono es tierra.
  - `roads.geojson`: líneas por el eje de cada calle principal (LineString o MultiLineString). Una calle marca
    cada casilla que cruza, así que una diagonal (D-058) queda en escalera unida por los lados.
- `overrides.json`: ajustes a mano que se aplican después de rasterizar, para que reimportar no los pise.
  `areas`: lista de `{"class": "river|dock|marsh|existing|land", "rects": [[x, y, ancho, alto]]}` (la última
  gana). `roads`: `{"add": [[x, y]], "remove": [[x, y]]}`. `dense_housing_cells` (opcional): `[[x, y]]`, las
  casillas donde arranca la vivienda densa, en orden (#154, D-075, D-079); cada una tiene que ser edificación
  existente con una calle a un lado, y `startup.dense_housing_occupied` dice cuántas se ocupan.

## Qué sale
`river_cells`, `dock_cells`, `road_cells`, `existing_cells`, `terrain` (`riverbank`: tierra junto al río o a
una dársena; `marsh`: lo calcado como marisma; el resto es tierra firme) y, si overrides lo trae,
`dense_housing_cells`. Las reglas de calles son de #67 y las de terreno de #88. La edificación existente no se puede
edificar hasta el calcado de #152; la vivienda densa inicial se pone sobre ella (D-075). Las dársenas no se pueden
edificar (D-020).

## Reimportar
```
GODOT=/ruta/a/godot tools/map_import.sh riverside_strip      # o: all
GODOT=/ruta/a/godot tools/map_import.sh all --check          # solo compara, sale con 1 si algo quedó viejo
```
En Windows: `powershell -ExecutionPolicy Bypass -File tools\map_import.ps1 riverside_strip`.
El test `tests/tools/test_map_import.gd` falla si un mapa commiteado no coincide con sus fuentes.

## Fuentes y atribución
Base: OS London 1:1056 (1862–1874), National Library of Scotland, CC-BY. Nombres y calles: Stanford's Library
Map of London (1862). Antes de descargar teselas, revisar los términos de uso de NLS; si no, calcar a mano desde
el visor. Créditos en `CREDITS.md` y en el juego. La franja `riverside_strip` es provisoria (D-074): sale solo de
`overrides.json` hasta el calcado de #152.
