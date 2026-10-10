class_name DemolishCommand
extends SimulationCommand

var _cell: Vector2i


func _init(cell: Vector2i) -> void:
	_cell = cell


func execute(state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
	accepted = false
	reason = &"no_building"
	for index: int in range(state.buildings.size()):
		if state.buildings[index]["cell"] == [_cell.x, _cell.y]:
			# Work in progress belongs to the building; global stocks survive demolition.
			state.buildings.remove_at(index)
			accepted = true
			reason = &""
			return
