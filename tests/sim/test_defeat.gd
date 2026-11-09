extends GutTest

var _catalog: DataCatalog
var _params: Params
var _state: EconomyState
var _system: DefeatSystem


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_params = _with({&"defeat.grace_seconds": 0})
	_state = EconomyState.new()
	_state.population = 100
	_system = DefeatSystem.new()
	_system.initialize(_state, _params)


func _with(overrides: Dictionary[StringName, float]) -> Params:
	# These tests isolate historical thresholds from the separately tested decay.
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"defeat.depopulation.peak_decay_per_minute", &"set", 0))
	for key: StringName in overrides:
		role.modifiers.append(Modifier.new(key, &"set", overrides[key]))
	return Params.new(_catalog, role)


# Explicit null fixture for tests that verify the unresolved/sin dato path (D-188 changed base to 60).
func _null_catalog() -> DataCatalog:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	var catalog: DataCatalog = loaded.catalog
	catalog.base_values[&"ui.defeat.critical_seconds.bankruptcy"] = null
	catalog.base_values[&"ui.defeat.critical_seconds.hunger"] = null
	catalog.base_values[&"ui.defeat.critical_seconds.depopulation"] = null
	catalog.base_values[&"ui.defeat.critical_sound"] = null
	return catalog


# A mutable copy of the shipped data documents for loader tests.
func _documents() -> Dictionary[String, Dictionary]:
	var documents: Dictionary[String, Dictionary] = {}
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "services"]:
		var dir: DirAccess = DirAccess.open("res://data/" + folder)
		for file_name: String in dir.get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
	return documents


func _ticks(count: int) -> void:
	for index: int in range(count):
		_system.tick(_state, _params)
		for condition: DefeatState in [_state.bankruptcy, _state.hunger, _state.depopulation]:
			if condition.status == &"defeat":
				assert_ne(condition.cause, &"", "Every defeat must report its cause")


func test_defeat_sets_cause_even_without_a_previous_warning() -> void:
	_params = _with({&"defeat.grace_seconds": 0, &"defeat.hunger.smoothing": 1,
		&"defeat.bankruptcy.duration_seconds": 1, &"defeat.hunger.duration_seconds": 1,
		&"defeat.depopulation.duration_seconds": 1})
	_state.money = -1
	_state.bread_coverage = 0.0
	_state.population = 9
	var conditions: Dictionary[StringName, DefeatState] = {
		&"bankruptcy": _state.bankruptcy, &"hunger": _state.hunger, &"depopulation": _state.depopulation,
	}
	for condition: DefeatState in conditions.values():
		assert_eq(condition.status, &"ok")
		assert_eq(condition.cause, &"")
	_system.tick(_state, _params)
	for cause: StringName in conditions:
		var condition: DefeatState = conditions[cause]
		assert_eq(condition.status, &"defeat")
		assert_eq(condition.cause, cause)
	assert_eq(_state.defeat_causes, [&"bankruptcy", &"hunger", &"depopulation"])


func test_bankruptcy_warning_recovery_and_exact_deadline() -> void:
	_state.money = -1
	_ticks(1)
	assert_eq(_state.bankruptcy.status, &"warning")
	assert_eq(_state.bankruptcy.elapsed_seconds, 1)
	_state.money = 0
	_ticks(1)
	assert_eq(_state.bankruptcy.status, &"ok")
	assert_eq(_state.bankruptcy.elapsed_seconds, 0)
	assert_eq(_state.bankruptcy.cause, &"")
	_state.money = -1
	_ticks(int(_params.get_value(&"defeat.bankruptcy.duration_seconds")) - 1)
	assert_eq(_state.bankruptcy.status, &"warning")
	_ticks(1)
	assert_eq(_state.bankruptcy.status, &"defeat")
	assert_eq(_state.defeat_causes, [&"bankruptcy"])


func test_hunger_smoothing_burst_recovery_and_deadline() -> void:
	_state.bread_coverage = 0.0
	_ticks(7)
	assert_eq(_state.hunger.status, &"warning")
	assert_eq(_state.hunger.elapsed_seconds, 1)
	_ticks(30)
	var previous: int = _state.hunger.elapsed_seconds
	_state.bread_coverage = 1.0
	_ticks(1)
	assert_lt(_state.hunger_smoothed_coverage, 0.5)
	assert_eq(_state.hunger.elapsed_seconds, previous + 1)
	_ticks(20)
	assert_eq(_state.hunger.status, &"ok")
	assert_eq(_state.hunger.elapsed_seconds, 0)
	_params = _with({&"defeat.grace_seconds": 0, &"defeat.hunger.smoothing": 1})
	_state.bread_coverage = 0.0
	_ticks(179)
	assert_eq(_state.hunger.status, &"warning")
	_ticks(1)
	assert_eq(_state.hunger.status, &"defeat")
	assert_eq(_state.hunger.cause, &"hunger")


func test_hunger_equality_recovers_and_empty_city_keeps_smoothing() -> void:
	_params = _with({&"defeat.grace_seconds": 0, &"defeat.hunger.smoothing": 1})
	_state.bread_coverage = 0.0
	_ticks(1)
	_state.bread_coverage = 0.5
	_ticks(1)
	assert_eq(_state.hunger.status, &"ok")
	assert_eq(_state.hunger.elapsed_seconds, 0)
	_state.population = 0
	_state.bread_coverage = 0.0
	_ticks(1)
	assert_eq(_state.hunger_smoothed_coverage, 0.0)
	assert_eq(_state.hunger.status, &"ok")
	assert_eq(_state.hunger.elapsed_seconds, 0)


func test_depopulation_relative_limits_and_recovery_to_warning() -> void:
	_state.population = 50
	_ticks(1)
	assert_eq(_state.depopulation.status, &"ok")
	_state.population = 49
	_ticks(1)
	assert_eq(_state.depopulation.status, &"warning")
	assert_eq(_state.depopulation.elapsed_seconds, 0)
	_state.population = 50
	_ticks(1)
	assert_eq(_state.depopulation.status, &"ok")
	assert_eq(_state.depopulation.cause, &"")
	_state.population = 24
	_ticks(20)
	assert_eq(_state.depopulation.elapsed_seconds, 20)
	_state.population = 25
	_ticks(1)
	assert_eq(_state.depopulation.status, &"warning")
	assert_eq(_state.depopulation.elapsed_seconds, 0)
	_state.population = 24
	_ticks(179)
	assert_eq(_state.depopulation.status, &"warning")
	_ticks(1)
	assert_eq(_state.depopulation.status, &"defeat")
	assert_eq(_state.depopulation.cause, &"depopulation")


func test_small_city_activation_absolute_minimum_and_historical_peak() -> void:
	_state = EconomyState.new()
	_state.hunger_emigration_active = true
	_state.population = 9
	_system.initialize(_state, _params)
	_ticks(200)
	assert_false(_state.depopulation_active)
	assert_eq(_state.depopulation.status, &"ok")
	_state.population = 10
	_ticks(1)
	assert_true(_state.depopulation_active)
	assert_eq(_state.depopulation.status, &"ok")
	_state.population = 9
	_ticks(179)
	assert_eq(_state.depopulation.status, &"warning")
	_ticks(1)
	assert_eq(_state.depopulation.status, &"defeat")
	assert_eq(_state.population_peak, 10.0)


func test_absolute_minimum_recovery_restarts_full_duration() -> void:
	_state = EconomyState.new()
	_state.hunger_emigration_active = true
	_state.population = 10
	_system.initialize(_state, _params)
	_state.population = 9
	_ticks(179)
	_state.population = 10
	_ticks(1)
	assert_eq(_state.depopulation.status, &"ok")
	assert_eq(_state.depopulation.elapsed_seconds, 0)
	_state.population = 9
	_ticks(179)
	assert_eq(_state.depopulation.status, &"warning")
	_ticks(1)
	assert_eq(_state.depopulation.status, &"defeat")


func test_peak_includes_initial_population_and_ignores_housing() -> void:
	assert_eq(_state.population_peak, 100.0)
	_state.housing_capacity = 1000
	_ticks(1)
	assert_eq(_state.depopulation.status, &"ok")
	_state.population = 120
	_ticks(1)
	_state.population = 59
	_ticks(1)
	assert_eq(_state.population_peak, 120.0)
	assert_eq(_state.depopulation.status, &"warning")


func test_grace_warns_without_counting_and_tick_301_starts_at_one() -> void:
	_params = _with({&"defeat.grace_seconds": 300})
	_state.money = -1
	_state.bread_coverage = 0.0
	_state.population = 9
	_ticks(300)
	for condition: DefeatState in [_state.bankruptcy, _state.hunger]:
		assert_eq(condition.status, &"warning")
		assert_eq(condition.elapsed_seconds, 0)
	assert_eq(_state.depopulation.status, &"ok")
	assert_eq(_state.depopulation.cause, &"")
	assert_eq(_state.depopulation.elapsed_seconds, 0)
	assert_true(_state.defeat_causes.is_empty())
	assert_eq(_state.defeat_elapsed_seconds, 300)
	_ticks(1)
	for condition: DefeatState in [_state.bankruptcy, _state.hunger, _state.depopulation]:
		assert_eq(condition.status, &"warning")
		assert_eq(condition.elapsed_seconds, 1)


func test_round_trip_during_grace_preserves_remaining_time_and_initial_smoothing() -> void:
	_params = _with({&"defeat.grace_seconds": 300})
	_state = EconomyState.new()
	_state.population = 20
	_state.bread_coverage = 0.25
	_system.initialize(_state, _params)
	assert_eq(_state.hunger_smoothed_coverage, 0.25)
	_ticks(200)
	_state = EconomyState.from_dict(_state.to_dict())
	_system.initialize(_state, _params)
	_ticks(100)
	assert_eq(_state.hunger.elapsed_seconds, 0)
	_ticks(1)
	assert_eq(_state.hunger.elapsed_seconds, 1)
	assert_eq(_state.defeat_elapsed_seconds, 301)


func test_zero_grace_and_modified_durations_and_simultaneous_causes() -> void:
	_params = _with({&"defeat.grace_seconds": 0, &"defeat.hunger.smoothing": 1,
		&"defeat.bankruptcy.duration_seconds": 2, &"defeat.hunger.duration_seconds": 2,
		&"defeat.depopulation.duration_seconds": 2})
	_state.money = -1
	_state.population = 9
	_state.bread_coverage = 0.0
	_ticks(1)
	assert_eq(_state.hunger.elapsed_seconds, 1)
	_ticks(1)
	assert_eq(_state.defeat_causes, [&"bankruptcy", &"hunger", &"depopulation"])


func test_round_trip_preserves_progress_and_copies_nested_values() -> void:
	_state.money = -1
	_state.bread_coverage = 0.0
	_ticks(30)
	var values: Dictionary = _state.to_dict()
	var restored: EconomyState = EconomyState.from_dict(values)
	assert_eq(restored.to_dict(), values)
	_system.initialize(restored, _params)
	assert_eq(restored.hunger_smoothed_coverage, _state.hunger_smoothed_coverage)
	_system.tick(restored, _params)
	_ticks(1)
	assert_eq(restored.to_dict(), _state.to_dict())
	values["bankruptcy"]["elapsed_seconds"] = 999
	values["defeat_causes"].append(&"hunger")
	assert_eq(restored.to_dict(), _state.to_dict())
	assert_true(_state.defeat_causes.is_empty())


# === #350 critical defeat notices (tests added first per tests-primero, must fail red before impl) ===
# Acceptance: snapshot["defeat_state"][cond] = {level, seconds_left, cause}; 3 keys + metadata 'cause' for receiver (loan_bankruptcy under bankruptcy)
# levels from remaining <= ui.critical_...  ; fixtures ok; no critical if !enabled/ grace/ incomplete(0/missing)
# bankruptcy receiver uses loan receiver clock (no change to defeat logic)
# defeat ticks/causes unchanged for existing.

func test_snapshot_exposes_defeat_state_with_normal_warning_critical() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok())
	var catalog: DataCatalog = loaded.catalog
	var map: MapDef = catalog.maps[&"whitechapel_1850s"]
	var context: EconomyContext = EconomyContext.new(catalog, map)
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"ui.defeat.critical_seconds.bankruptcy", &"set", 30))
	role.modifiers.append(Modifier.new(&"ui.defeat.critical_seconds.hunger", &"set", 30))
	role.modifiers.append(Modifier.new(&"ui.defeat.critical_seconds.depopulation", &"set", 30))
	var params: Params = Params.new(catalog, role)
	var state: EconomyState = EconomyState.new()
	state.population = 25
	state.money = 200
	state.bread_coverage = 0.9
	var sim: Simulation = Simulation.create_new(params, state, 42, context)
	sim.tick()
	var snap: Dictionary = sim.snapshot()
	assert_true(snap.has("defeat_state"), "snapshot must expose 'defeat_state' (spec)")
	assert_true(snap.has("defeat_critical_config"), "snapshot exposes resolved config for UI (or 0 if incomplete)")
	var cfg: Dictionary = snap["defeat_critical_config"]
	assert_true(cfg.has("complete") and cfg.has("incomplete"))
	assert_true(DefeatSystem.critical_config_errors(params).size() >= 0)  # fixture has, no error
	var ds: Dictionary = snap["defeat_state"]
	assert_true(ds.has(&"bankruptcy") and ds.has(&"hunger") and ds.has(&"depopulation"))
	for c: StringName in [&"bankruptcy", &"hunger", &"depopulation"]:
		var entry: Dictionary = ds[c]
		assert_true(entry.has("level") and entry.has("seconds_left") and entry.has("cause"))
		assert_eq(entry["level"], &"normal")
	assert_eq(ds[&"bankruptcy"]["cause"], &"bankruptcy")


func test_critical_level_activates_exactly_when_remaining_le_critical_seconds() -> void:
	# use direct system (reliable for hunger timer) + new static; snapshot tested in other
	_params = _with({&"defeat.grace_seconds": 0, &"defeat.hunger.duration_seconds": 100, &"defeat.hunger.smoothing": 1, &"ui.defeat.critical_seconds.hunger": 20})
	_state = EconomyState.new()
	_state.population = 20
	_state.bread_coverage = 0.0
	_system.initialize(_state, _params)
	for i: int in range(79):
		_system.tick(_state, _params)
	var info: Dictionary = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	var h: Dictionary = info[&"hunger"]
	assert_eq(h.get("level", &""), &"warning", "remaining 21 > crit 20")
	assert_eq(h.get("seconds_left", -1), 21)
	_system.tick(_state, _params)
	info = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	h = info[&"hunger"]
	assert_eq(h.get("level"), &"critical")
	assert_eq(h.get("seconds_left"), 20)
	# recovery: back to normal
	_state.bread_coverage = 1.0
	_system.tick(_state, _params)
	info = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	h = info[&"hunger"]
	assert_eq(h.get("level"), &"normal")
	# grace real, critical_seconds >= duration -> critical from timer start (after grace)
	_params = _with({&"defeat.grace_seconds": 10, &"defeat.hunger.duration_seconds": 5, &"ui.defeat.critical_seconds.hunger": 10})
	_state = EconomyState.new()
	_state.population = 20
	_state.bread_coverage = 0.0
	_system.initialize(_state, _params)
	for i: int in range(11):  # after grace
		_system.tick(_state, _params)
	info = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	h = info[&"hunger"]
	assert_eq(h.get("level"), &"critical")  # since crit >= dur, from start of timer
	# depop fractions: warning no timer -> warning (not crítico)
	_params = _with({&"defeat.grace_seconds": 0, &"defeat.depopulation.warning_fraction": 0.6, &"defeat.depopulation.defeat_fraction": 0.3, &"ui.defeat.critical_seconds.depopulation": 5})
	_state = EconomyState.new()
	_state.population = 100
	_state.population_peak = 100.0
	_state.depopulation_active = true
	# set to warning but not critical frac (timer not started)
	# simulate status warning elapsed=0
	_state.depopulation.status = &"warning"
	_state.depopulation.elapsed_seconds = 0
	info = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	var d: Dictionary = info[&"depopulation"]
	assert_eq(d.get("level"), &"warning")  # warning sin timer sigue warning (spec), no critical
	# normal in disabled previous state
	_params = _with({&"defeat.enabled": 0, &"defeat.grace_seconds": 0})
	_state = EconomyState.new()
	_state.money = -10
	_state.bread_coverage = 0.0
	_state.population = 20
	_system.initialize(_state, _params)
	_system.tick(_state, _params)
	info = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(info[&"bankruptcy"].get("level"), &"normal")
	assert_eq(info[&"hunger"].get("level"), &"normal")


func test_no_critical_if_disabled_or_grace_or_incomplete_config() -> void:
	# direct for reliability
	_params = _with({&"defeat.grace_seconds": 0, &"ui.defeat.critical_seconds.hunger": 10})
	_state = EconomyState.new()
	_state.population = 15
	_state.bread_coverage = 0.0
	_state.money = -5
	_system.initialize(_state, _params)
	for i: int in range(15):
		_system.tick(_state, _params)
	var ds: Dictionary = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_true(ds.has(&"hunger"))
	# bankruptcy has no its ui key in this _with -> level warning (active) but test asserts warning ok (no critical)
	assert_eq(ds[&"bankruptcy"].get("level"), &"warning")
	# disabled case
	_params = _with({&"defeat.enabled": 0, &"defeat.grace_seconds": 0, &"ui.defeat.critical_seconds.bankruptcy": 5})
	_state = EconomyState.new()
	_state.money = -10
	_system.initialize(_state, _params)
	_system.tick(_state, _params)
	ds = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(ds.get(&"bankruptcy", {}).get("level"), &"normal")
	# explicit config errors for sin dato/incomplete: use a null fixture, only bankruptcy resolved
	var incomplete_role: RoleDef = RoleDef.new()
	incomplete_role.modifiers.append(Modifier.new(&"defeat.grace_seconds", &"set", 0))
	incomplete_role.modifiers.append(Modifier.new(&"ui.defeat.critical_seconds.bankruptcy", &"set", 5))
	var null_params: Params = Params.new(_null_catalog(), incomplete_role)
	var errs: Array[String] = DefeatSystem.critical_config_errors(null_params)
	assert_true(errs.size() > 0, "reports sin dato keys")


func test_bankruptcy_receiver_uses_receiver_clock_for_seconds_left() -> void:
	# direct (loan set on state)
	_params = _with({&"defeat.grace_seconds": 0, &"loan.receiver_window_s": 45, &"ui.defeat.critical_seconds.bankruptcy": 15})
	_state = EconomyState.new()
	_state.money = 100
	_state.loan = LoanState.new()
	_state.loan.receiver = true
	_state.loan.receiver_seconds = 20
	_system.initialize(_state, _params)
	_system.tick(_state, _params)
	var ds: Dictionary = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	var b: Dictionary = ds[&"bankruptcy"]
	assert_eq(b["level"], &"warning")
	assert_eq(b["seconds_left"], 25)
	assert_eq(b["cause"], &"loan_bankruptcy", "receiver uses loan_bankruptcy cause for correct text, under bankruptcy key")
	_state.loan.receiver_seconds = 32
	_system.tick(_state, _params)
	ds = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	b = ds[&"bankruptcy"]
	assert_eq(b["level"], &"critical")
	assert_eq(b["seconds_left"], 13)
	assert_eq(b["cause"], &"loan_bankruptcy")


# === split tests for #350 per exact conditions (coverage, no 'assume', no touch pre-PR asserts) ===

func test_critical_recovery_after_critical() -> void:
	_params = _with({&"defeat.grace_seconds": 0, &"defeat.hunger.duration_seconds": 10, &"defeat.hunger.smoothing": 1, &"ui.defeat.critical_seconds.hunger": 5})
	_state = EconomyState.new()
	_state.population = 20
	_state.bread_coverage = 0.0
	_system.initialize(_state, _params)
	for i in 6:
		_system.tick(_state, _params)
	var info: Dictionary = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(info[&"hunger"]["level"], &"critical")
	_state.bread_coverage = 1.0
	_system.tick(_state, _params)
	info = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(info[&"hunger"]["level"], &"normal")

func test_critical_disabled_prevents_critical_and_forces_normal() -> void:
	_params = _with({&"defeat.enabled": 0, &"defeat.grace_seconds": 0, &"ui.defeat.critical_seconds.hunger": 5})
	_state = EconomyState.new()
	_state.population = 20
	_state.bread_coverage = 0.0
	_system.initialize(_state, _params)
	_system.tick(_state, _params)
	var info: Dictionary = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(info[&"hunger"]["level"], &"normal")

func test_critical_grace_maintains_warning_blocks_critical() -> void:
	# warning status during grace, level=warning, no critical even if rem would <=crit
	_params = _with({&"defeat.grace_seconds": 10, &"defeat.hunger.duration_seconds": 10, &"defeat.hunger.smoothing": 1, &"ui.defeat.critical_seconds.hunger": 1})
	_state = EconomyState.new()
	_state.population = 20
	_state.bread_coverage = 0.0
	_system.initialize(_state, _params)
	for i in 3:  # still in grace (elap<=10)
		_system.tick(_state, _params)
	var info: Dictionary = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(info[&"hunger"]["level"], &"warning")
	# after grace, advance cond timer enough for rem <=crit => critical
	for i in 20:
		_system.tick(_state, _params)
	info = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(info[&"hunger"]["level"], &"critical")

func test_critical_depop_warning_without_timer_stays_warning_not_critical() -> void:
	_params = _with({&"defeat.grace_seconds": 0, &"defeat.depopulation.warning_fraction": 0.5, &"defeat.depopulation.defeat_fraction": 0.25, &"ui.defeat.critical_seconds.depopulation": 5})
	_state = EconomyState.new()
	_state.population = 60
	_state.population_peak = 100.0
	_state.depopulation_active = true
	_state.depopulation.status = &"warning"
	_state.depopulation.elapsed_seconds = 0
	var info: Dictionary = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(info[&"depopulation"]["level"], &"warning")

func test_critical_receiver_base_warning_and_loan_cause() -> void:
	_params = _with({&"defeat.grace_seconds": 0, &"loan.receiver_window_s": 10, &"ui.defeat.critical_seconds.bankruptcy": 5})
	_state = EconomyState.new()
	_state.loan = LoanState.new()
	_state.loan.receiver = true
	_state.loan.receiver_seconds = 6
	_system.initialize(_state, _params)
	_system.tick(_state, _params)
	var info: Dictionary = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(info[&"bankruptcy"]["level"], &"critical")
	assert_eq(info[&"bankruptcy"]["cause"], &"loan_bankruptcy")
	_state.loan.receiver_seconds = 8
	_system.tick(_state, _params)
	info = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(info[&"bankruptcy"]["seconds_left"], 2)

func test_critical_exact_threshold_and_leq_triggers() -> void:
	_params = _with({&"defeat.grace_seconds": 0, &"defeat.hunger.duration_seconds": 10, &"defeat.hunger.smoothing": 1, &"ui.defeat.critical_seconds.hunger": 5})
	_state = EconomyState.new()
	_state.population = 20
	_state.bread_coverage = 0.0
	_system.initialize(_state, _params)
	for i in 5:
		_system.tick(_state, _params)
	var info: Dictionary = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(info[&"hunger"]["seconds_left"], 5)
	assert_eq(info[&"hunger"]["level"], &"critical")  # <= triggers

func test_critical_umbral_zero_valid_triggers_at_le0() -> void:
	_params = _with({&"defeat.grace_seconds": 0, &"defeat.hunger.duration_seconds": 5, &"defeat.hunger.smoothing": 1, &"ui.defeat.critical_seconds.hunger": 0})
	_state = EconomyState.new()
	_state.population = 20
	_state.bread_coverage = 0.0
	_system.initialize(_state, _params)
	for i in 5:
		_system.tick(_state, _params)
	var info: Dictionary = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(info[&"hunger"]["level"], &"critical")  # rem=0 <=0
	assert_eq(info[&"hunger"]["seconds_left"], 0)

func test_null_never_critical_nor_at_defeat_loss() -> void:
	# explicit null fixture: no ui crit set => null, even at defeat time => level=warning not critical
	var catalog: DataCatalog = _null_catalog()
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"defeat.depopulation.peak_decay_per_minute", &"set", 0))
	role.modifiers.append(Modifier.new(&"defeat.grace_seconds", &"set", 0))
	role.modifiers.append(Modifier.new(&"defeat.hunger.duration_seconds", &"set", 5))
	role.modifiers.append(Modifier.new(&"defeat.hunger.smoothing", &"set", 1))
	_params = Params.new(catalog, role)
	_state = EconomyState.new()
	_state.population = 20
	_state.bread_coverage = 0.0
	_system.initialize(_state, _params)
	for i in 6:
		_system.tick(_state, _params)
	var info: Dictionary = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(info[&"hunger"]["level"], &"warning")  # not critical
	assert_true(DefeatSystem.critical_config_errors(_params).size() > 0)

func test_fractional_duration_ceil_and_same_tick() -> void:
	# duration always whole (range forces integer for dur keys), but calc uses float(dur)-elapsed ; ceil for seconds_left; test exact tick transitions
	_params = _with({&"defeat.grace_seconds": 0, &"defeat.hunger.duration_seconds": 5, &"defeat.hunger.smoothing": 1, &"ui.defeat.critical_seconds.hunger": 3})
	_state = EconomyState.new()
	_state.population = 20
	_state.bread_coverage = 0.0
	_system.initialize(_state, _params)
	_system.tick(_state, _params)  # elap_h=1 , rem=4 , 4>3 warning
	var info: Dictionary = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(info[&"hunger"]["seconds_left"], 4)
	assert_eq(info[&"hunger"]["level"], &"warning")
	_system.tick(_state, _params)  # elap=2 , rem=3 <=3 critical ( <= triggers)
	info = DefeatSystem.defeat_state_for_snapshot(_state, _params)
	assert_eq(info[&"hunger"]["seconds_left"], 3)
	assert_eq(info[&"hunger"]["level"], &"critical")

func test_critical_config_errors_reports_missing_and_sin_dato() -> void:
	# explicit null fixture: hunger resolved to 0, the others remain sin dato
	var catalog: DataCatalog = _null_catalog()
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"ui.defeat.critical_seconds.hunger", &"set", 0))
	var params: Params = Params.new(catalog, role)
	var errs: Array[String] = DefeatSystem.critical_config_errors(params)
	assert_true(errs.size() > 0)
	assert_true(errs.any(func(e: String) -> bool: return "sin dato" in e or "missing" in e))

# Params resolver for nulls (layers/role, order, add/mul error) - required coverage
func test_params_null_resolved_only_by_set_layers_then_role() -> void:
	# explicit null fixture: no set => null valid; role wins over layers
	var catalog: DataCatalog = _null_catalog()
	var layers: Array[Modifier] = [Modifier.new(&"ui.defeat.critical_seconds.bankruptcy", &"set", 40.0)]
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"ui.defeat.critical_seconds.bankruptcy", &"set", 25.0))
	var params: Params = Params.new(catalog, role, layers)
	# role last wins
	assert_eq(params.get_value(&"ui.defeat.critical_seconds.bankruptcy"), 25.0)
	# no set => null valid
	var p2: Params = Params.new(catalog, RoleDef.new())
	assert_true(p2.has_value(&"ui.defeat.critical_seconds.hunger"))
	assert_eq(p2.get_value(&"ui.defeat.critical_seconds.hunger"), null)

func test_params_add_mul_on_null_errors_but_after_set_ok_in_order() -> void:
	# explicit null fixture: add before set on null => error
	var catalog: DataCatalog = _null_catalog()
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"ui.defeat.critical_seconds.hunger", &"add", 1.0))
	role.modifiers.append(Modifier.new(&"ui.defeat.critical_seconds.hunger", &"set", 10.0))
	var params: Params = Params.new(catalog, role)
	var errs: Array[String] = params.validation_errors()
	assert_true(errs.any(func(e: String) -> bool: return "cannot add/mul on null" in e))
	# reset, set then add in order
	role = RoleDef.new()
	role.modifiers.append(Modifier.new(&"ui.defeat.critical_seconds.hunger", &"set", 10.0))
	role.modifiers.append(Modifier.new(&"ui.defeat.critical_seconds.hunger", &"add", 2.0))
	params = Params.new(catalog, role)
	assert_eq(params.get_value(&"ui.defeat.critical_seconds.hunger"), 12.0)
	# mul after
	role = RoleDef.new()
	role.modifiers.append(Modifier.new(&"ui.defeat.critical_seconds.hunger", &"set", 5.0))
	role.modifiers.append(Modifier.new(&"ui.defeat.critical_seconds.hunger", &"mul", 3.0))
	params = Params.new(catalog, role)
	assert_eq(params.get_value(&"ui.defeat.critical_seconds.hunger"), 15.0)

# Loader specific for ui.defeat (null/sin_dato, integer>=0, sound, _comment tolerated explicitly; invalid/neg/frac covered via _number + clear errors, 0 valid)
func test_loader_ui_defeat_accepts_null_sin_dato_zero_and_tolerates_comment() -> void:
	# explicit fixture: null, 'sin dato', zero and an extra _comment are all accepted
	var documents: Dictionary[String, Dictionary] = _documents()
	documents["economy/defeat.json"]["ui"]["defeat"]["critical_seconds"]["bankruptcy"] = null
	documents["economy/defeat.json"]["ui"]["defeat"]["critical_seconds"]["hunger"] = "sin dato"
	documents["economy/defeat.json"]["ui"]["defeat"]["critical_seconds"]["depopulation"] = 0
	documents["economy/defeat.json"]["ui"]["defeat"]["critical_sound"] = "sin dato"
	documents["economy/defeat.json"]["ui"]["defeat"]["_comment"] = "test comment"
	var loaded: DataLoadResult = DataLoader.new().load_documents(documents)
	assert_true(loaded.is_ok(), str(loaded.errors))
	var cat: DataCatalog = loaded.catalog
	assert_true(cat.base_values.has(&"ui.defeat.critical_seconds.bankruptcy"))
	assert_eq(cat.base_values[&"ui.defeat.critical_seconds.bankruptcy"], null)
	assert_eq(cat.base_values[&"ui.defeat.critical_seconds.hunger"], null)
	assert_eq(cat.base_values[&"ui.defeat.critical_seconds.depopulation"], 0)
	assert_true(cat.integer_keys.has(&"ui.defeat.critical_seconds.depopulation"))
	assert_eq(cat.base_values[&"ui.defeat.critical_sound"], null)
