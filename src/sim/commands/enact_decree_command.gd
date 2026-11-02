class_name EnactDecreeCommand
extends SimulationCommand

# Enacts one decree, paid from the legitimacy reserve (issue #71, D-124).

var _id: StringName
var _context: EconomyContext


func _init(id: StringName) -> void:
	_id = id


func use_context(context: EconomyContext) -> void:
	_context = context


func execute(state: EconomyState, params: Params, _rng: RandomNumberGenerator) -> void:
	reason = DecreeSystem.enact(state, params, _context, _id)
	accepted = reason == &""
