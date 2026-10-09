class_name Simulation
extends RefCounted

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _state: EconomyState
var _params: Params
var _seed: int
var _tick_count: int = 0
var _commands: Array[SimulationCommand] = []
var _context: EconomyContext
var _workers: WorkersSystem = WorkersSystem.new()
var _market: MarketSystem = MarketSystem.new()
var _production: ProductionSystem = ProductionSystem.new()


func _init(params: Params, initial_state: EconomyState, seed_value: int,
		context: EconomyContext = null) -> void:
	_params = params
	_state = EconomyState.from_dict(initial_state.to_dict())
	_seed = seed_value
	_rng.seed = seed_value
	_context = context.copy() if context != null else null
	if _context != null:
		_state.wheat_price = int(_params.get_value(&"market.wheat.base_price"))


func apply_command(command: SimulationCommand) -> void:
	_commands.append(command)


func tick() -> void:
	# Detach the batch so commands queued during execution wait until the next tick.
	var pending: Array[SimulationCommand] = _commands
	_commands = []
	for command: SimulationCommand in pending:
		command.execute(_state, _params, _rng)
	_tick_count += 1
	if _context != null:
		_workers.tick(_state, _params)
		_market.tick(_state, _params, _rng, _tick_count)
		_production.tick(_state, _params, _context)


func get_rng_state() -> int:
	# Expose a value, not the mutable generator that commands use.
	return _rng.state


func snapshot() -> Dictionary:
	return {
		"economy": _state.to_dict(),
		"tick_count": _tick_count,
		"seed": _seed,
		"rng_state": get_rng_state(),
	}
