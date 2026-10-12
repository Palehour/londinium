extends GutTest


func _new_flow(enabled: bool = true) -> SplashFlow:
	return SplashFlow.new(enabled)


func test_starts_playing_when_enabled() -> void:
	assert_eq(_new_flow().phase, SplashFlow.Phase.PLAYING)


func test_video_finished_completes() -> void:
	var flow: SplashFlow = _new_flow()
	watch_signals(flow)
	flow.video_finished()
	assert_eq(flow.phase, SplashFlow.Phase.DONE)
	assert_signal_emit_count(flow, "completed", 1)


func test_skip_during_play_fades_then_completes() -> void:
	var flow: SplashFlow = _new_flow()
	watch_signals(flow)
	flow.skip_requested()
	assert_eq(flow.phase, SplashFlow.Phase.FADING)
	assert_signal_not_emitted(flow, "completed")
	flow.fade_finished()
	assert_eq(flow.phase, SplashFlow.Phase.DONE)
	assert_signal_emit_count(flow, "completed", 1)


func test_video_failed_shows_fallback_then_completes() -> void:
	var flow: SplashFlow = _new_flow()
	watch_signals(flow)
	flow.video_failed()
	assert_eq(flow.phase, SplashFlow.Phase.FALLBACK)
	assert_signal_not_emitted(flow, "completed")
	flow.fallback_elapsed()
	assert_eq(flow.phase, SplashFlow.Phase.DONE)
	assert_signal_emit_count(flow, "completed", 1)


func test_skip_during_fallback_fades_then_completes() -> void:
	var flow: SplashFlow = _new_flow()
	flow.video_failed()
	flow.skip_requested()
	assert_eq(flow.phase, SplashFlow.Phase.FADING)
	flow.fade_finished()
	assert_eq(flow.phase, SplashFlow.Phase.DONE)


func test_disabled_completes_immediately() -> void:
	var flow: SplashFlow = _new_flow(false)
	assert_true(flow.is_done())


func test_events_after_done_are_ignored() -> void:
	var flow: SplashFlow = _new_flow()
	watch_signals(flow)
	flow.video_finished()
	flow.skip_requested()
	flow.video_failed()
	flow.fallback_elapsed()
	flow.fade_finished()
	flow.video_finished()
	assert_eq(flow.phase, SplashFlow.Phase.DONE)
	assert_signal_emit_count(flow, "completed", 1)


func test_late_video_finished_during_fade_does_not_cut_the_fade() -> void:
	var flow: SplashFlow = _new_flow()
	flow.skip_requested()
	flow.video_finished()
	assert_eq(flow.phase, SplashFlow.Phase.FADING)


func test_repeated_skip_does_not_restart_the_fade() -> void:
	var flow: SplashFlow = _new_flow()
	watch_signals(flow)
	flow.skip_requested()
	flow.skip_requested()
	assert_signal_emit_count(flow, "phase_changed", 1)


func test_skip_events_are_keys_clicks_and_joypad_buttons() -> void:
	var key: InputEventKey = InputEventKey.new()
	key.pressed = true
	assert_true(SplashFlow.is_skip_event(key))
	key.echo = true
	assert_false(SplashFlow.is_skip_event(key), "Held keys do not repeat the skip")
	var key_up: InputEventKey = InputEventKey.new()
	key_up.pressed = false
	assert_false(SplashFlow.is_skip_event(key_up))
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.pressed = true
	assert_true(SplashFlow.is_skip_event(click))
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.pressed = true
	assert_true(SplashFlow.is_skip_event(pad))
	assert_false(SplashFlow.is_skip_event(InputEventMouseMotion.new()))


func test_settings_disabled_in_headless() -> void:
	assert_false(SplashSettings.is_enabled(PackedStringArray(), "headless"))


func test_settings_disabled_by_cli_flag() -> void:
	assert_false(SplashSettings.is_enabled(PackedStringArray(["--no-splash"]), "windows"))


func test_settings_enabled_by_default_with_a_display() -> void:
	assert_true(SplashSettings.is_enabled(PackedStringArray(), "windows"))


func test_splash_scene_instantiates_disabled_without_changing_scene() -> void:
	var splash: Splash = (load("res://src/ui/splash/splash.tscn") as PackedScene).instantiate() as Splash
	splash.auto_change_scene = false
	splash.enabled = false
	watch_signals(splash)
	add_child_autofree(splash)
	assert_signal_emit_count(splash, "finished", 1)


func test_main_scene_is_the_splash_and_it_leads_to_the_game() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://src/ui/splash/splash.tscn")
	assert_true(ResourceLoader.exists(Splash.MAIN_SCENE_PATH))
