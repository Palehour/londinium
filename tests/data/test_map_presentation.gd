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
		assert_false(presentation.colors[id] in seen)
		assert_false(presentation.labels[id] in labels)
		seen.append(presentation.colors[id])
		labels.append(presentation.labels[id])
	assert_ne(presentation.terrain["river"], presentation.terrain["cultivable"])
	assert_ne(presentation.terrain["land"], presentation.terrain["cultivable"])


func test_missing_labels_and_invalid_colors_fail_cleanly() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/map.json"))
	raw["terrain"]["land"] = "not a color"
	raw["buildings"]["mill"]["label"] = ""
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
	for field: String in ["money", "population"]:
		for value: Variant in [-1, 1.5, INF, "20"]:
			var invalid: Dictionary[String, Dictionary] = documents.duplicate(true)
			invalid["economy/startup.json"][field] = value
			assert_false(DataLoader.new().load_documents(invalid).is_ok(), "%s: %s" % [field, value])
		var missing: Dictionary[String, Dictionary] = documents.duplicate(true)
		missing["economy/startup.json"].erase(field)
		assert_false(DataLoader.new().load_documents(missing).is_ok())
	documents.erase("economy/startup.json")
	assert_false(DataLoader.new().load_documents(documents).is_ok())
