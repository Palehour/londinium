class_name MobilitySystem
extends RefCounted

# Mobility between classes (issue #53, D-061). A class with a mobility block takes people of its source class
# when its own need categories reach their minimum scores, the source class is satisfied enough and its housing
# has room; it gives them back when its demotion category stays under its score for long enough. Both move at a
# rate per minute, through a fraction like growth. It runs after growth (step 8b), so this tick's arrivals take
# the free housing first and the money step already taxes everyone in their new class.

const REASON_NO_SOURCE_POPULATION: StringName = &"no_source_population"
const REASON_NO_FREE_HOUSING: StringName = GrowthSystem.REASON_NO_FREE_HOUSING
const REASON_CATEGORY_BELOW: StringName = &"category_below"
const REASON_SOURCE_SATISFACTION_LOW: StringName = &"source_satisfaction_low"


func tick(state: EconomyState, params: Params, context: EconomyContext = null) -> void:
	if context == null:
		return
	var moved: bool = false
	for def: ClassDef in context.classes.values():
		if def.has_mobility():
			moved = _tick_class(state, params, context, def) or moved
	# Promoted people leave their jobs; the jobs of those still looking stay, so the unemployed rise first.
	if moved:
		WorkersSystem.trim_to_population(state)


# Returns whether anyone moved.
func _tick_class(state: EconomyState, params: Params, context: EconomyContext, def: ClassDef) -> bool:
	var source: ClassDef = context.classes[def.mobility_from]
	var entry: ClassState = ClassStates.checkout(state, def)
	# The clock only runs while there is someone to fall back: an empty class (no beer for nobody) has not been
	# short of anything, and its first arrivals must not fall back at once.
	var below: bool = entry.population > 0 and not NeedsSystem.reaches(score(state, def.id, def.demotion_category),
		float(params.get_value(def.demotion_below_key)))
	entry.demotion_seconds_below = entry.demotion_seconds_below + 1 if below else 0
	if is_demotion_active(entry, params, def):
		entry.promotion_fraction = 0.0
		entry.demotion_fraction += float(params.get_value(def.demotion_per_minute_key)) / 60.0
		var falling: int = mini(entry.population, ProductionSystem.whole_units(entry.demotion_fraction))
		_move(state, source, entry, -falling)
		state.demotions_tick += falling
		entry.demotion_fraction = maxf(0.0, entry.demotion_fraction - falling) if entry.population > 0 else 0.0
		return falling > 0
	entry.demotion_fraction = 0.0
	if not promotion_blockers(state, params, context, def).is_empty():
		# Blocked promotion never becomes a backlog, like blocked growth.
		entry.promotion_fraction = 0.0
		return false
	entry.promotion_fraction += float(params.get_value(def.promotion_per_minute_key)) / 60.0
	var room: int = mini(entry.housing_capacity - entry.population, ClassStates.population_of(state, source))
	var rising: int = mini(room, ProductionSystem.whole_units(entry.promotion_fraction))
	_move(state, source, entry, rising)
	state.promotions_tick += rising
	entry.promotion_fraction = maxf(0.0, entry.promotion_fraction - rising) if rising < room else 0.0
	return rising > 0


# The total never changes: the base class is what the others leave, and any other source gives its own people.
static func _move(state: EconomyState, source: ClassDef, entry: ClassState, change: int) -> void:
	entry.population += change
	if not source.base:
		state.class_states[source.id].population -= change


static func score(state: EconomyState, class_id: StringName, category: StringName) -> float:
	var categories: Dictionary = state.class_needs.get(class_id, {})
	return float(categories[category]["value"]) if categories.has(category) else 0.0


static func is_demotion_active(entry: ClassState, params: Params, def: ClassDef) -> bool:
	return entry.demotion_seconds_below >= int(params.get_value(def.demotion_seconds_key))


# Everything that stops people from rising into the class now, as ids the UI translates; empty when they rise.
static func promotion_blockers(state: EconomyState, params: Params, context: EconomyContext,
		def: ClassDef) -> Array[Dictionary]:
	var blockers: Array[Dictionary] = []
	var source: ClassDef = context.classes[def.mobility_from]
	if ClassStates.population_of(state, source) <= 0:
		blockers.append({"reason": REASON_NO_SOURCE_POPULATION})
	var entry: ClassState = ClassStates.checkout(state, def)
	if entry.housing_capacity - entry.population <= 0:
		blockers.append({"reason": REASON_NO_FREE_HOUSING})
	for category: StringName in def.promotion_min_score_keys:
		var minimum: float = float(params.get_value(def.promotion_min_score_keys[category]))
		var value: float = score(state, def.id, category)
		if not NeedsSystem.reaches(value, minimum):
			blockers.append({"reason": REASON_CATEGORY_BELOW, "category": category, "value": value,
				"minimum": minimum, "missing_goods": _missing_goods(state, params, def, category)})
	var satisfaction: float = ClassStates.checkout(state, source).satisfaction
	var required: float = float(params.get_value(def.promotion_source_satisfaction_key))
	if satisfaction < required:
		blockers.append({"reason": REASON_SOURCE_SATISFACTION_LOW, "satisfaction": satisfaction, "minimum": required})
	return blockers


# Goods of the category whose coverage could still raise its score (the beer, for the artisans' community).
static func _missing_goods(state: EconomyState, params: Params, def: ClassDef, category: StringName) -> Array[StringName]:
	var missing: Array[StringName] = []
	for need: NeedDef in def.needs:
		if need.category != category or NeedsSystem.coverage(state, need.good) >= 1.0:
			continue
		if float(params.get_value(StringName("class.%s.need.%s.value" % [def.id, need.good]))) > 0.0:
			missing.append(need.good)
	return missing


# What the mobility of a class is doing and why, for the panel (#54); empty for a class without mobility.
static func diagnostics(state: EconomyState, params: Params, context: EconomyContext, def: ClassDef) -> Dictionary:
	if not def.has_mobility():
		return {}
	var entry: ClassState = ClassStates.checkout(state, def)
	var blockers: Array[Dictionary] = promotion_blockers(state, params, context, def)
	return {
		"from": def.mobility_from,
		"promotion": {"active": blockers.is_empty(), "blockers": blockers,
			"per_minute": float(params.get_value(def.promotion_per_minute_key))},
		"demotion": {"active": is_demotion_active(entry, params, def), "category": def.demotion_category,
			"seconds_below": entry.demotion_seconds_below,
			"seconds_required": int(params.get_value(def.demotion_seconds_key)),
			"per_minute": float(params.get_value(def.demotion_per_minute_key))},
	}
