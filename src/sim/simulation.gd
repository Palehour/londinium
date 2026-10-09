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
var _consumption: ConsumptionSystem = ConsumptionSystem.new()
var _satisfaction: SatisfactionSystem = SatisfactionSystem.new()
var _growth: GrowthSystem = GrowthSystem.new()
var _money: MoneySystem = MoneySystem.new()
var _defeat: DefeatSystem = DefeatSystem.new()


# New-game defaults are explicit so loading a snapshot never grants supplies or resets happiness.
static func create_new(params: Params, initial_state: EconomyState, seed_value: int,
		context: EconomyContext) -> Simulation:
	var state: EconomyState = EconomyState.from_dict(initial_state.to_dict())
	state.stocks[&"bread"] = int(params.get_value(&"population.initial_bread"))
	state.bread_fraction = 0.0
	state.bread_consumed = 0.0
	if state.tax_rate < 0.0:
		state.tax_rate = float(params.get_value(&"population.tax.rate"))
	state.bread_coverage = ConsumptionSystem.new().coverage(state, params)
	state.hunger_smoothed_coverage = state.bread_coverage
	SatisfactionSystem.new().update_target(state, params, context)
	state.satisfaction = state.satisfaction_target
	state.satisfaction_breakdown["smoothed"] = state.satisfaction
	return Simulation.new(params, state, seed_value, context)


func _init(params: Params, initial_state: EconomyState, seed_value: int,
		context: EconomyContext = null) -> void:
	_params = params
	_state = EconomyState.from_dict(initial_state.to_dict())
	_seed = seed_value
	_rng.seed = seed_value
	_context = context.copy() if context != null else null
	if _context != null:
		_defeat.initialize(_state, _params)
	if _context != null and _state.wheat_price < 0:
		_state.wheat_price = int(_params.get_value(&"market.wheat.base_price"))
	if _context != null and _state.tax_rate < 0.0:
		_state.tax_rate = float(_params.get_value(&"population.tax.rate"))
		# Construction initializes diagnostics, but smoothing advances only on ticks.
		_satisfaction.update_target(_state, _params, _context)
	if _context != null:
		WorkersSystem.refresh_counts(_state)


func get_building_unavailable_reason(id: StringName) -> StringName:
	return _context.building_unavailable_reason(id) if _context != null else &"unknown_building"


func apply_command(command: SimulationCommand) -> void:
	if not _state.defeat_causes.is_empty():
		_reject_after_defeat(command)
		return
	_commands.append(command)


func tick() -> void:
	if not _state.defeat_causes.is_empty():
		return
	# Detach the batch so commands queued during execution wait until the next tick.
	var pending: Array[SimulationCommand] = _commands
	_commands = []
	for command: SimulationCommand in pending:
		command.use_context(_context)
		command.execute(_state, _params, _rng)
		command.release_context()
	_tick_count += 1
	if _context != null:
		_workers.tick(_state, _params)
		_market.tick(_state, _params, _rng, _tick_count)
		_production.tick(_state, _params, _context)
		_consumption.tick(_state, _params)
		_defeat.update_hunger_coverage(_state, _params)
		_satisfaction.tick(_state, _params, _context)
		_growth.tick(_state, _params)
		_money.tick(_state, _params)
		_defeat.tick(_state, _params, false)
		if not _state.defeat_causes.is_empty():
			for command: SimulationCommand in _commands:
				_reject_after_defeat(command)
			_commands.clear()


func _reject_after_defeat(command: SimulationCommand) -> void:
	command.accepted = false
	command.reason = &"simulation_defeated"


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
