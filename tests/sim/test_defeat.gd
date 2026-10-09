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
	var role: RoleDef = RoleDef.new()
	for key: StringName in overrides:
		role.modifiers.append(Modifier.new(key, &"set", overrides[key]))
	return Params.new(_catalog, role)


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
	_ticks(179)
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
	assert_eq(_state.population_peak, 10)


func test_absolute_minimum_recovery_restarts_full_duration() -> void:
	_state = EconomyState.new()
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
	assert_eq(_state.population_peak, 100)
	_state.housing_capacity = 1000
	_ticks(1)
	assert_eq(_state.depopulation.status, &"ok")
	_state.population = 120
	_ticks(1)
	_state.population = 59
	_ticks(1)
	assert_eq(_state.population_peak, 120)
	assert_eq(_state.depopulation.status, &"warning")


func test_grace_warns_without_counting_and_tick_301_starts_at_one() -> void:
	_params = _with({&"defeat.grace_seconds": 300})
	_state.money = -1
	_state.bread_coverage = 0.0
	_state.population = 9
	_ticks(300)
	for condition: DefeatState in [_state.bankruptcy, _state.hunger, _state.depopulation]:
		assert_eq(condition.status, &"warning")
		assert_eq(condition.elapsed_seconds, 0)
	assert_true(_state.defeat_causes.is_empty())
	assert_eq(_state.defeat_elapsed_seconds, 300)
	_ticks(1)
	for condition: DefeatState in [_state.bankruptcy, _state.hunger, _state.depopulation]:
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
