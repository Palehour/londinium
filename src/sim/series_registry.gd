class_name SeriesRegistry
extends RefCounted

# Every statistics series of a game (issue #82, D-066). The members come from the data (classes, goods, buildings,
# victory stages), so a class or good added to data/ gets its series without touching this file. Part 2 (#130) adds
# the flows that read the per-tick counters of EconomyState: per good, migration, mobility, administration, refunds.

const DEFEAT_CONDITIONS: Array[StringName] = [&"bankruptcy", &"hunger", &"depopulation"]
# Money that left the treasury this tick, by what paid for it. Upkeep is the base one, without administration;
# construction is what was paid, and demolition refunds are an income of their own.
const EXPENSE_SOURCES: Array[StringName] = [&"upkeep", &"administration", &"wages", &"construction", &"wheat",
	&"barley", &"imported_flour", &"tea"]
# Goods the wharf buys or imports (MarketSystem, ImportSystem).
const BOUGHT_GOODS: Array[StringName] = [&"wheat", &"barley", &"flour", &"tea"]
# Why people leave (GrowthSystem): hunger takes priority over low satisfaction.
const EMIGRATION_CAUSES: Array[StringName] = [&"hunger", &"satisfaction"]
# Goods whose coverage the state keeps: the ones a class eats.
const COVERED_GOODS: Array[StringName] = [&"bread", &"tea", &"beer"]
const BASE_MEMBER: StringName = &"base"


static func build(params: Params, context: EconomyContext, victory_stages: Array[Dictionary] = []) -> Array[SeriesDef]:
	var found: Array[SeriesDef] = []
	_money(found, context)
	_goods(found, params, context)
	_people(found, context)
	_buildings(found, params, context)
	_outcomes(found, victory_stages)
	return found


static func _money(found: Array[SeriesDef], context: EconomyContext) -> void:
	found.append(SeriesDef.create(&"money", &"pence", SeriesDef.AGGREGATION_LAST, {},
		func(state: EconomyState) -> float: return float(state.money)))
	for def: ClassDef in ClassStates.defs(context):
		var id: StringName = def.id
		found.append(SeriesDef.create(&"income", &"pence", SeriesDef.AGGREGATION_SUM,
			{&"source": &"tax", &"class": member_of(def)},
			func(state: EconomyState) -> float: return float(state.class_tax_tick.get(id, 0.0))))
	found.append(SeriesDef.create(&"income", &"pence", SeriesDef.AGGREGATION_SUM, {&"source": &"refund"},
		func(state: EconomyState) -> float: return float(state.refunds_tick)))
	for source: StringName in EXPENSE_SOURCES:
		found.append(SeriesDef.create(&"expense", &"pence", SeriesDef.AGGREGATION_SUM, {&"source": source},
			func(state: EconomyState) -> float: return float(expense(state, source))))


static func expense(state: EconomyState, source: StringName) -> float:
	match source:
		&"upkeep": return state.upkeep_tick - state.administration_tick
		&"administration": return state.administration_tick
		&"wages": return state.wages_tick
		&"construction": return state.construction_spent_tick + state.refunds_tick
		&"wheat": return state.wheat_spent_tick
		&"barley": return state.barley_spent_tick
		&"imported_flour": return state.imports_spent_tick - state.tea_spent_tick
		&"tea": return state.tea_spent_tick
	return 0.0


static func _goods(found: Array[SeriesDef], params: Params, context: EconomyContext) -> void:
	for good: StringName in goods(context):
		found.append(SeriesDef.create(&"stock", &"units", SeriesDef.AGGREGATION_LAST, {&"good": good},
			func(state: EconomyState) -> float: return float(state.stocks.get(good, 0))))
		if good in COVERED_GOODS:
			found.append(SeriesDef.create(&"coverage", &"ratio", SeriesDef.AGGREGATION_MEAN, {&"good": good},
				func(state: EconomyState) -> float: return coverage(state, good)))
	_flows(found, params, context)
	found.append(SeriesDef.create(&"price", &"pence", SeriesDef.AGGREGATION_MEAN, {&"good": &"wheat"},
		func(state: EconomyState) -> float: return float(state.wheat_price)))
	found.append(SeriesDef.create(&"price", &"pence", SeriesDef.AGGREGATION_MEAN, {&"good": &"barley"},
		func(state: EconomyState) -> float: return float(state.barley_price)))
	# Import prices come from the data (a role may change them): a lot of flour, a unit of tea.
	found.append(SeriesDef.create(&"price", &"pence", SeriesDef.AGGREGATION_MEAN, {&"good": &"flour"},
		func(_state: EconomyState) -> float: return float(params.get_value(&"market.imported_flour.price_per_lot"))))
	found.append(SeriesDef.create(&"price", &"pence", SeriesDef.AGGREGATION_MEAN, {&"good": &"tea"},
		func(_state: EconomyState) -> float: return float(params.get_value(&"market.tea.price"))))


# Per good: what converters make, what leaves the store (a converter's input or what people eat), what spoils
# (the goods with a decay rate in the data, and the bread) and what the wharf buys.
static func _flows(found: Array[SeriesDef], params: Params, context: EconomyContext) -> void:
	var made: Array[StringName] = recipe_goods(context, true)
	var used: Array[StringName] = recipe_goods(context, false)
	for good: StringName in goods(context):
		if good in made:
			found.append(SeriesDef.create(&"produced", &"units", SeriesDef.AGGREGATION_SUM, {&"good": good},
				func(state: EconomyState) -> float: return float(state.goods_produced_tick.get(good, 0))))
		if good in used or _eaten(context, good):
			found.append(SeriesDef.create(&"consumed", &"units", SeriesDef.AGGREGATION_SUM, {&"good": good},
				func(state: EconomyState) -> float: return float(state.goods_consumed_tick.get(good, 0.0))))
		if good == &"bread" or params.has_value(StringName("market.%s.decay_fraction_per_minute" % good)):
			found.append(SeriesDef.create(&"spoiled", &"units", SeriesDef.AGGREGATION_SUM, {&"good": good},
				func(state: EconomyState) -> float: return float(state.goods_spoiled_tick.get(good, 0.0))))
		if good in BOUGHT_GOODS:
			found.append(SeriesDef.create(&"bought", &"units", SeriesDef.AGGREGATION_SUM, {&"good": good},
				func(state: EconomyState) -> float: return float(state.goods_bought_tick.get(good, 0))))


# The outputs (or the inputs) of the converters ProductionSystem runs: the wharf's wheat is bought, not made.
static func recipe_goods(context: EconomyContext, outputs: bool) -> Array[StringName]:
	var found: Array[StringName] = []
	if context == null:
		return found
	for id: StringName in ProductionSystem.CONVERTERS:
		var definition: BuildingDef = context.buildings.get(id)
		if definition != null and definition.recipe != null:
			for good: StringName in definition.recipe.outputs if outputs else definition.recipe.inputs:
				if good not in found:
					found.append(good)
	return found


static func _eaten(context: EconomyContext, good: StringName) -> bool:
	for def: ClassDef in ClassStates.defs(context):
		for need: NeedDef in def.needs:
			if need.good == good:
				return true
	return false


# Every good a recipe uses or makes, or a class eats, in a stable order.
static func goods(context: EconomyContext) -> Array[StringName]:
	var found: Array[StringName] = []
	if context != null:
		for definition: BuildingDef in context.buildings.values():
			if definition.recipe != null:
				for good: StringName in definition.recipe.inputs + definition.recipe.outputs:
					if good not in found:
						found.append(good)
	for def: ClassDef in ClassStates.defs(context):
		for need: NeedDef in def.needs:
			if need.good not in found:
				found.append(need.good)
	found.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return found


static func coverage(state: EconomyState, good: StringName) -> float:
	match good:
		&"bread": return state.bread_coverage
		&"tea": return state.tea_coverage
		&"beer": return state.beer_coverage
	return 0.0


static func _people(found: Array[SeriesDef], context: EconomyContext) -> void:
	for def: ClassDef in ClassStates.defs(context):
		var member: Dictionary[StringName, StringName] = {&"class": member_of(def)}
		var class_id: StringName = def.id
		found.append(SeriesDef.create(&"population", &"people", SeriesDef.AGGREGATION_MEAN, member,
			func(state: EconomyState) -> float: return float(ClassStates.population_of(state, def))))
		found.append(SeriesDef.create(&"immigration", &"people", SeriesDef.AGGREGATION_SUM, member,
			func(state: EconomyState) -> float: return float(state.immigration_tick.get(class_id, 0))))
		for cause: StringName in EMIGRATION_CAUSES:
			found.append(SeriesDef.create(&"emigration", &"people", SeriesDef.AGGREGATION_SUM,
				{&"class": member_of(def), &"cause": cause},
				func(state: EconomyState) -> float: return float(emigrated(state, class_id, cause))))
		if def.has_mobility():
			found.append(SeriesDef.create(&"promotions", &"people", SeriesDef.AGGREGATION_SUM, member,
				func(state: EconomyState) -> float: return float(state.promotions_by_class_tick.get(class_id, 0))))
			found.append(SeriesDef.create(&"demotions", &"people", SeriesDef.AGGREGATION_SUM, member,
				func(state: EconomyState) -> float: return float(state.demotions_by_class_tick.get(class_id, 0))))
		found.append(SeriesDef.create(&"satisfaction", &"score", SeriesDef.AGGREGATION_MEAN, member,
			func(state: EconomyState) -> float: return satisfaction(state, def)))
		found.append(SeriesDef.create(&"housing_capacity", &"people", SeriesDef.AGGREGATION_MEAN, member,
			func(state: EconomyState) -> float: return float(housing_capacity(state, def))))
		found.append(SeriesDef.create(&"housing_occupancy", &"ratio", SeriesDef.AGGREGATION_MEAN, member,
			func(state: EconomyState) -> float: return occupancy(state, def)))
		for category: StringName in categories(def):
			var id: StringName = def.id
			found.append(SeriesDef.create(&"need_score", &"score", SeriesDef.AGGREGATION_MEAN,
				{&"class": member_of(def), &"category": category},
				func(state: EconomyState) -> float: return MobilitySystem.score(state, id, category)))


static func emigrated(state: EconomyState, class_id: StringName, cause: StringName) -> int:
	var counter: Dictionary[StringName, int] = state.emigration_hunger_tick if cause == &"hunger" \
		else state.emigration_unhappy_tick
	return counter.get(class_id, 0)


static func categories(def: ClassDef) -> Array[StringName]:
	var found: Array[StringName] = []
	for need: NeedDef in def.needs:
		if need.category not in found:
			found.append(need.category)
	return found


# Read without ClassStates.checkout(), which may add a missing class to the state.
static func satisfaction(state: EconomyState, def: ClassDef) -> float:
	if def.base:
		return state.satisfaction
	var entry: ClassState = state.class_states.get(def.id)
	return entry.satisfaction if entry != null else 0.0


static func housing_capacity(state: EconomyState, def: ClassDef) -> int:
	if def.base:
		return state.housing_capacity - ClassStates.others_capacity(state)
	var entry: ClassState = state.class_states.get(def.id)
	return entry.housing_capacity if entry != null else 0


# Residents over places; a class without housing has no occupancy.
static func occupancy(state: EconomyState, def: ClassDef) -> float:
	var capacity: int = housing_capacity(state, def)
	return float(ClassStates.population_of(state, def)) / float(capacity) if capacity > 0 else 0.0


static func _buildings(found: Array[SeriesDef], params: Params, context: EconomyContext) -> void:
	if context == null:
		return
	var ids: Array[StringName] = []
	ids.assign(context.buildings.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id: StringName in ids:
		if WorkersSystem.job_capacity(params, id) <= 0:
			continue
		found.append(SeriesDef.create(&"jobs_filled", &"people", SeriesDef.AGGREGATION_MEAN, {&"building": id},
			func(state: EconomyState) -> float: return float(workers_of(state, id))))


static func workers_of(state: EconomyState, id: StringName) -> int:
	var total: int = 0
	for building: Dictionary in state.buildings:
		if building["definition_id"] == id:
			total += int(building.get("workers", 0))
	return total


static func _outcomes(found: Array[SeriesDef], victory_stages: Array[Dictionary]) -> void:
	for condition: StringName in DEFEAT_CONDITIONS:
		found.append(SeriesDef.create(&"defeat_timer", &"seconds", SeriesDef.AGGREGATION_LAST,
			{&"condition": condition},
			func(state: EconomyState) -> float: return float(defeat_state(state, condition).elapsed_seconds)))
	for stage: Dictionary in victory_stages:
		var id: StringName = stage["id"]
		var mean: bool = stage["mode"] == &"mean"
		# A mean stage progresses in people, a revenue streak in whole minutes.
		found.append(SeriesDef.create(&"victory_progress", &"people" if mean else &"minutes",
			SeriesDef.AGGREGATION_LAST, {&"stage": id},
			func(state: EconomyState) -> float: return victory_progress(state, id, mean)))


static func defeat_state(state: EconomyState, condition: StringName) -> DefeatState:
	match condition:
		&"bankruptcy": return state.bankruptcy
		&"hunger": return state.hunger
	return state.depopulation


static func victory_progress(state: EconomyState, id: StringName, mean: bool) -> float:
	var entry: Dictionary = state.victory.stages.get(id, {})
	if entry.is_empty():
		return 0.0
	return float(entry.get("mean", 0.0)) if mean else float(entry.get("streak_minutes", 0))


static func member_of(def: ClassDef) -> StringName:
	return def.id if def.id != &"" else BASE_MEMBER
