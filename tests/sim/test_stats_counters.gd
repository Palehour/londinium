extends GutTest

# Issue #130 (#82 part 2, D-066): per-tick counters for the chapter statistics. The systems write them next to the
# stock or money they already move, and a series records each one. They are checked against what they explain: a
# store changes by what was made and bought minus what was used and spoiled, a purchase costs its units times the
# price, a class changes by who came, left, rose and fell.
# Issue #186 (D-086): the cells below are the corners (2x, 2y) of the 2x2 blocks of the old cells of 50 m.

# Seconds of the city game: the fine level keeps the last 600, one value a second.
const CITY_SECONDS: int = 900
# Goods kept in whole units, so their store changes exactly by the counters.
const WHOLE_GOODS: Array[StringName] = [&"wheat", &"flour", &"barley", &"malt"]
# Goods eaten in fractions of a unit (the part already eaten waits in a fraction the series do not show).
const EATEN_GOODS: Array[StringName] = [&"bread", &"tea", &"beer"]
const UNIT_TOLERANCE: float = 2.0
const EPSILON: float = 1e-6

var _catalog: DataCatalog
var _context: EconomyContext


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])


func _params(changes: Dictionary = {}) -> Params:
	var role: RoleDef = RoleDef.new()
	for key: StringName in changes:
		role.modifiers.append(Modifier.new(key, &"set", changes[key]))
	return Params.new(_catalog, role)


# A city with every chain, barley, tea and flour imports (two bakeries for one mill, so flour runs short), played
# 15 minutes.
func _city() -> Simulation:
	var state: EconomyState = EconomyState.new()
	state.money = 1000000
	state.population = 30
	state.stocks.assign({&"wheat": 20, &"flour": 0, &"bread": 40, &"barley": 0, &"malt": 0, &"beer": 0, &"tea": 0})
	var sim: Simulation = Simulation.new(_params(), state, 11, _context)
	var builds: Array[Array] = [[&"wharf", Vector2i(4, 14)], [&"wharf", Vector2i(8, 14)], [&"mill", Vector2i(4, 10)],
		[&"bakery", Vector2i(6, 10)], [&"bakery", Vector2i(8, 10)], [&"housing", Vector2i(10, 6)], [&"housing", Vector2i(10, 8)],
		[&"malthouse", Vector2i(4, 6)], [&"brewery", Vector2i(6, 6)], [&"artisan_housing", Vector2i(12, 6)]]
	for build: Array in builds:
		sim.apply_command(BuildCommand.new(_context, build[0], build[1]))
	sim.apply_command(SetUnloadingSplitCommand.new(15))
	sim.apply_command(SetFlourImportsCommand.new(true))
	sim.apply_command(SetTeaImportsCommand.new(true))
	for second: int in CITY_SECONDS:
		sim.tick()
	return sim


func _fine(sim: Simulation, id: StringName) -> PackedFloat32Array:
	var found: Dictionary = sim.stats_series(id, StatsHistory.TIER_FINE)
	assert_false(found.is_empty(), "series %s" % id)
	return found.get("values", PackedFloat32Array())


func _sum(values: PackedFloat32Array, from: int = 0) -> float:
	var total: float = 0.0
	for index: int in range(from, values.size()):
		total += values[index]
	return total


# 0 for a series the registry does not declare for this good (nothing makes wheat, nobody buys malt).
func _flow(sim: Simulation, id: StringName, size: int) -> PackedFloat32Array:
	var found: Dictionary = sim.stats_series(id, StatsHistory.TIER_FINE)
	if found.is_empty():
		var zeros: PackedFloat32Array = []
		zeros.resize(size)
		return zeros
	return found["values"]


func test_stores_change_by_what_was_made_bought_used_and_spoiled() -> void:
	var sim: Simulation = _city()
	for good: StringName in WHOLE_GOODS + EATEN_GOODS:
		var stock: PackedFloat32Array = _fine(sim, StringName("stock:%s" % good))
		var produced: PackedFloat32Array = _flow(sim, StringName("produced:%s" % good), stock.size())
		var bought: PackedFloat32Array = _flow(sim, StringName("bought:%s" % good), stock.size())
		var consumed: PackedFloat32Array = _flow(sim, StringName("consumed:%s" % good), stock.size())
		var spoiled: PackedFloat32Array = _flow(sim, StringName("spoiled:%s" % good), stock.size())
		var moved: float = _sum(produced, 1) + _sum(bought, 1) + _sum(consumed, 1) + _sum(spoiled, 1)
		assert_gt(moved, 0.0, "%s moved in the window" % good)
		if good in WHOLE_GOODS:
			for second: int in range(1, stock.size()):
				var expected: float = stock[second - 1] + produced[second] + bought[second] - consumed[second] \
					- spoiled[second]
				assert_almost_eq(stock[second], expected, EPSILON, "%s at second %d" % [good, second])
		else:
			var flows: float = _sum(produced, 1) + _sum(bought, 1) - _sum(consumed, 1) - _sum(spoiled, 1)
			assert_almost_eq(stock[stock.size() - 1] - stock[0], flows, UNIT_TOLERANCE, good)
	for good: StringName in [&"flour", &"bread", &"malt", &"beer"]:
		assert_gt(_sum(_fine(sim, StringName("produced:%s" % good))), 0.0, "%s was made" % good)
	for good: StringName in [&"wheat", &"barley", &"flour", &"tea"]:
		assert_gt(_sum(_fine(sim, StringName("bought:%s" % good))), 0.0, "%s was bought" % good)
	for good: StringName in [&"wheat", &"barley", &"malt", &"bread", &"tea", &"beer"]:
		assert_gt(_sum(_fine(sim, StringName("consumed:%s" % good))), 0.0, "%s was used" % good)
	# Grain is used as fast as it comes, so only the bread is sure to spoil here (test_spoilage_is_counted_per_good).
	assert_gt(_sum(_fine(sim, &"spoiled:bread")), 0.0, "bread spoiled")


func test_purchases_cost_their_units_at_the_price() -> void:
	var sim: Simulation = _city()
	var params: Params = _params()
	var wheat: PackedFloat32Array = _fine(sim, &"bought:wheat")
	var wheat_price: PackedFloat32Array = _fine(sim, &"price:wheat")
	var wheat_spent: PackedFloat32Array = _fine(sim, &"expense:wheat")
	var barley: PackedFloat32Array = _fine(sim, &"bought:barley")
	var barley_price: PackedFloat32Array = _fine(sim, &"price:barley")
	var barley_spent: PackedFloat32Array = _fine(sim, &"expense:barley")
	var tea: PackedFloat32Array = _fine(sim, &"bought:tea")
	var tea_spent: PackedFloat32Array = _fine(sim, &"expense:tea")
	var flour: PackedFloat32Array = _fine(sim, &"bought:flour")
	var flour_spent: PackedFloat32Array = _fine(sim, &"expense:imported_flour")
	var tea_price: float = float(params.get_value(&"market.tea.price"))
	var lot_price: float = float(params.get_value(&"market.imported_flour.price_per_lot"))
	var lot: float = float(params.get_value(&"market.imported_flour.lot_size"))
	for second: int in wheat.size():
		assert_eq(wheat_spent[second], wheat[second] * wheat_price[second], "wheat at second %d" % second)
		assert_eq(barley_spent[second], barley[second] * barley_price[second], "barley at second %d" % second)
		assert_eq(tea_spent[second], tea[second] * tea_price, "tea at second %d" % second)
		assert_eq(flour_spent[second], flour[second] / lot * lot_price, "flour at second %d" % second)


func test_counters_reset_each_tick_and_are_not_saved() -> void:
	var state: EconomyState = EconomyState.new()
	state.count_produced(&"flour", 3)
	state.count_consumed(&"wheat", 2.5)
	state.count_spoiled(&"bread", 0.25)
	state.count_bought(&"tea", 4)
	state.immigration_tick[&"worker"] = 1
	state.emigration_hunger_tick[&"worker"] = 2
	state.emigration_unhappy_tick[&"artisan"] = 3
	state.promotions_by_class_tick[&"artisan"] = 4
	state.demotions_by_class_tick[&"artisan"] = 5
	state.administration_tick = 6.5
	state.refunds_tick = 7
	state.count_produced(&"flour", 2)
	assert_eq(state.goods_produced_tick[&"flour"], 5, "counts add up within a tick")
	var saved: Dictionary = state.to_dict()
	for field: String in ["goods_produced_tick", "goods_consumed_tick", "goods_spoiled_tick", "goods_bought_tick",
			"immigration_tick", "emigration_hunger_tick", "emigration_unhappy_tick", "promotions_by_class_tick",
			"demotions_by_class_tick", "administration_tick", "refunds_tick"]:
		assert_false(saved.has(field), field + " is transient")
	state.reset_flows()
	for counter: Dictionary in [state.goods_produced_tick, state.goods_consumed_tick, state.goods_spoiled_tick,
			state.goods_bought_tick, state.immigration_tick, state.emigration_hunger_tick,
			state.emigration_unhappy_tick, state.promotions_by_class_tick, state.demotions_by_class_tick]:
		assert_true(counter.is_empty())
	assert_eq(state.administration_tick, 0.0)
	assert_eq(state.refunds_tick, 0)


func test_converters_count_what_they_make() -> void:
	var params: Params = _params()
	var state: EconomyState = EconomyState.new()
	state.stocks.assign({&"wheat": 10, &"flour": 0, &"barley": 10, &"malt": 0})
	for id: StringName in [&"mill", &"malthouse", &"malthouse"]:
		state.buildings.append({"definition_id": id, "workers": WorkersSystem.job_capacity(params, id)})
	var production: ProductionSystem = ProductionSystem.new()
	var made: Dictionary[StringName, int] = {}
	var used: Dictionary[StringName, float] = {}
	for second: int in 60:
		var before: Dictionary = state.stocks.duplicate()
		state.reset_flows()
		production.tick(state, params, _context)
		for good: StringName in [&"flour", &"malt"]:
			assert_eq(state.stocks[good] - int(before[good]), state.goods_produced_tick.get(good, 0), good)
		for good: StringName in [&"wheat", &"barley"]:
			assert_eq(float(int(before[good]) - state.stocks[good]), state.goods_consumed_tick.get(good, 0.0), good)
		for good: StringName in state.goods_produced_tick:
			made[good] = made.get(good, 0) + state.goods_produced_tick[good]
		for good: StringName in state.goods_consumed_tick:
			used[good] = used.get(good, 0.0) + state.goods_consumed_tick[good]
	assert_eq(made[&"flour"], 10, "the mill turns ten wheat into ten flour a minute")
	assert_eq(used[&"wheat"], 10.0)
	assert_gt(made[&"malt"], 0, "two malthouses share the capped malt store")


func test_people_count_what_they_eat_and_the_bread_that_spoils() -> void:
	var params: Params = _params()
	var state: EconomyState = EconomyState.new()
	state.population = 40
	state.class_states[&"artisan"] = ClassState.new()
	state.class_states[&"artisan"].population = 10
	state.stocks.assign({&"bread": 50, &"tea": 20, &"beer": 20})
	var consumption: ConsumptionSystem = ConsumptionSystem.new()
	for second: int in 30:
		var bread: float = float(state.stocks[&"bread"]) + state.bread_fraction
		state.reset_flows()
		consumption.tick(state, params, _context)
		assert_eq(state.goods_consumed_tick[&"bread"], state.bread_consumed)
		assert_eq(state.goods_consumed_tick[&"tea"], state.tea_consumed)
		assert_eq(state.goods_consumed_tick[&"beer"], state.beer_consumed)
		assert_gt(state.goods_consumed_tick[&"tea"], 0.0, "the workers drink tea")
		assert_gt(state.goods_consumed_tick[&"beer"], 0.0, "the artisans drink beer")
		var left: float = float(state.stocks[&"bread"]) + state.bread_fraction
		assert_gt(state.goods_spoiled_tick[&"bread"], 0.0, "stale bread decays")
		assert_almost_eq(bread - state.bread_consumed - state.goods_spoiled_tick[&"bread"], left, EPSILON)


func test_spoilage_is_counted_per_good() -> void:
	# Malt does not spoil in data/ today; a rate makes it count like the others.
	var params: Params = _params({&"market.malt.decay_fraction_per_minute": 0.01})
	var state: EconomyState = EconomyState.new()
	state.wheat_purchases_enabled = false
	state.unloading_barley_percent = 0
	state.stocks.assign({&"wheat": 400, &"barley": 400, &"malt": 400, &"beer": 400})
	state.beer_fraction = 0.5
	var market: MarketSystem = MarketSystem.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var spoiled: Dictionary[StringName, float] = {}
	var start: Dictionary = state.stocks.duplicate()
	var beer_start: float = 400.5
	for second: int in range(1, 121):
		state.reset_flows()
		market.tick(state, params, rng, second)
		for good: StringName in state.goods_spoiled_tick:
			spoiled[good] = spoiled.get(good, 0.0) + state.goods_spoiled_tick[good]
	for good: StringName in [&"wheat", &"barley", &"malt"]:
		assert_gt(spoiled[good], 0.0, good)
		assert_eq(spoiled[good], float(int(start[good]) - state.stocks[good]), good)
	assert_almost_eq(spoiled[&"beer"], beer_start - float(state.stocks[&"beer"]) - state.beer_fraction, EPSILON,
		"beer spoils in whole units and in the part of a unit left after drinking")


func test_migration_by_class_and_cause() -> void:
	var params: Params = _params()
	var growth: GrowthSystem = GrowthSystem.new()
	var state: EconomyState = EconomyState.new()
	ClassStates.ensure(state, _context)
	state.population = 20
	state.housing_capacity = 40
	state.bread_coverage = 1.0
	var phases: Array[Dictionary] = [
		{"name": "arriving", "hunger": 1.0, "satisfaction": 100.0, "counter": "immigration_tick"},
		{"name": "hungry", "hunger": 0.0, "satisfaction": 100.0, "counter": "emigration_hunger_tick"},
		{"name": "unhappy", "hunger": 1.0, "satisfaction": 0.0, "counter": "emigration_unhappy_tick"}]
	for phase: Dictionary in phases:
		state.hunger_smoothed_coverage = phase["hunger"]
		state.hunger_emigration_active = false
		state.satisfaction = phase["satisfaction"]
		state.satisfaction_target = phase["satisfaction"]
		var totals: Dictionary[String, int] = {"immigration_tick": 0, "emigration_hunger_tick": 0,
			"emigration_unhappy_tick": 0}
		for second: int in 60:
			var before: int = state.population
			state.reset_flows()
			growth.tick(state, params, _context)
			var arrived: int = state.immigration_tick.get(&"worker", 0)
			var left: int = state.emigration_hunger_tick.get(&"worker", 0) + state.emigration_unhappy_tick.get(&"worker", 0)
			assert_eq(state.population - before, arrived - left, "%s at second %d" % [phase["name"], second])
			for counter: String in totals:
				var values: Dictionary = state.get(counter)
				totals[counter] += int(values.get(&"worker", 0))
				assert_eq(int(values.get(&"artisan", 0)), 0, "nobody moves in a class without people or housing")
		for counter: String in totals:
			if counter == phase["counter"]:
				assert_gt(totals[counter], 0, "%s counts in %s" % [phase["name"], counter])
			else:
				assert_eq(totals[counter], 0, "%s does not count in %s" % [phase["name"], counter])
		state.population = 20


func test_mobility_by_class() -> void:
	var params: Params = _params()
	var mobility: MobilitySystem = MobilitySystem.new()
	var state: EconomyState = EconomyState.new()
	state.tax_rate = 0.25
	state.buildings.append({"definition_id": &"housing"})
	state.buildings.append({"definition_id": &"artisan_housing"})
	ClassStates.ensure(state, _context)
	state.population = 30
	for phase: Array in [[1.0, 1.0, &"promotions"], [1.0, 0.0, &"demotions"]]:
		state.hunger_smoothed_coverage = phase[0]
		state.bread_coverage = phase[0]
		state.beer_coverage = phase[1]
		SatisfactionSystem.new().update_target(state, params, _context)
		state.satisfaction = 100.0
		var by_class: int = 0
		for second: int in 180:
			var artisans: int = state.class_states[&"artisan"].population
			state.reset_flows()
			mobility.tick(state, params, _context)
			assert_eq(state.promotions_by_class_tick.get(&"artisan", 0), state.promotions_tick)
			assert_eq(state.demotions_by_class_tick.get(&"artisan", 0), state.demotions_tick)
			assert_eq(state.class_states[&"artisan"].population - artisans, state.promotions_tick - state.demotions_tick)
			by_class += state.promotions_tick if phase[2] == &"promotions" else state.demotions_tick
		assert_gt(by_class, 0, "%s happened" % phase[2])


func test_administration_is_split_from_upkeep() -> void:
	var params: Params = _params()
	var state: EconomyState = EconomyState.new()
	for index: int in 30:
		state.buildings.append({"definition_id": &"bakery", "cell": [index, 0]})
	var multiplier: float = BuildingCosts.administration_multiplier(params, state.buildings.size())
	assert_gt(multiplier, 1.0, "thirty buildings pay administration")
	var money: MoneySystem = MoneySystem.new()
	var paid: float = 0.0
	var administration: float = 0.0
	for second: int in 120:
		state.reset_flows()
		money.tick(state, params, _context)
		assert_almost_eq(state.administration_tick, state.upkeep_tick * (1.0 - 1.0 / multiplier), EPSILON)
		assert_almost_eq(SeriesRegistry.expense(state, &"upkeep") + SeriesRegistry.expense(state, &"administration"),
			float(state.upkeep_tick), EPSILON, "base upkeep and administration add up to what was paid")
		paid += state.upkeep_tick
		administration += state.administration_tick
	assert_gt(administration, 0.0)
	assert_lt(administration, paid)


func test_refund_is_other_income() -> void:
	var params: Params = _params()
	var state: EconomyState = EconomyState.new()
	state.money = 10000
	var sim: Simulation = Simulation.new(params, state, 3, _context)
	sim.apply_command(BuildCommand.new(_context, &"bakery", Vector2i(2, 2)))
	sim.tick()
	var cost: float = _sum(_fine(sim, &"expense:construction"))
	assert_gt(cost, 0.0)
	var demolish: DemolishCommand = DemolishCommand.new(Vector2i(2, 2))
	sim.apply_command(demolish)
	sim.tick()
	assert_true(demolish.accepted)
	var refund: PackedFloat32Array = _fine(sim, &"income:refund")
	var construction: PackedFloat32Array = _fine(sim, &"expense:construction")
	assert_gt(refund[1], 0.0, "a building demolished at once is refunded")
	assert_eq(construction[1], 0.0, "construction is what was paid, not net of the refund")
	assert_eq(_sum(construction), cost)
