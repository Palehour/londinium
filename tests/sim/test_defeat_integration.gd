extends GutTest


class SupplyBreadCommand extends SimulationCommand:
	func execute(state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
		state.stocks[&"bread"] = 200


class EnqueueAtDefeatCommand extends SimulationCommand:
	var target: WeakRef
	var pending: SimulationCommand = SetTaxCommand.new(0.5)


	func execute(_state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
		var sim: Simulation = target.get_ref() as Simulation
		sim.apply_command(pending)


func _params(catalog: DataCatalog) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"defeat.grace_seconds", &"set", 0),
		Modifier.new(&"defeat.bankruptcy.duration_seconds", &"set", 1),
		Modifier.new(&"population.growth.emigration_per_minute", &"set", 0)])
	return Params.new(catalog, role)


func test_money_step_triggers_terminal_defeat_and_rejects_queued_commands() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	var context: EconomyContext = EconomyContext.new(loaded.catalog, loaded.catalog.maps[&"whitechapel_1850s"])
	var state: EconomyState = EconomyState.new()
	state.population = 20
	state.stocks[&"bread"] = 100
	state.buildings.append({"definition_id": &"housing", "cell": [1, 1]})
	state.upkeep_fraction = 0.99
	var sim: Simulation = Simulation.new(_params(loaded.catalog), state, 42, context)
	var enqueue: EnqueueAtDefeatCommand = EnqueueAtDefeatCommand.new()
	enqueue.target = weakref(sim)
	sim.apply_command(enqueue)
	sim.tick()
	var final_state: Dictionary = sim.snapshot()
	assert_eq(final_state["economy"]["money"], -1)
	assert_eq(final_state["economy"]["defeat_causes"], [&"bankruptcy"])
	assert_eq(final_state["tick_count"], 1)
	assert_false(enqueue.pending.accepted)
	assert_eq(enqueue.pending.reason, &"simulation_defeated")
	var later: SetTaxCommand = SetTaxCommand.new(0.25)
	sim.apply_command(later)
	assert_false(later.accepted)
	assert_eq(later.reason, &"simulation_defeated")
	for index: int in range(900):
		sim.tick()
	assert_eq(sim.snapshot(), final_state)
	var restored: EconomyState = EconomyState.from_dict(final_state["economy"])
	var resumed: Simulation = Simulation.new(_params(loaded.catalog), restored, 42, context)
	var before: Dictionary = resumed.snapshot()
	resumed.tick()
	assert_eq(resumed.snapshot(), before)


func test_900_tick_replay_matches_snapshots_with_warning_recovery_and_defeat() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	var context: EconomyContext = EconomyContext.new(loaded.catalog, loaded.catalog.maps[&"whitechapel_1850s"])
	var state: EconomyState = EconomyState.new()
	state.population = 100
	state.money = 10000
	state.stocks[&"bread"] = 200
	state.buildings.append({"definition_id": &"housing", "cell": [1, 1]})
	var first: Simulation = Simulation.new(_params(loaded.catalog), state, 123, context)
	var second: Simulation = Simulation.new(_params(loaded.catalog), state, 123, context)
	var saw_warning: bool = false
	var saw_recovery: bool = false
	for index: int in range(900):
		if index == 180:
			first.apply_command(SupplyBreadCommand.new())
			second.apply_command(SupplyBreadCommand.new())
		if index % 60 == 0:
			first.apply_command(SetTaxCommand.new(0.25))
			second.apply_command(SetTaxCommand.new(0.25))
		first.tick()
		second.tick()
		assert_eq(first.snapshot(), second.snapshot())
		var status: StringName = first.snapshot()["economy"]["hunger"]["status"]
		saw_recovery = saw_recovery or (saw_warning and status == &"ok")
		saw_warning = saw_warning or status == &"warning"
	assert_true(saw_warning)
	assert_true(saw_recovery)
	assert_eq(first.snapshot()["economy"]["defeat_causes"], [&"hunger"])
	var values: Dictionary = first.snapshot()["economy"]
	values["hunger"]["status"] = &"ok"
	values["defeat_causes"].clear()
	assert_eq(first.snapshot(), second.snapshot())


func test_snapshot_reports_simultaneous_causes_in_stable_order() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	var context: EconomyContext = EconomyContext.new(loaded.catalog, loaded.catalog.maps[&"whitechapel_1850s"])
	var state: EconomyState = EconomyState.new()
	state.population = 9
	state.population_peak = 100
	state.depopulation_active = true
	state.defeat_initialized = true
	state.hunger_smoothed_coverage = 0.0
	state.money = -1
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"defeat.grace_seconds", &"set", 0),
		Modifier.new(&"defeat.bankruptcy.duration_seconds", &"set", 1),
		Modifier.new(&"defeat.hunger.duration_seconds", &"set", 1),
		Modifier.new(&"defeat.depopulation.duration_seconds", &"set", 1)])
	var sim: Simulation = Simulation.new(Params.new(loaded.catalog, role), state, 42, context)
	sim.tick()
	assert_eq(sim.snapshot()["economy"]["defeat_causes"], [&"bankruptcy", &"hunger", &"depopulation"])
