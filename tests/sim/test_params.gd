extends GutTest

var _catalog: DataCatalog


func before_each() -> void:
	var result: DataLoadResult = DataLoader.new().load_all()
	assert_true(result.is_ok(), str(result.errors))
	_catalog = result.catalog


func test_neutral_role_returns_every_base_value() -> void:
	var params: Params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	for key: StringName in _catalog.base_values:
		assert_eq(params.get_value(key), _catalog.base_values[key], str(key))


func test_synthetic_mul_changes_only_its_target() -> void:
	var role: RoleDef = RoleDef.new()
	role.id = &"test_only"
	var key: StringName = &"building.bakery.recipe.seconds"
	role.modifiers.append(Modifier.new(key, &"mul", 0.5))
	var params: Params = Params.new(_catalog, role)
	for other: StringName in _catalog.base_values:
		if other == key:
			assert_eq(params.get_value(other), float(_catalog.base_values[other]) * 0.5)
		else:
			assert_eq(params.get_value(other), _catalog.base_values[other], str(other))


func test_add_mul_set_follow_list_order_without_mutating_bases() -> void:
	var key: StringName = &"building.bakery.recipe.seconds"
	var base: Variant = _catalog.base_values[key]
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(key, &"add", 10), Modifier.new(key, &"mul", 2),
		Modifier.new(key, &"set", 7), Modifier.new(key, &"mul", 3), Modifier.new(key, &"add", 2)])
	var params: Params = Params.new(_catalog, role)
	assert_eq(params.get_value(key), 23.0)
	assert_eq(params.get_value(key), 23.0)
	assert_eq(_catalog.base_values[key], base)
	role.modifiers.reverse()
	assert_eq(Params.new(_catalog, role).get_value(key), 24.0)
	assert_eq(params.get_value(key), 23.0, "Params takes a snapshot of the active role")


func test_money_rounds_once_after_all_modifiers() -> void:
	var key: StringName = &"building.wharf.cost"
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(key, &"set", 1), Modifier.new(key, &"mul", 0.5),
		Modifier.new(key, &"mul", 3)])
	var params: Params = Params.new(_catalog, role)
	assert_eq(params.get_value(key), 2)
	assert_typeof(params.get_value(key), TYPE_INT)
	role.modifiers.append(Modifier.new(key, &"set", 1.49))
	assert_eq(Params.new(_catalog, role).get_value(key), 1)
	role.modifiers.append(Modifier.new(key, &"set", 2.5))
	assert_eq(Params.new(_catalog, role).get_value(key), 3)
	role.modifiers.append(Modifier.new(key, &"set", -2.5))
	assert_eq(Params.new(_catalog, role).get_value(key), -3)


func test_negative_wheat_base_price_is_rejected_after_modifiers() -> void:
	var key: StringName = &"market.wheat.base_price"
	for value: float in [-3.0, 1e30]:
		var role: RoleDef = RoleDef.new()
		role.modifiers.append(Modifier.new(key, &"set", value))
		assert_null(Params.new(_catalog, role).get_value(key))
		assert_push_error("Params: invalid range for '%s'" % key)
	var zero_role: RoleDef = RoleDef.new()
	zero_role.modifiers.append(Modifier.new(key, &"set", 0))
	assert_eq(Params.new(_catalog, zero_role).get_value(key), 0)


func test_unknown_key_is_an_error_not_zero() -> void:
	var params: Params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	assert_null(params.get_value(&"missing.key"))
	assert_push_error("Params: unknown key 'missing.key'")


func test_role_cannot_invert_depopulation_thresholds_on_either_read() -> void:
	var invalid: Dictionary[StringName, float] = {
		&"defeat.depopulation.defeat_fraction": 0.75,
		&"defeat.depopulation.warning_fraction": 0.1,
	}
	for modified_key: StringName in invalid:
		var role: RoleDef = RoleDef.new()
		role.modifiers.append(Modifier.new(modified_key, &"set", invalid[modified_key]))
		var params: Params = Params.new(_catalog, role)
		for key: StringName in invalid:
			assert_null(params.get_value(key))
			assert_push_error("defeat.depopulation.defeat_fraction must be <= defeat.depopulation.warning_fraction")


func test_depopulation_relation_uses_both_final_modified_values_and_allows_equality() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"defeat.depopulation.defeat_fraction", &"set", 0.75),
		Modifier.new(&"defeat.depopulation.warning_fraction", &"set", 0.75)])
	var params: Params = Params.new(_catalog, role)
	assert_eq(params.get_value(&"defeat.depopulation.defeat_fraction"), 0.75)
	assert_eq(params.get_value(&"defeat.depopulation.warning_fraction"), 0.75)


func test_defeat_ranges_apply_to_role_modifiers() -> void:
	var invalid: Dictionary[StringName, Array] = {
		&"defeat.grace_seconds": [-1.0],
		&"defeat.hunger.smoothing": [0.0, -0.1, 1.01],
		&"defeat.depopulation.duration_seconds": [0.0, -1.0, 1.5],
		&"defeat.bankruptcy.duration_seconds": [0.0, -1.0, 1.5],
		&"defeat.hunger.duration_seconds": [0.0, -1.0, 1.5],
	}
	for key: StringName in invalid:
		for value: float in invalid[key]:
			var role: RoleDef = RoleDef.new()
			role.modifiers.append(Modifier.new(key, &"set", value))
			assert_null(Params.new(_catalog, role).get_value(key))
			assert_push_error("Params: invalid range for '%s'" % key)
	for key: StringName in invalid:
		var role: RoleDef = RoleDef.new()
		role.modifiers.assign([Modifier.new(key, &"set", -1), Modifier.new(key, &"add", 2)])
		assert_eq(Params.new(_catalog, role).get_value(key), 1.0)


func test_invalid_synthetic_operation_is_an_error() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"market.wheat.base_price", &"divide", 2))
	assert_null(Params.new(_catalog, role).get_value(&"market.wheat.base_price"))
	assert_push_error("Params: unknown operation 'divide' for 'market.wheat.base_price'")


func test_modified_defeat_thresholds_match_schema_ranges() -> void:
	var invalid: Dictionary[StringName, Array] = {
		&"defeat.hunger.threshold": [-0.1, 2.0],
		&"defeat.depopulation.warning_fraction": [-0.1, 1.1],
		&"defeat.depopulation.defeat_fraction": [-0.1, 1.1],
		&"defeat.depopulation.minimum_population": [-1.0, 1.5, 1e30],
		&"defeat.bankruptcy.threshold": [-1.0, 1e30],
		&"defeat.bankruptcy.duration_seconds": [1e30],
		&"defeat.hunger.duration_seconds": [1e30],
		&"defeat.depopulation.duration_seconds": [1e30],
	}
	for key: StringName in invalid:
		for value: float in invalid[key]:
			var role: RoleDef = RoleDef.new()
			role.modifiers.append(Modifier.new(key, &"set", value))
			assert_null(Params.new(_catalog, role).get_value(key))
			assert_push_error("Params: invalid range for '%s'" % key)


func test_every_defeat_key_has_post_modifier_range_and_rejects_nonfinite_values() -> void:
	for key: StringName in _catalog.base_values:
		if not String(key).begins_with("defeat."):
			continue
		assert_true(ParameterRanges.BY_KEY.has(key), str(key))
		for value: float in [INF, NAN]:
			var role: RoleDef = RoleDef.new()
			role.modifiers.append(Modifier.new(key, &"set", value))
			assert_null(Params.new(_catalog, role).get_value(key))
			assert_push_error("Params: nonfinite result for '%s'" % key)


func test_modified_defeat_schema_boundaries_and_money_rounding() -> void:
	for boundary: float in [0.0, 1.0]:
		var role: RoleDef = RoleDef.new()
		for key: StringName in [&"defeat.hunger.threshold", &"defeat.depopulation.warning_fraction",
				&"defeat.depopulation.defeat_fraction", &"defeat.depopulation.minimum_population"]:
			role.modifiers.append(Modifier.new(key, &"set", boundary))
		var params: Params = Params.new(_catalog, role)
		for modifier: Modifier in role.modifiers:
			assert_eq(params.get_value(modifier.key), boundary)
	var money_role: RoleDef = RoleDef.new()
	money_role.modifiers.assign([Modifier.new(&"defeat.bankruptcy.threshold", &"set", 1),
		Modifier.new(&"defeat.bankruptcy.threshold", &"mul", 0.5),
		Modifier.new(&"defeat.bankruptcy.threshold", &"mul", 3)])
	var money: Variant = Params.new(_catalog, money_role).get_value(&"defeat.bankruptcy.threshold")
	assert_eq(money, 2)
	assert_typeof(money, TYPE_INT)


func test_nonfinite_modifier_result_is_an_error() -> void:
	var key: StringName = &"building.bakery.recipe.seconds"
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(key, &"mul", 1e308))
	assert_null(Params.new(_catalog, role).get_value(key))
	assert_push_error("Params: nonfinite result for 'building.bakery.recipe.seconds'")


func test_money_modifier_result_outside_int64_is_an_error() -> void:
	var key: StringName = &"building.wharf.cost"
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(key, &"set", 1e30))
	assert_null(Params.new(_catalog, role).get_value(key))
	assert_push_error("Params: money result outside int64 for 'building.wharf.cost'")


func test_role_modifiers_cannot_break_population_parameter_ranges() -> void:
	var invalid: Dictionary[StringName, Array] = {
		&"population.growth.hunger_emigration_multiplier": [0.99, -1.0],
		&"population.empty_city_bread_lookahead_seconds": [-1.0],
		&"population.satisfaction.smoothing_per_second": [0.0, -0.1, 1.01],
	}
	for key: StringName in invalid:
		for value: float in invalid[key]:
			var role: RoleDef = RoleDef.new()
			role.modifiers.append(Modifier.new(key, &"set", value))
			assert_null(Params.new(_catalog, role).get_value(key))
			assert_push_error("Params: invalid range for '%s'" % key)


func test_population_range_validation_uses_final_modified_value() -> void:
	for key: StringName in [&"population.growth.hunger_emigration_multiplier",
			&"population.empty_city_bread_lookahead_seconds", &"population.satisfaction.smoothing_per_second"]:
		var role: RoleDef = RoleDef.new()
		role.modifiers.assign([Modifier.new(key, &"set", -1), Modifier.new(key, &"add", 2)])
		assert_eq(Params.new(_catalog, role).get_value(key), 1.0)
	var zero_lookahead: RoleDef = RoleDef.new()
	zero_lookahead.modifiers.append(Modifier.new(&"population.empty_city_bread_lookahead_seconds", &"set", 0))
	assert_eq(Params.new(_catalog, zero_lookahead).get_value(&"population.empty_city_bread_lookahead_seconds"), 0.0)


func test_hunger_relation_is_checked_on_either_read() -> void:
	var threshold: StringName = &"population.growth.hunger_emigration_threshold"
	var recovery: StringName = &"population.growth.hunger_emigration_recovery"
	for modified_key: StringName in [threshold, recovery]:
		var role: RoleDef = RoleDef.new()
		role.modifiers.append(Modifier.new(modified_key, &"set", 0.8 if modified_key == threshold else 0.5))
		var params: Params = Params.new(_catalog, role)
		for key: StringName in [threshold, recovery]:
			assert_null(params.get_value(key))
			assert_push_error("hunger_emigration_recovery must be >= population.growth.hunger_emigration_threshold after role modifiers")


func test_hunger_ranges_and_final_relation_apply_after_modifiers() -> void:
	var threshold: StringName = &"population.growth.hunger_emigration_threshold"
	var recovery: StringName = &"population.growth.hunger_emigration_recovery"
	for key: StringName in [threshold, recovery]:
		assert_true(ParameterRanges.BY_KEY.has(key))
		for value: float in [-0.01, 1.01, INF, NAN]:
			var role: RoleDef = RoleDef.new()
			role.modifiers.append(Modifier.new(key, &"set", value))
			assert_null(Params.new(_catalog, role).get_value(key))
			assert_push_error("invalid range" if is_finite(value) else "nonfinite result")
	for boundary: float in [0.0, 1.0]:
		var role: RoleDef = RoleDef.new()
		role.modifiers.assign([Modifier.new(threshold, &"set", 2), Modifier.new(threshold, &"set", boundary),
			Modifier.new(recovery, &"set", -1), Modifier.new(recovery, &"set", boundary)])
		var params: Params = Params.new(_catalog, role)
		assert_eq(params.get_value(threshold), boundary)
		assert_eq(params.get_value(recovery), boundary)
		assert_true(params.validation_errors().is_empty())


func test_peak_decay_range_applies_to_final_modifier_value() -> void:
	var key: StringName = &"defeat.depopulation.peak_decay_per_minute"
	assert_eq(Params.new(_catalog, RoleDef.new()).get_value(key), 0.03)
	assert_true(ParameterRanges.BY_KEY.has(key))
	for invalid: float in [-0.01, 1.01, INF, NAN]:
		var role: RoleDef = RoleDef.new()
		role.modifiers.append(Modifier.new(key, &"set", invalid))
		assert_null(Params.new(_catalog, role).get_value(key))
		assert_push_error("invalid range" if is_finite(invalid) else "nonfinite result")
	for boundary: float in [0.0, 1.0]:
		var role: RoleDef = RoleDef.new()
		role.modifiers.assign([Modifier.new(key, &"set", 2), Modifier.new(key, &"set", boundary)])
		assert_eq(Params.new(_catalog, role).get_value(key), boundary)


func test_stability_window_range_applies_to_final_modifier_value() -> void:
	var key: StringName = &"defeat.depopulation.stability_window_seconds"
	assert_eq(Params.new(_catalog, RoleDef.new()).get_value(key), 60)
	assert_true(ParameterRanges.BY_KEY.has(key))
	for invalid: float in [0.0, -1.0, 1.5, INF, NAN]:
		var role: RoleDef = RoleDef.new()
		role.modifiers.append(Modifier.new(key, &"set", invalid))
		assert_null(Params.new(_catalog, role).get_value(key))
		assert_push_error("invalid range" if is_finite(invalid) else "nonfinite result")
	var valid_role: RoleDef = RoleDef.new()
	valid_role.modifiers.assign([Modifier.new(key, &"set", -5), Modifier.new(key, &"set", 90)])
	assert_eq(Params.new(_catalog, valid_role).get_value(key), 90)


func test_snap_epsilon_validates_final_modified_value_on_read() -> void:
	var key: StringName = &"population.satisfaction.snap_epsilon"
	for invalid: float in [0.0, -0.01, INF, NAN]:
		var role: RoleDef = RoleDef.new()
		role.modifiers.append(Modifier.new(key, &"set", invalid))
		assert_null(Params.new(_catalog, role).get_value(key))
		assert_push_error("invalid range" if is_finite(invalid) else "nonfinite result")
	var valid_role: RoleDef = RoleDef.new()
	valid_role.modifiers.assign([Modifier.new(key, &"set", -1.0), Modifier.new(key, &"add", 1.125),
		Modifier.new(key, &"mul", 0.5)])
	assert_eq(Params.new(_catalog, valid_role).get_value(key), 0.0625)


func test_coverage_snap_epsilon_validates_final_modified_value_on_read() -> void:
	var key: StringName = &"population.hunger_coverage_snap_epsilon"
	for invalid: float in [0.0, -0.01, INF, NAN]:
		var role: RoleDef = RoleDef.new()
		role.modifiers.append(Modifier.new(key, &"set", invalid))
		assert_null(Params.new(_catalog, role).get_value(key))
		assert_push_error("invalid range" if is_finite(invalid) else "nonfinite result")
	var valid_role: RoleDef = RoleDef.new()
	valid_role.modifiers.assign([Modifier.new(key, &"set", -1.0), Modifier.new(key, &"add", 1.125),
		Modifier.new(key, &"mul", 0.5)])
	assert_eq(Params.new(_catalog, valid_role).get_value(key), 0.0625)
