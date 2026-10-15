class_name DataLayers
extends RefCounted

var errors: Array[String] = []
var conflicts: Array[Dictionary] = []
var _owners: Dictionary[String, String] = {}


func load_layers(base: Dictionary[String, Dictionary], config: Dictionary, era: String, preset_definitions: Dictionary = {}) -> DataLoadResult:
	errors.clear()
	conflicts.clear()
	_owners.clear()
	var documents: Dictionary[String, Dictionary] = base.duplicate(true)
	var result: DataLoadResult = _validate(documents, era, "base")
	var root: String = config.get("mods_root", "user://mods")
	var order: Array[String] = []
	if not config.has("mods"):
		order = mod_order(root)
	if config.has("mods"):
		order.clear()
		for name: Variant in config["mods"]:
			if name is not String or not _safe_name(name) or order.has(name):
				errors.append("mods: invalid or duplicate name '%s'" % str(name))
			else:
				order.append(name)
	for name: String in order:
		var overlay: Dictionary[String, Dictionary] = {}
		_read_tree(root.path_join(name).path_join("data"), "", overlay)
		for path: String in overlay:
			var merged: Dictionary = documents.get(path, {}).duplicate(true)
			_merge(merged, overlay[path], path, name)
			documents[path] = merged
		result = _validate(documents, era, "mod " + name)
		if not errors.is_empty():
			break
	var preset_id: String = config.get("preset", "normal")
	var presets: Dictionary = read_object("res://data/difficulty/presets.json") if preset_definitions.is_empty() else preset_definitions
	if not presets.has(preset_id):
		errors.append("preset: unknown id '%s'" % preset_id)
	elif errors.is_empty():
		_apply_preset(documents, presets[preset_id])
		result = _validate(documents, era, "preset " + preset_id, true)
	if errors.is_empty():
		_apply_knobs(documents, config.get("knobs", {}))
		result = _validate(documents, era, "knobs", true)
	result.errors.assign(errors)
	result.conflicts.assign(conflicts)
	result.configuration = {"preset": preset_id, "knobs": config.get("knobs", {}).duplicate(true), "mods": order.duplicate()}
	if not errors.is_empty():
		result.catalog = null
	return result


func _validate(documents: Dictionary[String, Dictionary], era: String, source: String, layered_money: bool = false) -> DataLoadResult:
	var loader: DataLoader = DataLoader.new()
	loader._layered_money = layered_money
	var result: DataLoadResult = loader.load_documents(documents, era)
	for message: String in result.errors:
		errors.append(source + ": " + message)
	return result


func mod_order(root: String = "user://mods") -> Array[String]:
	var order: Array[String] = []
	var directory: DirAccess = DirAccess.open(root)
	if directory == null:
		return order
	var path: String = root.path_join("load_order.json")
	if FileAccess.file_exists(path):
		var json: JSON = JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK or json.data is not Array:
			errors.append(path + ": expected an array of mod names")
			return order
		for name: Variant in json.data:
			if name is not String or not _safe_name(name) or order.has(name) or not directory.dir_exists(name):
				errors.append(path + ": invalid, duplicate or missing mod '%s'" % str(name))
			else:
				order.append(name)
	else:
		for name: String in directory.get_directories():
			if _safe_name(name):
				order.append(name)
		order.sort()
	return order


func _safe_name(name: String) -> bool:
	return not name.is_empty() and name not in [".", ".."] and name == name.get_file() and not ":" in name and not "\\" in name


func read_object(path: String) -> Dictionary:
	var json: JSON = JSON.new()
	if not FileAccess.file_exists(path) or json.parse(FileAccess.get_file_as_string(path)) != OK or json.data is not Dictionary:
		errors.append(path + ": expected a JSON object")
		return {}
	return json.data


func _read_tree(root: String, relative: String, documents: Dictionary[String, Dictionary]) -> void:
	var directory: DirAccess = DirAccess.open(root.path_join(relative))
	if directory == null:
		errors.append(root.path_join(relative) + ": cannot open mod data directory")
		return
	var files: PackedStringArray = directory.get_files()
	files.sort()
	for file: String in files:
		if not file.ends_with(".json"):
			errors.append(root.path_join(relative).path_join(file) + ": only JSON data is supported")
			continue
		var path: String = relative.path_join(file)
		documents[path] = read_object(root.path_join(path))
	var folders: PackedStringArray = directory.get_directories()
	folders.sort()
	for folder: String in folders:
		if directory.is_link(folder):
			errors.append(root.path_join(relative).path_join(folder) + ": linked folders are unsupported")
		else:
			_read_tree(root, relative.path_join(folder), documents)


func _merge(target: Dictionary, overlay: Dictionary, path: String, source: String) -> void:
	var keys: Array = overlay.keys()
	keys.sort()
	for key: String in keys:
		var location: String = path + "." + key
		if overlay[key] is Dictionary:
			if target.get(key) is not Dictionary:
				target[key] = {}
			_merge(target[key], overlay[key], location, source)
		else:
			if _owners.has(location):
				conflicts.append({"key": location, "previous": _owners[location], "winner": source})
			_owners[location] = source
			target[key] = overlay[key].duplicate(true) if overlay[key] is Array or overlay[key] is Dictionary else overlay[key]


func _apply_preset(documents: Dictionary[String, Dictionary], preset: Variant) -> void:
	if preset is not Dictionary or preset.get("modifiers") is not Array:
		errors.append("preset: expected an object with a modifiers array")
		return
	for raw: Variant in preset["modifiers"]:
		if raw is not Dictionary or raw.get("key") is not String:
			errors.append("preset: expected a modifier with a string key")
			continue
		var modifier: Dictionary = raw
		var key: String = modifier.get("key", "")
		var parent: Dictionary = _parent(documents, key)
		var leaf: String = key.get_slice(".", key.get_slice_count(".") - 1)
		if parent.is_empty() or not parent.has(leaf) or typeof(parent[leaf]) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("preset: unknown or nonnumeric key '" + key + "'")
			continue
		var operand: Variant = modifier.get("value")
		if operand is not float and operand is not int:
			errors.append("preset: expected numeric value for '" + key + "'")
			continue
		var value: float = float(parent[leaf])
		match modifier.get("op", ""):
			"mul": value *= float(operand)
			"add": value += float(operand)
			_:
				errors.append("preset: expected add or mul for '" + key + "'")
				continue
		if not is_finite(value):
			errors.append("preset: nonfinite value for '" + key + "'")
			continue
		# Whole-second timers need an integer after relative scaling (5/3 and 2/3).
		parent[leaf] = roundi(value) if key.ends_with(".duration_seconds") else value


func _parent(documents: Dictionary[String, Dictionary], key: String) -> Dictionary:
	var parts: PackedStringArray = key.split(".")
	if parts.size() < 2:
		return {}
	var parent: Dictionary = documents.get("economy/" + parts[0] + ".json", {})
	for index: int in range(1, parts.size() - 1):
		if parent.get(parts[index]) is not Dictionary:
			return {}
		parent = parent[parts[index]]
	return parent


func _apply_knobs(documents: Dictionary[String, Dictionary], knobs: Dictionary) -> void:
	var definitions: Dictionary = read_object("res://data/difficulty/knobs.json")
	for name: String in knobs:
		if not definitions.has(name):
			errors.append("knobs: unknown key '" + name + "'")
			continue
		var definition: Dictionary = definitions[name]
		var value: Variant = knobs[name]
		if definition.get("boolean", false):
			if value is not bool:
				errors.append("knobs: %s must be boolean" % name)
				continue
		elif (value is not int and value is not float) or not is_finite(float(value)):
			errors.append("knobs: %s must be finite numeric" % name)
			continue
		elif value < definition["min"] or value > definition["max"] or not is_equal_approx(
				(float(value) - float(definition["min"])) / float(definition["step"]),
				round((float(value) - float(definition["min"])) / float(definition["step"]))):
			errors.append("knobs: %s outside range [%s, %s] or step %s" % [name, definition["min"], definition["max"], definition["step"]])
			continue
		for key: String in definition["keys"]:
			var parent: Dictionary = _parent(documents, key)
			parent[key.get_slice(".", key.get_slice_count(".") - 1)] = value
		if name == "volatility":
			var market: Dictionary = documents["economy/market.json"]
			for grain: String in market:
				var settings: Dictionary = market[grain]
				if not settings.has("max_step"):
					continue
				settings["max_step"] = roundi(float(settings["max_step"]) * float(value))
				settings["max_price"] = int(settings["base_price"]) + roundi(float(settings["max_price"] - settings["base_price"]) * float(value))
