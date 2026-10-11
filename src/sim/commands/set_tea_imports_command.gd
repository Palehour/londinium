class_name SetTeaImportsCommand
extends SimulationCommand

var _enabled: bool


func _init(enabled: bool) -> void:
	_enabled = enabled


func execute(state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
	state.tea_imports_enabled = _enabled
	accepted = true
	reason = &""
