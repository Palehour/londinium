class_name SimulationCommand
extends RefCounted

var accepted: bool = false
var reason: StringName = &"pending"


func use_context(_context: EconomyContext) -> void:
	# Optional shared context; commands without map/definition rules ignore it.
	pass


func release_context() -> void:
	# Context borrowers must clear retained references when their execution ends.
	use_context(null)


# Concrete game commands arrive with their systems; this contract has no game rules.
func execute(_state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
	push_error("SimulationCommand.execute must be overridden")
