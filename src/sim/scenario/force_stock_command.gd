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


func execute(state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
	state.stocks[_good] = _amount
	accepted = true
	reason = &""
