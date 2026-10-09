extends GutTest


class AddMoneyCommand extends SimulationCommand:
	func execute(state: EconomyState, params: Params, _rng: RandomNumberGenerator) -> void:
		state.money += int(params.get_value(&"building.bakery.cost"))


class DoubleMoneyCommand extends SimulationCommand:
	func execute(state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
		state.money *= 2


class RandomStockCommand extends SimulationCommand:
	func execute(state: EconomyState, _params: Params, generator: RandomNumberGenerator) -> void:
		state.stocks[&"wheat"] += generator.randi_range(1, 10)


class ContextProbeCommand extends SimulationCommand:
	var context: EconomyContext
	var context_received: bool = false
	var executed_context_id: int = 0


	func use_context(value: EconomyContext) -> void:
		context = value
		context_received = true


	func execute(_state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
		accepted = context_received
		executed_context_id = context.get_instance_id() if context != null else 0


class EnqueueCommand extends SimulationCommand:
	var target: WeakRef


	func _init(sim: Simulation) -> void:
		target = weakref(sim)


	func execute(_state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
		var sim: Simulation = target.get_ref() as Simulation
		sim.apply_command(AddMoneyCommand.new())


var _params: Params
var _initial: EconomyState


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
	_initial = EconomyState.new()
	_initial.stocks[&"wheat"] = 0
	_initial.money = 7
	_initial.population = 12
	_initial.buildings.append({"definition_id": &"bakery", "cell": [2, 3]})


func test_commands_wait_for_tick_run_in_fifo_order_and_only_once() -> void:
	var sim: Simulation = Simulation.new(_params, _initial, 123)
	var before: Dictionary = sim.snapshot()
	sim.apply_command(AddMoneyCommand.new())
	sim.apply_command(DoubleMoneyCommand.new())
	assert_eq(sim.snapshot(), before, "Enqueueing must not execute commands")
	sim.tick()
	var expected_money: int = (7 + int(_params.get_value(&"building.bakery.cost"))) * 2
	assert_eq(sim.snapshot()["economy"]["money"], expected_money)
	assert_eq(sim.snapshot()["tick_count"], 1)
	sim.tick()
	assert_eq(sim.snapshot()["economy"]["money"], expected_money)
	assert_eq(sim.snapshot()["tick_count"], 2)
	assert_typeof(sim.snapshot()["economy"]["money"], TYPE_INT)


func test_commands_enqueued_during_tick_wait_for_next_tick() -> void:
	var sim: Simulation = Simulation.new(_params, _initial, 123)
	sim.apply_command(EnqueueCommand.new(sim))
	sim.tick()
	assert_eq(sim.snapshot()["economy"]["money"], 7)
	sim.tick()
	assert_eq(sim.snapshot()["economy"]["money"], 7 + int(_params.get_value(&"building.bakery.cost")))
	sim.tick()
	assert_eq(sim.snapshot()["economy"]["money"], 7 + int(_params.get_value(&"building.bakery.cost")))


func test_same_seed_and_command_schedule_match_after_900_ticks() -> void:
	var first: Simulation = Simulation.new(_params, _initial, 456)
	var second: Simulation = Simulation.new(_params, _initial, 456)
	var initial_rng_state: int = first.snapshot()["rng_state"]
	for tick_index: int in range(900):
		if tick_index % 60 == 0:
			for sim: Simulation in [first, second]:
				sim.apply_command(RandomStockCommand.new())
				sim.apply_command(AddMoneyCommand.new())
		first.tick()
		second.tick()
	assert_eq(first.snapshot(), second.snapshot())
	assert_eq(first.snapshot()["tick_count"], 900)
	assert_ne(first.snapshot()["rng_state"], initial_rng_state, "Replay exercises the owned RNG")
	assert_gt(first.snapshot()["economy"]["stocks"][&"wheat"], 0)
	assert_eq(first.snapshot()["economy"]["population"], _initial.population)
	assert_eq(first.snapshot()["economy"]["buildings"], _initial.buildings)


func test_900_ticks_take_less_than_one_second() -> void:
	var sim: Simulation = Simulation.new(_params, _initial, 456)
	# Preparation is excluded; the first tick processes a batch of 900 commands.
	for index: int in range(900):
		sim.apply_command(RandomStockCommand.new())
	var started: int = Time.get_ticks_usec()
	for index: int in range(900):
		sim.tick()
	var elapsed: int = Time.get_ticks_usec() - started
	print("900 simulation ticks: %d us" % elapsed)
	assert_lt(elapsed, 1000000, "900 ticks must finish in under one second")
	assert_eq(sim.snapshot()["tick_count"], 900)
	assert_gte(sim.snapshot()["economy"]["stocks"][&"wheat"], 900)


func test_snapshots_do_not_mutate_state_or_consume_rng() -> void:
	var sim: Simulation = Simulation.new(_params, _initial, 123)
	var expected: Dictionary = sim.snapshot()
	var detached: Dictionary = sim.snapshot()
	detached["economy"]["stocks"][&"wheat"] = 99
	detached["economy"]["buildings"][0]["cell"][0] = 99
	detached["economy"]["buildings"].clear()
	detached["economy"]["money"] = 99
	detached["economy"]["population"] = 99
	detached["rng_state"] = 99
	assert_eq(sim.snapshot(), expected)
	assert_eq(sim.snapshot(), expected, "Reading again must not consume RNG")
	assert_eq(sim.get_rng_state(), expected["rng_state"])


func test_initial_state_and_rng_are_independent_between_simulations() -> void:
	var first: Simulation = Simulation.new(_params, _initial, 123)
	var second: Simulation = Simulation.new(_params, _initial, 123)
	var expected: Dictionary = second.snapshot()
	_initial.stocks[&"wheat"] = 99
	_initial.buildings[0]["cell"][0] = 99
	_initial.money = 99
	_initial.population = 99
	first.apply_command(RandomStockCommand.new())
	first.tick()
	assert_eq(second.snapshot(), expected)
	assert_ne(first.snapshot(), expected)
	assert_ne(first.snapshot()["rng_state"], second.snapshot()["rng_state"])


func test_seed_controls_random_sequence() -> void:
	var first: Simulation = Simulation.new(_params, _initial, 123)
	var second: Simulation = Simulation.new(_params, _initial, 124)
	var first_draws: Array[int] = []
	var second_draws: Array[int] = []
	for index: int in range(10):
		first.apply_command(RandomStockCommand.new())
		second.apply_command(RandomStockCommand.new())
		first.tick()
		second.tick()
		first_draws.append(first.snapshot()["economy"]["stocks"][&"wheat"])
		second_draws.append(second.snapshot()["economy"]["stocks"][&"wheat"])
	assert_ne(first_draws, second_draws)
	assert_eq(first.snapshot()["seed"], 123)
	assert_eq(second.snapshot()["seed"], 124)


func test_empty_ticks_only_advance_time() -> void:
	var sim: Simulation = Simulation.new(_params, _initial, 123)
	var before: Dictionary = sim.snapshot()
	for index: int in range(900):
		sim.tick()
	var expected: Dictionary = before.duplicate(true)
	expected["tick_count"] = 900
	assert_eq(sim.snapshot(), expected, "No economic system or artificial RNG advancement")


func test_economy_state_round_trip_copies_nested_values() -> void:
	var serialized: Dictionary = _initial.to_dict()
	var restored: EconomyState = EconomyState.from_dict(serialized)
	assert_eq(restored.to_dict(), _initial.to_dict())
	serialized["stocks"][&"wheat"] = 99
	serialized["buildings"][0]["cell"][0] = 99
	assert_eq(restored.to_dict(), _initial.to_dict())
	restored.buildings[0]["cell"][1] = 99
	restored.stocks[&"wheat"] = 99
	assert_eq(_initial.buildings[0]["cell"], [2, 3])
	assert_eq(_initial.stocks[&"wheat"], 0)


func test_contextless_snapshot_omits_uninitialized_price_and_round_trips() -> void:
	var sim: Simulation = Simulation.new(_params, _initial, 123)
	sim.tick()
	var economy: Dictionary = sim.snapshot()["economy"]
	assert_false(economy.has("wheat_price"), "An uninitialized price is absent, not negative")
	var restored: EconomyState = EconomyState.from_dict(economy)
	assert_eq(restored.to_dict(), economy)
	var reconstructed: Simulation = Simulation.new(_params, restored, 123)
	assert_eq(reconstructed.snapshot()["economy"], economy)
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	var context: EconomyContext = EconomyContext.new(loaded.catalog,
		loaded.catalog.maps[&"whitechapel_1850s"])
	var activated: Simulation = Simulation.new(_params, restored, 123, context)
	assert_eq(activated.snapshot()["economy"]["wheat_price"],
		_params.get_value(&"market.wheat.base_price"))


func test_any_command_receives_shared_simulation_context_before_execution() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	var context: EconomyContext = EconomyContext.new(loaded.catalog,
		loaded.catalog.maps[&"whitechapel_1850s"])
	var sim: Simulation = Simulation.new(_params, _initial, 123, context)
	var first: ContextProbeCommand = ContextProbeCommand.new()
	var second: ContextProbeCommand = ContextProbeCommand.new()
	sim.apply_command(first)
	sim.apply_command(second)
	assert_false(first.context_received, "Context delivery is deferred with execution")
	sim.tick()
	assert_true(first.accepted)
	assert_true(second.accepted)
	assert_ne(first.executed_context_id, 0, "Execution received a non-null context")
	assert_eq(first.executed_context_id, second.executed_context_id,
		"Commands receive the same reference during execution")
	assert_ne(first.executed_context_id, context.get_instance_id(),
		"The simulation still owns one isolated context")
	assert_null(first.context)
	assert_null(second.context)


func test_common_command_interface_accepts_absent_context() -> void:
	var sim: Simulation = Simulation.new(_params, _initial, 123)
	var command: ContextProbeCommand = ContextProbeCommand.new()
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted)
	assert_true(command.context_received)
	assert_null(command.context)


func test_completed_command_cannot_mutate_simulation_map_or_catalog() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	var context: EconomyContext = EconomyContext.new(loaded.catalog,
		loaded.catalog.maps[&"whitechapel_1850s"])
	_initial.money = 10000
	var sim: Simulation = Simulation.new(_params, _initial, 123, context)
	var command: ContextProbeCommand = ContextProbeCommand.new()
	sim.apply_command(command)
	sim.tick()
	assert_null(command.context, "The borrowed context must be released after execute")
	# Corrupt any retained reference; otherwise mutate the caller's available context.
	var accessible: EconomyContext = command.context if command.context != null else context
	accessible.map.river_cells.clear()
	accessible.map.cultivable_cells.append(Vector2i(3, 1))
	accessible.buildings[&"mill"].tags.append("river")
	var wharf: BuildCommand = BuildCommand.new(context, &"wharf", Vector2i(0, 7))
	var mill: BuildCommand = BuildCommand.new(context, &"mill", Vector2i(1, 1))
	var field: BuildCommand = BuildCommand.new(context, &"wheat_field", Vector2i(3, 1))
	sim.apply_command(wharf)
	sim.apply_command(mill)
	sim.apply_command(field)
	sim.tick()
	assert_true(wharf.accepted, "Original river cells survive external mutations")
	assert_true(mill.accepted, "Original catalog still permits mills on land")
	assert_false(field.accepted, "Whitechapel still has no cultivable cells")
	assert_eq(field.reason, &"not_cultivable")
