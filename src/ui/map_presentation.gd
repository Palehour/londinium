class_name MapPresentation
extends RefCounted

var terrain: Dictionary[String, Color] = {}
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
	colors.clear()
	labels.clear()
	if raw is not Dictionary or raw.get("terrain") is not Dictionary or raw.get("buildings") is not Dictionary:
		errors.append("data/ui/map.json: expected terrain and buildings objects")
		return
	for kind: String in ["land", "river", "cultivable"]:
		var color: Variant = raw["terrain"].get(kind)
		if _valid_color(color):
			terrain[kind] = Color(color)
		else:
			errors.append("data/ui/map.json.terrain.%s: invalid color" % kind)
	for id: StringName in building_ids:
		var entry: Variant = raw["buildings"].get(String(id))
		if entry is not Dictionary or not _valid_color(entry.get("color")) or entry.get("label") is not String or entry["label"].strip_edges().is_empty():
			errors.append("data/ui/map.json.buildings.%s: expected color and nonempty label" % id)
			continue
		colors[id] = Color(entry["color"])
		labels[id] = entry["label"]


func _valid_color(value: Variant) -> bool:
	return value is String and Color.html_is_valid(value)
