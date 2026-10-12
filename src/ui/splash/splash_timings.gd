class_name SplashTimings
extends RefCounted

const PATH: String = "res://data/ui/splash.json"
const KEYS: Array[String] = ["fade_seconds", "fallback_seconds", "watchdog_seconds"]

var fade_seconds: float = 0.0
var fallback_seconds: float = 0.0
var watchdog_seconds: float = 0.0
var errors: Array[String] = []


func load_data() -> void:
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(PATH)) != OK:
		errors.assign(["data/ui/splash.json: invalid JSON"])
		return
	validate(json.data)


func validate(raw: Variant) -> void:
	errors.clear()
	if raw is not Dictionary:
		errors.append("data/ui/splash.json: expected an object")
		return
	var values: Dictionary[String, float] = {}
	for key: String in KEYS:
		var value: Variant = raw.get(key)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) <= 0.0:
			errors.append("data/ui/splash.json.%s: invalid positive value" % key)
		else:
			values[key] = float(value)
	if not errors.is_empty():
		return
	fade_seconds = values["fade_seconds"]
	fallback_seconds = values["fallback_seconds"]
	watchdog_seconds = values["watchdog_seconds"]
