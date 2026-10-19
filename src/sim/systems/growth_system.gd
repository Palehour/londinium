class_name GrowthSystem
extends RefCounted

# Why a class is not growing (or is shrinking), for the diagnostics (issue #52).
const REASON_ARRIVING: StringName = &"arriving"
const REASON_NO_FREE_HOUSING: StringName = &"no_free_housing"
const REASON_SATISFACTION_LOW: StringName = &"satisfaction_below_threshold"
const REASON_HUNGRY: StringName = &"hungry_leaving"
const REASON_UNHAPPY: StringName = &"unhappy_leaving"
const REASON_STABLE: StringName = &"stable"


# Every class grows or shrinks by its own rules (its housing, satisfaction and rates); the people of one
# never move the others. Without a context the only class is the legacy one.
func tick(state: EconomyState, params: Params, context: EconomyContext = null) -> void:
	for def: ClassDef in ClassStates.defs(context):
		var entry: ClassState = ClassStates.checkout(state, def)
		_tick_class(state, params, def, entry)
		ClassStates.commit(state, def, entry)
	# Keep existing jobs; arrivals wait for step 2 of the following tick.
	WorkersSystem.trim_to_population(state)


func _tick_class(state: EconomyState, params: Params, def: ClassDef, entry: ClassState) -> void:
	# Ages first so the tick of a departure reads 0 and the window counts whole seconds since it.
	if entry.satisfaction_departure_age_seconds >= 0:
		entry.satisfaction_departure_age_seconds += 1
	var residents: int = entry.population
	var free_housing: int = free_room(state, params, def, entry)
	if entry.hunger_emigration_active:
		entry.hunger_emigration_active = state.hunger_coverage(def.id) \
			< float(params.get_value(def.hunger_recovery_key))
	else:
		entry.hunger_emigration_active = state.hunger_coverage(def.id) \
			< float(params.get_value(def.hunger_threshold_key))
	var hungry: bool = entry.hunger_emigration_active
	if not hungry and entry.satisfaction >= float(params.get_value(def.immigration_threshold_key)) \
			and free_housing > 0 and (residents > 0 or state.bread_coverage > 0.0):
		entry.emigration_fraction = 0.0
		entry.immigration_fraction += float(params.get_value(def.immigration_per_minute_key)) / 60.0
		var arrivals: int = mini(free_housing, ProductionSystem.whole_units(entry.immigration_fraction))
		ClassStates.grow(state, def, entry, arrivals)
		state.immigration_tick[def.id] = arrivals
		entry.immigration_fraction = maxf(0.0, entry.immigration_fraction - arrivals) \
			if arrivals < free_housing else 0.0
	elif (hungry or is_class_satisfaction_emigration_active(entry, params, def)) and residents > 0:
		entry.immigration_fraction = 0.0
		var rate: float = float(params.get_value(def.emigration_per_minute_key))
		if hungry:
			var multiplier: float = float(params.get_value(def.hunger_multiplier_key))
			rate *= 1.0 + (multiplier - 1.0) * (1.0 - state.bread_coverage * state.access(def.id, &"bread"))
		entry.emigration_fraction += rate / 60.0
		var departures: int = mini(residents, ProductionSystem.whole_units(entry.emigration_fraction))
		ClassStates.grow(state, def, entry, -departures)
		if hungry:
			state.emigration_hunger_tick[def.id] = departures
		else:
			state.emigration_unhappy_tick[def.id] = departures
		if departures > 0 and is_class_satisfaction_emigration_active(entry, params, def):
			entry.satisfaction_departure_age_seconds = 0
		entry.emigration_fraction = maxf(0.0, entry.emigration_fraction - departures) \
			if entry.population > 0 else 0.0
	else:
		# Blocked growth never becomes a backlog when housing or happiness recovers.
		entry.immigration_fraction = 0.0
		entry.emigration_fraction = 0.0


# The room immigrants can take (issue #180, D-085): only the free room of the served houses. People fill the served
# houses first (D-081), so that is the served room minus everybody, never more than the free room of all houses.
static func free_room(state: EconomyState, params: Params, def: ClassDef, entry: ClassState) -> int:
	var free: int = maxi(0, entry.housing_capacity - entry.population)
	if def.served_categories.is_empty() or not bool(params.get_value(&"population.growth.served_capacity_only")):
		return free
	var served: int = RoadSystem.served_room(state, params, def, entry.housing_capacity)
	return mini(free, maxi(0, served - entry.population))


static func is_satisfaction_emigration_active(state: EconomyState, params: Params) -> bool:
	var threshold: float = float(params.get_value(&"population.growth.emigration_threshold"))
	return state.satisfaction < threshold and state.satisfaction_target < threshold


static func is_class_satisfaction_emigration_active(entry: ClassState, params: Params, def: ClassDef) -> bool:
	var threshold: float = float(params.get_value(def.emigration_threshold_key))
	return entry.satisfaction < threshold and entry.satisfaction_target < threshold


# What the growth of a class is doing now and why, as a stable id the UI translates.
static func reason(state: EconomyState, params: Params, def: ClassDef, entry: ClassState) -> StringName:
	if entry.hunger_emigration_active and entry.population > 0:
		return REASON_HUNGRY
	if entry.population > 0 and is_class_satisfaction_emigration_active(entry, params, def):
		return REASON_UNHAPPY
	if entry.satisfaction < float(params.get_value(def.immigration_threshold_key)):
		return REASON_SATISFACTION_LOW
	if free_room(state, params, def, entry) <= 0:
		return REASON_NO_FREE_HOUSING
	return REASON_ARRIVING if entry.population > 0 or state.bread_coverage > 0.0 else REASON_STABLE
