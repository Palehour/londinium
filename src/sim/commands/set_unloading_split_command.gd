class_name SetUnloadingSplitCommand
extends SimulationCommand

# The player's one control over the wharf's unloading (issue #50): the whole percent of the capacity left
# after the imported flour that goes to barley; the rest goes to wheat.
const MAX_PERCENT: int = 100

var _barley_percent: int


func _init(barley_percent: int) -> void:
	_barley_percent = barley_percent


func execute(state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
	accepted = _barley_percent >= 0 and _barley_percent <= MAX_PERCENT
	reason = &"" if accepted else &"invalid_unloading_split"
	if accepted:
		state.unloading_barley_percent = _barley_percent
