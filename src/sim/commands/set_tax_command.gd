class_name SetTaxCommand
extends SimulationCommand

var _rate: float


func _init(rate: float) -> void:
	_rate = rate


func execute(state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
	accepted = is_finite(_rate) and _rate >= 0.0 and _rate <= 1.0
	reason = &"" if accepted else &"invalid_tax_rate"
	if accepted:
		state.tax_rate = _rate
