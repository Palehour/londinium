extends GutTest

const CELL: Vector2i = Vector2i(1, 1)
const NO_JOBS_RATIO_KEY: StringName = &"demolish.no_jobs_refund_ratio"

var _catalog: DataCatalog
var _context: EconomyContext
var _initial: EconomyState
var _cost: int
var _grace: int


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	var params: Params = SimTestParams.isolated_params(_catalog)
	_cost = int(params.get_value(&"building.bakery.cost"))
	_grace = int(params.get_value(&"demolish.refund_grace_seconds"))
	_initial = EconomyState.new()
	_initial.satisfaction = float(params.get_value(&"population.satisfaction.bread_weight"))
	_initial.money = 10000
	_initial.stocks.assign({&"wheat": 0, &"flour": 0, &"bread": 0})


func _sim(role: RoleDef = null) -> Simulation:
	return Simulation.new(SimTestParams.isolated_params(_catalog, role), _initial, 7, _context)


func _ticks(sim: Simulation, count: int) -> void:
	for index: int in range(count):
		sim.tick()


func _money(sim: Simulation) -> int:
	return sim.snapshot()["economy"]["money"]


func _build_and_wait(sim: Simulation, seconds: int) -> void:
	sim.apply_command(BuildCommand.new(_context, &"bakery", CELL))
	_ticks(sim, seconds)


func _demolish(sim: Simulation) -> DemolishCommand:
	var command: DemolishCommand = DemolishCommand.new(CELL)
	sim.apply_command(command)
	sim.tick()
	return command


func test_demolish_within_grace_refunds_full_cost_even_with_workers() -> void:
	_initial.population = 3
	var sim: Simulation = _sim()
	_build_and_wait(sim, _grace)
	assert_gt(sim.snapshot()["economy"]["buildings"][0]["workers"], 0)
	assert_true(_demolish(sim).accepted)
	assert_eq(_money(sim), _initial.money)


func test_demolish_after_grace_with_workers_refunds_half() -> void:
	_initial.population = 3
	var sim: Simulation = _sim()
	_build_and_wait(sim, _grace + 1)
	assert_true(_demolish(sim).accepted)
	assert_eq(_money(sim), _initial.money - _cost + roundi(_cost * 0.5))


func test_bakery_with_jobs_but_no_workers_refunds_full_cost_after_grace() -> void:
	_initial.population = 0
	var sim: Simulation = _sim()
	_build_and_wait(sim, _grace + 30)
	assert_true(_demolish(sim).accepted)
	assert_eq(_money(sim), _initial.money)


func test_building_without_build_time_counts_as_past_grace() -> void:
	_initial.population = 3
	_initial.buildings.append({"definition_id": &"bakery", "cell": [1, 1]})
	var sim: Simulation = _sim()
	sim.tick()
	assert_true(_demolish(sim).accepted)
	assert_eq(_money(sim), _initial.money + roundi(_cost * 0.5))


func test_work_in_progress_is_lost_and_unreserved_stock_kept_with_refund() -> void:
	_initial.population = 3
	_initial.buildings.append({"definition_id": &"bakery", "cell": [1, 1],
		"reserved_input": 0.5, "output_fraction": 0.75})
	_initial.stocks[&"wheat"] = 4
	_initial.stocks[&"bread"] = 2
	var sim: Simulation = _sim()
	sim.tick()
	var stocks_before: Dictionary = sim.snapshot()["economy"]["stocks"].duplicate()
	var demolish: DemolishCommand = DemolishCommand.new(CELL)
	var rebuild: BuildCommand = BuildCommand.new(_context, &"bakery", CELL)
	sim.apply_command(demolish)
	sim.apply_command(rebuild)
	sim.tick()
	assert_true(demolish.accepted)
	assert_true(rebuild.accepted)
	assert_eq(sim.snapshot()["economy"]["stocks"], stocks_before)
	var building: Dictionary = sim.snapshot()["economy"]["buildings"][0]
	assert_eq(building["reserved_input"], 0.0)
	assert_eq(building["output_fraction"], 0.0)


func test_role_modifiers_change_ratio_and_grace() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"demolish.refund_ratio", &"set", 0.25),
		Modifier.new(&"demolish.refund_grace_seconds", &"set", 2)])
	_initial.population = 3
	var sim: Simulation = _sim(role)
	_build_and_wait(sim, 3)
	assert_true(_demolish(sim).accepted)
	assert_eq(_money(sim), _initial.money - _cost + roundi(_cost * 0.25))


func test_refund_is_subtracted_from_construction_spending() -> void:
	var sim: Simulation = _sim()
	sim.apply_command(BuildCommand.new(_context, &"bakery", CELL))
	sim.apply_command(DemolishCommand.new(CELL))
	sim.tick()
	assert_eq(_money(sim), _initial.money)
	assert_eq(sim.snapshot()["stats"]["construction_spent_per_minute"], 0.0)


func _build_housing_and_wait(sim: Simulation, seconds: int) -> void:
	sim.apply_command(BuildCommand.new(_context, &"housing", CELL))
	_ticks(sim, seconds)


func _housing_cost() -> int:
	return int(SimTestParams.isolated_params(_catalog).get_value(&"building.housing.cost"))


func test_housing_within_grace_refunds_full_cost() -> void:
	var sim: Simulation = _sim()
	_build_housing_and_wait(sim, _grace)
	assert_true(_demolish(sim).accepted)
	assert_eq(_money(sim), _initial.money)


func test_housing_after_grace_refunds_the_no_jobs_fraction() -> void:
	var sim: Simulation = _sim()
	_build_housing_and_wait(sim, _grace + 1)
	assert_true(_demolish(sim).accepted)
	assert_eq(_money(sim), _initial.money - _housing_cost() + roundi(_housing_cost() * 0.5))


func test_initial_housing_without_build_time_refunds_the_no_jobs_fraction() -> void:
	_initial.buildings.append({"definition_id": &"housing", "cell": [1, 1]})
	var sim: Simulation = _sim()
	sim.tick()
	assert_true(_demolish(sim).accepted)
	assert_eq(_money(sim), _initial.money + roundi(_housing_cost() * 0.5))


func test_role_modifier_changes_the_no_jobs_ratio() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(NO_JOBS_RATIO_KEY, &"set", 0.25)])
	var sim: Simulation = _sim(role)
	_build_housing_and_wait(sim, _grace + 1)
	assert_true(_demolish(sim).accepted)
	assert_eq(_money(sim), _initial.money - _housing_cost() + roundi(_housing_cost() * 0.25))


func test_building_whose_jobs_a_role_zeroes_uses_the_no_jobs_ratio() -> void:
	# A role that gives the bakery zero job slots turns it into a jobless building.
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"building.bakery.jobs", &"set", 0)])
	_initial.population = 3
	var sim: Simulation = _sim(role)
	_build_and_wait(sim, _grace + 30)
	assert_true(_demolish(sim).accepted)
	assert_eq(_money(sim), _initial.money - _cost + roundi(_cost * 0.5))


func _bankrupt_sim() -> Simulation:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"defeat.grace_seconds", &"set", 0),
		Modifier.new(&"defeat.bankruptcy.duration_seconds", &"set", 2)])
	_initial.money = -10
	_initial.population = 3
	_initial.buildings.append({"definition_id": &"bakery", "cell": [1, 1]})
	return _sim(role)


func test_without_selling_a_building_bankruptcy_ends_the_game() -> void:
	var sim: Simulation = _bankrupt_sim()
	_ticks(sim, 2)
	assert_eq(sim.snapshot()["economy"]["defeat_causes"], [&"bankruptcy"])


func test_selling_a_building_gets_out_of_the_red_before_bankruptcy() -> void:
	var sim: Simulation = _bankrupt_sim()
	sim.tick()
	assert_eq(sim.snapshot()["economy"]["bankruptcy"]["status"], &"warning")
	assert_true(_demolish(sim).accepted)
	var state: Dictionary = sim.snapshot()["economy"]
	assert_eq(state["money"], -10 + roundi(_cost * 0.5))
	assert_eq(state["bankruptcy"]["status"], &"ok")
	assert_true(state["defeat_causes"].is_empty())
