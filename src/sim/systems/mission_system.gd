class_name MissionSystem
extends RefCounted

# Missions (issue #63, D-090): MissionCommand starts and abandons them, a trigger may start them (issue #202), and
# this step closes them when their time runs out. The goal is checked once, at the close, in goal_met(); each outcome
# runs its effects once. A cholera failure then empties the houses and speeds the immigration for a while.

const STARTED: StringName = &"started"
const ACTIVE: StringName = &"active"
const COMPLETED: StringName = &"completed"
const FAILED: StringName = &"failed"
const ABANDONED: StringName = &"abandoned"


static func start(state: EconomyState, params: Params, mission: MissionDef, context: EconomyContext) -> void:
	var entry: MissionState = MissionState.new()
	entry.remaining_ticks = SimTime.minutes_to_ticks(float(params.get_value(_key(mission, "duration_min"))))
	state.missions[mission.id] = entry
	_apply_effects(state, params, mission, STARTED, context)


static func tick(state: EconomyState, params: Params, context: EconomyContext, tick_count: int = 0) -> void:
	for id: StringName in state.missions:
		var entry: MissionState = state.missions[id]
		_age_aftermath(entry)
		# A saved mission the data no longer has stays as it was.
		if entry.status != ACTIVE or not context.missions.has(id):
			continue
		entry.remaining_ticks -= 1
		if entry.remaining_ticks <= 0:
			var mission: MissionDef = context.missions[id]
			close(state, params, mission, COMPLETED if goal_met(state, params, context, mission) else FAILED,
				context)
	# After the countdown, so a mission it starts lasts its whole duration from the next tick on.
	_trigger(state, params, context, tick_count)


static func close(state: EconomyState, params: Params, mission: MissionDef, outcome: StringName,
		context: EconomyContext) -> void:
	var entry: MissionState = state.missions[mission.id]
	entry.status = outcome
	entry.remaining_ticks = 0
	_apply_effects(state, params, mission, outcome, context)


# The only place a goal is checked, once, when the mission's time is over. Water: every district with houses has at
# least the threshold (D-090, D-098); with no house in any district the mission fails (D-102), so demolishing the city
# cannot meet it.
static func goal_met(state: EconomyState, params: Params, context: EconomyContext, mission: MissionDef) -> bool:
	match mission.goal_metric:
		&"population":
			return state.population >= int(params.get_value(mission.goal_key))
		&"water":
			return _housed(state, context) and _failing_districts(state, params, context, mission).is_empty()
	return false


static func defeat_paused(state: EconomyState, params: Params, context: EconomyContext) -> bool:
	for id: StringName in state.missions:
		var mission: MissionDef = context.missions.get(id)
		var entry: MissionState = state.missions[id]
		var running: bool = entry.status == ACTIVE or entry.vacancy_ticks > 0 or entry.recovery_ticks > 0
		if running and mission != null and mission.defeat_pause != &"" and params.get_value(mission.defeat_pause):
			return true
	return false


# What the growth step multiplies the immigration by (D-090): nobody moves into the emptied houses during the
# vacancy, then cholera.recovery_mult as fast during the recovery.
static func immigration_multiplier(state: EconomyState, params: Params) -> float:
	var multiplier: float = 1.0
	for entry: MissionState in state.missions.values():
		if entry.vacancy_ticks > 0:
			return 0.0
		if entry.recovery_ticks > 0:
			multiplier = float(params.get_value(&"cholera.recovery_mult"))
	return multiplier


# With the historic events on, a mission with a trigger starts by itself duration_min before the minute its trigger
# names, so its single check falls on that minute (Cristian, #202). It runs once a game.
static func _trigger(state: EconomyState, params: Params, context: EconomyContext, tick_count: int) -> void:
	if not bool(params.get_value(&"events.enabled")):
		return
	for mission: MissionDef in context.missions.values():
		if mission.trigger_id == &"" or state.missions.has(mission.id):
			continue
		var closes_at: int = SimTime.minutes_to_ticks(float(params.get_value(mission.closes_at_key)))
		var duration: int = SimTime.minutes_to_ticks(float(params.get_value(_key(mission, "duration_min"))))
		if tick_count >= closes_at - duration:
			start(state, params, mission, context)


static func _apply_effects(state: EconomyState, params: Params, mission: MissionDef, outcome: StringName,
		context: EconomyContext) -> void:
	for effect: Dictionary in mission.effects.get(outcome, []):
		match effect["type"]:
			&"money":
				state.money += int(params.get_value(effect["key"]))
			&"source_risk":
				for district: StringName in WaterSystem.districts_drinking(context, effect["source"]):
					state.district_source_risk[district] = float(params.get_value(effect["key"]))
			&"cholera":
				_cholera(state, params, context, mission)


# Each failing district loses pop x cholera.fail_mortality x (1 - prep), rounded; its houses then stay empty for
# cholera.vacancy_min and fill cholera.recovery_mult as fast for cholera.recovery_min. The city keeps no people per
# house, so a district's pop is its share of the houses (issue #209); on a map without districts it is the city, and
# every class loses its share.
static func _cholera(state: EconomyState, params: Params, context: EconomyContext, mission: MissionDef) -> void:
	var failing: Dictionary[StringName, float] = _failing_districts(state, params, context, mission)
	if failing.is_empty():
		return
	var entry: MissionState = state.missions[mission.id]
	var houses: Dictionary[StringName, Array] = WaterSystem.district_houses(state, context)
	var all_houses: int = houses.values().reduce(func(total: int, list: Array) -> int: return total + list.size(), 0)
	var deaths: int = 0
	for district: StringName in failing:
		var share: float = 1.0 if houses.size() == 1 else float(houses[district].size()) / maxi(1, all_houses)
		var prep: float = preparation(params, failing[district])
		deaths += roundi(state.population * share * float(params.get_value(&"cholera.fail_mortality")) * (1.0 - prep))
	entry.deaths = _kill(state, context, deaths)
	entry.vacancy_ticks = SimTime.minutes_to_ticks(float(params.get_value(&"cholera.vacancy_min")))
	entry.recovery_ticks = SimTime.minutes_to_ticks(float(params.get_value(&"cholera.recovery_min")))


# prep_d (D-088). Nothing gives sewer_d or health_d yet, so they are 0 until they exist (Cristian, #202).
static func preparation(params: Params, water: float, sewer: float = 0.0, health: float = 0.0) -> float:
	return float(params.get_value(&"events.prep.w_water")) * water \
		+ float(params.get_value(&"events.prep.w_sewer")) * sewer \
		+ float(params.get_value(&"events.prep.w_health")) * health


# Deaths spread over the classes by their people, the largest remainders first. Not emigration (D-022).
static func _kill(state: EconomyState, context: EconomyContext, deaths: int) -> int:
	var population: int = state.population
	if population <= 0 or deaths <= 0:
		return 0
	var defs: Array[ClassDef] = ClassStates.defs(context)
	var shares: Array[int] = []
	var remainders: Array[Array] = []
	var given: int = 0
	for index: int in range(defs.size()):
		var people: int = ClassStates.population_of(state, defs[index])
		var exact: float = float(deaths) * people / population
		shares.append(floori(exact))
		given += shares[index]
		remainders.append([exact - shares[index], index])
	remainders.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	for rank: int in range(deaths - given):
		shares[remainders[rank][1]] += 1
	for index: int in range(defs.size()):
		var class_entry: ClassState = ClassStates.checkout(state, defs[index])
		ClassStates.grow(state, defs[index], class_entry, -shares[index])
		ClassStates.commit(state, defs[index], class_entry)
	WorkersSystem.trim_to_population(state)
	return deaths


# The districts with houses under the threshold. An empty district has 0 water (D-089) but nobody to protect, so it
# never fails (D-098).
static func _failing_districts(state: EconomyState, params: Params, context: EconomyContext,
		mission: MissionDef) -> Dictionary[StringName, float]:
	var threshold: float = float(params.get_value(mission.goal_key))
	var failing: Dictionary[StringName, float] = {}
	var houses: Dictionary[StringName, Array] = WaterSystem.district_houses(state, context)
	var water: Dictionary[StringName, float] = WaterSystem.district_water(state, params, context)
	for district: StringName in water:
		if not houses[district].is_empty() and water[district] < threshold:
			failing[district] = water[district]
	return failing


static func _housed(state: EconomyState, context: EconomyContext) -> bool:
	return WaterSystem.district_houses(state, context).values().any(func(list: Array) -> bool:
		return not list.is_empty())


# The vacancy runs first and the recovery after it, one growth step each.
static func _age_aftermath(entry: MissionState) -> void:
	if entry.vacancy_ticks > 0:
		entry.vacancy_ticks -= 1
	elif entry.recovery_ticks > 0:
		entry.recovery_ticks -= 1


static func _key(mission: MissionDef, field: String) -> StringName:
	return StringName("mission.%s.%s" % [mission.id, field])
