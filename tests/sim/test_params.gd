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
	var key: StringName = &"market.wheat.base_price"
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


func test_unknown_key_is_an_error_not_zero() -> void:
	var params: Params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	assert_null(params.get_value(&"missing.key"))
	assert_push_error("Params: unknown key 'missing.key'")


func test_defeat_ranges_apply_to_role_modifiers() -> void:
	var invalid: Dictionary[StringName, Array] = {
		&"defeat.grace_seconds": [-1.0],
		&"defeat.hunger.smoothing": [0.0, -0.1, 1.01],
		&"defeat.depopulation.duration_seconds": [0.0, -1.0, 1.5],
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


func test_nonfinite_modifier_result_is_an_error() -> void:
	var key: StringName = &"building.bakery.recipe.seconds"
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(key, &"mul", 1e308))
	assert_null(Params.new(_catalog, role).get_value(key))
	assert_push_error("Params: nonfinite result for 'building.bakery.recipe.seconds'")


func test_money_modifier_result_outside_int64_is_an_error() -> void:
	var key: StringName = &"market.wheat.base_price"
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(key, &"set", 1e30))
	assert_null(Params.new(_catalog, role).get_value(key))
	assert_push_error("Params: money result outside int64 for 'market.wheat.base_price'")


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
