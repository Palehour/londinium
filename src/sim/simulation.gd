class_name Simulation
extends RefCounted

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _state: EconomyState
var _params: Params
var _seed: int
var _tick_count: int = 0
var _commands: Array[SimulationCommand] = []


func _init(params: Params, initial_state: EconomyState, seed_value: int) -> void:
	_params = params
	_state = EconomyState.from_dict(initial_state.to_dict())
	_seed = seed_value
	rng.seed = seed_value


func apply_command(command: SimulationCommand) -> void:
	_commands.append(command)


func tick() -> void:
	# Detach the batch so commands queued during execution wait until the next tick.
	var pending: Array[SimulationCommand] = _commands
	_commands = []
	for command: SimulationCommand in pending:
		command.execute(_state, _params, rng)
	_tick_count += 1


func snapshot() -> Dictionary:
	return {
		"economy": _state.to_dict(),
		"tick_count": _tick_count,
		"seed": _seed,
		"rng_state": rng.state,
	}
