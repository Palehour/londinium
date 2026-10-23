class_name MissionSystem
extends RefCounted

# Missions (issue #63, D-090): MissionCommand starts and abandons them, and this step closes them when their time runs
# out. The goal is checked once, at the close, in goal_met(); each outcome runs its effects once.

const ACTIVE: StringName = &"active"
const COMPLETED: StringName = &"completed"
const FAILED: StringName = &"failed"
const ABANDONED: StringName = &"abandoned"


static func start(state: EconomyState, params: Params, mission: MissionDef) -> void:
	var entry: MissionState = MissionState.new()
	entry.remaining_ticks = SimTime.minutes_to_ticks(float(params.get_value(_key(mission, "duration_min"))))
	state.missions[mission.id] = entry


static func tick(state: EconomyState, params: Params, context: EconomyContext) -> void:
	for id: StringName in state.missions:
		var entry: MissionState = state.missions[id]
		# A saved mission the data no longer has stays as it was.
		if entry.status != ACTIVE or not context.missions.has(id):
			continue
		entry.remaining_ticks -= 1
		if entry.remaining_ticks <= 0:
			var mission: MissionDef = context.missions[id]
			close(state, params, mission, COMPLETED if goal_met(state, params, mission) else FAILED)


static func close(state: EconomyState, params: Params, mission: MissionDef, outcome: StringName) -> void:
	var entry: MissionState = state.missions[mission.id]
	entry.status = outcome
	entry.remaining_ticks = 0
	# Money is the only effect so far; the loader refuses any other.
	for effect: Dictionary in mission.effects[outcome]:
		state.money += int(params.get_value(effect["key"]))


# The only place a goal is checked, once, when the mission's time is over.
static func goal_met(state: EconomyState, params: Params, mission: MissionDef) -> bool:
	match mission.goal_metric:
		&"population":
			return state.population >= int(params.get_value(_key(mission, "goal.at_least")))
	return false


static func defeat_paused(state: EconomyState, params: Params, context: EconomyContext) -> bool:
	for id: StringName in state.missions:
		var mission: MissionDef = context.missions.get(id)
		if state.missions[id].status == ACTIVE and mission != null and mission.defeat_pause != &"" \
				and params.get_value(mission.defeat_pause):
			return true
	return false


static func _key(mission: MissionDef, field: String) -> StringName:
	return StringName("mission.%s.%s" % [mission.id, field])
