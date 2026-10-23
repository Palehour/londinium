class_name MissionCommand
extends SimulationCommand

# The only way into a mission (issue #63, D-090): `start` one of the era's missions once, or `abandon` it while active.

var _action: StringName
var _id: StringName
var _context: EconomyContext


func _init(action: StringName, id: StringName) -> void:
	_action = action
	_id = id


func use_context(context: EconomyContext) -> void:
	_context = context


func execute(state: EconomyState, params: Params, _rng: RandomNumberGenerator) -> void:
	reason = _refusal(state)
	accepted = reason == &""
	if not accepted:
		return
	var mission: MissionDef = _context.missions[_id]
	if _action == &"start":
		MissionSystem.start(state, params, mission)
	else:
		MissionSystem.close(state, params, mission, MissionSystem.ABANDONED)


func _refusal(state: EconomyState) -> StringName:
	if _context == null or not _context.missions.has(_id):
		return &"unknown_mission"
	if _action == &"start":
		return &"mission_already_started" if state.missions.has(_id) else &""
	if _action == &"abandon":
		var active: bool = state.missions.has(_id) and state.missions[_id].status == MissionSystem.ACTIVE
		return &"" if active else &"mission_not_active"
	return &"unknown_mission_action"
