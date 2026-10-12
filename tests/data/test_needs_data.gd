extends GutTest

# Loading and validation of the era's needs and classes (issue #86).

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian"]:
		for file_name: String in DirAccess.open("res://data/" + folder).get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))


func _errors() -> String:
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_false(result.is_ok())
	return "\n".join(result.errors)


func test_the_shipped_data_loads_the_worker_class() -> void:
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	assert_eq(result.catalog.categories, [&"sustento", &"comunidad"] as Array[StringName])
	var worker: ClassDef = result.catalog.classes[&"worker"]
	assert_eq(worker.housing_building, &"housing")
	assert_eq(worker.needs[0].good, &"bread")
	assert_eq(worker.needs[1].good, &"tea")
	assert_eq(result.catalog.base_values[&"needs.sustento.threshold"], 75.0)
	assert_eq(result.catalog.base_values[&"needs.comunidad.threshold"], 50.0)
	assert_eq(result.catalog.base_values[&"needs.housing_bonus_per_category"], 2)


func test_values_out_of_range_are_rejected() -> void:
	var cases: Array[Array] = [
		["eras/victorian/needs.json", ["categories", "sustento", "threshold"], 101],
		["eras/victorian/needs.json", ["categories", "sustento", "threshold"], -1],
		["eras/victorian/needs.json", ["housing_bonus_per_category"], -1],
		["eras/victorian/needs.json", ["housing_bonus_per_category"], 101],
		["eras/victorian/needs.json", ["housing_bonus_per_category"], 1.5],
		["eras/victorian/classes.json", ["worker", "housing_max_bonus"], -1],
		["eras/victorian/classes.json", ["worker", "housing_max_bonus"], 21],
		["eras/victorian/classes.json", ["worker", "housing_max_bonus"], 2.5],
		["eras/victorian/classes.json", ["worker", "needs", "bread", "value"], 101],
		["eras/victorian/classes.json", ["worker", "needs", "bread", "value"], -1],
	]
	for entry: Array in cases:
		before_each()
		var target: Dictionary = _documents[entry[0]]
		var path: Array = entry[1]
		for index: int in range(path.size() - 1):
			target = target[path[index]]
		target[path[path.size() - 1]] = entry[2]
		assert_false(DataLoader.new().load_documents(_documents).is_ok(), "%s = %s" % [path, entry[2]])


func test_an_unknown_category_good_or_building_is_rejected() -> void:
	_documents["eras/victorian/classes.json"]["worker"]["needs"]["bread"]["category"] = "abrigo"
	assert_string_contains(_errors(), "unknown category")
	before_each()
	_documents["eras/victorian/classes.json"]["worker"]["needs"]["gin"] = {
		"category": "sustento", "value": 10, "satisfaction_key": "population.tea.satisfaction_bonus"}
	assert_string_contains(_errors(), "unknown good")
	before_each()
	_documents["eras/victorian/classes.json"]["worker"]["housing_building"] = "nowhere"
	assert_string_contains(_errors(), "unknown building")


func test_a_housing_building_must_have_the_housing_tag_and_one_class() -> void:
	_documents["eras/victorian/classes.json"]["worker"]["housing_building"] = "mill"
	assert_string_contains(_errors(), "is not a housing building")
	before_each()
	_documents["eras/victorian/classes.json"]["twin"] = _documents["eras/victorian/classes.json"]["worker"].duplicate(true)
	assert_string_contains(_errors(), "already belongs to another class")


func test_a_satisfaction_key_must_name_a_numeric_parameter() -> void:
	_documents["eras/victorian/classes.json"]["worker"]["needs"]["bread"]["satisfaction_key"] = "population.nowhere"
	assert_string_contains(_errors(), "satisfaction_key")
	before_each()
	_documents["eras/victorian/classes.json"]["worker"]["needs"]["bread"]["satisfaction_key"] = "startup.tea_imports_enabled"
	assert_string_contains(_errors(), "satisfaction_key")


func test_missing_era_files_and_unknown_fields_are_rejected() -> void:
	_documents.erase("eras/victorian/classes.json")
	assert_string_contains(_errors(), "eras/victorian/classes.json: missing file")
	before_each()
	_documents["eras/victorian/needs.json"]["surplus"] = 1
	assert_string_contains(_errors(), "unknown field")


func test_a_role_may_not_target_an_unknown_need_key() -> void:
	_documents["roles/neutral_administrator.json"]["modifiers"] = [
		{"key": "needs.abrigo.threshold", "op": "set", "value": 10}]
	assert_string_contains(_errors(), "unknown key 'needs.abrigo.threshold'")


func test_ranges_match_by_shape_so_a_new_era_needs_no_edit() -> void:
	assert_true(ParameterRanges.is_valid(&"needs.abrigo.threshold", 60.0))
	assert_false(ParameterRanges.is_valid(&"needs.abrigo.threshold", 100.5))
	assert_true(ParameterRanges.is_valid(&"class.artisan.housing_max_bonus", 4.0))
	assert_false(ParameterRanges.is_valid(&"class.artisan.housing_max_bonus", 4.5))
	assert_true(ParameterRanges.is_valid(&"class.artisan.housing_max_bonus", 20.0))
	assert_false(ParameterRanges.is_valid(&"class.artisan.housing_max_bonus", 21.0))
	assert_true(ParameterRanges.is_valid(&"class.artisan.need.beer.value", 100.0))
	assert_false(ParameterRanges.is_valid(&"class.artisan.need.beer.value", -0.1))


func test_another_era_loads_from_its_own_folder_without_code_changes() -> void:
	var era_documents: Dictionary[String, Dictionary] = {}
	for path: String in _documents:
		era_documents[path.replace("eras/victorian/", "eras/roman/")] = _documents[path]
	var result: DataLoadResult = DataLoader.new().load_documents(era_documents, "roman")
	assert_true(result.is_ok(), str(result.errors))
	assert_false(DataLoader.new().load_documents(era_documents).is_ok(), "The default era finds no files")
