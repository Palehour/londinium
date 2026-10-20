extends GutTest

# Money sinks of issue #118 (approved by Cristian on 2026-10-14, revised the same day): administration makes every
# building's upkeep grow past the free ones, and from the third copy of a type each one costs 15 % more than the one
# before (compounded, up to 3 times the base cost), except housing and the wharf (basic infrastructure). Wages stay
# as they were.
# Issue #186 (D-086): the cells below are the corners (2x, 2y) of the 2x2 blocks of the old cells of 50 m.

var _catalog: DataCatalog
var _context: EconomyContext
var _params: Params


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	_params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])


# A city of `count` buildings of one type on land cells, row by row, nobody living or working there.
func _state_with(definition_id: StringName, count: int) -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.money = 100000
	# No tax, so a minute's bill is wages and upkeep alone.
	state.tax_rate = 0.0
	for index: int in range(count):
		@warning_ignore("integer_division")
		state.buildings.append({"definition_id": definition_id, "cell": [index % 8 * 2, index / 8 * 2]})
	return state


func _build(state: EconomyState, definition_id: StringName, cell: Vector2i) -> BuildCommand:
	var command: BuildCommand = BuildCommand.new(_context, definition_id, cell)
	command.execute(state, _params, RandomNumberGenerator.new())
	return command


func _definition(definition_id: StringName) -> BuildingDef:
	return _context.buildings[definition_id]


func _upkeep_paid_in_a_minute(state: EconomyState, params: Params) -> int:
	var before: int = state.money
	for _tick: int in range(60):
		MoneySystem.new().tick(state, params)
	return before - state.money


# --- Administration ---

func test_the_approved_administration_values_are_in_data() -> void:
	assert_eq(_params.get_value(&"economy.administration.per_building"), 0.03)
	assert_eq(_params.get_value(&"economy.administration.free_buildings"), 12)
	assert_eq(_params.get_value(&"economy.administration.max_multiplier"), 2.0)


func test_administration_starts_after_the_twelfth_building_and_stops_at_twice() -> void:
	assert_eq(BuildingCosts.administration_multiplier(_params, 0), 1.0)
	assert_eq(BuildingCosts.administration_multiplier(_params, 12), 1.0)
	assert_almost_eq(BuildingCosts.administration_multiplier(_params, 13), 1.03, 1e-9)
	assert_almost_eq(BuildingCosts.administration_multiplier(_params, 22), 1.3, 1e-9)
	assert_almost_eq(BuildingCosts.administration_multiplier(_params, 45), 1.99, 1e-9)
	assert_eq(BuildingCosts.administration_multiplier(_params, 46), 2.0, "1 + 0.03 x 34 = 2.02 is capped")
	assert_eq(BuildingCosts.administration_multiplier(_params, 200), 2.0)


func test_upkeep_is_multiplied_by_administration() -> void:
	# Housing has no jobs, so the minute's bill is upkeep alone: 12 x 1 at x1, then 22 x 1 at x1.3.
	assert_eq(_upkeep_paid_in_a_minute(_state_with(&"housing", 12), _params), 12)
	var bigger: EconomyState = _state_with(&"housing", 22)
	assert_eq(_upkeep_paid_in_a_minute(bigger, _params), 28, "22 x 1.3 = 28.6: 28 paid, the fraction kept")
	assert_almost_eq(bigger.upkeep_fraction, 0.6, 1e-6)


func test_a_role_modifier_changes_administration() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"economy.administration.per_building", &"set", 0.1))
	var params: Params = Params.new(_catalog, role)
	assert_almost_eq(BuildingCosts.administration_multiplier(params, 13), 1.1, 1e-9)


# --- Construction escalation ---

func test_the_approved_escalation_values_are_in_data() -> void:
	assert_eq(_params.get_value(&"economy.construction_escalation.free_copies"), 2)
	assert_eq(_params.get_value(&"economy.construction_escalation.per_building"), 0.15)
	assert_eq(_params.get_value(&"economy.construction_escalation.max_multiplier"), 3.0)


func test_from_the_third_copy_each_costs_fifteen_percent_more_up_to_three_times() -> void:
	var base: int = int(_params.get_value(&"building.bakery.cost"))
	assert_eq(base, 120)
	var expected: Array[int] = [120, 120, 138, 159, 183, 210, 241, 278, 319, 360, 360]
	for copies: int in range(expected.size()):
		assert_eq(BuildingCosts.construction_cost(_params, _state_with(&"bakery", copies), _definition(&"bakery")),
			expected[copies], "bakery number %d" % (copies + 1))


func test_buildings_of_another_type_do_not_make_it_dearer() -> void:
	assert_eq(BuildingCosts.construction_cost(_params, _state_with(&"mill", 5), _definition(&"bakery")), 120)


func test_the_second_copy_still_costs_the_base_price() -> void:
	var state: EconomyState = _state_with(&"bakery", 1)
	assert_true(_build(state, &"bakery", Vector2i(6, 6)).accepted)
	assert_eq(state.money, 100000 - 120)
	assert_eq(state.buildings[1]["paid"], 120)


func test_build_charges_the_escalated_price_and_keeps_it_on_the_building() -> void:
	var state: EconomyState = _state_with(&"bakery", 2)
	var command: BuildCommand = _build(state, &"bakery", Vector2i(6, 6))
	assert_true(command.accepted)
	assert_eq(state.money, 100000 - 138, "the third bakery costs 120 x 1.15")
	assert_eq(state.construction_spent_tick, 138)
	assert_eq(state.buildings[2]["paid"], 138)


func test_insufficient_money_is_judged_on_the_escalated_price() -> void:
	var state: EconomyState = _state_with(&"bakery", 2)
	state.money = 137
	var refused: BuildCommand = _build(state, &"bakery", Vector2i(6, 6))
	assert_false(refused.accepted)
	assert_eq(refused.reason, &"insufficient_money")
	state.money = 138
	assert_true(_build(state, &"bakery", Vector2i(6, 6)).accepted)


func test_demolishing_a_copy_makes_the_next_one_cheaper_again() -> void:
	var state: EconomyState = _state_with(&"bakery", 0)
	_build(state, &"bakery", Vector2i(2, 2))
	_build(state, &"bakery", Vector2i(4, 2))
	_build(state, &"bakery", Vector2i(6, 2))
	assert_eq(BuildingCosts.construction_cost(_params, state, _definition(&"bakery")), 159)
	DemolishCommand.new(Vector2i(6, 2)).execute(state, _params, RandomNumberGenerator.new())
	assert_eq(BuildingCosts.construction_cost(_params, state, _definition(&"bakery")), 138)


func test_demolition_within_grace_refunds_what_was_paid() -> void:
	var state: EconomyState = _state_with(&"bakery", 2)
	_build(state, &"bakery", Vector2i(6, 6))
	var demolish: DemolishCommand = DemolishCommand.new(Vector2i(6, 6))
	demolish.execute(state, _params, RandomNumberGenerator.new())
	assert_true(demolish.accepted)
	assert_eq(state.money, 100000, "building and undoing at once costs nothing")


func test_demolition_after_grace_refunds_the_ratio_of_what_was_paid() -> void:
	# A jobless building, so the ratio applies (an idle bakery would be refunded in full); the third artisan housing
	# paid 120 x 1.15.
	var state: EconomyState = _state_with(&"artisan_housing", 2)
	_build(state, &"artisan_housing", Vector2i(6, 6))
	state.defeat_elapsed_seconds += int(_params.get_value(&"demolish.refund_grace_seconds")) + 1
	var ratio: float = float(_params.get_value(&"demolish.no_jobs_refund_ratio"))
	DemolishCommand.new(Vector2i(6, 6)).execute(state, _params, RandomNumberGenerator.new())
	assert_eq(state.money, 100000 - 138 + roundi(138 * ratio))


# --- Basic infrastructure (Cristian, #118, 2026-10-14 23:41) ---

func test_housing_and_the_wharf_are_basic_infrastructure_in_data() -> void:
	assert_true(BuildingCosts.BASIC_INFRASTRUCTURE_TAG in _definition(&"housing").tags)
	assert_true(BuildingCosts.BASIC_INFRASTRUCTURE_TAG in _definition(&"wharf").tags)
	assert_false(BuildingCosts.BASIC_INFRASTRUCTURE_TAG in _definition(&"artisan_housing").tags,
		"only the workers' housing was exempted")


func test_basic_infrastructure_always_costs_its_base_price() -> void:
	for copies: int in [2, 3, 8, 20]:
		assert_eq(BuildingCosts.construction_cost(_params, _state_with(&"housing", copies), _definition(&"housing")),
			60, "housing number %d" % (copies + 1))
		assert_eq(BuildingCosts.construction_cost(_params, _state_with(&"wharf", copies), _definition(&"wharf")),
			240, "wharf number %d" % (copies + 1))


func test_building_a_third_housing_charges_and_keeps_the_base_price() -> void:
	var state: EconomyState = _state_with(&"housing", 2)
	assert_true(_build(state, &"housing", Vector2i(6, 6)).accepted)
	assert_eq(state.money, 100000 - 60)
	assert_eq(state.buildings[2]["paid"], 60)


func test_artisan_housing_still_escalates() -> void:
	assert_eq(BuildingCosts.construction_cost(_params, _state_with(&"artisan_housing", 2),
		_definition(&"artisan_housing")), 138)


func test_basic_infrastructure_still_counts_for_administration() -> void:
	# 22 housings: upkeep 22 x 1 at x1.3, as in test_upkeep_is_multiplied_by_administration.
	assert_eq(_upkeep_paid_in_a_minute(_state_with(&"housing", 22), _params), 28)


func test_a_building_without_a_recorded_price_refunds_on_the_base_cost() -> void:
	# Games saved before #118 have no "paid" on their buildings, and their price was the base cost.
	var state: EconomyState = _state_with(&"housing", 2)
	state.buildings[1]["built_at"] = 0
	DemolishCommand.new(Vector2i(2, 0)).execute(state, _params, RandomNumberGenerator.new())
	assert_eq(state.money, 100000 + 60)


# --- Wages ---

func test_the_beer_chain_keeps_paying_two_per_worker() -> void:
	# The 3 of the first approval broke the artisans' payback (D-061); Cristian's revision kept 2.
	assert_eq(_catalog.base_values[&"building.malthouse.wage_per_worker_per_minute"], 2)
	assert_eq(_catalog.base_values[&"building.brewery.wage_per_worker_per_minute"], 2)
