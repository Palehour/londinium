extends GutTest

var _catalog: DataCatalog
var _params: Params
var _context: EconomyContext


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_catalog.base_values[&"ui.chains.bottleneck_margin"] = 0.0
	_catalog.base_values[&"ui.chains.min_samples"] = 1
	_catalog.base_values[&"ui.chains.tie_break"] = "upstream"
	_params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])


func _history() -> StatsHistory:
	return StatsHistory.new(SeriesRegistry.build(_params, _context), _params, _context)


func _state() -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.buildings.assign([
		{"definition_id": &"wharf", "cell": [0, 0], "workers": 3},
		{"definition_id": &"mill", "cell": [1, 1], "workers": 3},
		{"definition_id": &"bakery", "cell": [2, 2], "workers": 3},
	])
	return state


func _ranges(span: int, tier: StringName = StatsHistory.TIER_MEDIUM) -> Array[Dictionary]:
	return [{"id": &"fixture", "tier": tier, "span_seconds": span}]


func test_simulation_captures_stocks_before_the_first_tick() -> void:
	var state: EconomyState = _state()
	state.stocks.assign({&"bread": 111, &"flour": 222, &"wheat": 333})
	var sim: Simulation = Simulation.new(_params, state, 42, _context)
	assert_true(sim.stats_history_to_dict().get("opening", {}).is_empty())
	sim.tick()
	var opening: Dictionary = sim.stats_history_to_dict()["opening"]
	assert_eq(opening[&"bread"], 111.0)
	assert_eq(opening[&"flour"], 222.0)
	assert_eq(opening[&"wheat"], 333.0)
	state.stocks[&"bread"] = 0
	sim.tick()
	assert_eq(sim.stats_history_to_dict()["opening"][&"bread"], 111.0)
	assert_eq(sim.snapshot()["chain_bottlenecks"], {})


func test_opening_persists_and_old_histories_remain_readable_without_it() -> void:
	var history: StatsHistory = _history()
	var state: EconomyState = _state()
	state.stocks[&"bread"] = 77
	history.capture_opening(state)
	for tick: int in 60:
		history.record(state)
	var saved: Dictionary = history.to_dict()
	var restored: StatsHistory = _history()
	restored.restore(saved)
	assert_eq(restored.opening(&"bread"), 77.0)
	assert_eq(restored.seconds(), 60)
	saved.erase("opening")
	var old: StatsHistory = _history()
	old.restore(saved)
	assert_eq(old.seconds(), 60)
	assert_false(old.series(&"stock:bread", StatsHistory.TIER_CHAPTER).is_empty())
	assert_true(is_nan(old.opening(&"bread")))
	state.bread_demand_tick = 1.0
	assert_eq(ChainBottleneck.snapshot(old, _params, _context, state,
		_ranges(0, StatsHistory.TIER_CHAPTER))[&"fixture"]["status"], &"no_bottleneck")


func test_closed_windows_sum_demand_and_use_floor_not_partial_buckets() -> void:
	var history: StatsHistory = _history()
	var state: EconomyState = _state()
	state.buildings[2]["workers"] = 1 # Bakery is deliberately below the upstream capacities.
	history.capture_opening(state)
	for tick: int in 60:
		state.bread_demand_tick = 1.0 if tick < 50 else 0.0
		history.record(state)
	var demand: Dictionary = history.series(&"bread_demand", StatsHistory.TIER_MEDIUM)
	assert_eq(demand["total"].size(), 6)
	assert_eq(float(demand["total"][5]), 0.0)
	# 15 seconds selects only the last closed 10-second bucket, which has zero demand.
	var short: Dictionary = ChainBottleneck.snapshot(history, _params, _context, state, _ranges(15))[&"fixture"]
	assert_eq(short["status"], &"no_bottleneck")
	var longer: Dictionary = ChainBottleneck.snapshot(history, _params, _context, state, _ranges(20))[&"fixture"]
	assert_eq(longer["status"], &"bottleneck")
	assert_eq(longer["limiting_link"], &"bakery")
	var chapter: Dictionary = ChainBottleneck.snapshot(history, _params, _context, state,
		_ranges(0, StatsHistory.TIER_CHAPTER))[&"fixture"]
	assert_eq(chapter["status"], &"bottleneck")
	assert_eq(chapter["limiting_link"], &"bakery")


func test_opening_not_closing_stock_controls_the_first_window() -> void:
	var history: StatsHistory = _history()
	var state: EconomyState = _state()
	state.stocks[&"bread"] = 100
	history.capture_opening(state)
	state.stocks[&"bread"] = 0
	for tick: int in 60:
		state.bread_demand_tick = 1.0
		history.record(state)
	var result: Dictionary = ChainBottleneck.snapshot(history, _params, _context, state,
		_ranges(0, StatsHistory.TIER_CHAPTER))[&"fixture"]
	assert_eq(result["status"], &"no_bottleneck")
	assert_eq(result["links"][&"bakery"], &"excluded")


func test_barley_allocation_limits_wharf_without_changing_demand() -> void:
	var history: StatsHistory = _history()
	var state: EconomyState = _state()
	state.unloading_barley_percent = 100
	history.capture_opening(state)
	for tick: int in 60:
		state.bread_demand_tick = 0.1
		history.record(state)
	var result: Dictionary = ChainBottleneck.snapshot(history, _params, _context, state, _ranges(0))[&"fixture"]
	assert_eq(result["limiting_link"], &"wharf")
	assert_eq(result["barley_percent"], 100)


func test_minimum_samples_and_pending_configuration_produce_no_mark() -> void:
	var history: StatsHistory = _history()
	var state: EconomyState = _state()
	history.capture_opening(state)
	for tick: int in 10:
		history.record(state)
	_catalog.base_values[&"ui.chains.min_samples"] = 2
	var params: Params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	assert_eq(ChainBottleneck.snapshot(history, params, _context, state, _ranges(0))[&"fixture"]["status"], &"no_data")
	_catalog.base_values.erase(&"ui.chains.bottleneck_margin")
	params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	assert_eq(ChainBottleneck.snapshot(history, params, _context, state, _ranges(0))[&"fixture"]["status"], &"no_data")


func test_border_map_with_staffed_wharf_still_unloads_imported_flour() -> void:
	_context.map.river_cells.clear()
	_context.apply_border({"import_entries": [[0, 0]], "import_goods": ["flour"]})
	assert_true(_context.border_supplies(&"flour"))
	var history: StatsHistory = _history()
	var state: EconomyState = _state()
	state.money = 10000
	history.capture_opening(state)
	for tick: int in 60:
		state.bread_demand_tick = 0.3
		state.goods_bought_tick[&"flour"] = 1 if tick == 0 else 0
		history.record(state)
	var result: Dictionary = ChainBottleneck.snapshot(history, _params, _context, state, _ranges(0))[&"fixture"]
	assert_true(result["imported_flour_uses_capacity"])
	assert_eq(result["limiting_link"], &"wharf")
