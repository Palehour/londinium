class_name BuildRoadCommand
extends SimulationCommand

# A street of the player (issue #67, D-070, D-080): one piece of economy/roads.json footprint (2x2 since issue #186,
# D-086), orthogonal to its neighbours, for roads.cost. Streets are not buildings, so they neither escalate nor count
# for administration (D-063). DemolishCommand removes them.

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
	# The whole piece counts, its cell being the north-west corner (issue #186, D-086).
	var area: Rect2i = Rect2i(_cell, _context.road_footprint)
	if not Rect2i(Vector2i.ZERO, Vector2i(map.width, map.height)).encloses(area):
		return &"outside_map"
	var cells: Array[Vector2i] = EconomyContext.cells_of(area)
	if cells.any(func(cell: Vector2i) -> bool: return is_street(state, _context, cell)):
		return &"road_cell"
	# Any cell a building covers is taken, not only the one it stands on (issue #184, D-086).
	if cells.any(func(cell: Vector2i) -> bool: return not _context.building_at(state, cell).is_empty()):
		return &"occupied_cell"
	# Water and dock basins carry no street (D-020), and the standing buildings stay a block (D-075).
	if cells.any(func(cell: Vector2i) -> bool: return cell in map.river_cells or cell in map.dock_cells):
		return &"requires_land"
	if cells.any(func(cell: Vector2i) -> bool: return cell in map.existing_cells):
		return &"existing_building"
	if state.money < int(params.get_value(&"roads.cost")):
		return &"insufficient_money"
	return &""


# A historic street of the map or a cell of a piece the player built.
static func is_street(state: EconomyState, context: EconomyContext, cell: Vector2i) -> bool:
	if cell in context.map.road_cells:
		return true
	for road: Dictionary in state.player_roads:
		if context.road_area(road).has_point(cell):
			return true
	return false
