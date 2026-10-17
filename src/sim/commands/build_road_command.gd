class_name BuildRoadCommand
extends SimulationCommand

# A street of the player (issue #67, D-070, D-080): one cell, orthogonal to its neighbours, for roads.cost. Streets
# are not buildings, so they neither escalate nor count for administration (D-063). DemolishCommand removes them.

var _context: EconomyContext
var _cell: Vector2i


func _init(context: EconomyContext, cell: Vector2i) -> void:
	_context = context
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
	var cost: int = int(params.get_value(&"roads.cost"))
	state.money -= cost
	state.construction_spent_tick += cost
	# Built time and price, so demolition refunds it like a building without jobs (D-029).
	state.player_roads.append({"cell": [_cell.x, _cell.y], "built_at": state.defeat_elapsed_seconds, "paid": cost})
	accepted = true


func _validate(state: EconomyState, params: Params) -> StringName:
	var map: MapDef = _context.map
	if not map.roads_enabled:
		return &"roads_disabled"
	if _cell.x < 0 or _cell.y < 0 or _cell.x >= map.width or _cell.y >= map.height:
		return &"outside_map"
	if is_street(state, map, _cell):
		return &"road_cell"
	for building: Dictionary in state.buildings:
		if building["cell"] == [_cell.x, _cell.y]:
			return &"occupied_cell"
	# Water and dock basins carry no street (D-020), and the standing buildings stay a block (D-075).
	if _cell in map.river_cells or _cell in map.dock_cells:
		return &"requires_land"
	if _cell in map.existing_cells:
		return &"existing_building"
	if state.money < int(params.get_value(&"roads.cost")):
		return &"insufficient_money"
	return &""


# A historic street of the map or one the player built.
static func is_street(state: EconomyState, map: MapDef, cell: Vector2i) -> bool:
	if cell in map.road_cells:
		return true
	for road: Dictionary in state.player_roads:
		if road["cell"] == [cell.x, cell.y]:
			return true
	return false
