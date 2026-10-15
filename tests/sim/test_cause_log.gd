extends GutTest

# Issue #82 (D-066): causes are logged as events only when they change, and the oldest ones go past the cap.
# Cristian on 2026-10-15 (Mason's proposal): a change is logged once it lasts stats.causes.min_duration_seconds;
# a subject that flips faster gets one "intermittent" event with a count until a cause holds.

var _catalog: DataCatalog


func before_all() -> void:
	_catalog = DataLoader.new().load_all().catalog


func _params() -> Params:
	return Params.new(_catalog, RoleDef.new())


func _context() -> EconomyContext:
	return EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])


func _history() -> StatsHistory:
	var params: Params = _params()
	var context: EconomyContext = _context()
	return StatsHistory.new(SeriesRegistry.build(params, context), params, context)


func _state() -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.money = 5000
	state.population = 10
	state.tax_rate = 0.25
	state.stocks[&"bread"] = 100
	state.bread_coverage = 1.0
	state.satisfaction = 80.0
	state.hunger_smoothed_coverage = 1.0
	return state


func _min_duration() -> int:
	return int(_params().get_value(&"stats.causes.min_duration_seconds"))


# Records the same state long enough for a change to pass the duration filter.
func _hold(history: StatsHistory, state: EconomyState) -> void:
	for second: int in _min_duration() + 1:
		history.record(state)


func _causes(history: StatsHistory, kind: StringName, subject: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	for event: Dictionary in history.events():
		if event["kind"] == kind and event["subject"] == subject:
			found.append(event["cause"])
	return found


func test_records_only_on_change() -> void:
	var log_: CauseLog = CauseLog.new(100)
	assert_true(log_.note(1, &"building", &"mill@1,1", &"no_workers"))
	assert_false(log_.note(2, &"building", &"mill@1,1", &"no_workers"), "the same cause is not logged again")
	assert_true(log_.note(3, &"building", &"mill@1,1", &"ok"))
	assert_true(log_.note(3, &"building", &"mill@2,2", &"ok"), "another subject has its own cause")
	assert_true(log_.note(4, &"building", &"mill@1,1", &"no_workers"), "a cause that comes back is a change")
	var events: Array[Dictionary] = log_.events()
	assert_eq(events.size(), 4)
	assert_eq(events[0], {"second": 1, "kind": &"building", "subject": &"mill@1,1", "cause": &"no_workers"})
	assert_eq(log_.events(3).size(), 3, "events from a second on")


func test_cap_drops_oldest() -> void:
	var log_: CauseLog = CauseLog.new(3)
	for second: int in range(1, 6):
		log_.note(second, &"policy", &"tax_rate", StringName(str(second)))
	var events: Array[Dictionary] = log_.events()
	assert_eq(events.size(), 3)
	assert_eq(events[0]["second"], 3)
	assert_false(log_.note(6, &"policy", &"tax_rate", &"5"), "the current cause survives the cap")
	var restored: CauseLog = CauseLog.new(2)
	assert_true(restored.restore(log_.to_dict()))
	assert_eq(restored.events().size(), 2, "a smaller cap keeps the newest")
	assert_eq(restored.events()[1]["second"], 5)
	assert_false(restored.restore({"seconds": PackedInt32Array([1])}))
	assert_eq(restored.events().size(), 0)


func test_rejected_command_and_policy_change() -> void:
	var state: EconomyState = _state()
	var sim: Simulation = Simulation.new(_params(), state, 3, _context())
	sim.tick()
	sim.apply_command(SetTaxCommand.new(0.4))
	sim.apply_command(BuildCommand.new(_context(), &"cathedral", Vector2i(1, 1)))
	for second: int in _min_duration() + 1:
		sim.tick()
	var tax: Array = sim.stats_events(2).filter(
		func(event: Dictionary) -> bool: return event["kind"] == &"policy" and event["subject"] == &"tax_rate")
	assert_eq(tax.size(), 1)
	assert_eq(tax[0]["cause"], &"0.4")
	var commands: Array = sim.stats_events(2).filter(
		func(event: Dictionary) -> bool: return event["kind"] == &"command")
	assert_eq(commands.size(), 2)
	assert_eq(commands[0], {"second": 2, "kind": &"command", "subject": &"SetTaxCommand", "cause": &"accepted"})
	assert_eq(commands[1], {"second": 2, "kind": &"command", "subject": &"BuildCommand", "cause": &"unknown_building"})


func test_building_stop_reason() -> void:
	var history: StatsHistory = _history()
	var state: EconomyState = _state()
	state.buildings.append({"definition_id": &"mill", "cell": [4, 2], "workers": 0})
	state.buildings.append({"definition_id": &"housing", "cell": [6, 6]})
	history.record(state)
	assert_eq(_causes(history, &"building", &"mill@4,2"), [&"no_workers"] as Array[StringName])
	assert_eq(_causes(history, &"building", &"housing@6,6"), [] as Array[StringName], "no jobs, nothing to stop")
	state.buildings[0]["workers"] = 3
	_hold(history, state)
	assert_eq(_causes(history, &"building", &"mill@4,2"), [&"no_workers", &"no_input"] as Array[StringName],
		"a staffed mill without wheat waits for input, logged once")
	state.buildings.remove_at(0)
	history.record(state)
	history.record(state)
	assert_eq(_causes(history, &"building", &"mill@4,2"),
		[&"no_workers", &"no_input", StatsHistory.GONE] as Array[StringName], "a demolished building is gone once")


func test_emigration_cause() -> void:
	var history: StatsHistory = _history()
	var state: EconomyState = _state()
	history.record(state)
	state.hunger_emigration_active = true
	_hold(history, state)
	state.hunger_emigration_active = false
	state.satisfaction = 10.0
	state.satisfaction_target = 10.0
	_hold(history, state)
	assert_eq(_causes(history, &"emigration", &"worker"),
		[StatsHistory.NO_EMIGRATION, GrowthSystem.REASON_HUNGRY, GrowthSystem.REASON_UNHAPPY] as Array[StringName])


func test_defeat_warning() -> void:
	var history: StatsHistory = _history()
	var state: EconomyState = _state()
	history.record(state)
	state.bankruptcy.status = &"warning"
	history.record(state)
	state.bankruptcy.status = &"defeat"
	history.record(state)
	assert_eq(_causes(history, &"defeat", &"bankruptcy"), [&"ok", &"warning", &"defeat"] as Array[StringName])
	assert_eq(_causes(history, &"defeat", &"hunger"), [&"ok"] as Array[StringName])


func test_import_reasons() -> void:
	var history: StatsHistory = _history()
	var state: EconomyState = _state()
	history.record(state)
	state.tea_imports_enabled = true
	_hold(history, state)
	assert_eq(_causes(history, &"import", &"tea"), [&"tea_imports_disabled", &"no_wharf_for_imports"] as Array[StringName])


func test_data_sets_the_filter_and_the_cap() -> void:
	assert_eq(_min_duration(), 5)
	assert_eq(int(_params().get_value(&"stats.causes.max_events")), 20000)


func test_a_change_is_logged_once_it_lasts_at_the_second_it_began() -> void:
	var log_: CauseLog = CauseLog.new(100, 5)
	assert_true(log_.note(1, &"building", &"mill@1,1", &"running"), "the first cause is the starting state")
	for second: int in range(2, 7):
		assert_false(log_.note(second, &"building", &"mill@1,1", &"no_input"), "second %d: not lasting yet" % second)
	assert_true(log_.note(7, &"building", &"mill@1,1", &"no_input"), "five seconds later it lasts")
	assert_false(log_.note(8, &"building", &"mill@1,1", &"no_input"))
	assert_eq(log_.events(), [{"second": 1, "kind": &"building", "subject": &"mill@1,1", "cause": &"running"},
		{"second": 2, "kind": &"building", "subject": &"mill@1,1", "cause": &"no_input"}] as Array[Dictionary])


func test_a_short_blip_back_to_the_logged_cause_is_intermittent() -> void:
	var log_: CauseLog = CauseLog.new(100, 5)
	log_.note(1, &"building", &"mill@1,1", &"running")
	for second: int in range(2, 5):
		log_.note(second, &"building", &"mill@1,1", &"no_workers")
	assert_true(log_.note(5, &"building", &"mill@1,1", &"running"), "three seconds did not last")
	for second: int in range(6, 11):
		log_.note(second, &"building", &"mill@1,1", &"running")
	assert_eq(_logged_causes(log_), [&"running", CauseLog.INTERMITTENT, &"running"] as Array[StringName],
		"the blip is one intermittent event, then the cause that held again")
	assert_eq(log_.events()[1]["count"], 1)
	assert_eq(log_.events()[1]["second"], 2, "it starts when the blip began")
	assert_eq(log_.events()[2]["second"], 5)


func test_fast_flips_make_one_intermittent_event_with_a_count() -> void:
	var log_: CauseLog = CauseLog.new(100, 5)
	log_.note(1, &"building", &"mill@1,1", &"running")
	for second: int in range(2, 42):
		log_.note(second, &"building", &"mill@1,1", &"no_input" if second % 2 == 0 else &"running")
	assert_eq(_logged_causes(log_), [&"running", CauseLog.INTERMITTENT] as Array[StringName],
		"forty flips do not fill the log")
	assert_eq(log_.events()[1]["count"], 39, "every change that did not last; the last one is still pending")
	for second: int in range(42, 48):
		log_.note(second, &"building", &"mill@1,1", &"no_input")
	assert_eq(_logged_causes(log_), [&"running", CauseLog.INTERMITTENT, &"no_input"] as Array[StringName],
		"it ends once a cause holds")
	assert_eq(log_.events()[1]["count"], 40)
	assert_eq(log_.events()[2]["second"], 42)
	log_.note(48, &"building", &"mill@1,1", &"running")
	log_.note(49, &"building", &"mill@1,1", &"no_input")
	assert_eq(_logged_causes(log_).count(CauseLog.INTERMITTENT), 2, "a new burst is a new intermittent event")
	assert_eq(log_.events()[3]["count"], 1)


func test_other_subjects_are_not_held_back() -> void:
	var log_: CauseLog = CauseLog.new(100, 5)
	log_.note(1, &"building", &"mill@1,1", &"running")
	log_.note(1, &"building", &"mill@2,2", &"running")
	for second: int in range(2, 8):
		log_.note(second, &"building", &"mill@1,1", &"no_input" if second % 2 == 0 else &"running")
		log_.note(second, &"building", &"mill@2,2", &"no_workers")
	var other: Array[Dictionary] = log_.events().filter(
		func(event: Dictionary) -> bool: return event["subject"] == &"mill@2,2")
	assert_eq(other.size(), 2)
	assert_eq(other[1]["cause"], &"no_workers")


func test_zero_duration_and_immediate_notes_skip_the_filter() -> void:
	var unfiltered: CauseLog = CauseLog.new(100, 0)
	unfiltered.note(1, &"policy", &"tax_rate", &"0.25")
	assert_true(unfiltered.note(2, &"policy", &"tax_rate", &"0.4"))
	var log_: CauseLog = CauseLog.new(100, 5)
	log_.note(1, &"defeat", &"hunger", &"ok", true)
	assert_true(log_.note(2, &"defeat", &"hunger", &"warning", true), "a defeat warning does not wait")
	assert_true(log_.note(3, &"defeat", &"hunger", &"defeat", true), "the defeat that ends the game is logged")
	assert_eq(_logged_causes(log_), [&"ok", &"warning", &"defeat"] as Array[StringName])


func test_a_flipping_subject_resumes_after_a_restore() -> void:
	var log_: CauseLog = CauseLog.new(100, 5)
	log_.note(1, &"import", &"tea", &"ok")
	for second: int in range(2, 10):
		log_.note(second, &"import", &"tea", &"no_money" if second % 2 == 0 else &"ok")
	var restored: CauseLog = CauseLog.new(100, 5)
	assert_true(restored.restore(log_.to_dict()))
	for second: int in range(10, 14):
		log_.note(second, &"import", &"tea", &"no_money" if second % 2 == 0 else &"ok")
		restored.note(second, &"import", &"tea", &"no_money" if second % 2 == 0 else &"ok")
	assert_eq(restored.events(), log_.events(), "the same intermittent event keeps counting")
	assert_eq(restored.events()[1]["count"], 11)
	var saved: Dictionary = log_.to_dict()
	saved.erase("pending_keys")
	assert_false(restored.restore(saved), "a log missing its pending changes is malformed")


func test_the_ring_keeps_the_newest_in_order() -> void:
	var log_: CauseLog = CauseLog.new(4)
	for second: int in range(1, 12):
		log_.note(second, &"policy", &"tax_rate", StringName(str(second)))
	var seconds: Array[int] = []
	for event: Dictionary in log_.events():
		seconds.append(int(event["second"]))
	assert_eq(seconds, [8, 9, 10, 11] as Array[int])
	var restored: CauseLog = CauseLog.new(4)
	restored.restore(log_.to_dict())
	log_.note(12, &"policy", &"tax_rate", &"12")
	restored.note(12, &"policy", &"tax_rate", &"12")
	assert_eq(restored.events(), log_.events())


func test_a_flipping_building_in_the_history_is_one_intermittent_event() -> void:
	var history: StatsHistory = _history()
	var state: EconomyState = _state()
	state.buildings.append({"definition_id": &"mill", "cell": [4, 2], "workers": 0})
	for second: int in 60:
		state.buildings[0]["workers"] = 3 if second % 2 == 1 else 0
		history.record(state)
	var mill: Array[Dictionary] = history.events().filter(
		func(event: Dictionary) -> bool: return event["subject"] == &"mill@4,2")
	assert_eq(mill.size(), 2, "a minute of flips: the starting cause and one intermittent event")
	assert_eq(mill[1]["cause"], CauseLog.INTERMITTENT)
	assert_eq(mill[1]["count"], 58)


func _logged_causes(log_: CauseLog) -> Array[StringName]:
	var found: Array[StringName] = []
	for event: Dictionary in log_.events():
		found.append(event["cause"])
	return found
