extends GutTest

const FIXTURE_ROOT: String = "user://issue_2_invalid_data"

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
