class_name SimulationCommand
extends RefCounted

var accepted: bool = false
var reason: StringName = &"pending"


# Concrete game commands arrive with their systems; this contract has no game rules.
func execute(_state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
	push_error("SimulationCommand.execute must be overridden")
