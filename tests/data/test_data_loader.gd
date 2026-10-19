extends GutTest

const FIXTURE_ROOT: String = "user://issue_2_invalid_data"


func test_defeat_parameters_are_required_and_validate_ranges() -> void:
	for field: String in ["grace_seconds", "hunger.smoothing", "depopulation.duration_seconds",
			"depopulation.peak_decay_per_minute", "depopulation.stability_window_seconds"]:
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
		"depopulation.peak_decay_per_minute": [-0.01, 1.01, INF, NAN],
		"depopulation.stability_window_seconds": [0.0, -1.0, 1.5, INF, NAN],
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
	for folder: String in ["economy", "roles", "maps", "eras/victorian"]:
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


# Issue #118: a multiplier below 1 would turn a money sink into a discount, and free buildings are whole.
func test_money_sink_values_out_of_range_are_rejected() -> void:
	_documents["economy/economy.json"]["administration"]["max_multiplier"] = 0.5
	_assert_invalid("economy/economy.json.administration.max_multiplier: invalid number value 0.5")


func test_money_sink_free_buildings_must_be_whole() -> void:
	_documents["economy/economy.json"]["administration"]["free_buildings"] = 1.5
	_assert_invalid("economy/economy.json.administration.free_buildings: invalid integer value 1.5")


func test_free_copies_must_be_whole() -> void:
	_documents["economy/economy.json"]["construction_escalation"]["free_copies"] = 2.5
	_assert_invalid("economy/economy.json.construction_escalation.free_copies: invalid integer value 2.5")


func test_construction_escalation_cannot_be_negative() -> void:
	_documents["economy/economy.json"]["construction_escalation"]["per_building"] = -0.1
	_assert_invalid("economy/economy.json.construction_escalation.per_building: invalid number value -0.1")


func test_missing_field_identifies_file_and_field() -> void:
	_documents["economy/buildings.json"]["bakery"].erase("jobs")
	_assert_invalid("economy/buildings.json.bakery.jobs: missing field")


func test_wrong_numeric_type_is_readable() -> void:
	_documents["economy/population.json"]["growth"]["immigration_threshold"] = "high"
	_assert_invalid("population.json.growth.immigration_threshold: expected")


func test_fractional_money_is_rejected() -> void:
	_documents["economy/buildings.json"]["bakery"]["cost"] = 12.5
	_assert_invalid("buildings.json.bakery.cost: invalid money")


func test_negative_building_cost_is_rejected() -> void:
	_documents["economy/buildings.json"]["wharf"]["cost"] = -240
	_assert_invalid("buildings.json.wharf.cost: invalid money")


func test_tax_base_must_be_a_whole_non_negative_amount() -> void:
	_documents["economy/population.json"]["tax"]["base_per_employed_worker_per_minute"] = 10.5
	_assert_invalid("base_per_employed_worker_per_minute: invalid money")
	_documents["economy/population.json"]["tax"]["base_per_employed_worker_per_minute"] = -11
	_assert_invalid("base_per_employed_worker_per_minute: invalid money")


func test_negative_starting_money_is_rejected() -> void:
	_documents["economy/startup.json"]["money"] = -1000
	_assert_invalid("startup.json.money: invalid money")


func test_market_walk_parameters_are_validated() -> void:
	_documents["economy/market.json"]["wheat"]["max_step"] = 0
	_assert_invalid("wheat.max_step: invalid positive_integer value 0")
	_documents["economy/market.json"]["wheat"]["max_step"] = 1.5
	_assert_invalid("wheat.max_step: invalid positive_integer value 1.5")
	_documents["economy/market.json"]["wheat"]["max_step"] = 1
	_documents["economy/market.json"]["wheat"]["reversion"] = 1.5
	_assert_invalid("wheat.reversion: invalid fraction value 1.5")
	_documents["economy/market.json"]["wheat"]["reversion"] = -0.1
	_assert_invalid("wheat.reversion: invalid fraction value -0.1")


func test_market_walk_parameters_are_required() -> void:
	_documents["economy/market.json"]["wheat"].erase("max_step")
	_assert_invalid("max_step")
	_documents["economy/market.json"]["wheat"]["max_step"] = 1
	_documents["economy/market.json"]["wheat"].erase("reversion")
	_assert_invalid("reversion")


func test_unknown_good_reference_is_rejected() -> void:
	_documents["economy/buildings.json"]["mill"]["recipe"]["inputs"] = {"unknown": 1}
	_assert_invalid("mill.recipe.inputs.unknown: unknown good")


func test_malformed_recipe_is_rejected() -> void:
	_documents["economy/buildings.json"]["mill"]["recipe"] = []
	_assert_invalid("mill.recipe: expected an object")


func test_invalid_tags_are_rejected() -> void:
	_documents["economy/buildings.json"]["mill"]["tags"] = [false]
	_assert_invalid("mill.tags: expected nonempty strings")


func test_a_misspelled_tag_is_rejected() -> void:
	# A typo in basic_infrastructure would make housing escalate without warning (#118).
	_documents["economy/buildings.json"]["housing"]["tags"] = ["housing", "basic_infrastucture"]
	_assert_invalid("housing.tags: unknown tag basic_infrastucture")


func test_the_basic_infrastructure_tag_is_known() -> void:
	assert_true(BuildingCosts.BASIC_INFRASTRUCTURE_TAG in DataLoader.BUILDING_TAGS,
		"BuildingCosts reads a tag the loader accepts")


func test_housing_tag_works_with_a_different_building_id() -> void:
	var buildings: Dictionary = _documents["economy/buildings.json"]
	buildings["worker_housing"] = buildings["housing"]
	buildings.erase("housing")
	# The class that lives there follows the rename.
	_documents["eras/victorian/classes.json"]["worker"]["housing_building"] = "worker_housing"
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	if result.is_ok():
		assert_null(result.catalog.buildings[&"worker_housing"].recipe)
		assert_true(result.catalog.base_values.has(&"building.worker_housing.capacity"))


func test_housing_id_without_housing_tag_loads_as_a_producer() -> void:
	_documents["economy/buildings.json"]["housing"] = \
		_documents["economy/buildings.json"]["bakery"].duplicate(true)
	# A class still needs a real housing building to live in.
	_documents["economy/buildings.json"]["worker_housing"] = {"cost": 60, "upkeep_per_minute": 1,
		"wage_per_worker_per_minute": 0, "jobs": 0, "capacity": 20, "tags": ["housing"]}
	_documents["eras/victorian/classes.json"]["worker"]["housing_building"] = "worker_housing"
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


func test_negative_wheat_base_price_is_rejected_in_data() -> void:
	_documents["economy/market.json"]["wheat"]["base_price"] = -1
	_assert_invalid("base_price: invalid money value")


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
	for folder: String in ["economy", "roles", "maps", "eras/victorian"]:
		DirAccess.make_dir_recursive_absolute(FIXTURE_ROOT.path_join(folder))
	var path: String = FIXTURE_ROOT.path_join("economy/goods.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var result: DataLoadResult = DataLoader.new().load_all(FIXTURE_ROOT)
	DirAccess.remove_absolute(path)
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "eras"]:
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


func test_peak_decay_schema_and_final_modifier_validation() -> void:
	var key: String = "defeat.depopulation.peak_decay_per_minute"
	for invalid: Variant in ["0.01", null, true]:
		before_each()
		_documents["economy/defeat.json"]["depopulation"]["peak_decay_per_minute"] = invalid
		_assert_invalid("peak_decay_per_minute:")
	for boundary: float in [0.0, 1.0]:
		before_each()
		_documents["economy/defeat.json"]["depopulation"]["peak_decay_per_minute"] = boundary
		assert_true(DataLoader.new().load_documents(_documents).is_ok())
	for invalid: float in [-0.01, 1.01]:
		before_each()
		_set_modifier({"key": key, "op": "set", "value": invalid})
		_assert_invalid("Params: invalid range for '%s'" % key)
	before_each()
	_documents["roles/neutral_administrator.json"]["modifiers"] = [
		{"key": key, "op": "set", "value": 2.0},
		{"key": key, "op": "mul", "value": 0.25},
	]
	var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(loaded.is_ok(), str(loaded.errors))
	if loaded.is_ok():
		var params: Params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
		assert_eq(params.get_value(StringName(key)), 0.5)


func test_snap_epsilon_is_required_positive_finite_and_typed() -> void:
	_documents["economy/population.json"]["satisfaction"].erase("snap_epsilon")
	_assert_invalid("snap_epsilon")
	for invalid: Variant in ["0.01", null, true, 0.0, -0.01, INF, NAN]:
		before_each()
		_documents["economy/population.json"]["satisfaction"]["snap_epsilon"] = invalid
		_assert_invalid("snap_epsilon")
	for valid: float in [0.00000001, 0.01, 2.0]:
		before_each()
		_documents["economy/population.json"]["satisfaction"]["snap_epsilon"] = valid
		assert_true(DataLoader.new().load_documents(_documents).is_ok())
	for invalid: float in [0.0, -0.01, INF, NAN]:
		before_each()
		_set_modifier({"key": "population.satisfaction.snap_epsilon", "op": "set", "value": invalid})
		_assert_invalid("snap_epsilon" if is_finite(invalid) else "finite")


func test_coverage_snap_epsilon_is_required_positive_finite_and_typed() -> void:
	_documents["economy/population.json"].erase("hunger_coverage_snap_epsilon")
	_assert_invalid("snap_epsilon")
	for invalid: Variant in ["0.01", null, true, 0.0, -0.01, INF, NAN]:
		before_each()
		_documents["economy/population.json"]["hunger_coverage_snap_epsilon"] = invalid
		_assert_invalid("snap_epsilon")
	for valid: float in [0.00000001, 0.01, 2.0]:
		before_each()
		_documents["economy/population.json"]["hunger_coverage_snap_epsilon"] = valid
		assert_true(DataLoader.new().load_documents(_documents).is_ok())
	for invalid: float in [0.0, -0.01, INF, NAN]:
		before_each()
		_set_modifier({"key": "population.hunger_coverage_snap_epsilon", "op": "set", "value": invalid})
		_assert_invalid("snap_epsilon" if is_finite(invalid) else "finite")


func test_demolish_refund_parameters_are_required_and_validate_ranges() -> void:
	for field: String in ["refund_ratio", "refund_grace_seconds", "no_jobs_refund_ratio"]:
		before_each()
		_documents["economy/demolish.json"].erase(field)
		_assert_invalid(field + ": missing field")
	before_each()
	_documents.erase("economy/demolish.json")
	_assert_invalid("economy/demolish.json: missing file")
	for invalid: float in [-0.1, 1.5]:
		before_each()
		_documents["economy/demolish.json"]["refund_ratio"] = invalid
		_assert_invalid("demolish.json.refund_ratio: invalid fraction")
		before_each()
		_documents["economy/demolish.json"]["no_jobs_refund_ratio"] = invalid
		_assert_invalid("demolish.json.no_jobs_refund_ratio: invalid fraction")
	before_each()
	_documents["economy/demolish.json"]["refund_grace_seconds"] = -1
	_assert_invalid("demolish.json.refund_grace_seconds: invalid number")
	before_each()
	_set_modifier({"key": "demolish.refund_ratio", "op": "set", "value": 1.5})
	_assert_invalid("Params: invalid range for 'demolish.refund_ratio'")
	before_each()
	_set_modifier({"key": "demolish.no_jobs_refund_ratio", "op": "set", "value": 1.5})
	_assert_invalid("Params: invalid range for 'demolish.no_jobs_refund_ratio'")


# Issue #177 (D-083): a repair costs above 0, or it would be free, and at most a new wharf.
func test_repair_cost_ratio_is_required_and_above_0_and_at_most_1() -> void:
	before_each()
	_documents["economy/repair.json"].erase("wharf_cost_ratio")
	_assert_invalid("wharf_cost_ratio: missing field")
	before_each()
	_documents.erase("economy/repair.json")
	_assert_invalid("economy/repair.json: missing file")
	for invalid: float in [0.0, -0.1, 1.5]:
		before_each()
		_documents["economy/repair.json"]["wharf_cost_ratio"] = invalid
		_assert_invalid("repair.json.wharf_cost_ratio: invalid fraction")
		before_each()
		_set_modifier({"key": "repair.wharf_cost_ratio", "op": "set", "value": invalid})
		_assert_invalid("Params: invalid range for 'repair.wharf_cost_ratio'")
	for valid: float in [0.01, 1.0]:
		before_each()
		_documents["economy/repair.json"]["wharf_cost_ratio"] = valid
		assert_true(DataLoader.new().load_documents(_documents).is_ok(), str(valid))


func test_barley_and_unloading_parameters_are_required_and_validate_ranges() -> void:
	for field: String in ["base_price", "min_price", "max_price", "price_update_seconds", "max_step", "reversion",
			"storage_capacity", "decay_fraction_per_minute"]:
		before_each()
		_documents["economy/market.json"]["barley"].erase(field)
		_assert_invalid(field + ": missing field")
	before_each()
	_documents["economy/policy.json"]["unloading"].erase("default_barley_percent")
	_assert_invalid("default_barley_percent: missing field")
	for invalid: float in [-1.0, 101.0, 12.5]:
		before_each()
		_documents["economy/policy.json"]["unloading"]["default_barley_percent"] = invalid
		_assert_invalid("policy.json.unloading.default_barley_percent: invalid integer")
	for invalid: float in [INF, NAN]:
		before_each()
		_documents["economy/policy.json"]["unloading"]["default_barley_percent"] = invalid
		_assert_invalid("policy.json.unloading.default_barley_percent: expected a finite integer")
	for invalid: float in [-0.1, 1.5]:
		before_each()
		_documents["economy/market.json"]["barley"]["reversion"] = invalid
		_assert_invalid("market.json.barley.reversion: invalid fraction")
	before_each()
	_documents["economy/market.json"]["barley"]["storage_capacity"] = 10001
	_assert_invalid("market.json.barley.storage_capacity: invalid integer")
	before_each()
	_set_modifier({"key": "policy.unloading.default_barley_percent", "op": "set", "value": 101})
	_assert_invalid("Params: invalid range for 'policy.unloading.default_barley_percent'")


# Issue #54: the notch of the on-screen split is data, a whole percent from 1 to 100 (0 would never move).
func test_the_unloading_step_is_required_and_validates_its_range() -> void:
	_documents["economy/policy.json"]["unloading"].erase("step_percent")
	_assert_invalid("step_percent: missing field")
	for invalid: float in [0.0, 101.0, 12.5]:
		before_each()
		_documents["economy/policy.json"]["unloading"]["step_percent"] = invalid
		_assert_invalid("policy.json.unloading.step_percent: invalid integer")
	before_each()
	_set_modifier({"key": "policy.unloading.step_percent", "op": "set", "value": 0})
	_assert_invalid("Params: invalid range for 'policy.unloading.step_percent'")


func test_stats_levels_are_required_and_validated() -> void:
	_documents.erase("economy/stats.json")
	_assert_invalid("economy/stats.json: missing file")
	for field: String in ["fine.span_seconds", "medium.bucket_seconds", "medium.span_seconds",
			"chapter.bucket_seconds", "causes.max_events"]:
		for value: float in [0.0, -1.0, 1.5, INF, NAN]:
			before_each()
			var parts: PackedStringArray = field.split(".")
			_documents["economy/stats.json"][parts[0]][parts[1]] = value
			_assert_invalid(parts[1] + ":")
	before_each()
	_documents["economy/stats.json"]["medium"]["span_seconds"] = 7205
	_assert_invalid("stats.medium.span_seconds must be a multiple of stats.medium.bucket_seconds")


# Cristian on 2026-10-15 (Mason's proposal, D-066): max_events 1000 to 100000, min_duration_seconds 0 to 30.
func test_cause_log_cap_and_duration_ranges() -> void:
	for invalid: float in [999.0, 100001.0, 1500.5]:
		before_each()
		_documents["economy/stats.json"]["causes"]["max_events"] = invalid
		_assert_invalid("max_events:")
	for invalid: float in [-1.0, 31.0, 2.5]:
		before_each()
		_documents["economy/stats.json"]["causes"]["min_duration_seconds"] = invalid
		_assert_invalid("min_duration_seconds:")
	before_each()
	_documents["economy/stats.json"]["causes"].erase("min_duration_seconds")
	_assert_invalid("min_duration_seconds: missing field")
	for valid: Array in [[1000, 0], [100000, 30]]:
		before_each()
		_documents["economy/stats.json"]["causes"]["max_events"] = valid[0]
		_documents["economy/stats.json"]["causes"]["min_duration_seconds"] = valid[1]
		var result: DataLoadResult = DataLoader.new().load_documents(_documents)
		assert_eq(result.errors, [] as Array[String], str(valid))


func test_map_layers_are_optional_and_loaded_when_present() -> void:
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	if not result.is_ok():
		return
	assert_true(result.catalog.maps[&"whitechapel_1850s"].dock_cells.is_empty())
	var strip: Dictionary = _documents["maps/riverside_strip.json"]
	var map: MapDef = result.catalog.maps[&"riverside_strip"]
	assert_eq(map.dock_cells.size(), strip["dock_cells"].size())
	assert_eq(map.road_cells.size(), strip["road_cells"].size())
	assert_eq(map.existing_cells.size(), strip["existing_cells"].size())
	assert_eq(map.terrain.size(), strip["terrain"]["riverbank"].size() + strip["terrain"]["marsh"].size())


func test_a_dock_basin_cannot_overlap_the_river() -> void:
	_documents["maps/whitechapel_1850s.json"]["dock_cells"] = [[0, 7]]
	_assert_invalid("dock_cells: out of bounds or duplicate cell")


func test_standing_buildings_cannot_stand_on_water() -> void:
	_documents["maps/whitechapel_1850s.json"]["existing_cells"] = [[1, 7]]
	_assert_invalid("existing_cells: out of bounds or duplicate cell")


# An anchor (with a building) or a named site of the 8x8, tagged as Chronicler asks (issue #152).
func _place(name: String, cell: Array, building: Variant = null,
		history: String = "[FACT] On the sheet.") -> Dictionary:
	var place: Dictionary = {"name": name, "cell": cell, "source": "NLS", "history": history}
	if building != null:
		place["building"] = building
	return place


# Issue #152 (option A, 2026-10-18): each anchor stands where its building can: on the river for a wharf, on a
# standing building otherwise, and dense housing only on a start cell (D-079).
func test_anchors_must_stand_where_their_building_can() -> void:
	var cases: Array[Array] = [
		[_place("Church", [1, 1], ""), "[1, 1] is not a standing building"],
		[_place("Wharf", [1, 1], "wharf"), "[1, 1] is not on the river"],
		[_place("House", [1, 1], "dense_housing"), "[1, 1] is not a dense housing start cell"],
		[_place("Mill", [1, 7], "windmill"), "unknown building windmill"],
		[_place("", [1, 7], "wharf"), "needs a name, a source and a history tag"],
		[_place("Wharf", [1, 7], "wharf", "On the sheet"), "needs a name, a source and a history tag"],
	]
	for entry: Array in cases:
		before_each()
		if entry[0]["building"] == "dense_housing":
			# A standing building, so only the missing start cell is wrong.
			_documents["maps/whitechapel_1850s.json"]["existing_cells"] = [[1, 1]]
		_documents["maps/whitechapel_1850s.json"]["anchors"] = [entry[0]]
		_assert_invalid(entry[1])
	before_each()
	_documents["maps/whitechapel_1850s.json"]["anchors"] = [_place("Wharf", [1, 7], "wharf")]
	_documents["maps/whitechapel_1850s.json"]["named_sites"] = [_place("Stairs", [2, 7])]
	_documents["maps/whitechapel_1850s.json"]["history_notes"] = ["[DEBATED] Undated water."]
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_eq(result.errors, [] as Array[String])
	if result.is_ok():
		var map: MapDef = result.catalog.maps[&"whitechapel_1850s"]
		assert_eq(map.anchors, {Vector2i(1, 7): &"wharf"} as Dictionary[Vector2i, StringName])
		assert_eq(map.named_sites, {Vector2i(2, 7): "Stairs"} as Dictionary[Vector2i, String])
	before_each()
	_documents["maps/whitechapel_1850s.json"]["history_notes"] = ["Undated water"]
	_assert_invalid("history_notes: expected notes that open with a history tag")


# The 8x8 with a standing building at (1,1) and a street at (1,0); every free cell but `house` styled as a yard.
func _period_map(house: Array = [2, 0]) -> Dictionary:
	var map: Dictionary = _documents["maps/whitechapel_1850s.json"]
	map["existing_cells"] = [[1, 1]]
	map["road_cells"] = [[1, 0]]
	var free: Array = []
	for y: int in range(7):
		for x: int in range(8):
			if [x, y] not in [[1, 1], [1, 0], house]:
				free.append([x, y])
	map["lot_styles"] = {"yard": free}
	return map


func _damaged_wharf(cell: Array, history: String = "[INVENTED] Damaged.") -> Dictionary:
	return _place("Damaged wharf", cell, null, history)


# Issue #176 (D-083): a period house is free land beside a street (D-079) with no lot style, a damaged wharf is on the
# river, and every other free cell has one lot style. What a repair costs is economy/repair.json's (#177).
func test_period_houses_damaged_wharves_and_lot_styles_stand_where_their_rule_says() -> void:
	before_each()
	var map: Dictionary = _period_map()
	map["period_houses"] = [_place("Period house", [2, 0], null, "[INVENTED] A house.")]
	map["damaged_wharves"] = [_damaged_wharf([2, 7])]
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_eq(result.errors, [] as Array[String])
	if result.is_ok():
		var loaded: MapDef = result.catalog.maps[&"whitechapel_1850s"]
		assert_eq(loaded.period_houses, [Vector2i(2, 0)] as Array[Vector2i])
		assert_true(loaded.anchors.is_empty(), "Only data: a period house is not an anchor yet")
		assert_eq(loaded.damaged_wharves, [Vector2i(2, 7)] as Array[Vector2i])
		assert_eq(loaded.lot_styles.size(), 53)
		assert_eq(loaded.lot_styles[Vector2i(0, 0)], &"yard")
	var cases: Array[Array] = [
		["period_houses", [_place("House", [1, 1], null, "[INVENTED] A house.")], "[1, 1] is not free land"],
		["period_houses", [_place("House", [2, 0])], ""],
		["period_houses", [_place("House", [2, 0], null, "A house")], "needs a name, a source and a history tag"],
		["damaged_wharves", [_damaged_wharf([2, 2])], "[2, 2] is not on the river"],
		["damaged_wharves", [_damaged_wharf([2, 7], "Damaged")], "needs a name, a source and a history tag"],
	]
	for entry: Array in cases:
		before_each()
		var house: Array = entry[1][0]["cell"] if entry[0] == "period_houses" else [2, 0]
		var broken: Dictionary = _period_map(house)
		if entry[0] == "damaged_wharves":
			broken["lot_styles"]["yard"].append([2, 0])
		broken[entry[0]] = entry[1]
		if entry[2].is_empty():
			assert_true(DataLoader.new().load_documents(_documents).is_ok(), "Any tag will do for a house")
		else:
			_assert_invalid(entry[2])
	before_each()
	_period_map([3, 3])["period_houses"] = [_place("House", [3, 3])]
	_assert_invalid("[3, 3] has no street on any side")
	before_each()
	_period_map()["period_houses"] = [_place("House", [2, 0])]
	_documents["maps/whitechapel_1850s.json"]["lot_styles"]["garden"] = [[2, 0]]
	_assert_invalid("lot_styles.garden: [2, 0] is not free land")
	before_each()
	_period_map([])["lot_styles"]["garden"] = [[2, 7]]
	_assert_invalid("lot_styles.garden: [2, 7] is not free land")
	before_each()
	_period_map([])["lot_styles"]["garden"] = [[0, 0]]
	_assert_invalid("lot_styles.garden: out of bounds or duplicate cell")
	before_each()
	_period_map([0, 0])
	_assert_invalid("lot_styles: [0, 0] has no lot style")
	before_each()
	_period_map()["lot_styles"] = [[0, 0]]
	_assert_invalid("lot_styles: expected an object of style to cells")


# Issue #180 (D-085): a period house starts with start_population people, a whole number of at least 0; none when the
# field is missing.
func test_a_period_house_starts_with_its_people() -> void:
	before_each()
	var map: Dictionary = _period_map()
	var house: Dictionary = _place("Period house", [2, 0], null, "[INVENTED] A house.")
	map["period_houses"] = [house]
	var missing: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_eq(missing.errors, [] as Array[String])
	if missing.is_ok():
		assert_eq(missing.catalog.maps[&"whitechapel_1850s"].period_house_population,
			{Vector2i(2, 0): 0} as Dictionary[Vector2i, int])
	house["start_population"] = 3
	var three: DataLoadResult = DataLoader.new().load_documents(_documents)
	if three.is_ok():
		assert_eq(three.catalog.maps[&"whitechapel_1850s"].period_house_population[Vector2i(2, 0)], 3)
	for value: Variant in [-1, 1.5, "none", INF]:
		house["start_population"] = value
		_assert_invalid("[2, 0] start_population must be a whole number of at least 0")


# Issue #180 (D-085): growth.served_categories is optional and names categories of the class's own needs.
func test_served_categories_name_categories_of_the_class() -> void:
	before_each()
	var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(loaded.is_ok(), str(loaded.errors))
	if loaded.is_ok():
		assert_eq(loaded.catalog.classes[&"worker"].served_categories, [&"sustento"] as Array[StringName])
		assert_eq(loaded.catalog.classes[&"artisan"].served_categories, [] as Array[StringName],
			"Without the field every house counts")
	var growth: Dictionary = _documents["eras/victorian/classes.json"]["worker"]["growth"]
	for value: Variant in [["lujo"], [1], "sustento"]:
		growth["served_categories"] = value
		_assert_invalid("worker.growth.served_categories:")


func test_road_cells_must_be_inside_the_map_and_unique() -> void:
	_documents["maps/whitechapel_1850s.json"]["road_cells"] = [[8, 0]]
	_assert_invalid("road_cells: out of bounds or duplicate cell")
	before_each()
	_documents["maps/whitechapel_1850s.json"]["road_cells"] = [[1, 1], [1, 1]]
	_assert_invalid("road_cells: out of bounds or duplicate cell")


func test_terrain_labels_are_known_on_dry_cells_and_one_per_cell() -> void:
	_documents["maps/whitechapel_1850s.json"]["terrain"] = {"swamp": [[1, 1]]}
	_assert_invalid("terrain.swamp: unknown terrain label")
	before_each()
	_documents["maps/whitechapel_1850s.json"]["terrain"] = {"riverbank": [[0, 7]]}
	_assert_invalid("terrain.riverbank: water or duplicate cell")
	before_each()
	_documents["maps/whitechapel_1850s.json"]["terrain"] = {"riverbank": [[1, 6]], "marsh": [[1, 6]]}
	_assert_invalid("terrain.marsh: water or duplicate cell")


# Issue #154 (D-079): dense housing starts only on a standing building with a street on one side.
func test_dense_housing_start_cells_stand_on_existing_cells_beside_a_street() -> void:
	var small: Dictionary = _documents["maps/whitechapel_1850s.json"]
	small["existing_cells"] = [[1, 1], [3, 3]]
	small["road_cells"] = [[1, 2]]
	small["dense_housing_cells"] = [[1, 1]]
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	if result.is_ok():
		assert_eq(result.catalog.maps[&"whitechapel_1850s"].dense_housing_cells, [Vector2i(1, 1)] as Array[Vector2i])
	before_each()
	_documents["maps/whitechapel_1850s.json"]["existing_cells"] = [[1, 1]]
	_documents["maps/whitechapel_1850s.json"]["road_cells"] = [[1, 2]]
	_documents["maps/whitechapel_1850s.json"]["dense_housing_cells"] = [[2, 2]]
	_assert_invalid("dense_housing_cells: [2, 2] is not a standing building")
	before_each()
	_documents["maps/whitechapel_1850s.json"]["existing_cells"] = [[1, 1], [3, 3]]
	_documents["maps/whitechapel_1850s.json"]["road_cells"] = [[1, 2]]
	_documents["maps/whitechapel_1850s.json"]["dense_housing_cells"] = [[3, 3]]
	_assert_invalid("dense_housing_cells: [3, 3] has no street on any side")


func test_buildable_is_an_optional_boolean() -> void:
	_documents["economy/buildings.json"]["bakery"]["buildable"] = "no"
	_assert_invalid("buildings.json.bakery.buildable: expected a boolean")
	before_each()
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	if result.is_ok():
		assert_true(result.catalog.buildings[&"bakery"].buildable, "Buildable unless the data says otherwise")


func test_a_scenario_map_must_exist() -> void:
	_documents["scenarios/victorian_demo.json"] = {"map": "atlantis"}
	_assert_invalid("scenarios/victorian_demo.json.map: unknown map atlantis")
	before_each()
	_documents["scenarios/victorian_demo.json"] = {"map": "riverside_strip"}
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	if result.is_ok():
		assert_eq(result.catalog.scenarios[&"victorian_demo"]["map"], &"riverside_strip")


# Issue #67 (D-070, D-080): streets, transport and service radii are data with ranges, and the strip's map says
# whether it plays with streets and which diagonal edges its historic streets have.
func test_distance_values_load_with_their_numbers() -> void:
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	if not result.is_ok():
		return
	var params: Params = Params.new(result.catalog, result.catalog.roles[&"neutral_administrator"])
	assert_eq(params.get_value(&"roads.cost"), 10)
	assert_eq(params.get_value(&"roads.upkeep_per_minute"), 0)
	assert_eq(params.get_value(&"transport.cost_per_unit_per_step"), 0.1)
	assert_eq(params.get_value(&"transport.expensive_steps"), 10)
	assert_eq(params.get_value(&"building.bakery.service_radius"), 8)
	assert_eq(params.get_value(&"building.brewery.service_radius"), 6)
	assert_eq(params.get_value(&"building.wharf.service_radius"), 4)
	assert_eq(result.catalog.buildings[&"bakery"].distributes, [&"bread"] as Array[StringName])
	assert_eq(result.catalog.buildings[&"wharf"].distributes, [&"tea"] as Array[StringName])
	assert_eq(result.catalog.buildings[&"wharf"].supplies, [&"barley", &"flour"] as Array[StringName])
	assert_true(result.catalog.maps[&"riverside_strip"].roads_enabled)
	assert_true(result.catalog.maps[&"riverside_strip"].road_diagonals.is_empty())
	assert_false(result.catalog.maps[&"whitechapel_1850s"].roads_enabled)


func test_distance_values_validate_their_ranges() -> void:
	_documents["economy/transport.json"]["cost_per_unit_per_step"] = 1.5
	_assert_invalid("economy/transport.json.cost_per_unit_per_step: invalid number value 1.5")
	before_each()
	_documents["economy/transport.json"]["expensive_steps"] = 0
	_assert_invalid("economy/transport.json.expensive_steps: invalid positive_integer value 0")
	before_each()
	_documents["economy/roads.json"]["cost"] = 1001
	_assert_invalid("economy/roads.json.cost: invalid money value 1001")
	before_each()
	_documents["economy/roads.json"]["upkeep_per_minute"] = 101
	_assert_invalid("economy/roads.json.upkeep_per_minute: invalid money value 101")
	before_each()
	_documents["economy/buildings.json"]["bakery"]["service_radius"] = 31
	_assert_invalid("economy/buildings.json.bakery.service_radius: invalid integer value 31")
	before_each()
	_documents["economy/buildings.json"]["bakery"]["distributes"] = ["cake"]
	_assert_invalid("economy/buildings.json.bakery.distributes: unknown good cake")


func test_a_role_modifies_the_distance_values() -> void:
	_set_modifier({"key": "transport.cost_per_unit_per_step", "op": "mul", "value": 2})
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	if not result.is_ok():
		return
	var params: Params = Params.new(result.catalog, result.catalog.roles[&"neutral_administrator"])
	assert_almost_eq(float(params.get_value(&"transport.cost_per_unit_per_step")), 0.2, 1e-9)


func test_roads_enabled_is_a_boolean() -> void:
	_documents["maps/whitechapel_1850s.json"]["roads_enabled"] = 1
	_assert_invalid("maps/whitechapel_1850s.json.roads_enabled: expected a boolean")


func test_diagonal_must_join_historic_roads() -> void:
	_documents["maps/whitechapel_1850s.json"]["road_cells"] = [[1, 1], [2, 2], [3, 3]]
	_documents["maps/whitechapel_1850s.json"]["road_diagonals"] = [[1, 1, 2, 2]]
	var result: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(result.is_ok(), str(result.errors))
	if result.is_ok():
		assert_eq(result.catalog.maps[&"whitechapel_1850s"].road_diagonals, [Vector4i(1, 1, 2, 2)] as Array[Vector4i])
	_documents["maps/whitechapel_1850s.json"]["road_diagonals"] = [[1, 1, 3, 3]]
	_assert_invalid("road_diagonals: [1, 1, 3, 3] must join two diagonal street cells")
	_documents["maps/whitechapel_1850s.json"]["road_diagonals"] = [[3, 3, 4, 4]]
	_assert_invalid("road_diagonals: [3, 3, 4, 4] must join two diagonal street cells")
	_documents["maps/whitechapel_1850s.json"]["road_diagonals"] = [[1, 1, 2]]
	_assert_invalid("road_diagonals: expected [x1, y1, x2, y2]")
