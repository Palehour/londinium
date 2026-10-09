extends GutTest

const FIXTURE_ROOT: String = "user://issue_2_invalid_data"


func test_defeat_parameters_are_required_and_validate_ranges() -> void:
	for field: String in ["grace_seconds", "hunger.smoothing", "depopulation.duration_seconds"]:
		before_each()
		var parts: PackedStringArray = field.split(".")
		var section: Dictionary = _documents["economy/defeat.json"]
		if parts.size() == 2:
			section = section[parts[0]]
		section.erase(parts[-1])
		_assert_invalid(parts[-1] + ": missing field")
	var invalid: Dictionary[String, Array] = {
		"grace_seconds": [-1.0, INF, NAN],
		"hunger.smoothing": [0.0, -0.1, 1.01, INF, NAN],
		"depopulation.duration_seconds": [0.0, -1.0, 1.5, INF, NAN],
	}
	for field: String in invalid:
		for value: float in invalid[field]:
			before_each()
			var parts: PackedStringArray = field.split(".")
			var section: Dictionary = _documents["economy/defeat.json"]
			if parts.size() == 2:
				section = section[parts[0]]
			section[parts[-1]] = value
			_assert_invalid(parts[-1] + ":")
	before_each()
	_documents["economy/defeat.json"]["grace_seconds"] = 0
	_documents["economy/defeat.json"]["hunger"]["smoothing"] = 1
	assert_true(DataLoader.new().load_documents(_documents).is_ok())

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps"]:
		var dir: DirAccess = DirAccess.open("res://data/" + folder)
		for file_name: String in dir.get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))


func test_missing_file_has_no_partial_catalog() -> void:
	_documents.erase("economy/population.json")
	_assert_invalid("economy/population.json: missing file")


func test_depopulation_defeat_fraction_cannot_exceed_warning_fraction() -> void:
	_documents["economy/defeat.json"]["depopulation"]["defeat_fraction"] = 0.75
	_assert_invalid("defeat.depopulation.defeat_fraction must be <= defeat.depopulation.warning_fraction")
	_documents["economy/defeat.json"]["depopulation"]["defeat_fraction"] = 0.5
	assert_true(DataLoader.new().load_documents(_documents).is_ok(), "Equal thresholds are valid")


func test_role_invalid_final_parameter_values_fail_cleanly_during_load() -> void:
	var invalid: Dictionary[String, float] = {
		"defeat.hunger.threshold": 2.0,
		"defeat.depopulation.warning_fraction": -0.1,
		"defeat.depopulation.defeat_fraction": 1.1,
		"defeat.depopulation.minimum_population": 1.5,
		"defeat.bankruptcy.threshold": -1.0,
		"defeat.bankruptcy.duration_seconds": 0.0,
		"defeat.hunger.duration_seconds": 1.5,
		"defeat.depopulation.duration_seconds": -1.0,
		"defeat.hunger.smoothing": 0.0,
		"defeat.grace_seconds": -1.0,
		"population.satisfaction.smoothing_per_second": 0.0,
	}
	for key: String in invalid:
		before_each()
		_set_modifier({"key": key, "op": "set", "value": invalid[key]})
		_assert_invalid("roles/neutral_administrator.json.modifiers: Params: invalid range for '%s'" % key)


func test_role_inverted_depopulation_thresholds_fail_cleanly_during_load() -> void:
	for key: String in ["defeat.depopulation.defeat_fraction", "defeat.depopulation.warning_fraction"]:
		before_each()
		_set_modifier({"key": key, "op": "set", "value": 0.75 if key.ends_with("defeat_fraction") else 0.1})
		_assert_invalid("roles/neutral_administrator.json.modifiers: Params: defeat.depopulation.defeat_fraction must be <= defeat.depopulation.warning_fraction")


func test_role_validation_uses_final_values_instead_of_intermediate_modifiers() -> void:
	_documents["roles/neutral_administrator.json"]["modifiers"] = [
		{"key": "defeat.hunger.threshold", "op": "set", "value": 2.0},
		{"key": "defeat.hunger.threshold", "op": "set", "value": 0.5},
		{"key": "defeat.depopulation.defeat_fraction", "op": "set", "value": 0.75},
		{"key": "defeat.depopulation.warning_fraction", "op": "set", "value": 0.75},
	]
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	if result.is_ok():
		var params: Params = Params.new(result.catalog, result.catalog.roles[&"neutral_administrator"])
		assert_eq(params.get_value(&"defeat.hunger.threshold"), 0.5)
		assert_eq(params.get_value(&"defeat.depopulation.defeat_fraction"), 0.75)


func test_missing_field_identifies_file_and_field() -> void:
	_documents["economy/buildings.json"]["bakery"].erase("jobs")
	_assert_invalid("economy/buildings.json.bakery.jobs: missing field")


func test_wrong_numeric_type_is_readable() -> void:
	_documents["economy/population.json"]["growth"]["immigration_threshold"] = "high"
	_assert_invalid("population.json.growth.immigration_threshold: expected")


func test_fractional_money_is_rejected() -> void:
	_documents["economy/buildings.json"]["bakery"]["cost"] = 12.5
	_assert_invalid("buildings.json.bakery.cost: invalid money")


func test_unknown_good_reference_is_rejected() -> void:
	_documents["economy/buildings.json"]["mill"]["recipe"]["inputs"] = {"unknown": 1}
	_assert_invalid("mill.recipe.inputs.unknown: unknown good")


func test_malformed_recipe_is_rejected() -> void:
	_documents["economy/buildings.json"]["mill"]["recipe"] = []
	_assert_invalid("mill.recipe: expected an object")


func test_invalid_tags_are_rejected() -> void:
	_documents["economy/buildings.json"]["mill"]["tags"] = [false]
	_assert_invalid("mill.tags: expected nonempty strings")


func test_housing_tag_works_with_a_different_building_id() -> void:
	var buildings: Dictionary = _documents["economy/buildings.json"]
	buildings["worker_housing"] = buildings["housing"]
	buildings.erase("housing")
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	if result.is_ok():
		assert_null(result.catalog.buildings[&"worker_housing"].recipe)
		assert_true(result.catalog.base_values.has(&"building.worker_housing.capacity"))


func test_housing_id_without_housing_tag_loads_as_a_producer() -> void:
	_documents["economy/buildings.json"]["housing"] = \
		_documents["economy/buildings.json"]["bakery"].duplicate(true)
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	if result.is_ok():
		assert_not_null(result.catalog.buildings[&"housing"].recipe)
		assert_false(result.catalog.base_values.has(&"building.housing.capacity"))


func test_unknown_modifier_key_is_rejected() -> void:
	_set_modifier({"key": "unknown.key", "op": "mul", "value": 0.5})
	_assert_invalid("unknown key 'unknown.key'")


func test_unknown_modifier_operation_is_rejected() -> void:
	_set_modifier({"key": "market.wheat.base_price", "op": "divide", "value": 2})
	_assert_invalid("modifiers[0]: expected key string, op add|mul|set")


func test_modifier_missing_value_is_rejected() -> void:
	_set_modifier({"key": "market.wheat.base_price", "op": "mul"})
	_assert_invalid("modifiers[0].value: missing field")


func test_modifier_bad_value_is_rejected() -> void:
	_set_modifier({"key": "market.wheat.base_price", "op": "mul", "value": true})
	_assert_invalid("finite numeric value")


func test_valid_modifier_resolves_even_when_role_precedes_economy() -> void:
	_set_modifier({"key": "market.wheat.base_price", "op": "mul", "value": 2})
	var reordered: Dictionary[String, Dictionary] = {}
	reordered["roles/neutral_administrator.json"] = _documents["roles/neutral_administrator.json"]
	reordered.merge(_documents)
	var result: DataLoadResult = DataLoader.new().load_documents(reordered)
	assert_true(result.is_ok(), str(result.errors))
	if result.is_ok():
		assert_eq(result.catalog.roles[&"neutral_administrator"].modifiers.size(), 1)


func test_out_of_bounds_map_cell_is_rejected() -> void:
	_documents["maps/whitechapel_1850s.json"]["river_cells"] = [[999, 0]]
	_assert_invalid("river_cells: out of bounds")


func test_fractional_map_cell_is_rejected() -> void:
	_documents["maps/whitechapel_1850s.json"]["river_cells"] = [[0.5, 0]]
	_assert_invalid("river_cells.x: invalid integer")


func test_overlapping_map_cells_are_rejected() -> void:
	_documents["maps/whitechapel_1850s.json"]["cultivable_cells"] = [[0, 7]]
	_assert_invalid("cultivable_cells: out of bounds or duplicate")


func test_malformed_map_coordinates_are_rejected() -> void:
	_documents["maps/whitechapel_1850s.json"]["river_cells"] = [[0]]
	_assert_invalid("river_cells: expected [x, y]")


func test_nonfinite_number_is_rejected() -> void:
	_documents["economy/market.json"]["wheat"]["base_price"] = INF
	_assert_invalid("base_price: expected a finite money")


func test_money_outside_int64_is_rejected() -> void:
	_documents["economy/market.json"]["wheat"]["base_price"] = 1e30
	_assert_invalid("base_price: invalid money")


func test_unknown_field_is_not_silently_ignored() -> void:
	_documents["economy/market.json"]["wheat"]["typo"] = 1
	_assert_invalid("market.json.wheat.typo: unknown field")


func test_invalid_json_reports_file_and_line() -> void:
	var result: DataLoadResult = _load_file_fixture("{\n  \"wheat\": }")
	assert_false(result.is_ok())
	assert_null(result.catalog)
	assert_string_contains("\n".join(result.errors), "economy/goods.json:1:")


func test_json_root_must_be_an_object() -> void:
	var result: DataLoadResult = _load_file_fixture("[]")
	assert_false(result.is_ok())
	assert_string_contains("\n".join(result.errors), "economy/goods.json: expected an object")


func test_loader_can_be_reused_after_failure() -> void:
	var loader: DataLoader = DataLoader.new()
	assert_false(loader.load_documents({}).is_ok())
	assert_true(loader.load_documents(_documents).is_ok())


func _set_modifier(modifier: Dictionary) -> void:
	_documents["roles/neutral_administrator.json"]["modifiers"] = [modifier]


func _assert_invalid(message: String) -> void:
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_false(result.is_ok())
	assert_null(result.catalog, "Invalid data must not expose a partial catalog")
	assert_string_contains("\n".join(result.errors), message)


func _load_file_fixture(text: String) -> DataLoadResult:
	for folder: String in ["economy", "roles", "maps"]:
		DirAccess.make_dir_recursive_absolute(FIXTURE_ROOT.path_join(folder))
	var path: String = FIXTURE_ROOT.path_join("economy/goods.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var result: DataLoadResult = DataLoader.new().load_all(FIXTURE_ROOT)
	DirAccess.remove_absolute(path)
	for folder: String in ["economy", "roles", "maps"]:
		DirAccess.remove_absolute(FIXTURE_ROOT.path_join(folder))
	DirAccess.remove_absolute(FIXTURE_ROOT)
	return result


func test_hunger_multiplier_is_required_finite_and_at_least_one() -> void:
	before_each()
	_documents["economy/population.json"]["growth"].erase("hunger_emigration_multiplier")
	_assert_invalid("hunger_emigration_multiplier: missing field")
	for value: float in [0.99, -1.0, INF, NAN]:
		before_each()
		_documents["economy/population.json"]["growth"]["hunger_emigration_multiplier"] = value
		_assert_invalid("hunger_emigration_multiplier:")
	before_each()
	_documents["economy/population.json"]["growth"]["hunger_emigration_multiplier"] = 1.0
	assert_true(DataLoader.new().load_documents(_documents).is_ok())


func test_empty_city_lookahead_and_smoothing_are_validated_in_data() -> void:
	for value: float in [-1.0, INF, NAN]:
		before_each()
		_documents["economy/population.json"]["empty_city_bread_lookahead_seconds"] = value
		_assert_invalid("empty_city_bread_lookahead_seconds:")
	for value: float in [0.0, -0.1, 1.01, INF, NAN]:
		before_each()
		_documents["economy/population.json"]["satisfaction"]["smoothing_per_second"] = value
		_assert_invalid("smoothing_per_second:")
	before_each()
	_documents["economy/population.json"]["empty_city_bread_lookahead_seconds"] = 0
	_documents["economy/population.json"]["satisfaction"]["smoothing_per_second"] = 1.0
	assert_true(DataLoader.new().load_documents(_documents).is_ok())


func test_city_start_and_hunger_parameters_require_valid_data() -> void:
	for field: String in ["initial_bread", "growth.hunger_emigration_threshold", "growth.hunger_emigration_recovery"]:
		before_each()
		var parts: PackedStringArray = field.split(".")
		var section: Dictionary = _documents["economy/population.json"]
		if parts.size() == 2:
			section = section[parts[0]]
		section.erase(parts[-1])
		_assert_invalid(parts[-1] + ": missing field")
	var invalid: Dictionary[String, Array] = {
		"initial_bread": ["40", true, -1.0, 1.5, 1e30, INF, NAN],
		"growth.hunger_emigration_threshold": ["0.5", true, -0.01, 1.01, INF, NAN],
		"growth.hunger_emigration_recovery": ["0.75", true, -0.01, 1.01, INF, NAN],
	}
	for field: String in invalid:
		for value: Variant in invalid[field]:
			before_each()
			var section: Dictionary = _documents["economy/population.json"]
			var parts: PackedStringArray = field.split(".")
			if parts.size() == 2:
				section = section[parts[0]]
			section[parts[-1]] = value
			_assert_invalid(parts[-1] + ":")
	for threshold: float in [0.0, 1.0]:
		before_each()
		_documents["economy/population.json"]["initial_bread"] = 0
		_documents["economy/population.json"]["growth"]["hunger_emigration_threshold"] = threshold
		_documents["economy/population.json"]["growth"]["hunger_emigration_recovery"] = threshold
		assert_true(DataLoader.new().load_documents(_documents).is_ok())


func test_city_start_and_hunger_parameter_modifiers_validate_final_values() -> void:
	var invalid: Dictionary[String, Array] = {
		"population.initial_bread": [-1.0, 1.5, 1e30],
		"population.growth.hunger_emigration_threshold": [-0.1, 1.1],
		"population.growth.hunger_emigration_recovery": [-0.1, 1.1],
	}
	for key: String in invalid:
		for value: float in invalid[key]:
			before_each()
			_set_modifier({"key": key, "op": "set", "value": value})
			_assert_invalid("Params: invalid range for '%s'" % key)
	before_each()
	_documents["roles/neutral_administrator.json"]["modifiers"] = [
		{"key": "population.initial_bread", "op": "set", "value": 0},
		{"key": "population.growth.hunger_emigration_threshold", "op": "set", "value": 1},
		{"key": "population.growth.hunger_emigration_recovery", "op": "set", "value": 1},
	]
	var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(loaded.is_ok(), str(loaded.errors))
	if loaded.is_ok():
		var params: Params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
		assert_eq(params.get_value(&"population.initial_bread"), 0.0)
		assert_eq(params.get_value(&"population.growth.hunger_emigration_threshold"), 1.0)


func test_hunger_recovery_relation_rejects_base_and_modified_inversions() -> void:
	_documents["economy/population.json"]["growth"]["hunger_emigration_recovery"] = 0.4
	_assert_invalid("hunger_emigration_recovery must be >= population.growth.hunger_emigration_threshold")
	for field: String in ["threshold", "recovery"]:
		before_each()
		_set_modifier({"key": "population.growth.hunger_emigration_" + field,
			"op": "set", "value": 0.8 if field == "threshold" else 0.5})
		_assert_invalid("after role modifiers")


func test_hunger_relation_accepts_final_modifiers_and_equal_boundaries() -> void:
	for boundary: float in [0.0, 1.0]:
		before_each()
		_documents["roles/neutral_administrator.json"]["modifiers"] = [
			{"key": "population.growth.hunger_emigration_threshold", "op": "set", "value": 2},
			{"key": "population.growth.hunger_emigration_threshold", "op": "set", "value": boundary},
			{"key": "population.growth.hunger_emigration_recovery", "op": "set", "value": boundary},
		]
		var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
		assert_true(loaded.is_ok(), str(loaded.errors))
