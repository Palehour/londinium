class_name ForceWheatPriceCommand
extends SimulationCommand

# Scenario scripts only (ScenarioRunner "price_schedule"): the player has no way to set the price.
# Together with the runner switching the random walk off, it gives a deterministic market.
var _price: int


func _init(price: int) -> void:
	_price = price


func execute(state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
	state.wheat_previous_price = state.wheat_price
	state.wheat_price = _price
	accepted = true
	reason = &""
