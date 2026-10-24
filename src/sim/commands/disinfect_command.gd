class_name DisinfectCommand
extends SimulationCommand

# Disinfects a sick house within the health post's radius (issue #222, D-104, D-106). Any cell of its footprint picks
# it. Without the money it does not start and leaves no debt: the house waits for the end of the crisis.

var _cell: Vector2i
var _context: EconomyContext


func _init(cell: Vector2i) -> void:
	_cell = cell


func use_context(context: EconomyContext) -> void:
	_context = context


func execute(state: EconomyState, params: Params, _rng: RandomNumberGenerator) -> void:
	accepted = false
	reason = &"no_building"
	if _context == null:
		return
	for building: Dictionary in state.buildings:
		if not _context.area_of(building).has_point(_cell):
			continue
		reason = CrisisSystem.disinfect_reason(state, params, _context, building)
		if reason == &"":
			CrisisSystem.start_disinfection(state, params, building)
			accepted = true
		return
