class_name ForceStockCommand
extends SimulationCommand

# Scenario scripts only (the "set_stock" command of ScenarioRunner): the player has no way to empty a warehouse.
# The beer crisis of issue #55 demolishes the brewery and empties the beer in the same tick, so the
# artisans go exactly the scripted minutes without beer instead of drinking what was left in store.
var _good: StringName
var _amount: int


func _init(good: StringName, amount: int) -> void:
	_good = good
	_amount = amount


func execute(state: EconomyState, params: Params, _rng: RandomNumberGenerator) -> void:
	# A real warehouse never holds more than its cap (issue #116), and the part of a unit already eaten
	# belongs to the stock that was emptied.
	var cap_key: StringName = StringName("market.%s.storage_capacity" % _good)
	if params.has_value(cap_key):
		state.stocks[_good] = mini(_amount, int(params.get_value(cap_key)))
	else:
		# A good without a cap in data/ is a script or data mistake; say so instead of storing any amount quietly.
		push_warning("set_stock: %s has no %s in data/; the stock is not capped" % [_good, cap_key])
		state.stocks[_good] = _amount
	if _good == &"beer":
		state.beer_fraction = 0.0
	accepted = true
	reason = &""
