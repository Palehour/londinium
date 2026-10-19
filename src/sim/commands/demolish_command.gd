class_name DemolishCommand
extends SimulationCommand

var _cell: Vector2i
var _context: EconomyContext


func _init(cell: Vector2i) -> void:
	_cell = cell


# The map, to tell a historic street (never demolished, D-070) from a cell with nothing on it.
func use_context(context: EconomyContext) -> void:
	_context = context


func execute(state: EconomyState, params: Params, _rng: RandomNumberGenerator) -> void:
	accepted = false
	reason = &"no_building"
	for index: int in range(state.buildings.size()):
		if _covers(state.buildings[index]):
			if _is_anchor(state.buildings[index]["definition_id"], RoadNetwork.cell_of(state.buildings[index])):
				reason = &"historic_anchor"
				return
			var refund: int = _refund(state, params, state.buildings[index])
			state.money += refund
			# Net spending keeps the panel's construction line honest.
			state.construction_spent_tick -= refund
			state.refunds_tick += refund
			# Work in progress belongs to the building; global stocks survive demolition.
			state.buildings.remove_at(index)
			accepted = true
			reason = &""
			return
	_demolish_road(state, params)


# A street of the player refunds like a building without jobs (D-029, D-080): all of it within the correction window,
# demolish.no_jobs_refund_ratio after it.
func _demolish_road(state: EconomyState, params: Params) -> void:
	for index: int in range(state.player_roads.size()):
		var road: Dictionary = state.player_roads[index]
		if road["cell"] != [_cell.x, _cell.y]:
			continue
		var refund: int = int(road["paid"])
		if not _in_grace(state, params, road):
			refund = roundi(refund * float(params.get_value(&"demolish.no_jobs_refund_ratio")))
		state.money += refund
		state.construction_spent_tick -= refund
		state.refunds_tick += refund
		state.player_roads.remove_at(index)
		accepted = true
		reason = &""
		return
	# An anchor may share its cell with a historic street, like St John's with Green Bank: the anchor is what stands.
	if _is_anchor(&"", _cell):
		reason = &"historic_anchor"
	elif _context != null and _context.map.roads_enabled and _cell in _context.map.road_cells:
		reason = &"historic_road"


# Any cell of a building's footprint picks it (issue #184, D-086). Without the map only its own cell does.
func _covers(building: Dictionary) -> bool:
	if _context == null:
		return RoadNetwork.cell_of(building) == _cell
	return _context.area_of(building).has_point(_cell)


# A historic anchor of the map is never demolished (issue #152): the building it stands with, or the cell itself when
# it has no use. The dense housing of an 1870 house is kept the same way (issue #180, D-085). Another building on the
# cell, like one from a saved game (D-076), is demolished as usual. A building is known by the cell it stands on, the
# north-west corner of its footprint, whichever of its cells was touched (D-086).
func _is_anchor(definition_id: StringName, origin: Vector2i) -> bool:
	if _context == null:
		return false
	if definition_id == Simulation.DENSE_HOUSING and origin in _context.map.period_houses:
		return true
	return _context.map.anchors.has(origin) and _context.map.anchors[origin] == definition_id


func _refund(state: EconomyState, params: Params, building: Dictionary) -> int:
	# What the building cost when it was built (issue #118); a building without that record paid the base cost.
	var cost: int = int(building.get("paid",
		params.get_value(StringName("building.%s.cost" % building["definition_id"]))))
	if _in_grace(state, params, building):
		return cost
	var definition_id: StringName = building["definition_id"]
	# Housing and other jobless buildings never have workers, so "idle" cannot make them an undo.
	if WorkersSystem.job_capacity(params, definition_id) == 0:
		return roundi(cost * float(params.get_value(&"demolish.no_jobs_refund_ratio")))
	if int(building.get("workers", 0)) == 0:
		return cost
	return roundi(cost * float(params.get_value(&"demolish.refund_ratio")))


# Only the correction window is an undo for every building. A missing build time counts as established.
func _in_grace(state: EconomyState, params: Params, building: Dictionary) -> bool:
	if not building.has("built_at"):
		return false
	var age: int = state.defeat_elapsed_seconds - int(building["built_at"])
	return age <= float(params.get_value(&"demolish.refund_grace_seconds"))
