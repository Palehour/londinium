class_name MapImporter
extends RefCounted

# Turns layers traced in QGIS (GeoJSON in British National Grid metres, EPSG:27700) into the cell layers of
# data/maps/<id>.json (issue #60, D-069, D-073, D-074). Deterministic: the same folder always gives the same text.
# A folder holds import.json (grid), optional <layer>.geojson files and overrides.json (hand fixes applied last,
# so a new import never loses them).

const CONFIG_FIELDS: Array[String] = ["id", "width", "height", "origin", "cell_metres", "samples_per_axis", "priority"]
# Polygon layers and the area class each one paints; "land" is what no polygon covers.
const AREA_LAYERS: Dictionary[String, String] = {"river": "river", "docks": "dock", "marsh": "marsh",
	"existing": "existing"}
const ROAD_LAYER: String = "roads"
const AREA_CLASSES: Array[String] = ["river", "dock", "marsh", "existing", "land"]
const WATER: Array[String] = ["river", "dock"]
# Keeps a street that runs along a cell edge out of the cells on both sides of it.
const EDGE_EPSILON: float = 0.000001
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var errors: Array[String] = []


func import_folder(folder: String) -> Dictionary:
	errors.clear()
	var config: Variant = _read_json(folder.path_join("import.json"))
	var overrides: Variant = _read_json(folder.path_join("overrides.json"))
	var layers: Dictionary = {}
	for layer: String in AREA_LAYERS.keys() + [ROAD_LAYER]:
		var path: String = folder.path_join(layer + ".geojson")
		if FileAccess.file_exists(path):
			layers[layer] = _read_json(path)
	if not errors.is_empty():
		return {}
	return import_documents(config, layers, overrides)


# Returns the map as data/maps/<id>.json holds it, or {} with `errors` filled.
func import_documents(config: Variant, layers: Dictionary, overrides: Variant) -> Dictionary:
	errors.clear()
	if not _valid_config(config):
		return {}
	var size: Vector2i = Vector2i(int(config["width"]), int(config["height"]))
	var areas: Array[Dictionary] = []
	var roads: Array[PackedVector2Array] = []
	for layer: Variant in layers:
		if layer == ROAD_LAYER:
			roads = _lines(layers[layer], config)
		elif AREA_LAYERS.has(layer):
			for rings: Array[PackedVector2Array] in _polygons(layers[layer], config):
				areas.append({"class": AREA_LAYERS[layer], "rings": rings})
		else:
			errors.append("%s: unknown layer" % layer)
	var classes: Dictionary[Vector2i, String] = _rasterize_areas(areas, size, config)
	var road_cells: Dictionary[Vector2i, bool] = _rasterize_roads(roads, size)
	_apply_overrides(overrides, classes, road_cells, size)
	var start_cells: Array = _dense_housing_cells(overrides, size)
	if not errors.is_empty():
		return {}
	var map: Dictionary = _map(config, classes, road_cells, size)
	if not start_cells.is_empty():
		map["dense_housing_cells"] = start_cells
	return map


# Fixed layout so a reimport only changes the lines whose cells changed.
func to_text(map: Dictionary) -> String:
	if map.is_empty():
		return ""
	var lines: Array[String] = ['  "id": "%s", "width": %d, "height": %d' % [map["id"], map["width"], map["height"]]]
	for field: String in ["river_cells", "cultivable_cells", "dock_cells", "road_cells", "existing_cells"]:
		lines.append('  "%s": %s' % [field, _cells_text(map[field])])
	var labels: Array[String] = []
	for label: String in map["terrain"]:
		labels.append('"%s": %s' % [label, _cells_text(map["terrain"][label])])
	lines.append('  "terrain": {%s}' % ", ".join(labels))
	if map.has("dense_housing_cells"):
		lines.append('  "dense_housing_cells": %s' % _cells_text(map["dense_housing_cells"]))
	return "{\n%s\n}\n" % ",\n".join(lines)


func _valid_config(config: Variant) -> bool:
	if config is not Dictionary:
		errors.append("import.json: expected an object")
		return false
	for field: String in CONFIG_FIELDS:
		if not config.has(field):
			errors.append("import.json.%s: missing field" % field)
	if not errors.is_empty():
		return false
	for field: String in ["width", "height", "cell_metres", "samples_per_axis"]:
		if typeof(config[field]) not in [TYPE_INT, TYPE_FLOAT] or float(config[field]) <= 0 \
				or float(config[field]) != floorf(float(config[field])):
			errors.append("import.json.%s: expected a positive whole number" % field)
	if config["origin"] is not Array or config["origin"].size() != 2 \
			or typeof(config["origin"][0]) not in [TYPE_INT, TYPE_FLOAT] \
			or typeof(config["origin"][1]) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("import.json.origin: expected [easting, northing]")
	var priority: Array[String] = []
	if config["priority"] is Array and config["priority"].all(func(entry: Variant) -> bool: return entry is String):
		priority.assign(config["priority"])
	priority.sort()
	var classes: Array[String] = AREA_CLASSES.duplicate()
	classes.sort()
	if priority != classes:
		errors.append("import.json.priority: expected each of %s once" % str(AREA_CLASSES))
	return errors.is_empty()


# Easting/northing in metres to grid units: x grows east, y grows south from the north-west corner.
func _to_grid(point: Variant, config: Dictionary) -> Vector2:
	var cell: float = float(config["cell_metres"])
	return Vector2((float(point[0]) - float(config["origin"][0])) / cell,
		(float(config["origin"][1]) - float(point[1])) / cell)


func _geometries(collection: Variant, layer_types: Array[String]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if collection is not Dictionary or collection.get("features") is not Array:
		errors.append("expected a GeoJSON FeatureCollection")
		return found
	for feature: Variant in collection["features"]:
		var geometry: Variant = feature.get("geometry") if feature is Dictionary else null
		if geometry is not Dictionary or geometry.get("type") not in layer_types \
				or geometry.get("coordinates") is not Array:
			errors.append("unsupported geometry: expected %s" % " or ".join(layer_types))
			continue
		found.append(geometry)
	return found


func _points(raw: Variant, config: Dictionary) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for point: Variant in raw:
		if point is not Array or point.size() < 2 or typeof(point[0]) not in [TYPE_INT, TYPE_FLOAT] \
				or typeof(point[1]) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("invalid coordinate %s" % str(point))
			return PackedVector2Array()
		points.append(_to_grid(point, config))
	return points


# Each polygon as its rings: the outer one first, then its holes.
func _polygons(collection: Variant, config: Dictionary) -> Array[Array]:
	var polygons: Array[Array] = []
	for geometry: Dictionary in _geometries(collection, ["Polygon", "MultiPolygon"]):
		var parts: Array = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
		for part: Variant in parts:
			var rings: Array[PackedVector2Array] = []
			for ring: Variant in part:
				rings.append(_points(ring, config))
			polygons.append(rings)
	return polygons


func _lines(collection: Variant, config: Dictionary) -> Array[PackedVector2Array]:
	var lines: Array[PackedVector2Array] = []
	for geometry: Dictionary in _geometries(collection, ["LineString", "MultiLineString"]):
		var parts: Array = geometry["coordinates"] if geometry["type"] == "MultiLineString" else [geometry["coordinates"]]
		for part: Variant in parts:
			lines.append(_points(part, config))
	return lines


# Majority class over an n×n grid of sample points per cell; a point inside several polygons counts for the class
# that comes first in `priority`, and so do ties between classes.
func _rasterize_areas(areas: Array[Dictionary], size: Vector2i, config: Dictionary) -> Dictionary[Vector2i, String]:
	var priority: Array = config["priority"]
	var samples: int = int(config["samples_per_axis"])
	var classes: Dictionary[Vector2i, String] = {}
	for y: int in range(size.y):
		for x: int in range(size.x):
			var counts: Dictionary[String, int] = {}
			for sy: int in range(samples):
				for sx: int in range(samples):
					var point: Vector2 = Vector2(x + (sx + 0.5) / samples, y + (sy + 0.5) / samples)
					var found: String = _class_at(point, areas, priority)
					counts[found] = counts.get(found, 0) + 1
			var best: String = ""
			for candidate: String in priority:
				if counts.get(candidate, 0) > counts.get(best, -1):
					best = candidate
			classes[Vector2i(x, y)] = best
	return classes


func _class_at(point: Vector2, areas: Array[Dictionary], priority: Array) -> String:
	var best: int = priority.find("land")
	for area: Dictionary in areas:
		var rank: int = priority.find(area["class"])
		if rank < best and _inside(point, area["rings"]):
			best = rank
	return priority[best]


func _inside(point: Vector2, rings: Array[PackedVector2Array]) -> bool:
	if rings.is_empty() or not Geometry2D.is_point_in_polygon(point, rings[0]):
		return false
	for hole: int in range(1, rings.size()):
		if Geometry2D.is_point_in_polygon(point, rings[hole]):
			return false
	return true


# A street marks every cell its centre line crosses, so a diagonal comes out as a staircase whose steps share a
# side (#67 joins road cells through their four sides).
func _rasterize_roads(lines: Array[PackedVector2Array], size: Vector2i) -> Dictionary[Vector2i, bool]:
	var cells: Dictionary[Vector2i, bool] = {}
	for line: PackedVector2Array in lines:
		for index: int in range(line.size() - 1):
			var from: Vector2 = line[index]
			var to: Vector2 = line[index + 1]
			var low: Vector2i = Vector2i(from.min(to).floor()).max(Vector2i.ZERO)
			var high: Vector2i = Vector2i(from.max(to).floor()).min(size - Vector2i.ONE)
			for y: int in range(low.y, high.y + 1):
				for x: int in range(low.x, high.x + 1):
					if _crosses(from, to, Rect2(Vector2(x, y), Vector2.ONE).grow(-EDGE_EPSILON)):
						cells[Vector2i(x, y)] = true
	return cells


func _crosses(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	if rect.has_point(from) or rect.has_point(to):
		return true
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)]
	for index: int in range(corners.size()):
		if Geometry2D.segment_intersects_segment(from, to, corners[index], corners[(index + 1) % 4]) != null:
			return true
	return false


func _apply_overrides(overrides: Variant, classes: Dictionary[Vector2i, String],
		road_cells: Dictionary[Vector2i, bool], size: Vector2i) -> void:
	if overrides is not Dictionary:
		errors.append("overrides.json: expected an object")
		return
	var bounds: Rect2i = Rect2i(Vector2i.ZERO, size)
	for entry: Variant in overrides.get("areas", []):
		if entry is not Dictionary or entry.get("class") not in AREA_CLASSES or entry.get("rects") is not Array:
			errors.append("overrides.json.areas: expected a class of %s and rects" % str(AREA_CLASSES))
			continue
		for raw: Variant in entry["rects"]:
			var rect: Rect2i = _rect(raw)
			if rect.size.x <= 0 or rect.size.y <= 0 or not bounds.encloses(rect):
				errors.append("overrides.json.areas: rect %s is empty or outside the grid" % str(raw))
				continue
			for y: int in range(rect.position.y, rect.end.y):
				for x: int in range(rect.position.x, rect.end.x):
					classes[Vector2i(x, y)] = entry["class"]
	var roads: Variant = overrides.get("roads", {})
	if roads is not Dictionary:
		errors.append("overrides.json.roads: expected an object with add and remove")
		return
	for operation: String in ["add", "remove"]:
		for raw: Variant in roads.get(operation, []):
			var cell: Vector2i = _cell(raw)
			if not bounds.has_point(cell):
				errors.append("overrides.json.roads.%s: cell %s is outside the grid" % [operation, str(raw)])
			elif operation == "add":
				road_cells[cell] = true
			else:
				road_cells.erase(cell)


# Where dense housing stands at the start (issue #154), picked by hand in the order given. The data loader checks that
# each one is a standing building beside a street (D-079).
func _dense_housing_cells(overrides: Variant, size: Vector2i) -> Array:
	var cells: Array = []
	if overrides is not Dictionary:
		return cells
	var raw: Variant = overrides.get("dense_housing_cells", [])
	if raw is not Array:
		errors.append("overrides.json.dense_housing_cells: expected a list of cells")
		return cells
	for entry: Variant in raw:
		var cell: Vector2i = _cell(entry)
		if not Rect2i(Vector2i.ZERO, size).has_point(cell):
			errors.append("overrides.json.dense_housing_cells: cell %s is outside the grid" % str(entry))
		else:
			cells.append([cell.x, cell.y])
	return cells


# [x, y] as a cell, or (-1, -1) when it is not a pair of whole numbers.
func _cell(raw: Variant) -> Vector2i:
	if raw is not Array or raw.size() != 2:
		return Vector2i(-1, -1)
	return _rect([raw[0], raw[1], 1, 1]).position


func _rect(raw: Variant) -> Rect2i:
	if raw is not Array or raw.size() != 4:
		return Rect2i(-1, -1, 0, 0)
	for value: Variant in raw:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or float(value) != floorf(float(value)):
			return Rect2i(-1, -1, 0, 0)
	return Rect2i(int(raw[0]), int(raw[1]), int(raw[2]), int(raw[3]))


func _map(config: Dictionary, classes: Dictionary[Vector2i, String], road_cells: Dictionary[Vector2i, bool],
		size: Vector2i) -> Dictionary:
	var layers: Dictionary[String, Array] = {"river": [], "dock": [], "existing": [], "marsh": [], "riverbank": []}
	var roads: Array = []
	# Row by row, so the output order never depends on dictionary order.
	for y: int in range(size.y):
		for x: int in range(size.x):
			var cell: Vector2i = Vector2i(x, y)
			var kind: String = classes[cell]
			if kind == "land" and _beside_water(cell, classes):
				kind = "riverbank"
			if layers.has(kind):
				layers[kind].append([x, y])
			if road_cells.has(cell):
				roads.append([x, y])
	return {"id": config["id"], "width": size.x, "height": size.y, "river_cells": layers["river"],
		"cultivable_cells": [], "dock_cells": layers["dock"], "road_cells": roads,
		"existing_cells": layers["existing"], "terrain": {"riverbank": layers["riverbank"], "marsh": layers["marsh"]}}


func _beside_water(cell: Vector2i, classes: Dictionary[Vector2i, String]) -> bool:
	for side: Vector2i in SIDES:
		if classes.get(cell + side, "") in WATER:
			return true
	return false


func _cells_text(cells: Array) -> String:
	var parts: Array[String] = []
	for cell: Variant in cells:
		parts.append("[%d, %d]" % [cell[0], cell[1]])
	return "[%s]" % ", ".join(parts)


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s: missing file" % path)
		return null
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
