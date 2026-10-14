extends GutTest

# Money sinks of issue #118 (approved by Cristian on 2026-10-14, revised the same day): administration makes every
# building's upkeep grow past the free ones, and from the third copy of a type each one costs 15 % more than the one
# before (compounded, up to 3 times the base cost). Wages stay as they were.

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
		state.buildings.append({"definition_id": definition_id, "cell": [index % 8, index / 8]})
	return state


func _build(state: EconomyState, definition_id: StringName, cell: Vector2i) -> BuildCommand:
	var command: BuildCommand = BuildCommand.new(_context, definition_id, cell)
	command.execute(state, _params, RandomNumberGenerator.new())
	return command


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
		assert_eq(BuildingCosts.construction_cost(_params, _state_with(&"bakery", copies), &"bakery"),
			expected[copies], "bakery number %d" % (copies + 1))


func test_buildings_of_another_type_do_not_make_it_dearer() -> void:
	assert_eq(BuildingCosts.construction_cost(_params, _state_with(&"housing", 5), &"bakery"), 120)


func test_the_second_copy_still_costs_the_base_price() -> void:
	var state: EconomyState = _state_with(&"housing", 1)
	assert_true(_build(state, &"housing", Vector2i(3, 3)).accepted)
	assert_eq(state.money, 100000 - 60)
	assert_eq(state.buildings[1]["paid"], 60)


func test_build_charges_the_escalated_price_and_keeps_it_on_the_building() -> void:
	var state: EconomyState = _state_with(&"housing", 2)
	var command: BuildCommand = _build(state, &"housing", Vector2i(3, 3))
	assert_true(command.accepted)
	assert_eq(state.money, 100000 - 69, "the third housing costs 60 x 1.15")
	assert_eq(state.construction_spent_tick, 69)
	assert_eq(state.buildings[2]["paid"], 69)


func test_insufficient_money_is_judged_on_the_escalated_price() -> void:
	var state: EconomyState = _state_with(&"housing", 2)
	state.money = 68
	var refused: BuildCommand = _build(state, &"housing", Vector2i(3, 3))
	assert_false(refused.accepted)
	assert_eq(refused.reason, &"insufficient_money")
	state.money = 69
	assert_true(_build(state, &"housing", Vector2i(3, 3)).accepted)


func test_demolishing_a_copy_makes_the_next_one_cheaper_again() -> void:
	var state: EconomyState = _state_with(&"housing", 0)
	_build(state, &"housing", Vector2i(1, 1))
	_build(state, &"housing", Vector2i(2, 1))
	_build(state, &"housing", Vector2i(3, 1))
	assert_eq(BuildingCosts.construction_cost(_params, state, &"housing"), 79)
	DemolishCommand.new(Vector2i(3, 1)).execute(state, _params, RandomNumberGenerator.new())
	assert_eq(BuildingCosts.construction_cost(_params, state, &"housing"), 69)


func test_demolition_within_grace_refunds_what_was_paid() -> void:
	var state: EconomyState = _state_with(&"housing", 2)
	_build(state, &"housing", Vector2i(3, 3))
	var demolish: DemolishCommand = DemolishCommand.new(Vector2i(3, 3))
	demolish.execute(state, _params, RandomNumberGenerator.new())
	assert_true(demolish.accepted)
	assert_eq(state.money, 100000, "building and undoing at once costs nothing")


func test_demolition_after_grace_refunds_the_ratio_of_what_was_paid() -> void:
	var state: EconomyState = _state_with(&"housing", 2)
	_build(state, &"housing", Vector2i(3, 3))
	state.defeat_elapsed_seconds += int(_params.get_value(&"demolish.refund_grace_seconds")) + 1
	var ratio: float = float(_params.get_value(&"demolish.no_jobs_refund_ratio"))
	DemolishCommand.new(Vector2i(3, 3)).execute(state, _params, RandomNumberGenerator.new())
	assert_eq(state.money, 100000 - 69 + roundi(69 * ratio))


func test_a_building_without_a_recorded_price_refunds_on_the_base_cost() -> void:
	# Games saved before #118 have no "paid" on their buildings, and their price was the base cost.
	var state: EconomyState = _state_with(&"housing", 2)
	state.buildings[1]["built_at"] = 0
	DemolishCommand.new(Vector2i(1, 0)).execute(state, _params, RandomNumberGenerator.new())
	assert_eq(state.money, 100000 + 60)


# --- Wages ---

func test_the_beer_chain_keeps_paying_two_per_worker() -> void:
	# The 3 of the first approval broke the artisans' payback (D-061); Cristian's revision kept 2.
	assert_eq(_catalog.base_values[&"building.malthouse.wage_per_worker_per_minute"], 2)
	assert_eq(_catalog.base_values[&"building.brewery.wage_per_worker_per_minute"], 2)
