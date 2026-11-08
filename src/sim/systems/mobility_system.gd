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


func tick(state: EconomyState, params: Params, context: EconomyContext = null, events: Dictionary = {}) -> void:
	if context == null:
		return
	var moved: bool = false
	for def: ClassDef in context.classes.values():
		if def.has_mobility():
			moved = _tick_class(state, params, context, def) or moved
	# Promoted people leave their jobs; the jobs of those still looking stay, so the unemployed rise first.
	# Only record post losses from promotion (ascenso that decrease job class pop); trim after movements.
	# events provided by caller (Simulation) so no field in EconomyState (ADR0011). Snapshot uses real tick.
	if moved:
		var ev: Dictionary = events
		if ev.is_empty():
			ev = {"tick": 0, "employed_promoted": 0, "buildings": []}
		var pre: Dictionary = _capture_worker_counts(state)
		WorkersSystem.trim_to_population(state)
		_populate_promotion_events(ev, state, pre)


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
		state.demotions_by_class_tick[def.id] = falling
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
	state.promotions_by_class_tick[def.id] = rising
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


static func is_demotion_active_for_seconds(seconds: int, params: Params, def: ClassDef) -> bool:
	return seconds >= int(params.get_value(def.demotion_seconds_key))


# Everything that stops people from rising into the class now, as ids the UI translates; empty when they rise.
static func promotion_blockers(state: EconomyState, params: Params, context: EconomyContext,
		def: ClassDef) -> Array[Dictionary]:
	var blockers: Array[Dictionary] = []
	var source: ClassDef = context.classes[def.mobility_from]
	if ClassStates.population_of(state, source) <= 0:
		blockers.append({"reason": REASON_NO_SOURCE_POPULATION})
	var cap: int = ClassStates.housing_capacity_of(state, def)
	var pop: int = ClassStates.population_of(state, def)
	if cap - pop <= 0:
		blockers.append({"reason": REASON_NO_FREE_HOUSING})
	for category: StringName in def.promotion_min_score_keys:
		var minimum: float = float(params.get_value(def.promotion_min_score_keys[category]))
		var value: float = score(state, def.id, category)
		if not NeedsSystem.reaches(value, minimum):
			blockers.append({"reason": REASON_CATEGORY_BELOW, "category": category, "value": value,
				"minimum": minimum, "missing_goods": missing_goods(state, params, def, category)})
	var satisfaction: float = ClassStates.satisfaction_of(state, source)
	var required: float = float(params.get_value(def.promotion_source_satisfaction_key))
	if satisfaction < required:
		blockers.append({"reason": REASON_SOURCE_SATISFACTION_LOW, "satisfaction": satisfaction, "minimum": required})
	return blockers


# Goods of the category whose coverage could still raise its score (the beer, for the artisans' community).
static func missing_goods(state: EconomyState, params: Params, def: ClassDef, category: StringName) -> Array[StringName]:
	return NeedsSystem.missing_goods(state, params, def, category)


# What the mobility of a class is doing and why, for the panel (#54); empty for a class without mobility.
static func diagnostics(state: EconomyState, params: Params, context: EconomyContext, def: ClassDef) -> Dictionary:
	if not def.has_mobility():
		return {}
	var blockers: Array[Dictionary] = promotion_blockers(state, params, context, def)
	var entry_seconds: int = ClassStates.demotion_seconds_below_of(state, def)
	return {
		"from": def.mobility_from,
		"promotion": {"active": blockers.is_empty(), "blockers": blockers,
			"per_minute": float(params.get_value(def.promotion_per_minute_key))},
		"demotion": {"active": is_demotion_active_for_seconds(entry_seconds, params, def), "category": def.demotion_category,
			"seconds_below": entry_seconds,
			"seconds_required": int(params.get_value(def.demotion_seconds_key)),
			"seconds_left": maxi(0, int(params.get_value(def.demotion_seconds_key)) - entry_seconds),
			"per_minute": float(params.get_value(def.demotion_per_minute_key)),
			"missing_goods": missing_goods(state, params, def, def.demotion_category)},
	}


# Capture pre-trim workers counts by stable key (cell if present else index) to diff only ascenso losses.
# id is stable: cell array when building has "cell" (real games), else index for headless tests.
static func _capture_worker_counts(state: EconomyState) -> Dictionary:
	var counts: Dictionary = {}
	for i: int in range(state.buildings.size()):
		var b: Dictionary = state.buildings[i]
		var key: Variant = _building_key(b, i)
		counts[key] = int(b.get("workers", 0))
	return counts


static func _building_key(b: Dictionary, idx: int) -> Variant:
	if b.has("cell"):
		var c: Variant = b["cell"]
		if c is Vector2i:
			return [c.x, c.y]
		if c is Array:
			return c.duplicate()
		return c
	return idx


# Populate ONLY promotion lost posts (after trim, only ascenso). Does not alter trim/econ/order. Writes to provided events dict (outside state).
static func _populate_promotion_events(events: Dictionary, state: EconomyState, pre: Dictionary) -> void:
	var lost_total: int = 0
	var lost_list: Array[Dictionary] = []
	for i: int in range(state.buildings.size()):
		var b: Dictionary = state.buildings[i]
		var key: Variant = _building_key(b, i)
		var before: int = int(pre.get(key, 0))
		var after: int = int(b.get("workers", 0))
		var lost: int = before - after
		if lost > 0:
			lost_total += lost
			lost_list.append({
				"id": key,
				"definition_id": b["definition_id"],
				"workers_lost": lost
			})
	events["employed_promoted"] = lost_total
	events["buildings"] = lost_list
