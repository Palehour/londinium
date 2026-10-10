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
var _stats: Stats


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


# stats_window is snapshot()["stats"]["window"]; it is copied, so callers may keep mutating theirs.
func _init(params: Params, initial_state: EconomyState, seed_value: int,
		context: EconomyContext = null, stats_window: Array = []) -> void:
	_params = params
	_state = EconomyState.from_dict(initial_state.to_dict())
	_seed = seed_value
	_rng.seed = seed_value
	_context = context.copy() if context != null else null
	_stats = Stats.new(int(_params.get_value(&"population.stats_window_seconds")))
	_stats.restore(stats_window)
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
	_state.reset_flows()
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
		_stats.record(_state)


func _reject_after_defeat(command: SimulationCommand) -> void:
	command.accepted = false
	command.reason = &"simulation_defeated"


func get_rng_state() -> int:
	# Expose a value, not the mutable generator that commands use.
	return _rng.state


func snapshot() -> Dictionary:
	return {
		"economy": _state.to_dict(),
		"stats": _stats.snapshot(),
		"diagnostics": BreadDiagnostics.build(_state, _params, _context),
		"defeat": _defeat_snapshot(),
		"tick_count": _tick_count,
		"seed": _seed,
		"rng_state": get_rng_state(),
	}


func _defeat_snapshot() -> Dictionary:
	var grace: int = int(_params.get_value(&"defeat.grace_seconds"))
	return {
		"grace_active": _state.defeat_elapsed_seconds <= grace,
		"grace_remaining_seconds": maxi(0, grace - _state.defeat_elapsed_seconds),
		"causes": _state.defeat_causes.duplicate(),
		"bankruptcy": _condition_snapshot(_state.bankruptcy, &"bankruptcy",
			{"money": _state.money, "threshold": int(_params.get_value(&"defeat.bankruptcy.threshold"))}),
		"hunger": _condition_snapshot(_state.hunger, &"hunger",
			{"coverage": _state.hunger_smoothed_coverage, "threshold": float(_params.get_value(&"defeat.hunger.threshold"))}),
		"depopulation": _condition_snapshot(_state.depopulation, &"depopulation",
			{"population": _state.population, "peak": _state.population_peak, "active": _state.depopulation_active}),
	}


func _condition_snapshot(condition: DefeatState, key: StringName, metrics: Dictionary) -> Dictionary:
	var duration: int = int(_params.get_value(StringName("defeat.%s.duration_seconds" % key)))
	var result: Dictionary = metrics.duplicate(true)
	result["status"] = condition.status
	result["cause"] = condition.cause
	# The timer runs while the critical condition holds, which can differ from the warning.
	result["timer_running"] = condition.elapsed_seconds > 0
	result["elapsed_seconds"] = condition.elapsed_seconds
	result["remaining_seconds"] = maxi(0, duration - condition.elapsed_seconds)
	result["duration_seconds"] = duration
	return result
