class_name ConsumptionSystem
extends RefCounted


# Parameter that holds the per-person consumption of a good when there is no context to read the classes from:
# the whole population then eats it, as it did before the classes (issue #52).
const LEGACY_CONSUMPTION_KEYS: Dictionary[StringName, StringName] = {
	&"bread": &"population.bread_per_person_per_minute",
	&"tea": &"population.tea.per_person_per_minute",
}


# What the classes eat of a good per second: each class's residents times what one of them eats per minute.
# Only classes that list the good among their needs eat it.
static func demand_per_second(state: EconomyState, params: Params, context: EconomyContext, good: StringName) -> float:
	if context == null:
		if not LEGACY_CONSUMPTION_KEYS.has(good):
			return 0.0
		return float(state.population) * float(params.get_value(LEGACY_CONSUMPTION_KEYS[good])) / 60.0
	var total: float = 0.0
	for def: ClassDef in ClassStates.defs(context):
		for need: NeedDef in def.needs:
			if need.good == good:
				total += float(ClassStates.population_of(state, def)) 					* float(params.get_value(need.consumption_key)) / 60.0
	return total


func tick(state: EconomyState, params: Params, context: EconomyContext = null) -> void:
	state.bread_demand = demand_per_second(state, params, context, &"bread")
	state.bread_demand_tick = state.bread_demand
	var available: float = float(state.stocks.get(&"bread", 0)) + state.bread_fraction
	state.bread_consumed = minf(available, state.bread_demand)
	state.bread_consumed_tick = state.bread_consumed
	state.bread_coverage = coverage(state, params, context)
	var decay: float = float(params.get_value(&"population.bread_decay_fraction_per_minute"))
	var remaining: float = maxf(0.0, available - state.bread_consumed) * pow(1.0 - decay, 1.0 / 60.0)
	var whole: int = ProductionSystem.whole_units(remaining)
	if state.stocks.has(&"bread") or whole > 0:
		state.stocks[&"bread"] = whole
	state.bread_fraction = maxf(0.0, remaining - whole)
	_consume_tea(state, params, context)
	_consume_beer(state, params, context)


# Tea is optional: a city without any simply gets no bonus. It does not spoil, and the part of a unit
# already eaten waits in tea_fraction like the bread's.
func _consume_tea(state: EconomyState, params: Params, context: EconomyContext) -> void:
	state.tea_demand = demand_per_second(state, params, context, &"tea")
	var available: float = float(state.stocks.get(&"tea", 0)) + state.tea_fraction
	state.tea_consumed = minf(available, state.tea_demand)
	state.tea_coverage = tea_coverage(state, params, context)
	var remaining: float = maxf(0.0, available - state.tea_consumed)
	var whole: int = ProductionSystem.whole_units(remaining)
	if state.stocks.has(&"tea") or whole > 0:
		state.stocks[&"tea"] = whole
	state.tea_fraction = maxf(0.0, remaining - whole)


# Beer (issue #52) is eaten like tea. It spoils in the warehouse (MarketSystem) before this step, so what is
# eaten is what is left; the part of a unit already eaten waits in beer_fraction.
func _consume_beer(state: EconomyState, params: Params, context: EconomyContext) -> void:
	state.beer_demand = demand_per_second(state, params, context, &"beer")
	var available: float = float(state.stocks.get(&"beer", 0)) + state.beer_fraction
	state.beer_consumed = minf(available, state.beer_demand)
	state.beer_coverage = beer_coverage(state, params, context)
	var remaining: float = maxf(0.0, available - state.beer_consumed)
	var whole: int = ProductionSystem.whole_units(remaining)
	if state.stocks.has(&"beer") or whole > 0:
		state.stocks[&"beer"] = whole
	state.beer_fraction = maxf(0.0, remaining - whole)


# The part of a unit of a good still in the warehouse after people drank from it: it takes room and spoils
# like the whole units (PR #108). Only beer has a cap and is drunk in fractions.
static func stored_fraction(state: EconomyState, good: StringName) -> float:
	return state.beer_fraction if good == &"beer" else 0.0


# Share of the tea demand the store covers, without consuming anything.
func tea_coverage(state: EconomyState, params: Params, context: EconomyContext = null) -> float:
	return _stock_coverage(state, params, context, &"tea", state.tea_fraction)


func beer_coverage(state: EconomyState, params: Params, context: EconomyContext = null) -> float:
	return _stock_coverage(state, params, context, &"beer", state.beer_fraction)


# With nobody to eat it, a good in store counts as fully covered (so the first arrivals find it) and an
# empty store as not covered.
func _stock_coverage(state: EconomyState, params: Params, context: EconomyContext, good: StringName,
		fraction: float) -> float:
	var demand: float = demand_per_second(state, params, context, good)
	var available: float = float(state.stocks.get(good, 0)) + fraction
	if demand <= 0.0:
		return 1.0 if available > 0.0 else 0.0
	return clampf(available / demand, 0.0, 1.0)


# Preview supply against demand without consuming, decaying, or advancing the state.
func coverage(state: EconomyState, params: Params, context: EconomyContext = null) -> float:
	var demand: float = demand_per_second(state, params, context, &"bread")
	var available: float = float(state.stocks.get(&"bread", 0)) + state.bread_fraction
	return clampf(available / demand, 0.0, 1.0) if demand > 0.0 else _empty_city_coverage(available, params)


func _empty_city_coverage(available: float, params: Params) -> float:
	var immigrants: float = float(params.get_value(&"population.growth.immigration_per_minute"))
	var per_person: float = float(params.get_value(&"population.bread_per_person_per_minute"))
	var lookahead: float = float(params.get_value(&"population.empty_city_bread_lookahead_seconds"))
	return 1.0 if available >= immigrants * per_person * lookahead / 60.0 else 0.0
