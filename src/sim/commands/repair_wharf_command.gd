class_name RepairWharfCommand
extends SimulationCommand

# Repairs a damaged wharf of the map (issue #177, D-083): the cell becomes a wharf for repair.wharf_cost_ratio of what
# a new one costs, rounded down to whole pence. A cell stays damaged while nothing stands on it, so the state needs no
# record of its own and a demolished repaired wharf can be repaired again.

const WHARF: StringName = &"wharf"

var _cell: Vector2i
var _context: EconomyContext


func _init(cell: Vector2i) -> void:
	_cell = cell


func use_context(context: EconomyContext) -> void:
	_context = context


func execute(state: EconomyState, params: Params, _rng: RandomNumberGenerator) -> void:
	accepted = false
	reason = _validate(state, params)
	if reason != &"":
		return
	var cost: int = repair_cost(params, state, _context)
	state.money -= cost
	state.construction_spent_tick += cost
	# Like a new building: demolition refunds on what was paid (D-029) and tells a fresh one by its build time.
	state.buildings.append({"definition_id": WHARF, "cell": [_cell.x, _cell.y],
		"built_at": state.defeat_elapsed_seconds, "paid": cost})
	accepted = true


# What repairing costs now: a share of the price of a new wharf, which never escalates (basic infrastructure, D-063).
static func repair_cost(params: Params, state: EconomyState, context: EconomyContext) -> int:
	var new_wharf: int = BuildingCosts.construction_cost(params, state, context.buildings[WHARF])
	return floori(new_wharf * float(params.get_value(&"repair.wharf_cost_ratio")))


func _validate(state: EconomyState, params: Params) -> StringName:
	if _context == null or _cell not in _context.map.damaged_wharves:
		return &"not_damaged_wharf"
	if _is_taken(state, _context, _cell):
		return &"occupied_cell"
	if state.money < repair_cost(params, state, _context):
		return &"insufficient_money"
	return &""


# The damaged wharves that can be repaired now and what each costs, for the map to draw (issue #178). The cost is shown
# whether or not the treasury covers it.
static func snapshot(state: EconomyState, params: Params, context: EconomyContext) -> Dictionary:
	var wharves: Array[Dictionary] = []
	if context != null:
		for cell: Vector2i in context.map.damaged_wharves:
			if not _is_taken(state, context, cell):
				wharves.append({"cell": [cell.x, cell.y], "cost": repair_cost(params, state, context)})
	return {"wharves": wharves}


# Any building on a cell of the wharf's footprint takes it (issue #186, D-086).
static func _is_taken(state: EconomyState, context: EconomyContext, cell: Vector2i) -> bool:
	var area: Rect2i = Rect2i(cell, context.buildings[WHARF].footprint)
	for building: Dictionary in state.buildings:
		if context.area_of(building).intersects(area):
			return true
	return false
