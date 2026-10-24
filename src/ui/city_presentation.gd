class_name CityPresentation
extends RefCounted

# How the 3D greybox looks (issue #65, D-028): camera, light, the cold palette with its warm accents, and the height and
# silhouette of each building. Only presentation, read from data/ui/city.json like the 2D map reads data/ui/map.json.

const PATH: String = "res://data/ui/city.json"
const ROOFS: Array[String] = ["flat", "gable"]
const CAMERA_KEYS: Array[String] = ["pitch_deg", "fov_deg", "min_distance_m", "max_distance_m", "start_distance_m",
	"zoom_step", "zoom_smoothing", "pan_speed", "rotate_speed_deg", "drag_rotate_deg_per_px"]
const WORLD_COLORS: Array[String] = ["background", "ambient", "sun"]
const WORLD_NUMBERS: Array[String] = ["ambient_energy", "sun_energy", "sun_pitch_deg", "sun_yaw_deg"]
const GROUND_KEYS: Array[String] = ["depth_m", "gap_m"]
const FILLER_KEYS: Array[String] = ["height_m", "height_step_m", "width_m", "depth_m", "gap_m"]
const MARK_KEYS: Array[String] = ["selection_width_m", "mark_size_m", "damaged_wharf_height_m", "label_font_size",
	"label_pixel_size", "label_max_distance_m"]
const SHAPE_KEYS: Array[String] = ["height_m", "width_ratio", "depth_ratio", "roof_m", "chimney_m"]

var camera: Dictionary[String, float] = {}
var world_colors: Dictionary[String, Color] = {}
var world: Dictionary[String, float] = {}
var ground: Dictionary[String, float] = {}
var terrain: Dictionary[String, Color] = {}
var elevation: Dictionary[String, float] = {}
var lot_colors: Dictionary[StringName, Color] = {}
var filler_color: Color
var filler: Dictionary[String, float] = {}
var chimney_color: Color
var chimney_side: float
var selection_color: Color
var marks: Dictionary[String, float] = {}
var colors: Dictionary[StringName, Color] = {}
# Per building: height_m, width_ratio, depth_ratio, roof_m, chimney_m, plus roof ("flat" or "gable") and fillers.
var shapes: Dictionary[StringName, Dictionary] = {}
var errors: Array[String] = []


func load_data(building_ids: Array[StringName]) -> void:
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(PATH)) != OK:
		errors.append("data/ui/city.json: invalid JSON")
		return
	validate(json.data, building_ids)


func validate(raw: Variant, building_ids: Array[StringName]) -> void:
	errors.clear()
	shapes.clear()
	colors.clear()
	if raw is not Dictionary:
		errors.append("data/ui/city.json: expected an object")
		return
	_numbers(raw, "camera", CAMERA_KEYS, camera, true)
	if camera.get("zoom_step", 1.0) <= 1.0:
		errors.append("data/ui/city.json.camera.zoom_step: must be above 1")
	if camera.get("min_distance_m", 0.0) >= camera.get("max_distance_m", 0.0):
		errors.append("data/ui/city.json.camera: min_distance_m must be below max_distance_m")
	if camera.get("pitch_deg", 0.0) >= 90.0:
		errors.append("data/ui/city.json.camera.pitch_deg: must be below 90")
	_numbers(raw, "world", WORLD_NUMBERS, world, false)
	for key: String in WORLD_COLORS:
		var color: Variant = _section(raw, "world").get(key)
		if _valid_color(color):
			world_colors[key] = Color(color)
		else:
			errors.append("data/ui/city.json.world.%s: invalid color" % key)
	_numbers(raw, "ground", GROUND_KEYS, ground, true)
	for kind: String in MapPresentation.TERRAIN_KINDS:
		var entry: Variant = _section(raw, "terrain").get(kind)
		if entry is not Dictionary or not _valid_color(entry.get("color")) or not _is_number(entry.get("elevation_m")):
			errors.append("data/ui/city.json.terrain.%s: expected color and elevation_m" % kind)
			continue
		terrain[kind] = Color(entry["color"])
		elevation[kind] = float(entry["elevation_m"])
	for style: StringName in Strings.LOT_STYLE_LABELS:
		var color: Variant = _section(raw, "lot_styles").get(String(style))
		if _valid_color(color):
			lot_colors[style] = Color(color)
		else:
			errors.append("data/ui/city.json.lot_styles.%s: invalid color" % style)
	_numbers(raw, "filler", FILLER_KEYS, filler, true)
	filler_color = _color(raw, "filler", "color")
	chimney_color = _color(raw, "chimney", "color")
	var side: Dictionary[String, float] = {}
	_numbers(raw, "chimney", ["side_m"], side, true)
	chimney_side = side.get("side_m", 0.0)
	_numbers(raw, "marks", MARK_KEYS, marks, true)
	selection_color = _color(raw, "marks", "selection")
	for id: StringName in building_ids:
		_shape(_section(raw, "buildings").get(String(id)), id)


# Gives the 2D presentation the city's palette, so the legend in the header shows the colours on screen.
func apply_palette(presentation: MapPresentation) -> void:
	for kind: String in terrain:
		presentation.terrain[kind] = terrain[kind]
	for style: StringName in lot_colors:
		presentation.lot_colors[style] = lot_colors[style]
	for id: StringName in colors:
		presentation.colors[id] = colors[id]


func _shape(entry: Variant, id: StringName) -> void:
	var where: String = "data/ui/city.json.buildings.%s" % id
	if entry is not Dictionary or not _valid_color(entry.get("color")) or entry.get("roof") not in ROOFS \
			or entry.get("fillers") is not bool:
		errors.append("%s: expected color, roof (flat or gable) and fillers" % where)
		return
	var shape: Dictionary = {"roof": entry["roof"], "fillers": entry["fillers"]}
	for key: String in SHAPE_KEYS:
		var value: Variant = entry.get(key)
		# Ratios are a share of the footprint; a flat roof and a building without a chimney take 0.
		var top: float = 1.0 if key.ends_with("_ratio") else INF
		if not _is_number(value) or float(value) < 0.0 or float(value) > top or (key == "height_m" and float(value) == 0.0):
			errors.append("%s.%s: invalid value" % [where, key])
			return
		shape[key] = float(value)
	colors[id] = Color(entry["color"])
	shapes[id] = shape


func _numbers(raw: Dictionary, section: String, keys: Array[String], target: Dictionary[String, float], positive: bool) -> void:
	for key: String in keys:
		var value: Variant = _section(raw, section).get(key)
		if not _is_number(value) or (positive and float(value) <= 0.0):
			errors.append("data/ui/city.json.%s.%s: invalid %svalue" % [section, key, "positive " if positive else ""])
		else:
			target[key] = float(value)


func _color(raw: Dictionary, section: String, key: String) -> Color:
	var value: Variant = _section(raw, section).get(key)
	if _valid_color(value):
		return Color(value)
	errors.append("data/ui/city.json.%s.%s: invalid color" % [section, key])
	return Color.BLACK


func _section(raw: Dictionary, section: String) -> Dictionary:
	return raw.get(section) if raw.get(section) is Dictionary else {}


func _is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func _valid_color(value: Variant) -> bool:
	return value is String and Color.html_is_valid(value)
