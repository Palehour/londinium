extends GutTest

# The artisan class (issue #52): its housing, consumption, satisfaction, tax, jobs and serialization.

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
	_state.buildings.append({"definition_id": &"artisan_housing"})
	ClassStates.ensure(_state, _context)


func _params_with(changes: Dictionary) -> Params:
	var role: RoleDef = RoleDef.new()
	for key: StringName in changes:
		role.modifiers.append(Modifier.new(key, &"set", changes[key]))
	return Params.new(_catalog, role)


func _artisans() -> ClassDef:
	return _context.classes[&"artisan"]


func _workers() -> ClassDef:
	return _context.classes[&"worker"]


# Residents of each class; the total is what state.population holds.
func _live(workers: int, artisans: int) -> void:
	_state.population = workers + artisans
	_state.class_states[&"artisan"].population = artisans


func _evaluate(bread: float, tea: float = 0.0, beer: float = 0.0) -> void:
	_state.hunger_smoothed_coverage = bread
	_state.tea_coverage = tea
	_state.beer_coverage = beer
	SatisfactionSystem.new().update_target(_state, _params, _context)


func test_the_artisan_class_and_its_housing_come_from_the_data() -> void:
	var artisans: ClassDef = _artisans()
	assert_false(artisans.base)
	assert_false(artisans.takes_jobs)
	assert_eq(artisans.housing_building, &"artisan_housing")
	assert_eq(_params.get_value(&"building.artisan_housing.capacity"), 10)
	assert_eq(_params.get_value(&"building.artisan_housing.cost"), 120)
	assert_eq(_params.get_value(&"building.artisan_housing.upkeep_per_minute"), 2)
	assert_eq(_params.get_value(&"building.artisan_housing.jobs"), 0)
	assert_eq(_params.get_value(&"class.artisan.housing_max_bonus"), 4)
	assert_true(_workers().base)
	assert_true(_workers().takes_jobs)


func test_artisan_needs_are_bread_for_sustento_and_beer_for_comunidad() -> void:
	assert_eq(_artisans().needs[0].good, &"bread")
	assert_eq(_artisans().needs[0].category, &"sustento")
	assert_eq(_artisans().needs[1].good, &"beer")
	assert_eq(_artisans().needs[1].category, &"comunidad")
	assert_eq(_params.get_value(&"class.artisan.need.bread.value"), 100.0)
	assert_eq(_params.get_value(&"class.artisan.need.beer.value"), 100.0)
	assert_eq(_params.get_value(&"class.artisan.need.bread.per_person_per_minute"), 1.0)
	assert_eq(_params.get_value(&"class.artisan.need.beer.per_person_per_minute"), 0.4)


func test_artisan_eats_bread_and_beer_at_their_own_rates() -> void:
	_live(10, 5)
	_state.stocks[&"bread"] = 100
	_state.stocks[&"beer"] = 100
	ConsumptionSystem.new().tick(_state, _params, _context)
	assert_almost_eq(_state.bread_demand, (10 * 1.0 + 5 * 1.0) / 60.0, 0.0000001)
	assert_almost_eq(_state.beer_demand, 5 * 0.4 / 60.0, 0.0000001)
	assert_almost_eq(_state.beer_consumed, 5 * 0.4 / 60.0, 0.0000001)


func test_a_role_can_change_what_an_artisan_eats() -> void:
	_params = _params_with({&"class.artisan.need.beer.per_person_per_minute": 1.2})
	_live(10, 5)
	_state.stocks[&"beer"] = 100
	ConsumptionSystem.new().tick(_state, _params, _context)
	assert_almost_eq(_state.beer_demand, 5 * 1.2 / 60.0, 0.0000001)


func test_tea_demand_ignores_artisans() -> void:
	_live(10, 5)
	assert_almost_eq(ImportSystem.tea_demand_per_second(_state, _params, _context),
		10 * 0.2 / 60.0, 0.0000001)
	assert_almost_eq(ImportSystem.tea_demand_per_second(_state, _params),
		15 * 0.2 / 60.0, 0.0000001)


func test_beer_coverage_follows_stock_over_demand_and_empty_city_counts_stock_as_covered() -> void:
	_live(10, 0)
	ConsumptionSystem.new().tick(_state, _params, _context)
	assert_eq(_state.beer_coverage, 0.0)
	_state.stocks[&"beer"] = 5
	ConsumptionSystem.new().tick(_state, _params, _context)
	assert_eq(_state.beer_coverage, 1.0)
	_live(10, 30)
	_state.stocks[&"beer"] = 0
	_state.beer_fraction = 0.0
	ConsumptionSystem.new().tick(_state, _params, _context)
	assert_eq(_state.beer_coverage, 0.0)


func test_beer_is_eaten_in_fractions_that_add_up_to_whole_units() -> void:
	_live(0, 30)
	_state.stocks[&"beer"] = 3
	for index: int in range(60):
		ConsumptionSystem.new().tick(_state, _params, _context)
	# 30 artisans eat 12 a minute: three units are gone in the first 15 seconds.
	assert_eq(int(_state.stocks[&"beer"]), 0)
	assert_eq(_state.beer_coverage, 0.0)


func test_beer_consumption_leaves_the_stock_whole_when_nobody_drinks_it() -> void:
	_live(10, 0)
	_state.stocks[&"beer"] = 7
	for index: int in range(120):
		ConsumptionSystem.new().tick(_state, _params, _context)
	assert_eq(int(_state.stocks[&"beer"]), 7)
	assert_eq(_state.beer_fraction, 0.0)


# PR #108 review: the part of a unit left after drinking is still in the warehouse, so it takes room.
func test_the_beer_left_after_drinking_counts_against_the_warehouse_cap() -> void:
	var cap: int = int(_params.get_value(&"market.beer.storage_capacity"))
	_state.buildings.append({"definition_id": &"brewery", "workers": 3})
	_state.stocks[&"malt"] = 40
	_state.stocks[&"beer"] = cap - 1
	_state.beer_fraction = 0.6
	for index: int in range(120):
		ProductionSystem.new().tick(_state, _params, _context)
		assert_true(float(_state.stocks[&"beer"]) + _state.beer_fraction <= float(cap) + 0.0000001,
			"tick %d: %d + %f is above the cap of %d" % [index, _state.stocks[&"beer"], _state.beer_fraction, cap])


# PR #108 review: that part spoils at the same rate as the whole units.
func test_the_beer_left_after_drinking_spoils_like_the_rest() -> void:
	var rate: float = float(_params.get_value(&"market.beer.decay_fraction_per_minute"))
	_state.wheat_price = 2
	_state.barley_price = 2
	_state.stocks[&"beer"] = 0
	_state.beer_fraction = 0.6
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for index: int in range(60):
		MarketSystem.new().tick(_state, _params, rng, index + 1, RandomNumberGenerator.new())
	assert_almost_eq(_state.beer_fraction, 0.6 * (1.0 - rate), 0.0000001)


func test_artisan_satisfaction_uses_its_own_weights() -> void:
	_live(0, 5)
	_evaluate(1.0, 0.0, 1.0)
	var entry: ClassState = _state.class_states[&"artisan"]
	# 60 for bread, 40 for beer, 50 per point of tax, 30 per share of overcrowding.
	assert_almost_eq(entry.satisfaction_target, 60.0 + 40.0 - 50.0 * 0.25, 0.0000001)
	assert_almost_eq(entry.satisfaction_breakdown["bread"], 60.0, 0.0000001)
	assert_almost_eq(entry.satisfaction_breakdown["beer"], 40.0, 0.0000001)
	assert_almost_eq(entry.satisfaction_breakdown["tax"], 12.5, 0.0000001)
	_evaluate(0.5, 0.0, 0.5)
	assert_almost_eq(entry.satisfaction_target, 30.0 + 20.0 - 12.5, 0.0000001)


func test_artisan_overcrowding_uses_its_own_housing_and_weight() -> void:
	_live(0, 20)
	_evaluate(1.0, 0.0, 1.0)
	var entry: ClassState = _state.class_states[&"artisan"]
	# 20 residents in a house of 10 (+4 with both categories met): 6 over, 30 per share.
	assert_eq(entry.housing_capacity, 14)
	assert_almost_eq(entry.overcrowding, 6.0 / 20.0, 0.0000001)
	assert_almost_eq(entry.satisfaction_breakdown["overcrowding"], 6.0 / 20.0 * 30.0, 0.0000001)


func test_worker_and_artisan_satisfaction_are_independent() -> void:
	_live(10, 5)
	_evaluate(1.0, 0.0, 0.0)
	var worker_target: float = _state.satisfaction_target
	assert_almost_eq(worker_target, 100.0 - 0.25 * 40.0, 0.0000001)
	_evaluate(1.0, 0.0, 1.0)
	assert_eq(_state.satisfaction_target, worker_target, "Beer does not touch the workers")
	_evaluate(1.0, 1.0, 1.0)
	assert_almost_eq(_state.satisfaction_target, 100.0 + 4.0 - 10.0, 0.0000001)
	assert_almost_eq(_state.class_states[&"artisan"].satisfaction_target, 87.5, 0.0000001)


func test_artisans_do_not_take_jobs() -> void:
	_state.buildings.append({"definition_id": &"wharf"})
	_live(2, 6)
	WorkersSystem.new().tick(_state, _params)
	assert_eq(_state.employed, 2)
	assert_eq(_state.unemployed, 0)
	_live(0, 6)
	WorkersSystem.new().tick(_state, _params)
	assert_eq(_state.employed, 0)
	assert_eq(_state.unemployed, 0, "Artisans are not unemployed")


func test_housing_capacity_grows_two_per_met_category_up_to_four() -> void:
	_live(0, 1)
	_evaluate(0.0, 0.0, 0.0)
	assert_eq(_state.class_states[&"artisan"].housing_capacity, 10)
	_evaluate(1.0, 0.0, 0.0)
	assert_eq(_state.class_states[&"artisan"].housing_capacity, 12)
	_evaluate(1.0, 0.0, 0.5)
	assert_eq(_state.class_states[&"artisan"].housing_capacity, 14)
	_params = _params_with({&"needs.housing_bonus_per_category": 5})
	_evaluate(1.0, 0.0, 1.0)
	assert_eq(_state.class_states[&"artisan"].housing_capacity, 14, "The class maximum caps the bonus")


func test_each_class_lives_only_in_its_own_housing() -> void:
	_evaluate(0.0)
	assert_eq(NeedsSystem.class_housing_capacity(_state, _params, _context, _workers()), 20)
	assert_eq(NeedsSystem.class_housing_capacity(_state, _params, _context, _artisans()), 10)
	assert_eq(_state.housing_capacity, 30)
	_state.buildings.remove_at(0)
	_evaluate(0.0)
	assert_eq(NeedsSystem.class_housing_capacity(_state, _params, _context, _workers()), 0)
	assert_eq(_state.housing_capacity, 10)


func test_artisan_pays_per_resident_more_than_a_worker() -> void:
	_state.buildings.append({"definition_id": &"wharf", "workers": 4})
	_live(4, 10)
	MoneySystem.new().tick(_state, _params, _context)
	var artisans: float = _state.class_tax_tick[&"artisan"]
	var workers: float = _state.class_tax_tick[&"worker"]
	assert_almost_eq(artisans, 10 * 0.25 * 20 / 60.0, 0.0000001)
	assert_almost_eq(workers, 4 * 0.25 * 11 / 60.0, 0.0000001)
	assert_gt(artisans / 10.0, workers / 4.0, "Per head, an artisan pays more than a worker")


func test_artisan_tax_base_is_configurable_by_role() -> void:
	_params = _params_with({&"class.artisan.tax.base": 30})
	_live(0, 10)
	MoneySystem.new().tick(_state, _params, _context)
	assert_almost_eq(_state.class_tax_tick[&"artisan"], 10 * 0.25 * 30 / 60.0, 0.0000001)


func test_class_states_round_trip() -> void:
	_live(3, 7)
	_evaluate(1.0, 0.0, 1.0)
	_state.class_states[&"artisan"].immigration_fraction = 0.25
	_state.class_states[&"artisan"].satisfaction_departure_age_seconds = 12
	_state.beer_fraction = 0.5
	var copy: EconomyState = EconomyState.from_dict(_state.to_dict())
	assert_eq(copy.population, 10)
	assert_eq(copy.class_states[&"artisan"].population, 7)
	assert_eq(copy.class_states[&"artisan"].to_dict(), _state.class_states[&"artisan"].to_dict())
	assert_eq(copy.beer_fraction, 0.5)
	assert_eq(copy.to_dict(), _state.to_dict())


func test_a_state_saved_before_the_artisans_loads_with_none() -> void:
	var values: Dictionary = _state.to_dict()
	for key: String in ["class_states", "beer_fraction", "beer_demand", "beer_consumed", "beer_coverage"]:
		values.erase(key)
	var old: EconomyState = EconomyState.from_dict(values)
	assert_true(old.class_states.is_empty())
	assert_eq(old.beer_fraction, 0.0)
	var sim: Simulation = Simulation.new(_params, old, 1, _context)
	assert_true(sim.snapshot()["economy"]["class_states"].has(&"artisan"))
	assert_eq(sim.snapshot()["economy"]["class_states"][&"artisan"]["population"], 0)


func test_diagnostics_explain_the_growth_of_each_class() -> void:
	_live(0, 0)
	_state.bread_coverage = 1.0
	_evaluate(1.0, 0.0, 1.0)
	_state.class_states[&"artisan"].satisfaction = 90.0
	var info: Dictionary = NeedsDiagnostics.build(_state, _params, _context)["classes"]
	assert_eq(info[&"artisan"]["growth"]["reason"], &"arriving")
	assert_eq(info[&"artisan"]["population"], 0)
	_state.class_states[&"artisan"].satisfaction = 50.0
	info = NeedsDiagnostics.build(_state, _params, _context)["classes"]
	assert_eq(info[&"artisan"]["growth"]["reason"], &"satisfaction_below_threshold")
	_state.buildings.remove_at(1)
	_state.class_states[&"artisan"].satisfaction = 90.0
	_evaluate(1.0, 0.0, 1.0)
	info = NeedsDiagnostics.build(_state, _params, _context)["classes"]
	assert_eq(info[&"artisan"]["growth"]["reason"], &"no_free_housing")
