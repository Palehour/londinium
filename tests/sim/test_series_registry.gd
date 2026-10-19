extends GutTest

# Issue #82 (D-066): every series declares its label, unit, aggregation and dimensions, from the data.

# Ceiling of the format, approved with the metric list (2026-10-15).
const MAX_SERIES: int = 200

var _catalog: DataCatalog


func before_all() -> void:
	_catalog = DataLoader.new().load_all().catalog


func _defs() -> Array[SeriesDef]:
	var stages: Array[Dictionary] = []
	stages.assign(_catalog.scenarios[&"victorian_demo"]["stages"])
	return SeriesRegistry.build(Params.new(_catalog, RoleDef.new()),
		EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"]), stages)


func test_every_series_is_well_declared() -> void:
	var ids: Array[StringName] = []
	var labels: Array[StringName] = Strings.all_keys()
	for def: SeriesDef in _defs():
		assert_false(ids.has(def.id), "duplicate series " + def.id)
		ids.append(def.id)
		assert_has(SeriesDef.UNITS, def.unit, def.id)
		assert_has(SeriesDef.AGGREGATIONS, def.aggregation, def.id)
		assert_has(labels, def.label_key, def.id + " label in locale/ui.csv")
		for dimension: StringName in def.dimensions:
			assert_has(SeriesDef.DIMENSIONS, dimension, def.id)
		assert_true(def.sampler.is_valid(), def.id)


func test_series_count_fits_the_format() -> void:
	var defs: Array[SeriesDef] = _defs()
	gut.p("Series with today's data: %d" % defs.size())
	assert_between(defs.size(), 50, MAX_SERIES)


func test_members_come_from_the_data() -> void:
	var ids: Array[StringName] = []
	for def: SeriesDef in _defs():
		ids.append(def.id)
	for id: StringName in [&"money", &"income:tax:worker", &"income:tax:artisan", &"expense:imported_flour",
			&"stock:malt", &"coverage:beer", &"price:barley", &"population:artisan", &"satisfaction:worker",
			&"housing_occupancy:artisan", &"jobs_filled:brewery", &"defeat_timer:hunger", &"victory_progress:revenue"]:
		assert_has(ids, id)
	assert_does_not_have(ids, &"jobs_filled:housing", "housing has no jobs")
	var categories: int = 0
	for def: SeriesDef in _defs():
		if def.metric == &"need_score":
			categories += 1
			assert_eq(def.dimensions.keys(), [&"class", &"category"])
	assert_gt(categories, 0, "one series per class and need category")


func test_no_victory_stages_no_progress_series() -> void:
	var defs: Array[SeriesDef] = SeriesRegistry.build(Params.new(_catalog, RoleDef.new()),
		EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"]))
	for def: SeriesDef in defs:
		assert_ne(def.metric, &"victory_progress")


func test_district_is_a_declared_dimension() -> void:
	var def: SeriesDef = SeriesDef.create(&"population", &"people", SeriesDef.AGGREGATION_MEAN,
		{&"class": &"worker", &"district": &"spitalfields"}, func(_state: EconomyState) -> float: return 0.0)
	assert_eq(def.id, &"population:worker:spitalfields")
	assert_eq(def.describe()["dimensions"], {&"class": &"worker", &"district": &"spitalfields"})
	assert_has(SeriesDef.DIMENSIONS, &"district")


func test_samplers_read_the_state() -> void:
	var state: EconomyState = EconomyState.new()
	state.money = 1234
	state.population = 12
	state.stocks[&"malt"] = 7
	state.imports_spent_tick = 30
	state.tea_spent_tick = 10
	state.class_tax_tick[&"worker"] = 2.5
	var values: Dictionary = {}
	for def: SeriesDef in _defs():
		values[def.id] = def.sampler.call(state)
	assert_eq(values[&"money"], 1234.0)
	assert_eq(values[&"stock:malt"], 7.0)
	assert_eq(values[&"expense:imported_flour"], 20.0, "imports minus the tea part")
	assert_eq(values[&"expense:tea"], 10.0)
	assert_eq(values[&"income:tax:worker"], 2.5)
	assert_eq(values[&"population:worker"], 12.0, "the base class is what the others leave")
	assert_eq(values[&"population:artisan"], 0.0)


# Issue #130 (part 2): the series of the new per-tick counters, with their members from the data.
func test_part_two_series_come_from_the_data() -> void:
	var by_id: Dictionary[StringName, SeriesDef] = {}
	for def: SeriesDef in _defs():
		by_id[def.id] = def
	for id: StringName in [&"produced:flour", &"produced:malt", &"produced:beer", &"consumed:wheat",
			&"consumed:malt", &"consumed:tea", &"spoiled:wheat", &"spoiled:beer", &"spoiled:bread", &"bought:wheat",
			&"bought:barley", &"bought:flour", &"bought:tea", &"immigration:worker", &"immigration:artisan",
			&"emigration:worker:hunger", &"emigration:artisan:satisfaction", &"promotions:artisan",
			&"demotions:artisan", &"expense:administration", &"income:refund"]:
		assert_has(by_id, id)
	for id: StringName in [&"produced:wheat", &"produced:tea", &"spoiled:tea", &"spoiled:flour", &"bought:malt",
			&"promotions:worker", &"promotions", &"demotions"]:
		assert_does_not_have(by_id, id, "nothing makes, spoils, buys or promotes it")
	assert_eq(by_id[&"emigration:worker:hunger"].dimensions, {&"class": &"worker", &"cause": &"hunger"})
	assert_has(SeriesDef.DIMENSIONS, &"cause")


func test_part_two_samplers_read_the_counters() -> void:
	var state: EconomyState = EconomyState.new()
	state.count_produced(&"malt", 2)
	state.count_consumed(&"tea", 0.5)
	state.count_spoiled(&"beer", 0.25)
	state.count_bought(&"flour", 30)
	state.immigration_tick[&"artisan"] = 1
	state.emigration_hunger_tick[&"worker"] = 2
	state.emigration_unhappy_tick[&"worker"] = 3
	state.promotions_by_class_tick[&"artisan"] = 4
	state.demotions_by_class_tick[&"artisan"] = 5
	state.upkeep_tick = 10
	state.administration_tick = 2.5
	state.construction_spent_tick = 70
	state.refunds_tick = 30
	var values: Dictionary = {}
	for def: SeriesDef in _defs():
		values[def.id] = def.sampler.call(state)
	assert_eq(values[&"produced:malt"], 2.0)
	assert_eq(values[&"produced:flour"], 0.0)
	assert_eq(values[&"consumed:tea"], 0.5)
	assert_eq(values[&"spoiled:beer"], 0.25)
	assert_eq(values[&"bought:flour"], 30.0)
	assert_eq(values[&"immigration:artisan"], 1.0)
	assert_eq(values[&"emigration:worker:hunger"], 2.0)
	assert_eq(values[&"emigration:worker:satisfaction"], 3.0)
	assert_eq(values[&"promotions:artisan"], 4.0)
	assert_eq(values[&"demotions:artisan"], 5.0)
	assert_eq(values[&"expense:upkeep"], 7.5, "base upkeep is what administration leaves")
	assert_eq(values[&"expense:administration"], 2.5)
	assert_eq(values[&"expense:construction"], 100.0, "what was paid; the net 70 is after the refund")
	assert_eq(values[&"income:refund"], 30.0)
