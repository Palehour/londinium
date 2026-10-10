class_name MapPresentation
extends RefCounted

var terrain: Dictionary[String, Color] = {}
var ui_colors: Dictionary[String, Color] = {}
var layout: Dictionary[String, float] = {}
var camera: Dictionary[String, float] = {}
var colors: Dictionary[StringName, Color] = {}
var labels: Dictionary[StringName, String] = {}
var errors: Array[String] = []


func load_data(building_ids: Array[StringName]) -> void:
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string("res://data/ui/map.json")) != OK:
		errors.append("data/ui/map.json: invalid JSON")
		return
	validate(json.data, building_ids)


func validate(raw: Variant, building_ids: Array[StringName]) -> void:
	errors.clear()
	terrain.clear()
	ui_colors.clear()
	layout.clear()
	camera.clear()
	colors.clear()
	labels.clear()
	if raw is not Dictionary or raw.get("terrain") is not Dictionary or raw.get("buildings") is not Dictionary:
		errors.append("data/ui/map.json: expected terrain and buildings objects")
		return
	for key: String in ["header", "label", "selection", "alert"]:
		var color: Variant = raw.get("colors", {}).get(key) if raw.get("colors", {}) is Dictionary else null
		if _valid_color(color):
			ui_colors[key] = Color(color)
		else:
			errors.append("data/ui/map.json.colors.%s: invalid color" % key)
	_load_numbers(raw.get("layout"), ["cell_size", "header_height", "panel_width", "panel_margin", "help_x", "help_y", "grid_inset", "building_inset", "font_size", "label_offset_y", "selection_inset", "selection_width"], layout)
	_load_numbers(raw.get("camera"), ["pan_speed", "zoom_step", "max_zoom_factor"], camera)
	for kind: String in ["land", "river", "cultivable"]:
		var color: Variant = raw["terrain"].get(kind)
		if _valid_color(color):
			terrain[kind] = Color(color)
		else:
			errors.append("data/ui/map.json.terrain.%s: invalid color" % kind)
	for id: StringName in building_ids:
		var entry: Variant = raw["buildings"].get(String(id))
		var label: String = Strings.building_label(String(id))
		if entry is not Dictionary or not _valid_color(entry.get("color")) or label.is_empty():
			errors.append("data/ui/map.json.buildings.%s: expected color and label in Strings" % id)
			continue
		colors[id] = Color(entry["color"])
		labels[id] = label


func _valid_color(value: Variant) -> bool:
	return value is String and Color.html_is_valid(value)


func building_unavailable_reason(reason: StringName) -> String:
	return "" if reason == &"" else Strings.command_result(false, reason)


func _load_numbers(raw: Variant, keys: Array[String], target: Dictionary[String, float]) -> void:
	for key: String in keys:
		var value: Variant = raw.get(key) if raw is Dictionary else null
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) <= 0.0 \
				or (key in ["zoom_step", "max_zoom_factor"] and float(value) <= 1.0) \
				or (key == "font_size" and float(value) != floor(float(value))):
			errors.append("data/ui/map.json.%s: invalid positive value" % key)
		else:
			target[key] = float(value)
