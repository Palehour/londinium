extends GutTest


func test_real_presentation_is_complete_and_distinct() -> void:
	var ids: Array[StringName] = []
	ids.assign(DataLoader.new().load_all().catalog.buildings.keys())
	var presentation: MapPresentation = MapPresentation.new()
	presentation.load_data(ids)
	assert_true(presentation.errors.is_empty(), str(presentation.errors))
	var seen: Array[Color] = []
	var labels: Array[String] = []
	for id: StringName in ids:
		assert_eq(presentation.labels[id], Strings.building_label(String(id)))
		assert_false(presentation.colors[id] in seen)
		assert_false(presentation.labels[id] in labels)
		seen.append(presentation.colors[id])
		labels.append(presentation.labels[id])
	assert_ne(presentation.terrain["river"], presentation.terrain["cultivable"])
	assert_ne(presentation.terrain["land"], presentation.terrain["cultivable"])


func test_missing_labels_and_invalid_colors_fail_cleanly() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/map.json"))
	raw["terrain"]["land"] = "not a color"
	raw["buildings"]["mill"].erase("color")
	var presentation: MapPresentation = MapPresentation.new()
	presentation.validate(raw, [&"mill", &"unknown"])
	assert_eq(presentation.errors.size(), 3)
	presentation.validate([], [])
	assert_eq(presentation.errors.size(), 1)


func test_startup_data_is_required_and_rejects_invalid_values() -> void:
	var documents: Dictionary[String, Dictionary] = {}
	for folder: String in ["economy", "roles", "maps"]:
		for file_name: String in DirAccess.open("res://data/" + folder).get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
	for field: String in ["money", "population", "seed"]:
		for value: Variant in [-1, 1.5, INF, NAN, "20"]:
			var invalid: Dictionary[String, Dictionary] = documents.duplicate(true)
			invalid["economy/startup.json"][field] = value
			assert_false(DataLoader.new().load_documents(invalid).is_ok(), "%s: %s" % [field, value])
		var missing: Dictionary[String, Dictionary] = documents.duplicate(true)
		missing["economy/startup.json"].erase(field)
		assert_false(DataLoader.new().load_documents(missing).is_ok())
	documents.erase("economy/startup.json")
	assert_false(DataLoader.new().load_documents(documents).is_ok())


func test_building_labels_resolve_by_id_and_reject_unknown_ids() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/map.json"))
	var presentation: MapPresentation = MapPresentation.new()
	presentation.validate(raw, [&"mill"])
	assert_eq(presentation.labels[&"mill"], "Molino")
	raw["buildings"]["unknown"] = {"color": "#123456"}
	presentation.validate(raw, [&"unknown"])
	assert_eq(presentation.errors.size(), 1)
	assert_false(presentation.labels.has(&"unknown"))
	assert_eq(Strings.building_label("unknown"), "")
	for entry: Dictionary in raw["buildings"].values():
		assert_eq(entry.keys(), ["color"])


func test_invalid_startup_role_modifiers_are_rejected() -> void:
	var documents: Dictionary[String, Dictionary] = {}
	for folder: String in ["economy", "roles", "maps"]:
		for file_name: String in DirAccess.open("res://data/" + folder).get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
	for key: String in ["startup.money", "startup.population", "startup.seed"]:
		for value: float in [-1.0, NAN]:
			var invalid: Dictionary[String, Dictionary] = documents.duplicate(true)
			invalid["roles/neutral_administrator.json"]["modifiers"] = [{"key": key, "op": "set", "value": value}]
			assert_false(DataLoader.new().load_documents(invalid).is_ok(), key)
	for key: String in ["startup.population", "startup.seed"]:
		var invalid: Dictionary[String, Dictionary] = documents.duplicate(true)
		invalid["roles/neutral_administrator.json"]["modifiers"] = [{"key": key, "op": "set", "value": 1.5}]
		assert_false(DataLoader.new().load_documents(invalid).is_ok(), key)


func test_ui_settings_are_validated_and_keep_existing_defaults() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/map.json"))
	var presentation: MapPresentation = MapPresentation.new()
	presentation.validate(raw, [&"mill"])
	assert_true(presentation.errors.is_empty())
	assert_eq(presentation.camera["pan_speed"], 500.0)
	assert_eq(presentation.camera["max_zoom_factor"], 4.0)
	assert_eq(presentation.layout["cell_size"], 112.0)
	for section: String in ["layout", "camera"]:
		for key: String in raw[section]:
			for value: Variant in [NAN, 0, "invalid"]:
				var invalid: Dictionary = raw.duplicate(true)
				invalid[section][key] = value
				presentation.validate(invalid, [&"mill"])
				assert_eq(presentation.errors.size(), 1, key)
	for key: String in ["header", "label", "selection"]:
		var invalid: Dictionary = raw.duplicate(true)
		invalid["colors"][key] = "invalid"
		presentation.validate(invalid, [&"mill"])
		assert_eq(presentation.errors.size(), 1, key)
