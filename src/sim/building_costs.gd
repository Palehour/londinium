class_name BuildingCosts
extends RefCounted

# Money sinks of issue #118 (D-063): a bigger city costs more to run and each copy of a building more to build.
# Both depend on the city, so they cannot be role modifiers; their parameters still go through Params (D-014).


# Upkeep multiplier: every building past the free ones adds per_building, up to max_multiplier.
static func administration_multiplier(params: Params, building_count: int) -> float:
	var free: int = int(params.get_value(&"economy.administration.free_buildings"))
	var per_building: float = float(params.get_value(&"economy.administration.per_building"))
	var extra: int = maxi(0, building_count - free)
	return minf(float(params.get_value(&"economy.administration.max_multiplier")), 1.0 + per_building * extra)


# Price of the next building of this type: the first free_copies cost the base price, and each copy after them is
# per_building dearer than the one before (compounded), up to max_multiplier times the base cost. Compounding was
# decided by Cristian in the plan of #118, and the free copies in his revision of 2026-10-14.
static func construction_cost(params: Params, state: EconomyState, definition_id: StringName) -> int:
	var base: int = int(params.get_value(StringName("building.%s.cost" % definition_id)))
	var step: float = 1.0 + float(params.get_value(&"economy.construction_escalation.per_building"))
	var free_copies: int = int(params.get_value(&"economy.construction_escalation.free_copies"))
	# The next building is copy number count + 1.
	var escalated: int = maxi(0, count_of(state, definition_id) + 1 - free_copies)
	var multiplier: float = pow(step, escalated)
	return roundi(base * minf(float(params.get_value(&"economy.construction_escalation.max_multiplier")), multiplier))


static func count_of(state: EconomyState, definition_id: StringName) -> int:
	var count: int = 0
	for building: Dictionary in state.buildings:
		if StringName(building["definition_id"]) == definition_id:
			count += 1
	return count
