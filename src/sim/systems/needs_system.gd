class_name NeedsSystem
extends RefCounted

# Needs by category (issue #86). Each class lists goods; a good adds coverage * value to its category, and a
# category that reaches its threshold is met. Every met category grows the capacity of the class's housing.
# It runs inside step 7 (SatisfactionSystem.update_target), so the order of the tick does not change.


# Share of the demand for a good that the store covers, as the earlier steps of this tick left it.
# Bread uses the smoothed coverage the satisfaction already reads, so a category does not flicker per tick.
static func coverage(state: EconomyState, good: StringName) -> float:
	match good:
		&"bread":
			return state.hunger_smoothed_coverage
		&"tea":
			return state.tea_coverage
		_:
			# Nothing consumes the other goods yet (beer arrives with the artisans, issue #52).
			return 0.0


# Fills state.class_needs: for every class, its categories with value, threshold and whether it is met.
static func evaluate(state: EconomyState, params: Params, context: EconomyContext) -> void:
	state.class_needs.clear()
	for definition: ClassDef in context.classes.values():
		var categories: Dictionary = {}
		for need: NeedDef in definition.needs:
			var key: StringName = StringName("class.%s.need.%s.value" % [definition.id, need.good])
			var points: float = coverage(state, need.good) * float(params.get_value(key))
			var entry: Dictionary = categories.get(need.category, {"value": 0.0})
			entry["value"] = float(entry["value"]) + points
			categories[need.category] = entry
		for category: StringName in categories:
			var entry: Dictionary = categories[category]
			entry["threshold"] = float(params.get_value(StringName("needs.%s.threshold" % category)))
			entry["met"] = reaches(entry["value"], entry["threshold"])
		state.class_needs[definition.id] = categories


# Largest share of the threshold that is arithmetic drift and not a real shortfall: a score is a handful of
# products and sums of doubles, whose rounding error is about 1e-16 of their size. Relative, so a tiny
# threshold is never swallowed. It is not a balance value.
const DRIFT_TOLERANCE: float = 1e-12


# A score that is exactly the threshold on paper can land a hair under it in binary floating point
# (0.7 * 90 is 62.99999999999999, not 63), so the comparison forgives only that drift.
static func reaches(value: float, threshold: float) -> bool:
	return value >= threshold * (1.0 - DRIFT_TOLERANCE)


static func met_count(state: EconomyState, class_id: StringName) -> int:
	var count: int = 0
	for entry: Dictionary in state.class_needs.get(class_id, {}).values():
		if entry["met"]:
			count += 1
	return count


# Extra capacity per housing building of a class: a fixed bonus for each met category, up to the class maximum.
static func housing_bonus(state: EconomyState, params: Params, class_id: StringName) -> int:
	if class_id == &"":
		return 0
	var per_category: int = int(params.get_value(&"needs.housing_bonus_per_category"))
	var maximum: int = int(params.get_value(StringName("class.%s.housing_max_bonus" % class_id)))
	return mini(per_category * met_count(state, class_id), maximum)


# Total capacity of the housing buildings: their base plus the bonus of the class that lives in each.
# A housing building no class claims keeps its base.
static func housing_capacity(state: EconomyState, params: Params, context: EconomyContext) -> int:
	var total: int = 0
	var bonuses: Dictionary[StringName, int] = {}
	for building: Dictionary in state.buildings:
		var id: StringName = building["definition_id"]
		if "housing" not in context.buildings[id].tags:
			continue
		var class_id: StringName = context.class_of_housing(id)
		if not bonuses.has(class_id):
			bonuses[class_id] = housing_bonus(state, params, class_id)
		total += maxi(0, int(params.get_value(StringName("building.%s.capacity" % id)))) + bonuses[class_id]
	return total
