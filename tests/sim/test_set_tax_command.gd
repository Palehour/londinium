extends GutTest

var _params: Params
var _context: EconomyContext
var _state: EconomyState


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	# Pinned so these arithmetic checks do not move when Mason retunes the tax base in data/.
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"population.tax.base_per_employed_worker_per_minute", &"set", 8))
	_params = Params.new(loaded.catalog, role)
	_context = EconomyContext.new(loaded.catalog, loaded.catalog.maps[&"whitechapel_1850s"])
	_state = EconomyState.new()
	_state.population = 3
	_state.stocks[&"bread"] = 100
	_state.buildings.assign([{"definition_id": &"bakery", "cell": [1, 1]},
		{"definition_id": &"housing", "cell": [2, 1]}])


func test_tax_is_deferred_fifo_and_affects_satisfaction_and_money_same_tick() -> void:
	var sim: Simulation = Simulation.new(_params, _state, 42, _context)
	var first: SetTaxCommand = SetTaxCommand.new(0.0)
	var second: SetTaxCommand = SetTaxCommand.new(1.0)
	var before: Dictionary = sim.snapshot()
	sim.apply_command(first)
	sim.apply_command(second)
	assert_eq(sim.snapshot(), before)
	assert_false(first.accepted)
	assert_eq(first.reason, &"pending")
	sim.tick()
	assert_true(first.accepted)
	assert_true(second.accepted)
	assert_eq(second.reason, &"")
	var after: Dictionary = sim.snapshot()["economy"]
	assert_eq(after["tax_rate"], 1.0)
	assert_eq(after["satisfaction_target"], 60.0)
	assert_eq(after["satisfaction"], 6.0)
	assert_almost_eq(after["tax_fraction"], 24.0 / 60.0, 0.00000001)
	sim.apply_command(SetTaxCommand.new(0.0))
	sim.tick()
	sim.tick()
	assert_eq(sim.snapshot()["economy"]["tax_rate"], 0.0, "Old commands must not execute again")


func test_invalid_rates_are_rejected_without_changing_state() -> void:
	for rate: float in [-0.01, 1.01, INF, -INF, NAN]:
		_state.tax_rate = 0.25
		var before: Dictionary = _state.to_dict()
		var command: SetTaxCommand = SetTaxCommand.new(rate)
		command.execute(_state, _params, RandomNumberGenerator.new())
		assert_false(command.accepted)
		assert_eq(command.reason, &"invalid_tax_rate")
		assert_eq(_state.to_dict(), before)


func test_initial_tax_uses_params_and_saved_zero_rate_is_preserved() -> void:
	var sim: Simulation = Simulation.new(_params, _state, 42, _context)
	assert_eq(sim.snapshot()["economy"]["tax_rate"], 0.25)
	_state.tax_rate = 0.0
	sim = Simulation.new(_params, _state, 42, _context)
	assert_eq(sim.snapshot()["economy"]["tax_rate"], 0.0)


func test_role_modifier_controls_default_tax_and_initial_snapshot_employment() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"population.tax.rate", &"set", 0.5))
	_params = Params.new(loaded.catalog, role)
	var sim: Simulation = Simulation.new(_params, _state, 42, _context)
	var initial: Dictionary = sim.snapshot()["economy"]
	assert_eq(initial["tax_rate"], 0.5)
	assert_eq(initial["employed"], 0)
	assert_eq(initial["unemployed"], 3)
	sim.tick()
	assert_eq(sim.snapshot()["economy"]["employed"], 3)


func test_round_trip_preserves_every_nonzero_population_and_finance_field() -> void:
	_state.tax_rate = 0.0
	_state.bread_fraction = 0.7
	_state.bread_demand = 0.5
	_state.bread_consumed = 0.4
	_state.bread_coverage = 0.8
	_state.satisfaction = 55.0
	_state.satisfaction_target = 70.0
	_state.satisfaction_breakdown.assign({"bread": 80.0, "tea": 0.0, "tax": 10.0, "overcrowding": 15.0})
	_state.housing_capacity = 20
	_state.overcrowding = 0.5
	_state.employed = 2
	_state.unemployed = 1
	_state.immigration_fraction = 0.3
	_state.emigration_fraction = 0.4
	_state.tax_fraction = 0.5
	_state.wage_fraction = 0.6
	_state.upkeep_fraction = 0.7
	var serialized: Dictionary = _state.to_dict()
	var restored: EconomyState = EconomyState.from_dict(serialized)
	assert_eq(restored.to_dict(), serialized)
	serialized["satisfaction_breakdown"]["tax"] = 99.0
	assert_eq(restored.satisfaction_breakdown["tax"], 10.0)


func test_full_loop_replay_and_snapshot_round_trip_are_deterministic() -> void:
	_state.money = 10000
	_state.population = 10
	_state.buildings.append({"definition_id": &"mill", "cell": [3, 1]})
	_state.buildings.append({"definition_id": &"wharf", "cell": [0, 7]})
	var first: Simulation = Simulation.new(_params, _state, 73, _context)
	var second: Simulation = Simulation.new(_params, _state, 73, _context)
	for index: int in range(900):
		if index % 60 == 0:
			var rate: float = float(index % 180) / 180.0
			first.apply_command(SetTaxCommand.new(rate))
			second.apply_command(SetTaxCommand.new(rate))
		first.tick()
		second.tick()
		assert_eq(first.snapshot(), second.snapshot())
	var snapshot: Dictionary = first.snapshot()
	var restored: EconomyState = EconomyState.from_dict(snapshot["economy"])
	assert_eq(restored.to_dict(), snapshot["economy"])
	var reconstructed: Simulation = Simulation.new(_params, restored, 73, _context)
	assert_eq(reconstructed.snapshot()["economy"], snapshot["economy"])
	restored.satisfaction_breakdown["tea"] = 99.0
	restored.bread_fraction = 99.0
	snapshot["economy"]["buildings"].clear()
	snapshot["economy"]["satisfaction_breakdown"]["tax"] = 99.0
	assert_eq(first.snapshot(), second.snapshot())
	assert_ne(reconstructed.snapshot()["economy"]["satisfaction_breakdown"]["tea"], 99.0)
