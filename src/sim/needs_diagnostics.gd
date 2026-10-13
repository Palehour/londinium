class_name NeedsDiagnostics
extends RefCounted

# Why each class meets or misses its need categories, and what that does to its housing (issue #86).
# The UI only formats this; ids (class, category, good, reason) are the keys that strings.gd translates.


# unreachable_threshold: even with every good fully covered the category could not reach its threshold.
static func _reason(entry: Dictionary, attainable: float) -> StringName:
	if entry["met"]:
		return &"ok"
	var reachable: bool = NeedsSystem.reaches(attainable, float(entry["threshold"]))
	return &"below_threshold" if reachable else &"unreachable_threshold"


static func build(state: EconomyState, params: Params, context: EconomyContext) -> Dictionary:
	var classes: Dictionary = {}
	if context == null:
		return {"classes": classes}
	for definition: ClassDef in context.classes.values():
		var categories: Array[Dictionary] = []
		var evaluated: Dictionary = state.class_needs.get(definition.id, {})
		for category: StringName in evaluated:
			var entry: Dictionary = evaluated[category]
			var goods: Array[Dictionary] = []
			var missing: Array[StringName] = []
			var attainable: float = 0.0
			for need: NeedDef in definition.needs:
				if need.category != category:
					continue
				var coverage: float = NeedsSystem.coverage(state, need.good)
				var worth: float = float(params.get_value(StringName("class.%s.need.%s.value" % [definition.id, need.good])))
				goods.append({"good": need.good, "coverage": coverage})
				# A good worth nothing cannot raise the score, so covering it is never what is missing.
				if coverage < 1.0 and worth > 0.0:
					missing.append(need.good)
				attainable += worth
			categories.append({
				"category": category, "value": entry["value"], "threshold": entry["threshold"],
				"met": entry["met"], "reason": _reason(entry, attainable),
				"goods": goods, "missing_goods": missing,
			})
		var entry: ClassState = ClassStates.checkout(state, definition)
		classes[definition.id] = {
			"categories": categories,
			"population": ClassStates.population_of(state, definition),
			"satisfaction": {
				"current": entry.satisfaction, "target": entry.satisfaction_target,
				"breakdown": entry.satisfaction_breakdown.duplicate(),
			},
			"growth": {"reason": GrowthSystem.reason(state, params, definition, entry)},
			"housing": {
				"building": definition.housing_building,
				"base": maxi(0, int(params.get_value(StringName("building.%s.capacity" % definition.housing_building)))),
				"bonus": NeedsSystem.housing_bonus(state, params, definition.id),
				"max_bonus": int(params.get_value(StringName("class.%s.housing_max_bonus" % definition.id))),
			},
		}
	return {"classes": classes}
