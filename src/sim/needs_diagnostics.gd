class_name NeedsDiagnostics
extends RefCounted

# Why each class meets or misses its need categories, and what that does to its housing (issue #86).
# The UI only formats this; ids (class, category, good, reason) are the keys that strings.gd translates.

const REASON_UNSERVED_HOUSING: StringName = &"unserved_housing"


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
		# Use safe reads only (no checkout/ensure for diagnosis; read-only snapshot even if class state missing).
		var sat_cur: float = ClassStates.satisfaction_of(state, definition)
		var sat_tgt: float = ClassStates.satisfaction_target_of(state, definition)
		var sat_bd: Dictionary = ClassStates.satisfaction_breakdown_of(state, definition)
		classes[definition.id] = {
			"categories": categories,
			"population": ClassStates.population_of(state, definition),
			"satisfaction": {
				"current": sat_cur, "target": sat_tgt,
				"breakdown": sat_bd,
			},
			"growth": {"reason": GrowthSystem.reason(state, params, definition, _temp_entry_for_reason(state, definition))},
			"housing": {
				"building": definition.housing_building,
				"base": maxi(0, int(params.get_value(StringName("building.%s.capacity" % definition.housing_building)))),
				"bonus": NeedsSystem.housing_bonus(state, params, definition.id),
				"max_bonus": int(params.get_value(StringName("class.%s.housing_max_bonus" % definition.id))),
			},
			"mobility": MobilitySystem.diagnostics(state, params, context, definition),
			"blockers": compute_blockers(state, params, context, definition),
		}
	var top: Dictionary = {"classes": classes}
	if context != null and params != null:
		if params.has_value(&"ui.blockers.max_lines"):
			top["blockers_max_lines"] = int(params.get_value(&"ui.blockers.max_lines"))
		else:
			top["blockers_max_lines"] = 1
		if params.has_value(&"ui.blockers.sort"):
			top["blockers_sort"] = params.get_value(&"ui.blockers.sort")
		else:
			top["blockers_sort"] = &"gap"
	return top


# Pure function (no mutation, no ClassStates.ensure/checkout). house optional for room calc to keep read-only.
static func compute_blockers(state: EconomyState, params: Params, context: EconomyContext, definition: ClassDef, house: ClassState = null) -> Array[Dictionary]:
	if context == null or params == null:
		return []
	var gbs: Array[Dictionary] = _growth_blockers(state, params, definition, house)
	var pbs: Array[Dictionary] = []
	if definition.has_mobility():
		pbs = _promotion_blockers(state, params, context, definition)
	gbs = _sort_blockers(gbs)
	pbs = _sort_blockers(pbs)
	var result: Array[Dictionary] = []
	for b: Dictionary in gbs:
		var bb: Dictionary = b.duplicate(true)
		bb["group"] = &"growth"
		result.append(bb)
	for b: Dictionary in pbs:
		var bb: Dictionary = b.duplicate(true)
		bb["group"] = &"promotion"
		if bb.has("minimum"):
			bb["threshold"] = bb["minimum"]
			if bb.has("satisfaction") and not bb.has("value"):
				bb["value"] = bb["satisfaction"]
		result.append(bb)
	return result


static func _growth_blockers(state: EconomyState, params: Params, def: ClassDef, house: ClassState = null) -> Array[Dictionary]:
	var gbs: Array[Dictionary] = []
	var evaluated: Dictionary = state.class_needs.get(def.id, {})
	var cat_order: Array[StringName] = []
	for n: NeedDef in def.needs:
		if n.category not in cat_order:
			cat_order.append(n.category)
	for cat: StringName in cat_order:
		if not evaluated.has(cat):
			continue
		var entry: Dictionary = evaluated[cat]
		if entry["met"]:
			continue
		var missing: Array[StringName] = NeedsSystem.missing_goods(state, params, def, cat)
		gbs.append({
			"reason": entry.get("reason", &"below_threshold"),
			"category": cat,
			"value": entry["value"],
			"threshold": entry["threshold"],
			"missing_goods": missing,
		})
	# Housing blocker (unmeasurable) for growth if no free room.
	# A served house that is full is different from a house beyond the goods' reach (D-085, issue #351).
	var popu: int = ClassStates.population_of(state, def)
	var cap: int = ClassStates.housing_capacity_of(state, def)
	var h: ClassState = house if house != null else ClassState.new()
	if house == null:
		h.population = popu
		h.housing_capacity = cap
	var free: int = GrowthSystem.free_room(state, params, def, h)
	if free <= 0:
		var physical_free: int = maxi(0, cap - popu)
		if physical_free > 0 and not def.served_categories.is_empty():
			var missing: Array[StringName] = []
			for need: NeedDef in def.needs:
				if need.category in def.served_categories:
					missing.append(need.good)
			gbs.append({"reason": REASON_UNSERVED_HOUSING, "missing_goods": missing})
		else:
			gbs.append({"reason": GrowthSystem.REASON_NO_FREE_HOUSING})
	return gbs


static func _promotion_blockers(state: EconomyState, params: Params, context: EconomyContext, def: ClassDef) -> Array[Dictionary]:
	# Delegate to (updated) Mobility but normalize for snapshot contract (value/threshold).
	var raw: Array[Dictionary] = MobilitySystem.promotion_blockers(state, params, context, def)
	var norm: Array[Dictionary] = []
	for b: Dictionary in raw:
		var bb: Dictionary = b.duplicate(true)
		if bb.has("minimum"):
			bb["threshold"] = bb["minimum"]
			if bb.has("satisfaction") and not bb.has("value"):
				bb["value"] = bb["satisfaction"]
		norm.append(bb)
	return norm


static func _measurable_gap(b: Dictionary) -> float:
	if b.has("value") and b.has("threshold"):
		var v: float = float(b["value"])
		var t: float = float(b["threshold"])
		if is_finite(v) and is_finite(t):
			return t - v
	return -1.0


static func _sort_blockers(bs: Array[Dictionary]) -> Array[Dictionary]:
	if bs.is_empty():
		return bs
	var indexed: Array = []
	for i: int in bs.size():
		var g: float = _measurable_gap(bs[i])
		var is_meas: int = 0 if g >= 0.0 else 1
		var is_unserved: int = 0 if bs[i].get("reason") == REASON_UNSERVED_HOUSING else 1
		indexed.append({"b": bs[i], "key": [is_unserved, is_meas, -g, i]})
	indexed.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var kx: Array = x["key"]
		var ky: Array = y["key"]
		for j: int in range(kx.size()):
			if kx[j] != ky[j]:
				return kx[j] < ky[j]
		return false
	)
	var out: Array[Dictionary] = []
	for item: Dictionary in indexed:
		out.append(item["b"])
	return out


# Temp entry for legacy GrowthSystem.reason (read-only fields only; never inserted to state).
static func _temp_entry_for_reason(state: EconomyState, def: ClassDef) -> ClassState:
	var e: ClassState = ClassState.new()
	e.population = ClassStates.population_of(state, def)
	e.housing_capacity = ClassStates.housing_capacity_of(state, def)
	e.satisfaction = ClassStates.satisfaction_of(state, def)
	e.satisfaction_target = ClassStates.satisfaction_target_of(state, def)
	if def.base:
		e.hunger_emigration_active = state.hunger_emigration_active
	else:
		var entry: ClassState = state.class_states.get(def.id)
		e.hunger_emigration_active = entry.hunger_emigration_active if entry != null else false
	return e
