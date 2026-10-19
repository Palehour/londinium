extends GutTest

class LoseMoneyCommand extends SimulationCommand:
	func execute(state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
		state.money = -1000


func _simulation(enabled: bool = true) -> Simulation:
	var catalog: DataCatalog = DataLoader.new().load_all().catalog
	var role: RoleDef = RoleDef.new()
	for id: String in ["population", "artisans", "revenue"]:
		role.modifiers.append(Modifier.new(StringName("victory.victorian_demo.%s.threshold" % id), &"set", 0))
	role.modifiers.append(Modifier.new(&"victory.victorian_demo.revenue.required_minutes", &"set", 1))
	for id: String in ["population", "artisans"]:
		role.modifiers.append(Modifier.new(StringName("victory.victorian_demo.%s.duration_seconds" % id), &"set", 1))
	role.modifiers.append(Modifier.new(&"defeat.grace_seconds", &"set", 0))
	role.modifiers.append(Modifier.new(&"defeat.bankruptcy.duration_seconds", &"set", 1))
	var state: EconomyState = EconomyState.new()
	state.money = 100000
	state.population = 20
	state.stocks[&"bread"] = 10000
	var stages: Array[Dictionary] = []
	if enabled:
		stages.assign(catalog.scenarios[&"victorian_demo"]["stages"])
	return Simulation.new(Params.new(catalog, role), state, 42,
		EconomyContext.new(catalog, catalog.maps[&"whitechapel_1850s"]), [], stages)


func test_same_seed_and_commands_produce_same_victory_without_changing_economy() -> void:
	var first: Simulation = _simulation()
	var replay: Simulation = _simulation()
	var disabled: Simulation = _simulation(false)
	for tick_index: int in range(60):
		first.tick()
		replay.tick()
		disabled.tick()
		assert_eq(first.snapshot(), replay.snapshot())
		var economy: Dictionary = first.snapshot()["economy"]
		var baseline: Dictionary = disabled.snapshot()["economy"]
		economy.erase("victory")
		baseline.erase("victory")
		assert_eq(economy, baseline)
		assert_eq(first.get_rng_state(), disabled.get_rng_state())
		if tick_index < 59:
			assert_false(first.snapshot()["victory"]["won"])
	assert_true(first.snapshot()["victory"]["won"])
	assert_eq(first.snapshot()["victory"]["won_tick"], 60)
	assert_false(disabled.snapshot()["victory"]["enabled"])


func test_commands_work_after_victory_and_later_defeat_keeps_record() -> void:
	var sim: Simulation = _simulation()
	for tick_index: int in range(60):
		sim.tick()
	var command: SetTaxCommand = SetTaxCommand.new(0.4)
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted)
	assert_eq(sim.snapshot()["tick_count"], 61)
	assert_eq(sim.snapshot()["economy"]["tax_rate"], 0.4)
	sim.apply_command(LoseMoneyCommand.new())
	sim.tick()
	assert_eq(sim.snapshot()["defeat"]["causes"], [&"bankruptcy"])
	assert_true(sim.snapshot()["victory"]["won"])
	assert_eq(sim.snapshot()["victory"]["won_tick"], 60)
	var final_snapshot: Dictionary = sim.snapshot()
	sim.tick()
	assert_eq(sim.snapshot(), final_snapshot)
	var refused: SetTaxCommand = SetTaxCommand.new(0.5)
	sim.apply_command(refused)
	assert_false(refused.accepted)


func test_defeat_on_the_winning_tick_prevents_a_victory_record() -> void:
	var sim: Simulation = _simulation()
	for tick_index: int in range(59):
		sim.tick()
	sim.apply_command(LoseMoneyCommand.new())
	sim.tick()
	assert_eq(sim.snapshot()["tick_count"], 60)
	assert_eq(sim.snapshot()["defeat"]["causes"], [&"bankruptcy"])
	assert_false(sim.snapshot()["victory"]["won"])
	assert_eq(sim.snapshot()["victory"]["won_tick"], -1)
