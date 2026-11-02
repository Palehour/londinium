class_name RevokeDecreeCommand
extends SimulationCommand

# Revokes one active decree (issue #71, D-124). Competence is not checked again.

var _id: StringName
var _context: EconomyContext


func _init(id: StringName) -> void:
	_id = id


func use_context(context: EconomyContext) -> void:
	_context = context


func execute(state: EconomyState, params: Params, _rng: RandomNumberGenerator) -> void:
	reason = DecreeSystem.revoke(state, params, _context, _id)
	accepted = reason == &""
