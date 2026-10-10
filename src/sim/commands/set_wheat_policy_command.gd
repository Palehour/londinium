class_name SetWheatPolicyCommand
extends SimulationCommand

var _accumulate_price: int
var _max_price: int
var _target_stock: int
var _reserve_minutes: int


func _init(accumulate_price: int, max_price: int, target_stock: int, reserve_minutes: int) -> void:
	_accumulate_price = accumulate_price
	_max_price = max_price
	_target_stock = target_stock
	_reserve_minutes = reserve_minutes


# The limits come from Params, so a role that changes the storage or the price range changes them too.
func execute(state: EconomyState, params: Params, _rng: RandomNumberGenerator) -> void:
	var message: String = WheatPolicy.validation_error(_accumulate_price, _max_price, _target_stock, _reserve_minutes,
		int(params.get_value(&"market.wheat.storage_capacity")),
		int(params.get_value(&"market.wheat.min_price")), int(params.get_value(&"market.wheat.max_price")))
	accepted = message.is_empty()
	reason = &"" if accepted else &"invalid_wheat_policy"
	if accepted:
		state.wheat_accumulate_price = _accumulate_price
		state.wheat_max_price = _max_price
		state.wheat_target_stock = _target_stock
		state.wheat_reserve_minutes = _reserve_minutes
