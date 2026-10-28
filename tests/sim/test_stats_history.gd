extends GutTest

# Issue #82 (D-066): chapter statistics in three levels, derived from the state and never feeding back into it.

const EIGHT_HOURS: int = 8 * 3600
const FIVE_MB: int = 5 * 1024 * 1024
const WORST_CASE_SERIES: int = 200
# Eight hours in 10 s buckets: the last two hours (720) are kept, after the first 2160.
const MEDIUM_BUCKETS: int = 720
const MEDIUM_FIRST_BUCKET: int = 2160
const CHAPTER_BUCKETS: int = 480

var _catalog: DataCatalog


func before_all() -> void:
	_catalog = DataLoader.new().load_all().catalog


func _params(modifiers: Array[Modifier] = []) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	return Params.new(_catalog, role)


func _context() -> EconomyContext:
	return EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])


# A flow, a mean level and a last level that all read state.money, so a test drives them by setting it.
func _money_defs() -> Array[SeriesDef]:
	var read: Callable = func(state: EconomyState) -> float: return float(state.money)
	var defs: Array[SeriesDef] = [
		SeriesDef.create(&"flow", &"pence", SeriesDef.AGGREGATION_SUM, {}, read),
		SeriesDef.create(&"level", &"pence", SeriesDef.AGGREGATION_MEAN, {}, read),
		SeriesDef.create(&"cash", &"pence", SeriesDef.AGGREGATION_LAST, {}, read),
	]
	return defs


func _history(params: Params = null, defs: Array[SeriesDef] = []) -> StatsHistory:
	return StatsHistory.new(defs if not defs.is_empty() else _money_defs(), params if params != null else _params(),
		_context())


func _feed(history: StatsHistory, state: EconomyState, values: Array) -> void:
	for value: Variant in values:
		state.money = int(value)
		history.record(state)


func _simulation(stats_history: Dictionary = {}) -> Simulation:
	var state: EconomyState = EconomyState.new()
	state.money = 5000
	state.population = 20
	state.stocks[&"bread"] = 100
	state.buildings.append({"definition_id": &"wharf", "cell": [0, 0]})
	state.buildings.append({"definition_id": &"mill", "cell": [3, 3]})
	return Simulation.new(_params(), state, 7, _context(), [], [], stats_history)


func test_bucket_keeps_min_max_mean_sum_last() -> void:
	var history: StatsHistory = _history()
	var state: EconomyState = EconomyState.new()
	var values: Array = []
	for second: int in range(1, 61):
		values.append(second)
	_feed(history, state, values)
	var flow: Dictionary = history.series(&"flow", StatsHistory.TIER_MEDIUM)
	assert_eq(flow["bucket_seconds"], 10)
	assert_eq(flow["min"].size(), 6, "six closed 10 s buckets in a minute")
	assert_eq(flow["min"][0], 1.0)
	assert_eq(flow["max"][0], 10.0)
	assert_eq(flow["mean"][0], 5.5)
	assert_eq(flow["total"][0], 55.0, "a flow totals its sum")
	assert_eq(flow["total"][5], 555.0)
	var cash: Dictionary = history.series(&"cash", StatsHistory.TIER_MEDIUM)
	assert_eq(cash["total"][0], 10.0, "a last-value level keeps the value at the bucket's end")
	assert_eq(cash["mean"][1], 15.5)
	var minute: Dictionary = history.series(&"flow", StatsHistory.TIER_CHAPTER)
	assert_eq(minute["min"].size(), 1)
	assert_eq(minute["min"][0], 1.0)
	assert_eq(minute["max"][0], 60.0)
	assert_eq(minute["mean"][0], 30.5)
	assert_eq(minute["total"][0], 1830.0)
	assert_eq(history.series(&"cash", StatsHistory.TIER_CHAPTER)["total"][0], 60.0)
	assert_eq(history.series(&"level", StatsHistory.TIER_CHAPTER)["total"][0], 1830.0,
		"a mean level still keeps its sum")


func test_open_bucket_is_not_exposed_until_it_closes() -> void:
	var history: StatsHistory = _history()
	_feed(history, EconomyState.new(), [1, 2, 3, 4, 5, 6, 7, 8, 9])
	assert_eq(history.series(&"flow", StatsHistory.TIER_MEDIUM)["min"].size(), 0)
	_feed(history, EconomyState.new(), [10])
	assert_eq(history.series(&"flow", StatsHistory.TIER_MEDIUM)["min"].size(), 1)


func test_fine_ring_keeps_600_seconds() -> void:
	var history: StatsHistory = _history()
	var values: Array = []
	for second: int in range(1, 602):
		values.append(second)
	_feed(history, EconomyState.new(), values)
	var fine: Dictionary = history.series(&"cash", StatsHistory.TIER_FINE)
	assert_eq(fine["values"].size(), 600)
	assert_eq(fine["first_second"], 2)
	assert_eq(fine["values"][0], 2.0)
	assert_eq(fine["values"][599], 601.0)


func test_medium_keeps_last_two_hours() -> void:
	var history: StatsHistory = _history()
	var state: EconomyState = EconomyState.new()
	for second: int in range(1, 7211):
		state.money = second
		history.record(state)
	var medium: Dictionary = history.series(&"cash", StatsHistory.TIER_MEDIUM)
	assert_eq(medium["min"].size(), 720, "two hours of 10 s buckets")
	assert_eq(medium["first_bucket"], 1, "the first 10 s fell out")
	assert_eq(medium["total"][0], 20.0)
	assert_eq(medium["total"][719], 7210.0)


func test_chapter_keeps_every_minute() -> void:
	var history: StatsHistory = _history(null, [SeriesDef.create(&"cash", &"pence", SeriesDef.AGGREGATION_LAST, {},
		func(state: EconomyState) -> float: return float(state.money))])
	var state: EconomyState = EconomyState.new()
	for second: int in range(1, EIGHT_HOURS + 1):
		state.money = second
		history.record(state)
	var chapter: Dictionary = history.series(&"cash", StatsHistory.TIER_CHAPTER)
	assert_eq(chapter["min"].size(), 480, "every minute of eight hours")
	assert_eq(chapter["first_bucket"], 0)
	assert_eq(chapter["total"][479], float(EIGHT_HOURS))


# Worst case for size: the ~200 series ceiling, eight hours, every event the log keeps, and noise that does not
# compress. A real game compresses far better (measured in long_test_drift.gd).
func test_eight_hour_history_compresses_under_5_mb() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 82
	var defs: Array[SeriesDef] = []
	for index: int in WORST_CASE_SERIES:
		defs.append(SeriesDef.create(StringName("series_%d" % index), &"units", SeriesDef.AGGREGATION_SUM, {},
			func(_state: EconomyState) -> float: return 0.0))
	var params: Params = _params()
	var saved: Dictionary = {"version": StatsHistory.VERSION, "seconds": EIGHT_HOURS,
		"medium": _noise_tier(rng, defs, 10, MEDIUM_FIRST_BUCKET, MEDIUM_BUCKETS),
		"chapter": _noise_tier(rng, defs, 60, 0, CHAPTER_BUCKETS), "causes": _full_cause_log(params).to_dict()}
	var history: StatsHistory = _history(params, defs)
	history.restore(saved)
	assert_eq(history.seconds(), EIGHT_HOURS, "the worst case is a valid save")
	assert_eq(history.events().size(), int(params.get_value(&"stats.causes.max_events")), "the log is full")
	var size: int = StatsHistory.compressed_size(history.to_dict())
	gut.p("Worst-case 8 h history: %d bytes compressed" % size)
	assert_lt(size, FIVE_MB)


func _noise_tier(rng: RandomNumberGenerator, defs: Array[SeriesDef], bucket_seconds: int, first: int,
		count: int) -> Dictionary:
	var columns: Dictionary = {}
	var opens: Dictionary = {}
	for def: SeriesDef in defs:
		var packed: PackedFloat32Array = []
		packed.resize(count * StatsHistory.BUCKET_FIELDS)
		for index: int in packed.size():
			packed[index] = rng.randf() * 100000.0
		columns[String(def.id)] = packed
		opens[String(def.id)] = PackedFloat64Array([0.0, INF, -INF, 0.0, NAN])
	return {"bucket_seconds": bucket_seconds, "first_bucket": first, "count": count, "open_bucket": first + count,
		"columns": columns, "open": opens}


@warning_ignore("integer_division")
func _full_cause_log(params: Params) -> CauseLog:
	var causes: CauseLog = CauseLog.new(int(params.get_value(&"stats.causes.max_events")))
	for index: int in int(params.get_value(&"stats.causes.max_events")):
		causes.note(index, &"building", StringName("brewery@%d,%d" % [index % 100, index / 100]),
			&"no_malt" if index % 2 == 0 else &"storage_full")
	return causes


func test_recording_does_not_mutate_state() -> void:
	var sim: Simulation = _simulation()
	for tick_index: int in 30:
		sim.tick()
	var state: EconomyState = EconomyState.from_dict(sim.snapshot()["economy"])
	state.taxes_tick = 7
	state.class_tax_tick[&"worker"] = 3.5
	var params: Params = _params()
	var context: EconomyContext = _context()
	var history: StatsHistory = StatsHistory.new(SeriesRegistry.build(params, context), params, context)
	var before: Dictionary = state.to_dict()
	history.record(state)
	history.record(state)
	assert_eq(state.to_dict(), before)
	assert_eq(state.taxes_tick, 7)
	assert_eq(state.class_tax_tick, {&"worker": 3.5})


func test_simulation_is_same_with_restored_or_broken_history() -> void:
	var source: Simulation = _simulation()
	for tick_index: int in 75:
		source.tick()
	var plain: Simulation = _simulation()
	var broken: Simulation = _simulation({"version": 99, "seconds": "x"})
	assert_push_warning("StatsHistory: malformed saved history")
	var restored: Simulation = _simulation(source.stats_history_to_dict())
	for tick_index: int in 120:
		for sim: Simulation in [plain, broken, restored]:
			sim.apply_command(SetTaxCommand.new(0.3 if tick_index % 40 < 20 else 0.2))
			sim.tick()
		assert_eq(broken.snapshot(), plain.snapshot())
		assert_eq(restored.snapshot(), plain.snapshot())


func test_missing_or_malformed_history_starts_empty() -> void:
	var missing: Simulation = _simulation()
	assert_eq(missing.stats_history_to_dict()["seconds"], 0)
	assert_eq(missing.stats_series(&"money", StatsHistory.TIER_CHAPTER)["min"].size(), 0)
	var good: Dictionary = _played_history(70)
	var broken: Array[Dictionary] = [
		{"version": StatsHistory.VERSION},
		{"version": StatsHistory.VERSION, "seconds": 70, "medium": "x", "chapter": good["chapter"], "causes": good["causes"]},
		{"version": StatsHistory.VERSION, "seconds": 69, "medium": good["medium"], "chapter": good["chapter"],
			"causes": good["causes"]},
	]
	var truncated: Dictionary = good.duplicate(true)
	truncated["chapter"]["columns"]["money"] = PackedFloat32Array([1.0])
	broken.append(truncated)
	var resized: Dictionary = good.duplicate(true)
	resized["medium"]["bucket_seconds"] = 5
	broken.append(resized)
	for saved: Dictionary in broken:
		var sim: Simulation = _simulation(saved)
		assert_push_warning("StatsHistory: malformed saved history")
		assert_eq(sim.stats_history_to_dict()["seconds"], 0, str(saved.keys()))
		sim.tick()
		assert_eq(sim.stats_series(&"money", StatsHistory.TIER_FINE)["values"].size(), 1, "the game still plays")


func _played_history(ticks: int) -> Dictionary:
	var sim: Simulation = _simulation()
	for tick_index: int in ticks:
		sim.tick()
	return sim.stats_history_to_dict()


func test_round_trip_restores_buckets_and_events() -> void:
	var first: StatsHistory = _history()
	var state: EconomyState = EconomyState.new()
	var values: Array = []
	for second: int in range(1, 126):
		values.append(second * 3 % 17)
	_feed(first, state, values)
	var saved: Dictionary = first.to_dict()
	var second_history: StatsHistory = _history()
	second_history.restore(saved)
	assert_eq(second_history.to_dict(), saved)
	assert_eq(second_history.events(), first.events())
	# Both continue the half-filled buckets alike: the open bucket's samples were saved too.
	var more: Array = []
	for second: int in range(126, 200):
		more.append(second % 11)
	_feed(first, state, more)
	_feed(second_history, state, more)
	assert_eq(second_history.to_dict(), first.to_dict())
	assert_eq(second_history.series(&"flow", StatsHistory.TIER_CHAPTER),
		first.series(&"flow", StatsHistory.TIER_CHAPTER))


func test_a_series_the_save_lacks_reads_as_no_data() -> void:
	var first: StatsHistory = _history()
	_feed(first, EconomyState.new(), range(1, 61))
	var saved: Dictionary = first.to_dict()
	var defs: Array[SeriesDef] = _money_defs()
	defs.append(SeriesDef.create(&"new_metric", &"units", SeriesDef.AGGREGATION_SUM, {&"district": &"east"},
		func(_state: EconomyState) -> float: return 1.0))
	var later: StatsHistory = _history(null, defs)
	later.restore(saved)
	assert_eq(later.seconds(), 60)
	var added: Dictionary = later.series(&"new_metric:east", StatsHistory.TIER_CHAPTER)
	assert_eq(added["min"].size(), 1)
	assert_true(is_nan(added["total"][0]), "no data before the series existed")
	assert_eq(later.series(&"flow", StatsHistory.TIER_CHAPTER)["total"][0], 1830.0)


func test_simulation_records_real_series_every_tick() -> void:
	var sim: Simulation = _simulation()
	for tick_index: int in 60:
		sim.tick()
	var money: Dictionary = sim.stats_series(&"money", StatsHistory.TIER_FINE)
	assert_eq(money["values"].size(), 60)
	assert_eq(money["values"][59], float(sim.treasury()))
	var chapter: Dictionary = sim.stats_series(&"money", StatsHistory.TIER_CHAPTER)
	assert_eq(chapter["total"][0], float(sim.treasury()))
	assert_eq(sim.stats_series(&"unknown", StatsHistory.TIER_CHAPTER), {})
	assert_eq(sim.stats_series(&"money", &"weekly"), {})


# Issue #73 (D-137): the views read the cause log only through these, read-only.
func test_the_simulation_exposes_the_cause_chain_entries_and_seconds() -> void:
	var simulation: Simulation = _simulation()
	for second: int in 5:
		simulation.tick()
	assert_eq(simulation.stats_seconds(), 5)
	var entries: Array[Dictionary] = simulation.stats_cause_entries(0)
	assert_eq(entries.size(), simulation.stats_events().size())
	assert_eq(simulation.stats_cause_count(), entries.size())
	assert_eq(simulation.stats_cause_first_serial(), 0)
	var mill: StringName = StatsHistory.building_subject({"definition_id": &"mill", "cell": [3, 3]})
	var chain: Array[Dictionary] = simulation.stats_cause_chain(&"building", mill)
	assert_false(chain.is_empty(), "the mill has its starting cause")
	assert_eq(chain[-1]["subject"], mill)
	var bare: Simulation = Simulation.new(_params(), EconomyState.new(), 7)
	assert_eq(bare.stats_cause_chain(&"building", mill), [] as Array[Dictionary], "no context, no history")
	assert_eq(bare.stats_cause_entries(0), [] as Array[Dictionary])
	assert_eq(bare.stats_seconds(), 0)
