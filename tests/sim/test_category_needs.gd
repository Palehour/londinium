extends GutTest

# Needs by category and housing bonuses (issue #86).

var _catalog: DataCatalog
var _params: Params
var _context: EconomyContext
var _state: EconomyState


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	_params = _params_with({})
	_state = EconomyState.new()
	_state.tax_rate = 0.25
	_state.buildings.append({"definition_id": &"housing"})


func _params_with(changes: Dictionary) -> Params:
	var role: RoleDef = RoleDef.new()
	for key: StringName in changes:
		role.modifiers.append(Modifier.new(key, &"set", changes[key]))
	return Params.new(_catalog, role)


func _evaluate(bread: float, tea: float = 0.0) -> void:
	_state.hunger_smoothed_coverage = bread
	_state.tea_coverage = tea
	SatisfactionSystem.new().update_target(_state, _params, _context)


func _category(id: StringName) -> Dictionary:
	return _state.class_needs[&"worker"][id]


func test_category_below_threshold_is_not_met() -> void:
	_evaluate(0.74)
	assert_false(_category(&"sustento")["met"])
	assert_almost_eq(float(_category(&"sustento")["value"]), 74.0, 0.0000001)


func test_category_exactly_at_threshold_is_met() -> void:
	_evaluate(0.75, 0.5)
	assert_true(_category(&"sustento")["met"])
	assert_eq(_category(&"sustento")["value"], 75.0)
	assert_true(_category(&"comunidad")["met"])
	assert_eq(_category(&"comunidad")["value"], 50.0)


func test_a_threshold_reached_exactly_on_paper_is_met_despite_float_drift() -> void:
	_params = _params_with({&"class.worker.need.bread.value": 90, &"needs.sustento.threshold": 63})
	assert_lt(0.7 * 90.0, 63.0, "The raw product really lands under the threshold")
	_evaluate(0.7)
	assert_true(_category(&"sustento")["met"])
	var category: Dictionary = NeedsDiagnostics.build(_state, _params, _context)["classes"][&"worker"]["categories"][0]
	assert_eq(category["reason"], &"ok")
	_evaluate(0.69)
	assert_false(_category(&"sustento")["met"])


func test_a_genuine_shortfall_is_not_forgiven_as_float_drift() -> void:
	_evaluate(0.749995)
	assert_false(_category(&"sustento")["met"])
	_params = _params_with({&"class.worker.housing_max_bonus": 10})
	_evaluate(0.749995)
	assert_eq(_state.housing_capacity, 20)


func test_category_just_below_the_community_threshold_is_not_met() -> void:
	_evaluate(1.0, 0.49)
	assert_false(_category(&"comunidad")["met"])


func test_category_above_threshold_is_met() -> void:
	_evaluate(1.0)
	assert_true(_category(&"sustento")["met"])
	assert_eq(_category(&"sustento")["value"], 100.0)


func test_exceeding_a_threshold_gives_the_same_bonus_as_reaching_it() -> void:
	_params = _params_with({&"class.worker.housing_max_bonus": 10})
	_evaluate(0.75)
	var at_threshold: int = _state.housing_capacity
	_evaluate(1.0)
	assert_eq(_state.housing_capacity, at_threshold)


func test_housing_bonus_adds_per_met_category() -> void:
	_params = _params_with({&"class.worker.housing_max_bonus": 10})
	_evaluate(0.0)
	assert_eq(_state.housing_capacity, 20)
	_evaluate(1.0)
	assert_eq(_state.housing_capacity, 22)
	_evaluate(1.0, 1.0)
	assert_eq(_state.housing_capacity, 24)


func test_housing_bonus_is_capped_by_the_class_maximum() -> void:
	_params = _params_with({&"class.worker.housing_max_bonus": 3})
	_evaluate(1.0, 1.0)
	assert_eq(_state.housing_capacity, 23)


func test_housing_bonus_applies_to_every_building_of_the_class() -> void:
	_params = _params_with({&"class.worker.housing_max_bonus": 10})
	_state.buildings.append({"definition_id": &"housing"})
	_evaluate(1.0)
	assert_eq(_state.housing_capacity, 44)


func test_a_housing_building_no_class_claims_keeps_its_base() -> void:
	var housing: BuildingDef = _catalog.buildings[&"housing"]
	var alternate: BuildingDef = BuildingDef.new()
	alternate.id = &"unclaimed_housing"
	alternate.tags.assign(housing.tags)
	_catalog.buildings[alternate.id] = alternate
	_catalog.base_values[&"building.unclaimed_housing.capacity"] = 7
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	_params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	_state.buildings.assign([{"definition_id": &"unclaimed_housing"}])
	_evaluate(1.0, 1.0)
	assert_eq(_state.housing_capacity, 7)


func test_worker_housing_is_unchanged_with_every_category_met() -> void:
	_evaluate(1.0, 1.0)
	assert_eq(_state.housing_capacity, 20)
	_evaluate(0.0, 0.0)
	assert_eq(_state.housing_capacity, 20)


func test_worker_satisfaction_terms_are_the_legacy_ones() -> void:
	_evaluate(0.8, 0.5)
	assert_eq(_state.satisfaction_breakdown["bread"], 80.0)
	assert_eq(_state.satisfaction_breakdown["tea"], 2.0)
	assert_eq(_state.satisfaction_breakdown["tax"], 10.0)
	assert_eq(_state.satisfaction_target, 72.0)


func test_tea_still_adds_four_at_full_coverage() -> void:
	_evaluate(1.0, 1.0)
	assert_eq(_state.satisfaction_breakdown["tea"], 4.0)


func test_a_role_can_change_a_threshold() -> void:
	_params = _params_with({&"needs.sustento.threshold": 90})
	_evaluate(0.8)
	assert_false(_category(&"sustento")["met"])
	assert_eq(_category(&"sustento")["threshold"], 90.0)


func test_a_role_can_change_the_bonus_and_the_class_maximum() -> void:
	_params = _params_with({&"needs.housing_bonus_per_category": 5, &"class.worker.housing_max_bonus": 5})
	_evaluate(1.0, 1.0)
	assert_eq(_state.housing_capacity, 25)


func test_a_role_can_change_what_a_good_is_worth() -> void:
	_params = _params_with({&"class.worker.need.bread.value": 50})
	_evaluate(1.0)
	assert_eq(_category(&"sustento")["value"], 50.0)
	assert_false(_category(&"sustento")["met"])


func test_a_role_that_breaks_a_range_is_refused() -> void:
	for key: StringName in [&"needs.sustento.threshold", &"needs.housing_bonus_per_category",
			&"class.worker.housing_max_bonus", &"class.worker.need.bread.value"]:
		assert_null(_params_with({key: -1}).get_value(key))
		assert_push_error("Params: invalid range for '%s'" % key)
	assert_null(_params_with({&"needs.sustento.threshold": 101}).get_value(&"needs.sustento.threshold"))
	assert_push_error("Params: invalid range for 'needs.sustento.threshold'")
	assert_null(_params_with({&"class.worker.housing_max_bonus": 1.5}).get_value(&"class.worker.housing_max_bonus"))
	assert_push_error("Params: invalid range for 'class.worker.housing_max_bonus'")


func test_diagnostics_name_the_category_that_is_missing() -> void:
	_evaluate(0.5, 1.0)
	var needs: Dictionary = NeedsDiagnostics.build(_state, _params, _context)
	var categories: Array = needs["classes"][&"worker"]["categories"]
	assert_eq(categories.size(), 2)
	assert_eq(categories[0]["category"], &"sustento")
	assert_false(categories[0]["met"])
	assert_eq(categories[0]["reason"], &"below_threshold")
	assert_eq(categories[0]["goods"], [{"good": &"bread", "coverage": 0.5}])
	assert_eq(categories[0]["missing_goods"], [&"bread"] as Array[StringName])
	assert_true(categories[1]["met"])
	var housing: Dictionary = needs["classes"][&"worker"]["housing"]
	assert_eq([housing["base"], housing["bonus"], housing["max_bonus"]], [20, 0, 0])


func test_every_category_and_class_in_the_data_has_a_label() -> void:
	for category: StringName in _catalog.categories:
		assert_true(Strings.CATEGORY_LABELS.has(category), str(category))
	for id: StringName in _catalog.classes:
		assert_true(Strings.CLASS_LABELS.has(id), str(id))
		for need: NeedDef in _catalog.classes[id].needs:
			assert_true(Strings.GOOD_LABELS.has(need.good), str(need.good))


func test_state_without_class_needs_loads_from_an_old_save() -> void:
	_evaluate(1.0)
	var values: Dictionary = _state.to_dict()
	assert_true(values.has("class_needs"))
	assert_eq(EconomyState.from_dict(values).class_needs, _state.class_needs)
	values.erase("class_needs")
	var old: EconomyState = EconomyState.from_dict(values)
	assert_true(old.class_needs.is_empty())
	assert_eq(old.housing_capacity, _state.housing_capacity)


func test_a_category_value_is_not_capped() -> void:
	_params = _params_with({&"class.worker.need.bread.value": 100, &"class.worker.need.tea.value": 100})
	_catalog.classes[&"worker"].needs[1].category = &"sustento"
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	_evaluate(1.0, 1.0)
	assert_eq(_category(&"sustento")["value"], 200.0)


func test_restoring_an_old_snapshot_recomputes_the_needs() -> void:
	_evaluate(1.0, 1.0)
	var values: Dictionary = _state.to_dict()
	values.erase("class_needs")
	var restored: Simulation = Simulation.new(_params, EconomyState.from_dict(values), 1, _context)
	var needs: Dictionary = restored.snapshot()["economy"]["class_needs"]
	assert_true(needs[&"worker"][&"sustento"]["met"])
	assert_true(needs[&"worker"][&"comunidad"]["met"])
	assert_eq(restored.snapshot()["economy"]["housing_capacity"], _state.housing_capacity)


func test_diagnostics_flag_a_threshold_no_coverage_can_reach() -> void:
	_params = _params_with({&"class.worker.need.bread.value": 50})
	_evaluate(0.5)
	var category: Dictionary = NeedsDiagnostics.build(_state, _params, _context)["classes"][&"worker"]["categories"][0]
	assert_eq(category["reason"], &"unreachable_threshold")
	assert_eq(category["missing_goods"], [&"bread"] as Array[StringName])
	_params = _params_with({&"class.worker.need.bread.value": 80})
	_evaluate(0.5)
	category = NeedsDiagnostics.build(_state, _params, _context)["classes"][&"worker"]["categories"][0]
	assert_eq(category["reason"], &"below_threshold")
