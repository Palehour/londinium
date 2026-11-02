class_name DecreeSystem
extends RefCounted

# Decrees paid from the legitimacy reserve (issue #71, D-124, D-125, D-126). Enacting costs the weight of the
# factions against, revoking the weight of those in favor, then FactionSystem.cost applies the low-legitimacy
# multiplier. Upkeep is charged outside the administration multiplier and joins the rates spending.
# TODO-OK-Cristian: decree ids, upkeep_per_min values and scenario competencies are not in D-124, D-125 or D-126. The shipped catalog stays empty.

const UNKNOWN: StringName = &"unknown_decree"
const NOT_IN_COMPETENCE: StringName = &"not_in_competence"
const ALREADY_ACTIVE: StringName = &"already_active"
const NOT_ACTIVE: StringName = &"not_active"
const NO_FACTIONS: StringName = &"no_factions"


static func enact(state: EconomyState, params: Params, context: EconomyContext, id: StringName) -> StringName:
	if not _known(context, id):
		return UNKNOWN
	if id not in context.decree_competencies:
		return NOT_IN_COMPETENCE
	if id in state.active_decrees:
		return ALREADY_ACTIVE
	if not _factions_ready(state, context):
		return NO_FACTIONS
	if not FactionSystem.spend(state, enact_cost(state, params, context, context.decrees[id])):
		return FactionSystem.NOT_ENOUGH_LEGITIMACY
	state.active_decrees.append(id)
	return &""


static func revoke(state: EconomyState, params: Params, context: EconomyContext, id: StringName) -> StringName:
	if not _known(context, id):
		return UNKNOWN
	if id not in state.active_decrees:
		return NOT_ACTIVE
	if not _factions_ready(state, context):
		return NO_FACTIONS
	if not FactionSystem.spend(state, revoke_cost(state, params, context, context.decrees[id])):
		return FactionSystem.NOT_ENOUGH_LEGITIMACY
	state.active_decrees.erase(id)
	return &""


static func enact_cost(state: EconomyState, params: Params, context: EconomyContext, decree: DecreeDef) -> float:
	return FactionSystem.cost(state, params, _side_cost(state, params, context, decree.against_factions))


static func revoke_cost(state: EconomyState, params: Params, context: EconomyContext, decree: DecreeDef) -> float:
	return FactionSystem.cost(state, params, _side_cost(state, params, context, decree.for_factions))


# After the loan tick, so the receiver flag is already set, and before the faction tick, which reads this upkeep.
static func tick(state: EconomyState, params: Params, _context: EconomyContext) -> void:
	if state.loan != null and state.loan.receiver:
		# Lapse is not a revoke: the unpaid remainder is dropped, not charged later.
		state.active_decrees.clear()
		state.decree_upkeep_fraction = 0.0
		return
	state.decree_upkeep_fraction += upkeep_per_minute(state, params) / float(SimTime.TICKS_PER_MINUTE)
	var paid: int = ProductionSystem.whole_units(state.decree_upkeep_fraction)
	state.money -= paid
	state.decree_upkeep_fraction = maxf(0.0, state.decree_upkeep_fraction - float(paid))


# A missing key is 0, so a fixture without one does not push_error.
static func upkeep_per_minute(state: EconomyState, params: Params) -> float:
	var total: float = 0.0
	for id: StringName in state.active_decrees:
		var key: StringName = DecreeDef.upkeep_key_for(id)
		if params.has_value(key):
			total += float(params.get_value(key))
	return total


static func save_of(state: EconomyState) -> Dictionary:
	return {"active": state.active_decrees.duplicate(), "upkeep_fraction": state.decree_upkeep_fraction}


static func restore(state: EconomyState, saved: Dictionary) -> void:
	state.active_decrees.clear()
	var active: Variant = saved.get("active", [])
	if active is Array:
		for id: Variant in active:
			state.active_decrees.append(StringName(id))
	state.decree_upkeep_fraction = float(saved.get("upkeep_fraction", 0.0))


static func _known(context: EconomyContext, id: StringName) -> bool:
	return context != null and context.decrees.has(id)


static func _factions_ready(state: EconomyState, context: EconomyContext) -> bool:
	return FactionSystem.enabled(context) and state.legitimacy >= 0.0


static func _side_cost(state: EconomyState, params: Params, context: EconomyContext,
		ids: Array[StringName]) -> float:
	return float(params.get_value(&"factions.decree_legitimacy_cost")) * _weight_sum(state, params, context, ids)


static func _weight_sum(state: EconomyState, params: Params, context: EconomyContext,
		ids: Array[StringName]) -> float:
	if context == null:
		return 0.0
	var weights: Dictionary[StringName, float] = FactionSystem.weights(state, params, context)
	var total: float = 0.0
	for id: StringName in ids:
		total += float(weights.get(id, 0.0))
	return total
