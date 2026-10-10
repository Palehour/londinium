extends GutTest

var _clock: SimClock


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	var params: Params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
	_clock = SimClock.new()
	_clock.simulation = Simulation.new(params, EconomyState.new(), 123)


func after_each() -> void:
	_clock.free()


func test_speeds_produce_whole_game_seconds() -> void:
	for multiplier: int in [1, 2, 3]:
		_clock.speed = multiplier
		var before: int = _ticks()
		_clock.advance(1.0)
		assert_eq(_ticks() - before, multiplier)


func test_fractional_seconds_accumulate() -> void:
	_clock.advance(0.25)
	_clock.advance(0.25)
	_clock.advance(0.25)
	assert_eq(_ticks(), 0)
	_clock.advance(0.25)
	assert_eq(_ticks(), 1)


func test_tick_signal_follows_each_completed_tick_and_not_pause() -> void:
	watch_signals(_clock)
	_clock.speed = 3
	_clock.advance(1.0)
	assert_signal_emit_count(_clock, "tick_advanced", 3)
	assert_eq(_ticks(), 3)
	_clock.speed = 0
	_clock.advance(1.0)
	assert_signal_emit_count(_clock, "tick_advanced", 3)


func test_pause_preserves_fraction_and_ignores_elapsed_time() -> void:
	_clock.advance(0.75)
	_clock.speed = 0
	_clock.advance(100.0)
	assert_eq(_ticks(), 0)
	_clock.speed = 1
	_clock.advance(0.25)
	assert_eq(_ticks(), 1)


func test_cap_retains_backlog_even_across_pause() -> void:
	assert_eq(_clock.max_ticks_per_frame, 8)
	_clock.advance(20.5)
	assert_eq(_ticks(), 8)
	_clock.speed = 0
	_clock.advance(1.0)
	assert_eq(_ticks(), 8)
	_clock.speed = 1
	_clock.advance(0.0)
	assert_eq(_ticks(), 16)
	_clock.advance(0.0)
	assert_eq(_ticks(), 20)
	_clock.advance(0.5)
	assert_eq(_ticks(), 21)


func test_cap_is_configurable() -> void:
	_clock.max_ticks_per_frame = 2
	_clock.speed = 3
	_clock.advance(1.0)
	assert_eq(_ticks(), 2)
	_clock.advance(0.0)
	assert_eq(_ticks(), 3)


func test_speed_changes_preserve_game_time_fraction() -> void:
	_clock.advance(0.5)
	_clock.speed = 2
	_clock.advance(0.25)
	assert_eq(_ticks(), 1)


func test_no_simulation_does_not_accumulate_time() -> void:
	var sim: Simulation = _clock.simulation
	_clock.simulation = null
	_clock.advance(100.0)
	_clock.simulation = sim
	_clock.advance(0.0)
	assert_eq(_ticks(), 0)


func test_process_delegates_to_fixed_step_clock() -> void:
	_clock._process(1.0)
	assert_eq(_ticks(), 1)


func test_invalid_clock_settings_are_rejected() -> void:
	_clock.speed = 4
	assert_push_error("SimClock: speed must be 0, 1, 2 or 3")
	assert_eq(_clock.speed, 1)
	_clock.max_ticks_per_frame = 0
	assert_push_error("SimClock: max_ticks_per_frame must be positive")
	assert_eq(_clock.max_ticks_per_frame, 8)
	for delta: float in [-1.0, INF, NAN]:
		_clock.advance(delta)
		assert_push_error("SimClock: delta must be finite and nonnegative")
	assert_eq(_ticks(), 0)
	_clock.advance(1.0)
	assert_eq(_ticks(), 1)


func _ticks() -> int:
	return _clock.simulation.snapshot()["tick_count"]
