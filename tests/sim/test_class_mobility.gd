extends GutTest

# Mobility between classes (issue #53, D-061): workers rise into artisans with room, beer, bread and a satisfied
# worker class; artisans fall back when their community stays under its threshold for 60 s.

var _catalog: DataCatalog
var _params: Params
var _context: EconomyContext
var _state: EconomyState
var _mobility: MobilitySystem


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	_params = _params_with({})
	_mobility = MobilitySystem.new()
	_state = EconomyState.new()
	_state.tax_rate = 0.25
	_state.buildings.append({"definition_id": &"housing"})
	_state.buildings.append({"definition_id": &"artisan_housing"})
	ClassStates.ensure(_state, _context)


func _params_with(changes: Dictionary) -> Params:
	var role: RoleDef = RoleDef.new()
	for key: StringName in changes:
		role.modifiers.append(Modifier.new(key, &"set", changes[key]))
	return Params.new(_catalog, role)


func _artisans() -> ClassDef:
	return _context.classes[&"artisan"]


func _artisan_state() -> ClassState:
	return _state.class_states[&"artisan"]


func _live(workers: int, artisans: int) -> void:
	_state.population = workers + artisans
	_artisan_state().population = artisans


# Scores the needs and housing for the given coverages, and sets the worker's smoothed satisfaction.
func _city(bread: float, beer: float, worker_satisfaction: float) -> void:
	_state.hunger_smoothed_coverage = bread
	_state.bread_coverage = bread
	_state.beer_coverage = beer
	SatisfactionSystem.new().update_target(_state, _params, _context)
	_state.satisfaction = worker_satisfaction


func _ticks(count: int) -> void:
	for index: int in range(count):
		_state.reset_flows()
		_mobility.tick(_state, _params, _context)


func _blocker_reasons() -> Array[StringName]:
	var reasons: Array[StringName] = []
	for blocker: Dictionary in MobilitySystem.promotion_blockers(_state, _params, _context, _artisans()):
		reasons.append(blocker["reason"])
	return reasons


func test_promotion_needs_community_80() -> void:
	_live(20, 0)
	_city(1.0, 0.79, 100.0)
	assert_has(_blocker_reasons(), MobilitySystem.REASON_CATEGORY_BELOW, "Community 79 is under 80")
	_city(1.0, 0.80, 100.0)
	assert_eq(_blocker_reasons(), [] as Array[StringName], "Community 80 is enough")


func test_promotion_needs_sustenance_met() -> void:
	_live(20, 0)
	_city(0.74, 1.0, 100.0)
	assert_has(_blocker_reasons(), MobilitySystem.REASON_CATEGORY_BELOW)
	_city(0.75, 1.0, 100.0)
	assert_eq(_blocker_reasons(), [] as Array[StringName])


func test_promotion_needs_worker_satisfaction_70() -> void:
	_live(20, 0)
	_city(1.0, 1.0, 69.0)
	assert_eq(_blocker_reasons(), [MobilitySystem.REASON_SOURCE_SATISFACTION_LOW] as Array[StringName])
	_city(1.0, 1.0, 70.0)
	assert_eq(_blocker_reasons(), [] as Array[StringName])


func test_promotion_moves_two_per_minute() -> void:
	_live(20, 0)
	_city(1.0, 1.0, 100.0)
	_ticks(29)
	assert_eq(_artisan_state().population, 0)
	_ticks(1)
	assert_eq(_artisan_state().population, 1, "One every 30 s at 2 per minute")
	_ticks(30)
	assert_eq(_artisan_state().population, 2)
	assert_eq(_state.population, 20, "Promotion never changes the total")
	assert_eq(ClassStates.population_of(_state, _context.classes[&"worker"]), 18)


func test_promotion_counts_this_tick() -> void:
	_live(20, 0)
	_city(1.0, 1.0, 100.0)
	_ticks(30)
	assert_eq(_state.promotions_tick, 1)
	_ticks(1)
	assert_eq(_state.promotions_tick, 0)


func test_promotion_limited_by_free_housing() -> void:
	_live(20, 10)
	_city(1.0, 1.0, 100.0)
	# Base 10 plus +2 for each of the two met categories: 14 places, 4 free.
	assert_eq(_artisan_state().housing_capacity, 14)
	_ticks(600)
	assert_eq(_artisan_state().population, 14)
	assert_has(_blocker_reasons(), MobilitySystem.REASON_NO_FREE_HOUSING)


func test_promotion_does_not_build_a_backlog() -> void:
	_live(20, 0)
	_city(1.0, 1.0, 100.0)
	_ticks(20)
	_city(1.0, 0.5, 100.0)
	_ticks(100)
	_city(1.0, 1.0, 100.0)
	_ticks(29)
	assert_eq(_artisan_state().population, 0, "The 20 s before the stop do not count")
	_ticks(1)
	assert_eq(_artisan_state().population, 1)


func test_promoted_workers_leave_their_jobs() -> void:
	_state.buildings.append({"definition_id": &"bakery", "workers": 3})
	_live(3, 0)
	WorkersSystem.refresh_counts(_state)
	_city(1.0, 1.0, 100.0)
	_ticks(30)
	assert_eq(_state.employed, 2, "An artisan does not take jobs")


func test_promotion_prefers_the_unemployed() -> void:
	_state.buildings.append({"definition_id": &"bakery", "workers": 3})
	_live(5, 0)
	WorkersSystem.refresh_counts(_state)
	_city(1.0, 1.0, 100.0)
	_ticks(60)
	assert_eq(_artisan_state().population, 2)
	assert_eq(_state.employed, 3)


func test_demotion_starts_after_60_seconds_below_community() -> void:
	_live(20, 10)
	_city(1.0, 0.0, 100.0)
	_ticks(59)
	assert_false(MobilitySystem.is_demotion_active(_artisan_state(), _params, _artisans()), "59 s")
	assert_eq(_artisan_state().demotion_fraction, 0.0, "Nothing accumulates before 60 s")
	_ticks(1)
	assert_true(MobilitySystem.is_demotion_active(_artisan_state(), _params, _artisans()), "60 s")
	assert_gt(_artisan_state().demotion_fraction, 0.0)
	_ticks(1)
	assert_true(MobilitySystem.is_demotion_active(_artisan_state(), _params, _artisans()), "61 s")


func test_demotion_needs_community_under_50() -> void:
	_live(20, 10)
	_city(1.0, 0.50, 100.0)
	_ticks(120)
	assert_eq(_artisan_state().demotion_seconds_below, 0, "Community 50 is not under 50")
	_city(1.0, 0.49, 100.0)
	_ticks(60)
	assert_true(MobilitySystem.is_demotion_active(_artisan_state(), _params, _artisans()))


func test_demotion_timer_resets_when_community_recovers() -> void:
	_live(20, 10)
	_city(1.0, 0.0, 100.0)
	_ticks(59)
	_city(1.0, 0.6, 100.0)
	_ticks(1)
	assert_eq(_artisan_state().demotion_seconds_below, 0)
	_city(1.0, 0.0, 100.0)
	_ticks(59)
	assert_false(MobilitySystem.is_demotion_active(_artisan_state(), _params, _artisans()))


func test_demotion_clock_waits_for_someone_to_fall_back() -> void:
	_live(20, 0)
	_city(1.0, 0.0, 100.0)
	_ticks(120)
	assert_eq(_artisan_state().demotion_seconds_below, 0, "No artisans, nobody to fall back")


func test_demotion_moves_two_per_minute() -> void:
	_live(20, 10)
	_city(1.0, 0.0, 100.0)
	# Active from the 60th second, which already counts: one every 30 s from there, the first at second 89.
	_ticks(88)
	assert_eq(_artisan_state().population, 10)
	_ticks(1)
	assert_eq(_artisan_state().population, 9)
	assert_eq(_state.demotions_tick, 1)
	_ticks(30)
	assert_eq(_artisan_state().population, 8)
	assert_eq(_state.population, 30)


func test_demotion_does_not_need_room_in_worker_housing() -> void:
	# 20 workers already fill their housing.
	_live(20, 10)
	_city(1.0, 0.0, 100.0)
	_ticks(89)
	assert_eq(_artisan_state().population, 9)


func test_values_out_of_range_are_rejected_through_role_modifiers() -> void:
	for change: Array in [[&"class.artisan.mobility.promotion.comunidad.min_score", 101.0],
			[&"class.artisan.mobility.promotion.source_satisfaction", -1.0],
			[&"class.artisan.mobility.promotion.per_minute", -1.0],
			[&"class.artisan.mobility.demotion.seconds", 0.0],
			[&"class.artisan.mobility.demotion.seconds", 1.5],
			[&"class.artisan.mobility.demotion.per_minute", -0.5]]:
		var params: Params = _params_with({change[0]: change[1]})
		assert_false(params.validation_errors().is_empty(), "%s = %s" % change)


func test_a_role_can_change_the_promotion_minimum() -> void:
	_params = _params_with({&"class.artisan.mobility.promotion.comunidad.min_score": 70.0})
	_live(20, 0)
	_city(1.0, 0.7, 100.0)
	assert_eq(_blocker_reasons(), [] as Array[StringName])


func test_the_linked_thresholds_follow_the_category_ones() -> void:
	_params = _params_with({&"needs.comunidad.threshold": 40.0})
	_live(20, 10)
	_city(1.0, 0.45, 100.0)
	_ticks(120)
	assert_eq(_artisan_state().demotion_seconds_below, 0, "45 is not under the category's 40")


func test_blockers_report_no_housing_low_beer_low_satisfaction() -> void:
	_state.buildings.clear()
	_state.buildings.append({"definition_id": &"housing"})
	_live(20, 0)
	_city(1.0, 0.0, 10.0)
	var blockers: Array[Dictionary] = MobilitySystem.promotion_blockers(_state, _params, _context, _artisans())
	var reasons: Array[StringName] = _blocker_reasons()
	assert_has(reasons, MobilitySystem.REASON_NO_FREE_HOUSING)
	assert_has(reasons, MobilitySystem.REASON_CATEGORY_BELOW)
	assert_has(reasons, MobilitySystem.REASON_SOURCE_SATISFACTION_LOW)
	for blocker: Dictionary in blockers:
		if blocker["reason"] == MobilitySystem.REASON_CATEGORY_BELOW:
			assert_eq(blocker["category"], &"comunidad")
			assert_eq(blocker["missing_goods"], [&"beer"] as Array[StringName])


func test_blockers_report_no_workers() -> void:
	_live(0, 0)
	_city(1.0, 1.0, 100.0)
	assert_eq(_blocker_reasons(), [MobilitySystem.REASON_NO_SOURCE_POPULATION] as Array[StringName])


func test_snapshot_explains_the_mobility() -> void:
	var state: EconomyState = EconomyState.new()
	state.population = 20
	state.buildings.append({"definition_id": &"housing"})
	var sim: Simulation = Simulation.new(_params, state, 1, _context)
	var needs: Dictionary = sim.snapshot()["needs"]
	var mobility: Dictionary = needs["classes"][&"artisan"]["mobility"]
	assert_eq(mobility["from"], &"worker")
	assert_false(mobility["promotion"]["active"])
	assert_eq(mobility["promotion"]["per_minute"], 2.0)
	var reasons: Array = mobility["promotion"]["blockers"].map(func(entry: Dictionary) -> StringName: return entry["reason"])
	assert_has(reasons, MobilitySystem.REASON_NO_FREE_HOUSING)
	assert_eq(mobility["demotion"]["seconds_required"], 60)
	assert_eq(needs["classes"][&"worker"]["mobility"], {})


func test_mobility_state_round_trips() -> void:
	_artisan_state().promotion_fraction = 0.25
	_artisan_state().demotion_fraction = 0.5
	_artisan_state().demotion_seconds_below = 42
	var copy: ClassState = EconomyState.from_dict(_state.to_dict()).class_states[&"artisan"]
	assert_eq(copy.promotion_fraction, 0.25)
	assert_eq(copy.demotion_fraction, 0.5)
	assert_eq(copy.demotion_seconds_below, 42)
	var old: ClassState = ClassState.from_dict({"population": 3})
	assert_eq(old.demotion_seconds_below, 0, "A state saved before mobility starts with no timer")


# Restarts the game from its own snapshot with the given stocks of bread and beer, the way a save loads.
# The test is about mobility, not the chains, so the stocks are set by hand.
func _reload(sim: Simulation, bread: int, beer: int) -> Simulation:
	var snapshot: Dictionary = sim.snapshot()
	var state: EconomyState = EconomyState.from_dict(snapshot["economy"])
	state.stocks[&"bread"] = bread
	state.stocks[&"beer"] = beer
	state.beer_fraction = 0.0
	return Simulation.new(_params, state, 1, _context, snapshot["stats"]["window"])


func _artisans_in(sim: Simulation) -> int:
	return int(sim.snapshot()["economy"]["class_states"][&"artisan"]["population"])


func _run(sim: Simulation, ticks: int) -> void:
	for index: int in range(ticks):
		sim.tick()


# A beer shortage makes artisans fall back; when the beer returns they stop falling and workers rise again.
func test_beer_shortage_demotes_and_recovers() -> void:
	var initial: EconomyState = EconomyState.new()
	initial.money = 1000000
	initial.population = 30
	initial.buildings.append({"definition_id": &"housing", "cell": [1, 1]})
	initial.buildings.append({"definition_id": &"housing", "cell": [2, 1]})
	initial.buildings.append({"definition_id": &"artisan_housing", "cell": [3, 1]})
	var sim: Simulation = _reload(Simulation.create_new(_params, initial, 1, _context), 100000, 1000)
	_run(sim, 300)
	var with_beer: int = _artisans_in(sim)
	assert_gt(with_beer, 0, "Workers rise with beer")
	sim = _reload(sim, 100000, 0)
	_run(sim, 59)
	assert_eq(_artisans_in(sim), with_beer, "Nobody falls back before 60 s without beer")
	_run(sim, 121)
	var after_shortage: int = _artisans_in(sim)
	assert_lt(after_shortage, with_beer, "Artisans fall back without beer")
	sim = _reload(sim, 100000, 1000)
	_run(sim, 300)
	assert_gt(_artisans_in(sim), after_shortage, "Workers rise again when the beer returns")


# New tests for #352 sim scope: mobility_events for UI (only ascenso lost posts), demotion seconds_left + missing_goods reuse,
# 2 emp +1 unemp promotes unemployed first then employed causing losses in 2 buildings, reloj infer, reset, mobility_events, transient saves compat.

# Helper only for new #352 tests: allows replaying red on HEAD (no method yet) without compile error.
# Returns {} when absent so existing asserts (using get(,-1) or direct) fail naturally if no channel.
# No fallback/assert that hides absence. Production getter stays normal typed (no reflection).
func _reported_mobility_events(sim: Simulation) -> Dictionary:
	return sim.call(&"mobility_events") if sim.has_method(&"mobility_events") else {}


func test_promotion_2_employed_plus_1_unemployed_reports_correct_buildings_and_employed_promoted() -> void:
	_state.buildings.append({"definition_id": &"bakery", "cell": [0, 0], "workers": 1})
	_state.buildings.append({"definition_id": &"mill", "cell": [1, 0], "workers": 1})
	_state.buildings.append({"definition_id": &"wharf", "cell": [2, 0], "workers": 1})
	_live(4, 0)  # 3 jobs => emp=3, unemp=1
	WorkersSystem.refresh_counts(_state)
	_city(1.0, 1.0, 100.0)
	# fixture high rate (no prod change) so exactly 3 promote in 1 tick: 1 unemp (0 loss) + 2 emp (2 losses)
	var params_high: Params = _params_with({&"class.artisan.mobility.promotion.per_minute": 180.0})
	_state.reset_flows()
	var ev := {"tick": 0, "employed_promoted": 0, "buildings": []}
	_mobility.tick(_state, params_high, _context, ev)
	assert_eq(_artisan_state().population, 3)
	assert_eq(ev.get("employed_promoted", -1), 2)
	var blds: Array = ev.get("buildings", [])
	assert_eq(blds.size(), 2)
	assert_eq(blds, [
		{"id": [0, 0], "definition_id": &"bakery", "workers_lost": 1},
		{"id": [1, 0], "definition_id": &"mill", "workers_lost": 1}
	])
	for b: Dictionary in blds:
		assert_true(b.has("id"))
		assert_true(b.has("definition_id"))
		assert_eq(b.get("workers_lost", -1), 1)
	assert_eq(_state.employed, 1)
	assert_eq(_state.unemployed, 0)


func test_mobility_events_reset_per_tick_and_has_real_tick() -> void:
	_state.buildings.append({"definition_id": &"bakery", "cell": [0, 0], "workers": 1})
	_live(2, 0)
	WorkersSystem.refresh_counts(_state)
	_city(1.0, 1.0, 100.0)
	_state.reset_flows()
	var ev := {"tick": 0, "employed_promoted": 0, "buildings": []}
	_mobility.tick(_state, _params, _context, ev)
	# mobility_events() uses real tick counter (transient, not via snapshot)
	var sim: Simulation = Simulation.new(_params, _state, 123, _context)
	sim.tick()
	var sev: Dictionary = _reported_mobility_events(sim)
	assert_eq(sev["tick"], 1)
	assert_eq(sev["employed_promoted"], 0)
	assert_true(sev["buildings"] is Array)


func test_demotion_diagnostics_adds_seconds_left_and_reuses_missing_goods() -> void:
	_live(20, 5)
	_city(1.0, 0.0, 100.0)
	_ticks(30)
	var diag: Dictionary = MobilitySystem.diagnostics(_state, _params, _context, _artisans())
	var dem: Dictionary = diag["demotion"]
	assert_eq(dem["seconds_below"], 30)
	assert_eq(dem.get("seconds_left", -1), 30)
	assert_true(dem.has("missing_goods"))
	assert_eq(dem["missing_goods"], [&"beer"] as Array[StringName])
	# active clock inferable from seconds_below >0 and pop >0
	assert_true(dem["seconds_below"] > 0)
	assert_gt(_artisan_state().population, 0)


func test_demotion_clock_at_59_no_active_no_loss_and_resets() -> void:
	_live(20, 5)
	_city(1.0, 0.0, 100.0)
	_ticks(59)
	assert_eq(_artisan_state().population, 5)
	assert_eq(_artisan_state().demotion_seconds_below, 59)
	var diag: Dictionary = MobilitySystem.diagnostics(_state, _params, _context, _artisans())
	assert_eq(diag["demotion"].get("seconds_left", -1), 1)
	# exactly at 60 (use high rate fixture for demo so 1 tick after threshold demotes)
	var p_high_demo: Params = _params_with({&"class.artisan.mobility.demotion.per_minute": 60.0})
	_state.reset_flows()
	var ev_demo := {"tick": 0, "employed_promoted": 0, "buildings": []}
	_mobility.tick(_state, p_high_demo, _context, ev_demo)
	assert_eq(_artisan_state().population, 4)
	assert_eq(_artisan_state().demotion_seconds_below, 60)
	# recovery exactly after, resets without further descent, seconds_left falls 1 per tick while low
	_city(1.0, 1.0, 100.0)
	_ticks(1)
	assert_eq(_artisan_state().demotion_seconds_below, 0)
	# check decreases 1 per tick (while low)
	_city(1.0, 0.0, 100.0)
	_ticks(5)
	diag = MobilitySystem.diagnostics(_state, _params, _context, _artisans())
	assert_eq(diag["demotion"].get("seconds_left", -1), 55)  # example after some
	_ticks(1)
	diag = MobilitySystem.diagnostics(_state, _params, _context, _artisans())
	assert_eq(diag["demotion"].get("seconds_left", -1), 54)
	# recovery resets clock
	_city(1.0, 1.0, 100.0)
	_ticks(1)
	assert_eq(_artisan_state().demotion_seconds_below, 0)


func test_no_artisans_no_demotion_clock_runs_and_snapshot_compatible() -> void:
	_live(20, 0)
	_city(1.0, 0.0, 100.0)
	_ticks(100)
	assert_eq(_artisan_state().demotion_seconds_below, 0)
	# roundtrip save compat for transients
	_artisan_state().demotion_seconds_below = 42
	var copy: EconomyState = EconomyState.from_dict(_state.to_dict())
	assert_eq(copy.class_states[&"artisan"].demotion_seconds_below, 42)
	# mobility_events not in save
	assert_false(_state.to_dict().has("mobility_events"))


func test_mobility_events_tick1_event_tick2_zero_and_mutation_safe() -> void:
	_state.buildings.append({"definition_id": &"bakery", "cell": [0, 0], "workers": 1})
	_live(2, 0)
	WorkersSystem.refresh_counts(_state)
	_city(1.0, 1.0, 100.0)
	var params_high: Params = _params_with({&"class.artisan.mobility.promotion.per_minute": 180.0})
	_state.reset_flows()
	var ev := {"tick": 0, "employed_promoted": 0, "buildings": []}
	_mobility.tick(_state, params_high, _context, ev)
	var sim: Simulation = Simulation.new(_params, _state, 123, _context)
	sim.tick()
	var e1: Dictionary = _reported_mobility_events(sim)
	assert_eq(e1.get("tick", -1), 1)
	assert_gt(e1.get("employed_promoted", -1), -1)
	# mutation of mobility_events copy does not affect internal
	e1["tick"] = 999
	e1["employed_promoted"] = 99
	var e1b: Dictionary = _reported_mobility_events(sim)
	assert_ne(e1b.get("tick", -1), 999)
	assert_ne(e1b.get("employed_promoted", -1), 99)
	# next tick zero event
	sim.tick()
	var e2: Dictionary = _reported_mobility_events(sim)
	assert_eq(e2.get("tick", -1), 2)
	assert_eq(e2.get("employed_promoted", -1), 0)
	assert_eq(e2.get("buildings", []).size(), 0)


func test_demotion_seconds_left_decreases_and_exact_recovery_at_60() -> void:
	_live(20, 5)
	_city(1.0, 0.0, 100.0)
	_ticks(55)
	var diag: Dictionary = MobilitySystem.diagnostics(_state, _params, _context, _artisans())["demotion"]
	assert_eq(diag.get("seconds_left", -1), 5)
	_ticks(4)
	diag = MobilitySystem.diagnostics(_state, _params, _context, _artisans())["demotion"]
	assert_eq(diag.get("seconds_left", -1), 1)
	_ticks(30)
	assert_eq(_artisan_state().population, 4)
	_city(1.0, 1.0, 100.0)
	_ticks(1)
	assert_eq(_artisan_state().demotion_seconds_below, 0)
	# no further descent
	_ticks(1)
	assert_eq(_artisan_state().demotion_seconds_below, 0)


func test_recovery_after_59_seconds_resets_countdown_without_demotion() -> void:
	_live(20, 5)
	_city(1.0, 0.0, 100.0)
	_ticks(58)
	var before: Dictionary = MobilitySystem.diagnostics(_state, _params, _context, _artisans())["demotion"]
	assert_eq(before.get("seconds_left", -1), 2)
	_ticks(1)
	var after: Dictionary = MobilitySystem.diagnostics(_state, _params, _context, _artisans())["demotion"]
	assert_eq(after.get("seconds_left", -1), 1)
	_city(1.0, 1.0, 100.0)
	_ticks(1)
	var recovered: Dictionary = MobilitySystem.diagnostics(_state, _params, _context, _artisans())["demotion"]
	assert_eq(recovered.get("seconds_left", -1), 60)
	assert_eq(recovered["seconds_below"], 0)
	assert_false(recovered["active"])
	assert_eq(_artisan_state().population, 5)
	assert_eq(_state.demotions_tick, 0)


func test_simulation_publishes_employed_promotion_and_clears_next_tick() -> void:
	var role: RoleDef = RoleDef.new()
	for key: StringName in [&"building.bakery.jobs", &"building.mill.jobs"]:
		role.modifiers.append(Modifier.new(key, &"set", 1))
	role.modifiers.append(Modifier.new(&"class.artisan.mobility.promotion.per_minute", &"set", 180))
	var params: Params = SimTestParams.isolated_params(_catalog, role)
	var initial: EconomyState = EconomyState.new()
	initial.population = 3
	initial.money = 1000000
	initial.satisfaction = 100.0
	initial.stocks[&"bread"] = 100000
	initial.stocks[&"beer"] = 1000
	for id: StringName in [&"housing", &"artisan_housing", &"bakery", &"mill"]:
		initial.buildings.append({"definition_id": id, "cell": [initial.buildings.size(), 0]})
	var sim: Simulation = Simulation.new(params, initial, 1, _context)
	sim.tick()
	var events: Dictionary = _reported_mobility_events(sim)
	assert_eq(events.get("tick", -1), 1)
	assert_eq(events.get("employed_promoted", -1), 2)
	assert_eq(events.get("buildings", []), [
		{"id": [2, 0], "definition_id": &"bakery", "workers_lost": 1},
		{"id": [3, 0], "definition_id": &"mill", "workers_lost": 1}
	])
	sim.tick()
	var next: Dictionary = _reported_mobility_events(sim)
	assert_eq(next.get("tick", -1), 2)
	assert_eq(next.get("employed_promoted", -1), 0)
	assert_eq(next.get("buildings", []), [])


# Added for #352: save/load using to_save/from_save at tick N>0 (reuses setup from test_simulation_publishes_employed_promotion_and_clears_next_tick).
# Snapshots before/after load must be equal (no mobility_events key). After load, mobility_events reports 0 data at the real tick.
func test_save_load_at_nonzero_tick_keeps_snapshot_equal_and_mobility_events_zeroed_at_realtick() -> void:
	# reuse fixture setup (not extracted to avoid touching the publishing test)
	var role: RoleDef = RoleDef.new()
	for key: StringName in [&"building.bakery.jobs", &"building.mill.jobs"]:
		role.modifiers.append(Modifier.new(key, &"set", 1))
	role.modifiers.append(Modifier.new(&"class.artisan.mobility.promotion.per_minute", &"set", 180))
	var params: Params = SimTestParams.isolated_params(_catalog, role)
	var initial: EconomyState = EconomyState.new()
	initial.population = 3
	initial.money = 1000000
	initial.satisfaction = 100.0
	initial.stocks[&"bread"] = 100000
	initial.stocks[&"beer"] = 1000
	for id: StringName in [&"housing", &"artisan_housing", &"bakery", &"mill"]:
		initial.buildings.append({"definition_id": id, "cell": [initial.buildings.size(), 0]})
	var sim: Simulation = Simulation.new(params, initial, 1, _context)
	sim.tick()
	# at tick N>0 with events
	var snap_before: Dictionary = sim.snapshot()
	var ev_before: Dictionary = _reported_mobility_events(sim)
	assert_eq(ev_before.get("tick", -1), 1)
	assert_eq(ev_before.get("employed_promoted", -1), 2)
	# save and load
	var saved: Dictionary = sim.to_save()
	var loaded: Simulation = Simulation.from_save(params, _context, [], saved)
	# snapshots IGUALES (after stripping other transients like production.input_starved which is never saved; mobility_events key absent)
	var snap_after: Dictionary = loaded.snapshot()
	var b: Dictionary = snap_before.duplicate(true)
	var a: Dictionary = snap_after.duplicate(true)
	b.erase("production")
	a.erase("production")
	assert_eq(b, a)
	assert_false(snap_after.has("mobility_events"))
	# eventos al cargar: 0 at realtick
	var ev_after: Dictionary = _reported_mobility_events(loaded)
	assert_eq(ev_after.get("tick", -1), 1)
	assert_eq(ev_after.get("employed_promoted", -1), 0)
	assert_eq(ev_after.get("buildings", []), [])
