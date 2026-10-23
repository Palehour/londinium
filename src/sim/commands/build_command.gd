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
	var cost: int = BuildingCosts.construction_cost(params, state, _context.buildings[_definition_id])
	state.money -= cost
	state.construction_spent_tick += cost
	# Game-second clock, so demolition can tell a fresh building from an established one. The price paid is kept
	# because it grows with each copy (issue #118) and demolition refunds on it.
	state.buildings.append({"definition_id": _definition_id, "cell": [_cell.x, _cell.y],
		"built_at": state.defeat_elapsed_seconds, "paid": cost})
	accepted = true


func _validate(state: EconomyState, params: Params) -> StringName:
	if not _context.buildings.has(_definition_id):
		return &"unknown_building"
	if not _context.buildings[_definition_id].buildable:
		return &"not_buildable"
	var events_reason: StringName = WaterSystem.unavailable_reason(params, _context.buildings[_definition_id])
	if events_reason != &"":
		return events_reason
	var map: MapDef = _context.map
	# The whole footprint counts, its cell being the north-west corner (issue #184, D-086).
	var area: Rect2i = Rect2i(_cell, _context.buildings[_definition_id].footprint)
	if not Rect2i(Vector2i.ZERO, Vector2i(map.width, map.height)).encloses(area):
		return &"outside_map"
	for building: Dictionary in state.buildings:
		if _context.area_of(building).intersects(area):
			return &"occupied_cell"
	var terrain_reason: StringName = _context.placement_reason(_definition_id, _cell)
	if terrain_reason != &"":
		return terrain_reason
	# On a map with streets (issue #67) a street cell stays a street.
	if map.roads_enabled and EconomyContext.cells_of(area).any(func(cell: Vector2i) -> bool:
			return BuildRoadCommand.is_street(state, _context, cell)):
		return &"road_cell"
	if state.money < BuildingCosts.construction_cost(params, state, _context.buildings[_definition_id]):
		return &"insufficient_money"
	return &""
