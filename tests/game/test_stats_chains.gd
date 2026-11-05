extends GutTest

# Chains view numbers (issue #315, D-173). Each column is the D-066 series over the same three windows as the other
# tabs: flows add the bucket totals, stock keeps the last one. A series the registry does not have is missing, not
# zero. The highlight (issue #353) is the one link the simulation says limits the bread chain; bread_causes plays no part.


var _catalog: DataCatalog
var _params: Params
var _context: EconomyContext
var _look: StatsPresentation


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_params = SimTestParams.isolated_params(_catalog)
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	_look = StatsPresentation.new()
	_look.load_data()
	assert_eq(_look.errors, [], "The chains block in stats.json loads")


func test_the_chains_are_bread_then_beer_and_do_not_move_the_shared_strokes() -> void:
	assert_eq(_look.chains_order.size(), 2)
	assert_eq(_look.chains_order[0]["id"], &"bread")
	assert_eq(_look.chains_order[0]["diagnostic"], &"bread")
	assert_eq(_look.chains_order[1]["id"], &"beer")
	assert_eq(_look.chains_order[1]["diagnostic"], &"", "Beer has no diagnostic")
	var strokes: JSON = JSON.new()
	assert_eq(strokes.parse(FileAccess.get_file_as_string(StatsPresentation.PATH)), OK)
	assert_eq(_look.stroke_colors.size(), strokes.data["strokes"].size(), "Chains do not add to the shared strokes")
	assert_eq(_look.chains_columns.size(), 5)
	assert_eq(_look.chains_highlight_color, Color.html("#d55e00"))
	assert_eq(_look.chains_highlight_width, 4.0)


func test_an_unknown_diagnostic_is_rejected() -> void:
	var json: JSON = JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(StatsPresentation.PATH)), OK)
	var raw: Dictionary = json.data
	raw["chains"]["order"][1]["diagnostic"] = "beer"
	var look: StatsPresentation = StatsPresentation.new()
	look.validate(raw)
	assert_true(look.errors.has("data/ui/stats.json.chains.order.1.diagnostic: expected bread"))


func test_columns_match_the_series_in_the_three_windows() -> void:
	var initial: EconomyState = EconomyState.new()
	initial.stocks.assign({&"wheat": 10, &"flour": 0, &"bread": 0})
	initial.money = 10000
	initial.population = 10
	initial.buildings.append({"definition_id": &"mill", "cell": [1, 1]})
	var simulation: Simulation = Simulation.new(_params, initial, 123, _context)
	for _tick: int in 60:
		simulation.tick()
	var columns: Array[StringName] = _column_ids()
	for entry: Dictionary in _look.history_ranges:
		var chain: Dictionary = StatsChains.build(simulation, _look.chains_order, 0, entry["span_seconds"],
			entry["tier"])
		var flour: Dictionary = chain["links"][1]
		assert_true(flour["present"], "The mill is on the map")
		var expected: Dictionary[StringName, float] = _expected(simulation, &"flour", entry["tier"],
			entry["span_seconds"])
		for column: StringName in columns:
			_assert_amount(float(flour["values"][column]), expected[column], "%s %s" % [entry["id"], column])
		assert_gt(float(flour["values"][StatsChains.COLUMN_PRODUCED]), 0.0, "The mill did produce flour")
		var wheat: Dictionary = chain["links"][0]["values"]
		var wheat_produced: float = wheat[StatsChains.COLUMN_PRODUCED]
		assert_true(is_nan(wheat_produced), "Wheat is not produced: %s" % entry["id"])
		assert_ne(wheat_produced, 0.0)
		assert_true(is_nan(float(flour["values"][StatsChains.COLUMN_SPOILED])), "Flour does not spoil")
		_assert_amount(float(wheat[StatsChains.COLUMN_IN]), _flow(simulation, &"bought", &"wheat", entry["tier"],
			entry["span_seconds"]), "Entradas uses the series that exists")


func test_a_missing_series_is_not_drawn_as_zero() -> void:
	var simulation: Simulation = Simulation.new(_params, EconomyState.new(), 1, _context)
	simulation.tick()
	var chain: Dictionary = StatsChains.build(simulation, _look.chains_order, 0, 600, StatsHistory.TIER_MEDIUM)
	var wheat: Dictionary = chain["links"][0]["values"]
	assert_true(is_nan(wheat[StatsChains.COLUMN_PRODUCED]))
	assert_ne(wheat[StatsChains.COLUMN_PRODUCED], 0.0)
	var reading: String = StatsChains.reading(chain["links"][0], _column_ids())
	assert_eq(reading, Strings.text(Strings.STATS_SCREEN_CHAINS_ABSENT) % [
		Strings.building_label("wharf"), Strings.text(Strings.STATS_SCREEN_NO_DATA)])
	assert_false(reading.contains("0"), "An absent link does not invent zeros")


func test_exactly_one_bread_link_is_marked_and_beer_never() -> void:
	for link_id: StringName in [&"wharf", &"mill", &"bakery"]:
		var simulation: FakeBottleneckSim = _fake({"ten_minutes": _reading(StatsChains.STATUS_BOTTLENECK, link_id)})
		var bread: Dictionary = _build(simulation, 0)
		var beer: Dictionary = _build(simulation, 1)
		assert_eq(_marked(bread), [link_id], "Only the limiting link is marked (%s)" % link_id)
		assert_eq(_marked(beer), [], "Beer is never marked (%s)" % link_id)
		assert_eq(beer["bottleneck"]["status"], StatsChains.STATUS_NONE)
		assert_eq(StatsChains.cause(beer["bottleneck"]), "", "Beer has no cause line")


# Same call as before #353, on the empty city that used to mark the missing wharf from bread_causes.
func test_an_empty_city_marks_no_bread_link_on_the_old_call() -> void:
	var simulation: Simulation = Simulation.new(_params, EconomyState.new(), 1, _context)
	simulation.tick()
	var bread: Dictionary = StatsChains.build(simulation, _look.chains_order, 0, 0, StatsHistory.TIER_CHAPTER)
	assert_eq(_marked(bread), [], "No reading from the simulation means no mark")


func test_the_window_on_screen_picks_its_own_reading() -> void:
	var simulation: FakeBottleneckSim = _fake({
		"ten_minutes": _reading(StatsChains.STATUS_BOTTLENECK, &"mill"),
		"hour": _reading(StatsChains.STATUS_BOTTLENECK, &"bakery"),
	})
	assert_eq(_marked(_build(simulation, 0, "ten_minutes")), [&"mill"])
	assert_eq(_marked(_build(simulation, 0, "hour")), [&"bakery"])
	assert_eq(_marked(_build(simulation, 0, "chapter")), [], "A window the snapshot lacks has no data")


func test_bread_causes_no_longer_marks_anything() -> void:
	var simulation: FakeBottleneckSim = _fake({"ten_minutes": _reading(StatsChains.STATUS_BOTTLENECK, &"bakery")})
	simulation.diagnostics_causes = [{"definition_id": &"wharf", "reason": &"wheat_purchases_disabled"}]
	assert_eq(_marked(_build(simulation, 0)), [&"bakery"], "The contradicting cause does not move the mark")
	var quiet: FakeBottleneckSim = _fake({"ten_minutes": _reading(StatsChains.STATUS_NO_BOTTLENECK, &"")})
	quiet.diagnostics_causes = [{"definition_id": &"mill", "reason": &"no_road_access"}]
	assert_eq(_marked(_build(quiet, 0)), [], "A bread cause alone marks nothing")


func test_no_data_and_no_bottleneck_mark_nothing_and_say_so() -> void:
	var empty_city: Simulation = Simulation.new(_params, EconomyState.new(), 1, _context)
	empty_city.tick()
	var no_key: Dictionary = _build(empty_city, 0)
	assert_eq(_marked(no_key), [], "A snapshot without the contract marks nothing")
	assert_eq(StatsChains.cause(no_key["bottleneck"]), Strings.text(Strings.STATS_SCREEN_NO_DATA))
	for status: StringName in [StatsChains.STATUS_NO_DATA, StatsChains.STATUS_NO_BOTTLENECK]:
		var chain: Dictionary = _build(_fake({"ten_minutes": _reading(status, &"mill")}), 0)
		assert_eq(_marked(chain), [], "%s marks nothing, even if a link is named" % status)
	var calm: Dictionary = _build(_fake({"ten_minutes": _reading(StatsChains.STATUS_NO_BOTTLENECK, &"")}), 0)
	assert_eq(StatsChains.cause(calm["bottleneck"]), Strings.text(Strings.STATS_SCREEN_CHAINS_NO_BOTTLENECK))
	var broken: Dictionary = _build(_fake({"ten_minutes": _reading(StatsChains.STATUS_BOTTLENECK, &"")}), 0)
	assert_eq(_marked(broken), [], "A bottleneck that names no link is treated as no data")
	assert_eq(StatsChains.cause(broken["bottleneck"]), Strings.text(Strings.STATS_SCREEN_NO_DATA))


func test_the_cause_names_the_link_and_the_wharf_adds_the_split_and_imports() -> void:
	var mill: Dictionary = _build(_fake({"ten_minutes": _reading(StatsChains.STATUS_BOTTLENECK, &"mill")}), 0)
	assert_eq(StatsChains.cause(mill["bottleneck"]), Strings.text(Strings.STATS_SCREEN_CHAINS_CAUSE) % Strings.building_label("mill"))
	var wharf_reading: Dictionary = _reading(StatsChains.STATUS_BOTTLENECK, &"wharf")
	wharf_reading["barley_percent"] = 100.0
	wharf_reading["imported_flour_uses_capacity"] = true
	var wharf: Dictionary = _build(_fake({"ten_minutes": wharf_reading}), 0)
	var text: String = StatsChains.cause(wharf["bottleneck"])
	assert_true(text.contains("100 %"), text)
	assert_true(text.contains("0 %"), text)
	assert_true(text.contains(Strings.text(Strings.STATS_SCREEN_CHAINS_IMPORTS_TAKE)), text)
	wharf_reading["imported_flour_uses_capacity"] = false
	text = StatsChains.cause(_build(_fake({"ten_minutes": wharf_reading}), 0)["bottleneck"])
	assert_true(text.contains(Strings.text(Strings.STATS_SCREEN_CHAINS_IMPORTS_FREE)), text)


# The contract of the simulation (snapshot()["chain_bottlenecks"]), faked so the view is tested apart from the sim.
class FakeBottleneckSim extends Simulation:
	var bottlenecks: Dictionary = {}
	var diagnostics_causes: Array = []


	func snapshot(ranges: Array[Dictionary] = []) -> Dictionary:
		var data: Dictionary = super.snapshot(ranges)
		data["chain_bottlenecks"] = bottlenecks
		data["diagnostics"]["bread_causes"] = diagnostics_causes
		return data


func _fake(bottlenecks: Dictionary) -> FakeBottleneckSim:
	var simulation: FakeBottleneckSim = FakeBottleneckSim.new(_params, EconomyState.new(), 1, _context)
	simulation.bottlenecks = bottlenecks
	return simulation


func _reading(status: StringName, link: StringName) -> Dictionary:
	return {"status": status, "limiting_link": link, "reason": &"", "barley_percent": 0.0,
		"imported_flour_uses_capacity": false}


func _build(simulation: Simulation, chain_index: int, window: String = "ten_minutes") -> Dictionary:
	for entry: Dictionary in _look.history_ranges:
		if entry["id"] == window:
			return StatsChains.build(simulation, _look.chains_order, chain_index, entry["span_seconds"], entry["tier"],
				_look.history_ranges)
	return {}


func _marked(chain: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for link: Dictionary in chain["links"]:
		if link["highlighted"]:
			ids.append(link["building"])
	return ids


func _assert_amount(got: float, expected: float, label: String) -> void:
	if is_nan(expected):
		assert_true(is_nan(got), label)
		return
	assert_almost_eq(got, expected, 0.001, label)


func _column_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for column: Dictionary in _look.chains_columns:
		ids.append(column["id"])
	return ids


# The same window rule the view claims to use, read from the series and not from StatsChains.
func _expected(simulation: Simulation, good: StringName, tier: StringName, span: int) -> Dictionary[StringName, float]:
	var bought: float = _flow(simulation, &"bought", good, tier, span)
	var produced: float = _flow(simulation, &"produced", good, tier, span)
	var incoming: float = NAN
	if not is_nan(bought) or not is_nan(produced):
		incoming = (0.0 if is_nan(bought) else bought) + (0.0 if is_nan(produced) else produced)
	return {
		StatsChains.COLUMN_IN: incoming,
		StatsChains.COLUMN_PRODUCED: produced,
		StatsChains.COLUMN_CONSUMED: _flow(simulation, &"consumed", good, tier, span),
		StatsChains.COLUMN_SPOILED: _flow(simulation, &"spoiled", good, tier, span),
		StatsChains.COLUMN_STOCK: _last(simulation, good, tier, span),
	}


func _flow(simulation: Simulation, metric: StringName, good: StringName, tier: StringName, span: int) -> float:
	return _reduce(simulation.stats_series(_series_id(metric, good), tier), span, false)


func _last(simulation: Simulation, good: StringName, tier: StringName, span: int) -> float:
	return _reduce(simulation.stats_series(_series_id(&"stock", good), tier), span, true)


func _series_id(metric: StringName, good: StringName) -> StringName:
	return SeriesDef.create(metric, &"units", SeriesDef.AGGREGATION_SUM, {&"good": good}, _unused).id


func _unused(_state: Variant) -> float:
	return 0.0


func _reduce(series: Dictionary, span: int, last: bool) -> float:
	if series.is_empty():
		return NAN
	var values: PackedFloat32Array = StatsSummary.window(series, "total", span)
	if last:
		for index: int in range(values.size() - 1, -1, -1):
			if not is_nan(values[index]):
				return values[index]
		return NAN
	var total: float = 0.0
	var found: bool = false
	for value: float in values:
		if is_nan(value):
			continue
		total += value
		found = true
	return total if found else NAN
