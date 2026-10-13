extends GutTest

# Population, satisfaction and emigration are worked out per class (issue #52).

var _catalog: DataCatalog
var _params: Params
var _context: EconomyContext
var _state: EconomyState


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	_params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	_state = EconomyState.new()
	_state.tax_rate = 0.25
	_state.bread_coverage = 1.0
	_state.hunger_smoothed_coverage = 1.0
	_state.buildings.append({"definition_id": &"housing"})
	_state.buildings.append({"definition_id": &"artisan_housing"})
	ClassStates.ensure(_state, _context)
	# Neither class is happy or unhappy enough to move until a test says so.
	_state.satisfaction = 50.0
	_state.satisfaction_target = 50.0
	_set_artisans(0, 50.0)


func _set_artisans(residents: int, satisfaction: float) -> void:
	var entry: ClassState = _state.class_states[&"artisan"]
	_state.population += residents - entry.population
	entry.population = residents
	entry.satisfaction = satisfaction
	entry.satisfaction_target = satisfaction


func _artisans() -> ClassState:
	return _state.class_states[&"artisan"]


func _workers() -> int:
	return _state.population - _artisans().population


# Capacities come from the satisfaction step, which runs just before growth in the tick; the satisfaction the
# test chose is kept, so only growth is under test.
func _grow(seconds: int) -> void:
	var worker: Array[float] = [_state.satisfaction, _state.satisfaction_target]
	var artisan: Array[float] = [_artisans().satisfaction, _artisans().satisfaction_target]
	SatisfactionSystem.new().update_target(_state, _params, _context)
	_state.satisfaction = worker[0]
	_state.satisfaction_target = worker[1]
	_artisans().satisfaction = artisan[0]
	_artisans().satisfaction_target = artisan[1]
	for index: int in range(seconds):
		GrowthSystem.new().tick(_state, _params, _context)


func test_artisans_arrive_only_with_free_artisan_housing() -> void:
	_set_artisans(0, 90.0)
	_grow(60)
	assert_eq(_artisans().population, 2, "Two a minute")
	assert_eq(_workers(), 0, "Workers are not moved by artisans arriving")
	assert_eq(_state.population, 2)
	_state.buildings.remove_at(1)
	_grow(60)
	assert_eq(_artisans().population, 2, "No artisan housing, nobody new")


func test_artisans_stop_arriving_when_their_housing_is_full() -> void:
	_set_artisans(9, 90.0)
	_grow(180)
	# Ten of base plus two for the bread category, which is met.
	assert_eq(_artisans().population, 12)


func test_artisans_arrive_only_at_a_satisfaction_of_75() -> void:
	_set_artisans(0, 74.99)
	_grow(60)
	assert_eq(_artisans().population, 0)
	_set_artisans(0, 75.0)
	_grow(60)
	assert_eq(_artisans().population, 2)


func test_artisans_leave_below_35_and_leave_the_city() -> void:
	_set_artisans(10, 30.0)
	_grow(60)
	assert_eq(_artisans().population, 8, "Two a minute")
	assert_eq(_state.population, 8, "They leave the city, they do not become workers")
	assert_eq(_workers(), 0)


func test_artisans_at_35_and_in_between_neither_leave_nor_arrive() -> void:
	_set_artisans(5, 35.0)
	_grow(60)
	assert_eq(_artisans().population, 5)
	_set_artisans(5, 60.0)
	_grow(60)
	assert_eq(_artisans().population, 5)


func test_hunger_emigration_has_its_own_hysteresis_per_class() -> void:
	_set_artisans(10, 90.0)
	_state.hunger_smoothed_coverage = 0.5
	_grow(1)
	assert_true(_artisans().hunger_emigration_active)
	_state.hunger_smoothed_coverage = 0.7
	_grow(1)
	assert_true(_artisans().hunger_emigration_active, "Still hungry until coverage reaches 0.75")
	_state.hunger_smoothed_coverage = 0.75
	_grow(1)
	assert_false(_artisans().hunger_emigration_active)


func test_hungry_artisans_leave_faster_the_less_bread_there_is() -> void:
	_set_artisans(10, 90.0)
	_state.hunger_smoothed_coverage = 0.0
	_state.bread_coverage = 0.0
	_grow(60)
	# Two a minute, doubled when there is no bread at all.
	assert_eq(_artisans().population, 6)


func test_artisan_emigration_does_not_move_workers() -> void:
	_state.population = 8
	_set_artisans(4, 30.0)
	assert_eq(_workers(), 8)
	_grow(60)
	assert_eq(_workers(), 8)
	assert_eq(_artisans().population, 2)
	assert_eq(_state.population, 10)


func test_worker_growth_is_the_same_with_artisans_present() -> void:
	_state.population = 10
	_state.satisfaction = 90.0
	_state.satisfaction_target = 90.0
	_set_artisans(0, 50.0)
	_grow(60)
	var with_artisan_housing: int = _workers()
	_state.population = 10
	_state.immigration_fraction = 0.0
	_state.buildings.remove_at(1)
	_state.class_states.clear()
	ClassStates.ensure(_state, _context)
	_set_artisans(0, 50.0)
	_grow(60)
	assert_eq(_workers(), with_artisan_housing)
	assert_eq(with_artisan_housing, 14, "Four a minute, as before")


func test_the_city_is_not_stable_while_artisans_are_leaving() -> void:
	var defeat: DefeatSystem = DefeatSystem.new()
	assert_true(defeat.is_city_stable(_state, _params))
	_set_artisans(10, 30.0)
	_grow(31)
	assert_true(_artisans().satisfaction_departure_age_seconds >= 0)
	assert_false(defeat.is_city_stable(_state, _params))
	var window: int = int(_params.get_value(&"defeat.depopulation.stability_window_seconds"))
	_set_artisans(_artisans().population, 60.0)
	_artisans().satisfaction_departure_age_seconds = window
	assert_true(defeat.is_city_stable(_state, _params))


func test_an_empty_class_with_a_hunger_flag_does_not_make_the_city_unstable() -> void:
	_state.hunger_smoothed_coverage = 0.7
	_artisans().hunger_emigration_active = true
	assert_true(DefeatSystem.new().is_city_stable(_state, _params))


func test_a_whole_game_brings_artisans_when_bread_and_beer_are_there() -> void:
	var initial: EconomyState = EconomyState.new()
	initial.money = 100000
	initial.population = 4
	initial.stocks.assign({&"bread": 500, &"beer": 100})
	initial.buildings.append({"definition_id": &"housing", "cell": [1, 1]})
	initial.buildings.append({"definition_id": &"artisan_housing", "cell": [2, 1]})
	var sim: Simulation = Simulation.create_new(_params, initial, 7, _context)
	# A new game starts with 40 loaves and no bakery, so look before they run out.
	for index: int in range(120):
		sim.tick()
	var economy: Dictionary = sim.snapshot()["economy"]
	var artisans: int = economy["class_states"][&"artisan"]["population"]
	assert_gt(artisans, 0, "Artisans moved in")
	assert_true(economy["population"] >= artisans)
	assert_true(artisans <= 14, "Never above the housing with its bonus")
	assert_gt(float(economy["beer_consumed"]), 0.0)
	assert_gt(economy["class_states"][&"artisan"]["satisfaction"], 75.0 - 0.001)
