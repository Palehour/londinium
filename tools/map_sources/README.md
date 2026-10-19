# tools/map_sources (issue #170)

Turns the raw downloads of a map, kept in `data/maps/sources/<map>/` and listed in its `sources.json`, into what
`tools/map_import` reads, and draws the image Cristian validates the map with. Nothing here goes online: the
downloads are committed with their date, and the tests only use them and the fixtures in `tests/tools/fixtures/`.

```
GODOT=/path/to/godot tools/map_sources.sh <map_id>|all              # write the GeoJSON layers
GODOT=/path/to/godot tools/map_sources.sh <map_id>|all --check      # exit 1 when a layer or nls_report.md is stale
GODOT=/path/to/godot tools/map_sources.sh <map_id> --compare        # docs/screenshots/<map_id>_compare.png + nls_report.md
```
On Windows: `powershell -ExecutionPolicy Bypass -File tools\map_sources.ps1 <map_id>`. The order is layers, then
`tools/map_import`, then `--compare` (the image and the report read the imported map).

## Files
- `osgb_projection.gd`: WGS84 (OHM) to British National Grid metres (EPSG:27700), with the Ordnance Survey's
  Helmert shift and Transverse Mercator formulas.
- `ohm_converter.gd`: an Overpass export (`out geom`) to `roads.geojson`, `river.geojson` and `docks.geojson`,
  keeping only the ways standing in the map's year, and the grid position of every node.
- `sheet_georeference.gd`: a least-squares similarity (scale, rotation, shift) from sheet pixels to grid metres,
  with the error of every control point in metres.
- `nls_sheets.gd`: the sheets of `sources.json` (`nls.sheets`), each fitted from its control points, sampled by
  grid position, and the report of the fits and of where the sheets put each named place (`nls.places`).
- `nls_digitizer.gd`: standing buildings from the grey fill of the sheets, only when `nls.buildings` gives its
  settings (the riverside strip has none: option A of 2026-10-18).
- `map_comparison.gd`: the comparison image; the corner with no sheet (`nls.gap.cells`) is hatched in both halves.

## The `nls` section of sources.json
Every pixel is a full-resolution pixel of the IIIF sheet (`<iiif>/info.json` gives its size).
```
"nls": {
  "sheets": [{
    "sheet": "VII.88", "iiif": "https://map-view.nls.uk/iiif/2/22995%2F229950236",
    "image": "nls_sheets/VII.88.jpg", "image_origin": [x, y], "image_scale": 8,
    "map_area": [x0, y0, x1, y1],
    "control_points": [
      {"name": "Green Bank x Red Lion Street", "pixel": [x, y], "ohm_node": 2093038601},
      {"name": "neatline corner shared with VII.88", "pixel": [x, y], "same_as": {"sheet": "VII.88", "pixel": [x, y]}}
    ]}],
  "places": [{"name": "St John's Church", "sheet": "VII.88", "pixel": [x, y]}],
  "gap": {"cells": [x, y, width, height]},
  "buildings": {"probes_per_axis": 4, "...": "only to digitize buildings"}
}
```
- `image` is a crop of the sheet: `image_origin` is its top-left corner and `image_scale` how many sheet pixels make
  one of its pixels. `map_area` is the neatline: outside every neatline there is no sheet.
- A control point is an OHM street corner (`ohm_node`, a node id of the export) or a neatline corner shared with a
  sheet listed before it (`same_as`), whose position that sheet's fit gives. Two points are the least; with more, the
  report shows each one's error. A point more than 25 m off (half a cell) gets a `note` in sources.json.

## Downloading a sheet
The NLS IIIF server serves at most 270 000 pixels per request, so a crop comes in tiles of 4096 sheet pixels cut at
1/8, which `--join` puts together:
```
base='https://map-view.nls.uk/iiif/2/22995%2F229950236'; s=8; T=4096
for y in 0 4096 8192; do for x in 0 4096 8192 12288; do
  curl -s -o "tiles/229950236_${s}_${x}_${y}.jpg" "$base/$x,$y,$T,$T/$((T / s)),/0/default.jpg"; done; done
"$GODOT" --headless --path . -s tools/map_sources/map_sources.gd -- --join tiles 229950236 8 x y width height out.jpg
```
At the edge of a sheet the server answers the part of the tile that exists.
