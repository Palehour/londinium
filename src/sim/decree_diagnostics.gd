class_name DecreeDiagnostics
extends RefCounted

# Read-only view of the era's decrees (issue #71). Must not mutate state.

const EFFECT_RATES_UPKEEP: StringName = &"rates_upkeep"


static func build(state: EconomyState, params: Params, context: EconomyContext) -> Array:
	var rows: Array[Dictionary] = []
	if context == null:
		return rows
	for decree: DecreeDef in context.decrees.values():
		rows.append({
			"id": decree.id,
			"name_key": decree.name_key,
			"active": decree.id in state.active_decrees,
			"in_competence": decree.id in context.decree_competencies,
			"for": decree.for_factions.duplicate(),
			"against": decree.against_factions.duplicate(),
			"enact_cost": DecreeSystem.enact_cost(state, params, context, decree),
			"revoke_cost": DecreeSystem.revoke_cost(state, params, context, decree),
			"upkeep_per_min": _upkeep(params, decree),
			"effect": EFFECT_RATES_UPKEEP,
		})
	return rows


static func _upkeep(params: Params, decree: DecreeDef) -> int:
	if not params.has_value(decree.upkeep_key):
		return 0
	return int(params.get_value(decree.upkeep_key))
