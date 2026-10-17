class_name SaveSettings
extends RefCounted

# Autosave numbers (issue #57, approved by Cristian on 2026-10-13). They are not economy, so they stay out of the
# catalog and of Params, like the splash timings.
const PATH: String = "res://data/game/save.json"
const KEYS: Array[String] = ["autosave_interval_seconds", "autosave_slots"]

var autosave_interval_seconds: int = 0
var autosave_slots: int = 0
var errors: Array[String] = []


func load_data() -> void:
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(PATH)) != OK:
		errors.assign(["data/game/save.json: invalid JSON"])
		return
	validate(json.data)


func validate(raw: Variant) -> void:
	errors.clear()
	if raw is not Dictionary:
		errors.append("data/game/save.json: expected an object")
		return
	var values: Dictionary[String, int] = {}
	for key: String in KEYS:
		var value: Variant = raw.get(key)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or float(value) != floorf(float(value)) or float(value) < 1.0:
			errors.append("data/game/save.json.%s: expected a whole number of at least 1" % key)
		else:
			values[key] = int(value)
	if not errors.is_empty():
		return
	autosave_interval_seconds = values["autosave_interval_seconds"]
	autosave_slots = values["autosave_slots"]
