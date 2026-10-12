extends GutTest

var _catalog: DataCatalog
var _params: Params
var _context: EconomyContext


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])


func test_snap_strict_boundary_from_both_sides_and_role_modifier() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"population.satisfaction.smoothing_per_second", &"set", 0.5),
		Modifier.new(&"population.satisfaction.snap_epsilon", &"set", 0.125)])
	var params: Params = Params.new(_catalog, role)
	for direction: float in [-1.0, 1.0]:
		for difference: float in [0.125, 0.25, 0.5]:
			var state: EconomyState = EconomyState.new()
			state.population = 20
			state.tax_rate = 1.0
			state.satisfaction = 30.0 + direction * difference
			SatisfactionSystem.new().tick(state, params, _context)
			var expected: float = 30.0 if difference < 0.25 else 30.0 + direction * difference * 0.5
			assert_eq(state.satisfaction, expected)
			assert_eq(state.satisfaction_breakdown["smoothed"], expected)


func test_real_epsilon_converges_exactly_to_30_and_round_trips() -> void:
	assert_eq(_params.get_value(&"population.satisfaction.snap_epsilon"), 0.01)
	for starting: float in [0.0, 60.0]:
		var state: EconomyState = EconomyState.new()
		state.population = 20
		state.tax_rate = 1.0
		state.satisfaction = starting
		for index: int in range(30):
			SatisfactionSystem.new().tick(state, _params, _context)
		var restored: EconomyState = EconomyState.from_dict(state.to_dict())
		for index: int in range(90):
			SatisfactionSystem.new().tick(state, _params, _context)
			SatisfactionSystem.new().tick(restored, _params, _context)
			assert_eq(restored.to_dict(), state.to_dict())
		assert_eq(state.satisfaction, 30.0)
		assert_eq(state.overcrowding, 1.0)


func test_satisfaction_uses_shared_coverage_and_tick_updates_it_once() -> void:
	var state: EconomyState = EconomyState.new()
	state.population = 20
	state.tax_rate = 0.0
	state.bread_coverage = 0.0
	state.hunger_smoothed_coverage = 0.8
	state.defeat_initialized = true
	SatisfactionSystem.new().update_target(state, _params, _context)
	assert_eq(state.satisfaction_breakdown["bread"], 80.0)
	assert_eq(state.satisfaction_target, 50.0)
	var sim: Simulation = Simulation.new(_params, state, 42, _context)
	assert_eq(sim.snapshot()["economy"]["hunger_smoothed_coverage"], 0.8)
	sim.tick()
	var current: Dictionary = sim.snapshot()["economy"]
	var expected: float = 0.8 * (1.0 - float(_params.get_value(&"defeat.hunger.smoothing")))
	assert_almost_eq(float(current["hunger_smoothed_coverage"]), expected, 0.00000001)
	assert_almost_eq(float(current["satisfaction_target"]), expected * 100.0 - 30.0, 0.00000001)


func test_new_city_initializes_shared_coverage_before_target() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"population.initial_bread", &"set", 0))
	var state: EconomyState = EconomyState.new()
	state.population = 20
	state.hunger_smoothed_coverage = 1.0
	var sim: Simulation = Simulation.create_new(Params.new(_catalog, role), state, 42, _context)
	var current: Dictionary = sim.snapshot()["economy"]
	assert_eq(current["hunger_smoothed_coverage"], 0.0)
	assert_eq(current["satisfaction_target"], 0.0)
	assert_eq(current["satisfaction"], 0.0)


func test_bailey_real_chain_without_housing_survives_maximum_tax_and_stabilizes_at_20_with_09() -> void:
	for tax: float in [1.0, 0.9]:
		var state: EconomyState = EconomyState.new()
		state.population = 30
		state.money = 10000
		var sim: Simulation = Simulation.create_new(_params, state, 42, _context)
		var wharf: BuildCommand = BuildCommand.new(_context, &"wharf", Vector2i(0, 7))
		var mill: BuildCommand = BuildCommand.new(_context, &"mill", Vector2i(0, 0))
		var bakery: BuildCommand = BuildCommand.new(_context, &"bakery", Vector2i(1, 0))
		sim.apply_command(wharf)
		sim.apply_command(mill)
		sim.apply_command(bakery)
		for index: int in range(300):
			sim.tick()
		assert_true(wharf.accepted)
		assert_true(mill.accepted)
		assert_true(bakery.accepted)
		var change_tax: SetTaxCommand = SetTaxCommand.new(tax)
		sim.apply_command(change_tax)
		var threshold: float = float(_params.get_value(&"population.growth.emigration_threshold"))
		var saw_emigration: bool = false
		var stabilization_tick: int = -1
		for index: int in range(3300):
			sim.tick()
			var current: Dictionary = sim.snapshot()["economy"]
			if tax == 1.0:
				var active: bool = bool(current["hunger_emigration_active"]) or (float(current["satisfaction"]) < threshold and float(current["satisfaction_target"]) < threshold)
				if active:
					saw_emigration = true
					stabilization_tick = -1
				elif saw_emigration and stabilization_tick < 0:
					# Record the start of the final uninterrupted stable period.
					stabilization_tick = index + 301
				if index + 301 >= 468:
					assert_eq(current["population"], 19)
					assert_eq(current["satisfaction_target"], 30.0)
					if index + 301 >= 531:
						assert_eq(current["satisfaction"], 30.0)
					assert_eq(current["emigration_fraction"], 0.0)
					assert_false(current["hunger_emigration_active"])
			assert_true(current["defeat_causes"].is_empty())
			assert_gt(current["population"], 0)
			assert_eq(current["housing_capacity"], 0)
			assert_eq(current["overcrowding"], 1.0)
			if tax == 0.9 and index >= 2700:
				assert_eq(current["population"], 20)
		assert_true(change_tax.accepted)
		var final_state: Dictionary = sim.snapshot()["economy"]
		assert_eq(sim.snapshot()["tick_count"], 3600)
		assert_false(final_state["hunger_emigration_active"])
		assert_eq(final_state["emigration_fraction"], 0.0)
		assert_eq(final_state["depopulation"]["status"], &"ok")
		if tax == 1.0:
			assert_true(saw_emigration, "The real chain must exercise the satisfaction crisis")
			assert_eq(stabilization_tick, 468)
			assert_eq(final_state["population"], 19)
			assert_eq(final_state["satisfaction_target"], 30.0)
			assert_eq(final_state["satisfaction"], 30.0)
		else:
			assert_eq(final_state["population"], 20)
			assert_almost_eq(float(final_state["satisfaction_target"]), 33.743789163801793, 0.00000001)


func test_coverage_snap_strict_boundary_from_both_sides_and_role_modifier() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"defeat.hunger.smoothing", &"set", 0.5),
		Modifier.new(&"population.hunger_coverage_snap_epsilon", &"set", 0.125)])
	var params: Params = Params.new(_catalog, role)
	for direction: float in [-1.0, 1.0]:
		for difference: float in [0.125, 0.25, 0.5]:
			var state: EconomyState = EconomyState.new()
			state.defeat_initialized = true
			state.bread_coverage = 0.5
			state.hunger_smoothed_coverage = 0.5 + direction * difference
			DefeatSystem.new().update_hunger_coverage(state, params)
			var expected: float = 0.5 if difference < 0.25 else 0.5 + direction * difference * 0.5
			assert_eq(state.hunger_smoothed_coverage, expected)


func test_coverage_snap_real_epsilon_and_snapshot_continuation() -> void:
	assert_eq(_params.get_value(&"population.hunger_coverage_snap_epsilon"), 0.01)
	var params: Params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	for target: float in [0.0, 1.0]:
		var state: EconomyState = EconomyState.new()
		state.defeat_initialized = true
		state.bread_coverage = target
		state.hunger_smoothed_coverage = 1.0 - target
		for index: int in range(30):
			DefeatSystem.new().update_hunger_coverage(state, params)
		assert_ne(state.hunger_smoothed_coverage, target, "Save before the default snap occurs")
		var restored: EconomyState = EconomyState.from_dict(state.to_dict())
		assert_eq(restored.hunger_smoothed_coverage, state.hunger_smoothed_coverage)
		for index: int in range(20):
			DefeatSystem.new().update_hunger_coverage(state, params)
			DefeatSystem.new().update_hunger_coverage(restored, params)
			assert_eq(restored.to_dict(), state.to_dict())
			if index >= 13:
				assert_eq(state.hunger_smoothed_coverage, target, "Default snap occurs exactly at tick 44")
			else:
				assert_ne(state.hunger_smoothed_coverage, target)
		assert_eq(state.hunger_smoothed_coverage, target)


func test_real_chain_with_one_house_and_maximum_tax_finishes_with_26_residents() -> void:
	var state: EconomyState = EconomyState.new()
	state.population = 30
	state.money = 10000
	var sim: Simulation = Simulation.create_new(_params, state, 42, _context)
	var commands: Array[BuildCommand] = [
		BuildCommand.new(_context, &"wharf", Vector2i(0, 7)),
		BuildCommand.new(_context, &"mill", Vector2i(0, 0)),
		BuildCommand.new(_context, &"bakery", Vector2i(1, 0)),
		BuildCommand.new(_context, &"housing", Vector2i(2, 0))]
	for command: BuildCommand in commands:
		sim.apply_command(command)
	for index: int in range(300):
		sim.tick()
	for command: BuildCommand in commands:
		assert_true(command.accepted)
	var change_tax: SetTaxCommand = SetTaxCommand.new(1.0)
	sim.apply_command(change_tax)
	var decay: float = float(_params.get_value(&"defeat.depopulation.peak_decay_per_minute"))
	var defeat: DefeatSystem = DefeatSystem.new()
	var previous_peak: float = sim.snapshot()["economy"]["population_peak"]
	for index: int in range(3300):
		sim.tick()
		var current: Dictionary = sim.snapshot()["economy"]
		assert_true(current["defeat_causes"].is_empty())
		assert_gt(current["population"], 0)
		assert_eq(current["housing_capacity"], 20)
		if index >= 2700:
			assert_eq(current["population"], 26)
			# Measured on real departures: sustained stability, no flicker at the satisfaction edge.
			assert_true(defeat.is_city_stable(EconomyState.from_dict(current), _params))
			assert_almost_eq(float(current["population_peak"]),
				maxf(26.0, previous_peak * pow(1.0 - decay, 1.0 / 60.0)), 0.00000001)
		previous_peak = current["population_peak"]
	assert_true(change_tax.accepted)
	assert_eq(sim.snapshot()["tick_count"], 3600)
	assert_eq(sim.snapshot()["economy"]["population"], 26)
