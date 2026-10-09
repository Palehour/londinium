class_name BuildCommand
extends SimulationCommand

var _context: EconomyContext
var _definition_id: StringName
var _cell: Vector2i


func _init(context: EconomyContext, definition_id: StringName, cell: Vector2i) -> void:
	_context = context
	_definition_id = definition_id
	_cell = cell


func use_context(context: EconomyContext) -> void:
	if context != null:
		_context = context


func release_context() -> void:
	_context = null


func execute(state: EconomyState, params: Params, _rng: RandomNumberGenerator) -> void:
	accepted = false
	reason = _validate(state, params)
	if reason != &"":
		return
	state.money -= int(params.get_value(StringName("building.%s.cost" % _definition_id)))
	state.buildings.append({"definition_id": _definition_id, "cell": [_cell.x, _cell.y]})
	accepted = true


func _validate(state: EconomyState, params: Params) -> StringName:
	if not _context.buildings.has(_definition_id):
		return &"unknown_building"
	var map: MapDef = _context.map
	if _cell.x < 0 or _cell.y < 0 or _cell.x >= map.width or _cell.y >= map.height:
		return &"outside_map"
	for building: Dictionary in state.buildings:
		if building["cell"] == [_cell.x, _cell.y]:
			return &"occupied_cell"
	var terrain_reason: StringName = _context.terrain_placement_reason(_definition_id, _cell)
	if terrain_reason != &"":
		return terrain_reason
	if state.money < int(params.get_value(StringName("building.%s.cost" % _definition_id))):
		return &"insufficient_money"
	return &""
