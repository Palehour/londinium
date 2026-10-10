class_name SetWheatPurchasesCommand
extends SimulationCommand

var _enabled: bool


func _init(enabled: bool) -> void:
	_enabled = enabled


func execute(state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
	state.wheat_purchases_enabled = _enabled
	accepted = true
	reason = &""
