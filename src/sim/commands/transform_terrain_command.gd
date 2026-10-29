class_name TransformTerrainCommand
extends SimulationCommand

# Transforms one cell of land (issue #88, D-148, D-150): draining a marsh makes it firm ground for terrain.drain_cost,
# and firm ground beside water becomes riverbank for drain_cost × terrain.riverbank_cost_mult, rounded down to whole
# pence. A taken cell is never transformed: any cell of a building's footprint (D-152), a street, or what the map
# already has standing there.

const TRANSFORMATIONS: Dictionary[StringName, StringName] = {
	EconomyContext.FIRM: EconomyContext.MARSH,
	EconomyContext.RIVERBANK: EconomyContext.FIRM,
}

var _cell: Vector2i
var _target: StringName
var _context: EconomyContext


func _init(cell: Vector2i, target: StringName) -> void:
	_cell = cell
	_target = target


func use_context(context: EconomyContext) -> void:
	_context = context


func execute(state: EconomyState, params: Params, _rng: RandomNumberGenerator) -> void:
	accepted = false
	reason = _validate(state, params)
	if reason != &"":
		return
	var cost: int = transform_cost(params, _target)
	state.money -= cost
	state.construction_spent_tick += cost
	state.terrain_changes[_cell] = _target
	accepted = true


# What turning a cell into the target terrain costs, whether or not the treasury covers it.
static func transform_cost(params: Params, target: StringName) -> int:
	var drain_cost: int = int(params.get_value(&"terrain.drain_cost"))
	if target == EconomyContext.RIVERBANK:
		return floori(drain_cost * float(params.get_value(&"terrain.riverbank_cost_mult")))
	return drain_cost


func _validate(state: EconomyState, params: Params) -> StringName:
	if _context == null:
		return &"no_map"
	var map: MapDef = _context.map
	if not Rect2i(Vector2i.ZERO, Vector2i(map.width, map.height)).has_point(_cell):
		return &"outside_map"
	if _context.is_water(_cell):
		return &"water_cell"
	if _is_taken(state):
		return &"occupied_cell"
	if TRANSFORMATIONS.get(_target, &"") != _context.terrain_at(state, _cell):
		return &"invalid_transformation"
	if _target == EconomyContext.RIVERBANK and not _beside_water():
		return &"no_water_nearby"
	if state.money < transform_cost(params, _target):
		return &"insufficient_money"
	return &""


func _is_taken(state: EconomyState) -> bool:
	var map: MapDef = _context.map
	if _cell in map.existing_cells or _cell in map.stairs_cells:
		return true
	if BuildRoadCommand.is_street(state, _context, _cell):
		return true
	return not _context.building_at(state, _cell).is_empty()


# Water on one of the four sides, as the streets reach a cell (D-148 asks for adjacency, not a diagonal).
func _beside_water() -> bool:
	for side: Vector2i in RoadNetwork.SIDES:
		if _context.is_water(_cell + side):
			return true
	return false
