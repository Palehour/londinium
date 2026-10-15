extends GutTest

# Issue #82 (D-066): causes are logged as events only when they change, and the oldest ones go past the cap.

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
	history.record(state)
	history.record(state)
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
	history.record(state)
	history.record(state)
	state.hunger_emigration_active = false
	state.satisfaction = 10.0
	state.satisfaction_target = 10.0
	history.record(state)
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
	history.record(state)
	assert_eq(_causes(history, &"import", &"tea"), [&"tea_imports_disabled", &"no_wharf_for_imports"] as Array[StringName])
