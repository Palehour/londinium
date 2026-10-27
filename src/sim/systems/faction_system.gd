class_name FactionSystem
extends RefCounted

# Factions and legitimacy (issue #84, D-115, D-116, D-139, D-140; values of D-141). Each faction's support follows a
# target set by its fixed engine at support_drift_per_min. The ceiling P weighs those supports by how much of the
# population leans to each faction (each class splits its affinity among them), and the legitimacy reserve fills
# towards P at legitimacy_fill_per_min, or falls to it legitimacy_drain_multiplier times faster when P is below it.
# Spending it is what decrees (#71) do: an action that costs more than the reserve is refused, so it is never negative,
# and below low_legitimacy_threshold everything costs low_legitimacy_cost_multiplier times more. Low legitimacy only
# makes things dearer or impossible: no defeat and no event at any threshold (D-139, point 3).
# Hooks for #81 (D-139, point 6): prestige adds to state.legitimacy_gain_tick, like an early loan payoff, and a patron
# moves its faction's support with shift_support().

const MIN_POINTS: float = 0.0
const MAX_POINTS: float = 100.0
const NOT_ENOUGH_LEGITIMACY: StringName = &"not_enough_legitimacy"


static func enabled(context: EconomyContext) -> bool:
	return context != null and not context.factions.is_empty()


# A new game, or a save from before the factions: supports start at their targets and the reserve at legitimacy_start.
static func initialize(state: EconomyState, params: Params, context: EconomyContext) -> void:
	if not enabled(context) or state.legitimacy >= 0.0:
		return
	for faction: FactionDef in context.factions.values():
		state.faction_support[faction.id] = target(state, params, context, faction)
	state.legitimacy = float(params.get_value(&"factions.legitimacy_start"))


# After LoanSystem, so the rates it charged and the legitimacy an early payoff earned count this very tick.
static func tick(state: EconomyState, params: Params, context: EconomyContext) -> void:
	if not enabled(context) or state.legitimacy < 0.0:
		return
	var step: float = float(params.get_value(&"factions.support_drift_per_min")) / SimTime.TICKS_PER_MINUTE
	for faction: FactionDef in context.factions.values():
		var support: float = state.faction_support.get(faction.id, target(state, params, context, faction))
		state.faction_support[faction.id] = move_toward(support, target(state, params, context, faction), step)
	_fill(state, params, ceiling(state, params, context))


static func _fill(state: EconomyState, params: Params, top: float) -> void:
	var fill: float = float(params.get_value(&"factions.legitimacy_fill_per_min")) / SimTime.TICKS_PER_MINUTE
	var reserve: float = state.legitimacy + state.legitimacy_gain_tick
	if reserve < top:
		reserve = minf(top, reserve + fill)
	else:
		reserve = maxf(top, reserve - fill * float(params.get_value(&"factions.legitimacy_drain_multiplier")))
	state.legitimacy = clampf(reserve, MIN_POINTS, MAX_POINTS)


# target_base + target_scale x the engine's driver, clipped to 0-100. The ratepayers' driver is minus their ratio.
static func target(state: EconomyState, params: Params, context: EconomyContext, faction: FactionDef) -> float:
	var driver: float = 0.0
	match faction.engine:
		FactionDef.RATES_RATIO:
			driver = -rates_ratio(state, params, context)
		FactionDef.SERVICE_COVERAGE:
			driver = coverage(state, context, faction.coverage)
		FactionDef.STABILITY:
			driver = stability(state, context)
	var value: float = float(params.get_value(faction.target_base_key())) \
		+ float(params.get_value(faction.target_scale_key())) * driver
	return clampf(value, MIN_POINTS, MAX_POINTS)


# gasto_tasas / max(R, factions.ratio_income_floor) (D-139, D-140), both per minute: with R = 0 it stays finite.
static func rates_ratio(state: EconomyState, params: Params, context: EconomyContext) -> float:
	var income: float = MoneySystem.tax_per_minute(state, params, context)
	var floor_income: float = float(params.get_value(&"factions.ratio_income_floor"))
	return rates_spending_per_minute(state, params, income) / maxf(income, floor_income)


# What the rates pay for, per minute: the loan installment (charged as a rate, D-127) spread over its interval, or
# every tax while the receiver takes them (D-128). The decree upkeep of #71 (D-125) joins here.
static func rates_spending_per_minute(state: EconomyState, params: Params, income: float) -> float:
	var loan: LoanState = state.loan
	if loan == null:
		return 0.0
	if loan.receiver:
		return income
	var interval: float = float(params.get_value(&"loan.installment_interval_s"))
	return loan.installment(loan.installments_paid) * SimTime.TICKS_PER_MINUTE / interval


# Share of the houses, 0 to 1, that every service in `attributes` reaches (D-141). No houses: 0.
static func coverage(state: EconomyState, context: EconomyContext, attributes: Array[StringName]) -> float:
	var houses: int = 0
	var covered: int = 0
	for building: Dictionary in state.buildings:
		var definition: BuildingDef = context.buildings.get(StringName(building["definition_id"]))
		if definition == null or WaterSystem.HOUSING_TAG not in definition.tags:
			continue
		houses += 1
		# A building of an old save may have no cell yet: nothing covers it.
		var cover: Dictionary = state.service_cover.get(RoadNetwork.cell_of(building), {}) \
			if building.has("cell") else {}
		if attributes.all(func(attribute: StringName) -> bool: return not cover.get(attribute, []).is_empty()):
			covered += 1
	return float(covered) / houses if houses > 0 else 0.0


# The mean satisfaction over 100, every class weighed by its people (D-141). An empty city: the base class's.
static func stability(state: EconomyState, context: EconomyContext) -> float:
	var people: int = 0
	var total: float = 0.0
	for def: ClassDef in ClassStates.defs(context):
		var count: int = ClassStates.population_of(state, def)
		people += count
		total += count * _satisfaction_of(state, def)
	var mean: float = total / people if people > 0 else state.satisfaction
	return clampf(mean / MAX_POINTS, 0.0, 1.0)


static func _satisfaction_of(state: EconomyState, def: ClassDef) -> float:
	if def.base:
		return state.satisfaction
	return state.class_states[def.id].satisfaction if state.class_states.has(def.id) else 0.0


# w_f = sum over classes of pop_c x affinity_c,f / pop_total (D-116), each class's affinities taken as shares of their
# sum. An empty city weighs every class the same, so the ceiling still follows the supports.
static func weights(state: EconomyState, params: Params, context: EconomyContext) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for faction_id: StringName in context.factions:
		result[faction_id] = 0.0
	var defs: Array[ClassDef] = ClassStates.defs(context)
	var people: int = 0
	for def: ClassDef in defs:
		people += ClassStates.population_of(state, def)
	for def: ClassDef in defs:
		var share: float = float(ClassStates.population_of(state, def)) / people if people > 0 else 1.0 / defs.size()
		var affinities: Dictionary[StringName, float] = {}
		var total: float = 0.0
		for faction_id: StringName in context.factions:
			var key: StringName = FactionDef.affinity_key(def.id, faction_id)
			affinities[faction_id] = float(params.get_value(key)) if params.has_value(key) else 0.0
			total += affinities[faction_id]
		if total <= 0.0:
			continue
		for faction_id: StringName in affinities:
			result[faction_id] += share * affinities[faction_id] / total
	return result


# The ceiling P = sum of w_f x support_f, 0 to 100 (D-116).
static func ceiling(state: EconomyState, params: Params, context: EconomyContext) -> float:
	var top: float = 0.0
	var by_faction: Dictionary[StringName, float] = weights(state, params, context)
	for faction_id: StringName in by_faction:
		top += by_faction[faction_id] * state.faction_support.get(faction_id, 0.0)
	return clampf(top, MIN_POINTS, MAX_POINTS)


# What an action of `base_cost` points costs now: low_legitimacy_cost_multiplier times more below the threshold (D-141).
static func cost(state: EconomyState, params: Params, base_cost: float) -> float:
	if state.legitimacy < float(params.get_value(&"factions.low_legitimacy_threshold")):
		return base_cost * float(params.get_value(&"factions.low_legitimacy_cost_multiplier"))
	return base_cost


static func decree_cost(state: EconomyState, params: Params) -> float:
	return cost(state, params, float(params.get_value(&"factions.decree_legitimacy_cost")))


# Takes `amount` points off the reserve, or refuses without changes when the reserve does not cover it (D-139, point 5).
static func spend(state: EconomyState, amount: float) -> bool:
	if state.legitimacy < 0.0 or amount < 0.0 or amount > state.legitimacy:
		return false
	state.legitimacy -= amount
	return true


# The hook of a patron or a decree moving a faction (#81, #71): its support changes now and drifts back to its target.
static func shift_support(state: EconomyState, faction_id: StringName, points: float) -> void:
	if state.faction_support.has(faction_id):
		state.faction_support[faction_id] = clampf(state.faction_support[faction_id] + points, MIN_POINTS, MAX_POINTS)


static func snapshot(state: EconomyState, params: Params, context: EconomyContext) -> Dictionary:
	if not enabled(context) or state.legitimacy < 0.0:
		return {}
	var by_faction: Dictionary[StringName, float] = weights(state, params, context)
	var factions: Dictionary = {}
	for faction: FactionDef in context.factions.values():
		factions[faction.id] = {"support": state.faction_support.get(faction.id, 0.0),
			"target": target(state, params, context, faction), "weight": by_faction[faction.id]}
	return {"legitimacy": state.legitimacy, "ceiling": ceiling(state, params, context),
		"decree_cost": decree_cost(state, params), "rates_ratio": rates_ratio(state, params, context),
		"factions": factions}
