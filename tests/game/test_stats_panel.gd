extends GutTest

var _catalog: DataCatalog
var _session: GameSession
var _clock: SimClock
var _panel: StatsPanel


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_session = _new_session([])
	_clock = SimClock.new()
	_clock.simulation = _session.simulation
	add_child_autofree(_clock)
	_clock.set_process(false)
	_panel = _new_panel(_session)


func _new_panel(session: GameSession) -> StatsPanel:
	var panel: StatsPanel = StatsPanel.new()
	panel.setup(session, _clock)
	add_child_autofree(panel)
	return panel


func _new_session(modifiers: Array[Modifier]) -> GameSession:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	return GameSession.new(_catalog, Params.new(_catalog, role))


func _tick() -> void:
	_session.simulation.tick()
	_panel.update_snapshot(_session.get_snapshot())


func _text(section: String) -> String:
	return (_panel.get(section) as Label).text


func test_panel_shows_economy_in_pounds_shillings_pence_without_sending_commands() -> void:
	_panel.update_snapshot(_session.get_snapshot())
	assert_true(_session.get("_pending").is_empty(), "binding a snapshot must not submit commands")
	assert_eq(Strings.money(10000), "£41 13s 4d")
	assert_eq(Strings.money(-25), "-£0 2s 1d")
	assert_string_contains(_text("_economy"), Strings.TREASURY % "£41 13s 4d")
	assert_string_contains(_text("_economy"), Strings.WINDOW_PARTIAL % [0, 60])
	assert_string_contains(_text("_bread"), Strings.STOCKS % [0, 0, 40])
	assert_string_contains(_text("_buildings"), Strings.NO_BUILDINGS)
	assert_string_contains(_text("_crises"), Strings.GRACE % 300)
	assert_false((_panel.get("_alert") as Label).visible)
	assert_false((_panel.get("_restart") as Button).visible)


func test_panel_explains_missing_bread_from_diagnostics() -> void:
	_session = _new_session([Modifier.new(&"population.initial_bread", &"set", 0)])
	_panel = _new_panel(_session)
	for id: StringName in [&"wharf", &"mill", &"bakery"]:
		var cell: Vector2i = Vector2i(0, 7) if id == &"wharf" else Vector2i(_session.get_snapshot()["economy"]["buildings"].size(), 1)
		_session.submit_command(BuildCommand.new(_session.context, id, cell))
		_session.simulation.tick()
	_session.submit_command(SetWheatPurchasesCommand.new(false))
	_tick()
	var bread: String = _text("_bread")
	assert_string_contains(bread, Strings.BREAD_SHORT)
	assert_string_contains(bread, Strings.BREAD_CAUSE % [Strings.building_label("wharf"), Strings.reason(&"wheat_purchases_disabled")])
	assert_string_contains(bread, Strings.BREAD_CAUSE % [Strings.building_label("mill"), Strings.reason(&"no_input")])
	assert_string_contains(_text("_buildings"), Strings.BUILDING_STATUS % [Strings.building_label("wharf"), 0, 7, 4, 4, Strings.reason(&"wheat_purchases_disabled")])


func test_panel_shows_chain_wide_capacity_cause_without_a_building_label() -> void:
	_panel.update_snapshot(_session.get_snapshot())
	var snapshot: Dictionary = _session.get_snapshot()
	snapshot["diagnostics"]["bread_short"] = true
	snapshot["diagnostics"]["bread_causes"] = [{"definition_id": &"", "reason": &"insufficient_capacity"}]
	_panel.update_snapshot(snapshot)
	assert_string_contains(_text("_bread"), Strings.BREAD_SHORT + "
" + Strings.BREAD_CHAIN_CAUSE % Strings.reason(&"insufficient_capacity"))


func test_money_formats_int64_extremes_without_overflow() -> void:
	var int64_min: int = -9223372036854775807 - 1
	assert_eq(Strings.money(int64_min), "-£38430716820228232 10s 8d")
	assert_eq(Strings.money(9223372036854775807), "£38430716820228232 10s 7d")
	assert_eq(Strings.money(0), "£0 0s 0d")
	assert_eq(Strings.money(-1), "-£0 0s 1d")


func test_hunger_causes_show_only_when_bread_is_short() -> void:
	var snapshot: Dictionary = _session.get_snapshot()
	snapshot["diagnostics"]["bread_short"] = false
	snapshot["diagnostics"]["bread_causes"] = [{"definition_id": &"wharf", "reason": &"wheat_purchases_disabled"}]
	_panel.update_snapshot(snapshot)
	var cause: String = Strings.BREAD_CAUSE % [Strings.building_label("wharf"), Strings.reason(&"wheat_purchases_disabled")]
	assert_string_contains(_text("_bread"), Strings.BREAD_OK)
	assert_false(_text("_bread").contains(Strings.BREAD_SHORT))
	assert_false(_text("_bread").contains(cause))
	snapshot["diagnostics"]["bread_short"] = true
	_panel.update_snapshot(snapshot)
	assert_string_contains(_text("_bread"), cause)
	assert_false(_text("_bread").contains(Strings.BREAD_OK))


func test_tax_box_sends_set_tax_command_and_resyncs_from_snapshot() -> void:
	_panel.update_snapshot(_session.get_snapshot())
	var tax: SpinBox = _panel.get("_tax") as SpinBox
	assert_eq(tax.value, 25.0)
	tax.value = 40.0
	assert_eq(_session.get("_pending").size(), 1)
	_tick()
	_session.publish_tick()
	assert_almost_eq(float(_session.get_snapshot()["economy"]["tax_rate"]), 0.4, 0.0001)
	assert_eq(tax.value, 40.0)
	assert_true(_session.get("_pending").is_empty(), "resyncing the box does not resend the command")


func test_wheat_toggle_sends_command_and_reflects_state() -> void:
	_panel.update_snapshot(_session.get_snapshot())
	var wheat: CheckButton = _panel.get("_wheat") as CheckButton
	assert_true(wheat.button_pressed)
	wheat.button_pressed = false
	_tick()
	assert_false(_session.get_snapshot()["economy"]["wheat_purchases_enabled"])
	assert_false(wheat.button_pressed)
	wheat.button_pressed = true
	_tick()
	assert_true(_session.get_snapshot()["economy"]["wheat_purchases_enabled"])


func test_pause_and_speeds_drive_the_clock_without_changing_tick_length() -> void:
	var speeds: Dictionary = _panel.get("_speed_buttons")
	var pause: Button = _panel.get("_pause") as Button
	(speeds[3] as Button).pressed.emit()
	assert_eq(_clock.speed, 3)
	_clock.advance(1.0)
	assert_eq(_session.simulation.snapshot()["tick_count"], 3, "3x runs three one-second ticks")
	pause.pressed.emit()
	assert_eq(_clock.speed, 0)
	assert_eq(pause.text, Strings.RESUME)
	_clock.advance(1.0)
	assert_eq(_session.simulation.snapshot()["tick_count"], 3)
	(speeds[2] as Button).pressed.emit()
	assert_eq(_clock.speed, 0, "choosing a speed while paused does not resume")
	assert_true((speeds[2] as Button).button_pressed)
	assert_false((speeds[3] as Button).button_pressed)
	pause.pressed.emit()
	assert_eq(_clock.speed, 2)
	assert_eq(SimClock.TICK_SECONDS, 1.0)


func test_defeat_shows_cause_blocks_controls_and_offers_restart() -> void:
	_session = _new_session([Modifier.new(&"defeat.grace_seconds", &"set", 0),
		Modifier.new(&"defeat.bankruptcy.duration_seconds", &"set", 2),
		Modifier.new(&"defeat.bankruptcy.threshold", &"set", 20000)])
	_panel = _new_panel(_session)
	_tick()
	var alert: Label = _panel.get("_alert") as Label
	assert_true(alert.visible)
	assert_string_contains(alert.text, Strings.CONDITION_LABELS[&"bankruptcy"])
	assert_string_contains(alert.text, Strings.TIMER % [1, 2, 1])
	_tick()
	assert_eq(alert.text, Strings.ALERT_DEFEAT % Strings.CONDITION_LABELS[&"bankruptcy"])
	assert_string_contains(_text("_crises"), Strings.STATUS_LABELS[&"defeat"])
	assert_false((_panel.get("_tax") as SpinBox).editable)
	assert_true((_panel.get("_wheat") as CheckButton).disabled)
	var restart: Button = _panel.get("_restart") as Button
	assert_true(restart.visible)
	watch_signals(_panel)
	restart.pressed.emit()
	assert_signal_emitted(_panel, "restart_requested")


func _scene(size: Vector2i) -> Array:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	add_child_autofree(viewport)
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	viewport.add_child(scene)
	var view: Node2D = scene.get_node("Map") as Node2D
	(view.get("clock") as SimClock).speed = 0
	return [viewport, view]


func test_panel_docks_right_and_map_keeps_the_rest_on_resize() -> void:
	var parts: Array = await _scene_ready(Vector2i(1152, 800))
	var viewport: SubViewport = parts[0]
	var view: Node2D = parts[1]
	var presentation: MapPresentation = view.get("presentation") as MapPresentation
	var width: float = presentation.layout["panel_width"]
	var panel: StatsPanel = view.get("_stats_panel") as StatsPanel
	var geometry: MapGeometry = view.get("geometry") as MapGeometry
	assert_eq(panel.get_global_rect(), Rect2(1152 - width, 0, width, 800))
	assert_eq(geometry.viewport_size, Vector2(1152 - width, 800 - presentation.layout["header_height"]))
	viewport.size = Vector2i(1400, 900)
	await get_tree().process_frame
	assert_eq(panel.get_global_rect(), Rect2(1400 - width, 0, width, 900))
	assert_eq(geometry.viewport_size, Vector2(1400 - width, 900 - presentation.layout["header_height"]))


func test_hud_input_never_reaches_the_map() -> void:
	var parts: Array = await _scene_ready(Vector2i(1152, 800))
	var viewport: SubViewport = parts[0]
	var view: Node2D = parts[1]
	var geometry: MapGeometry = view.get("geometry") as MapGeometry
	var over_panel: Vector2 = Vector2(1100, 600)
	var zoom: float = geometry.zoom
	for button: MouseButton in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_UP]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = button
		click.position = over_panel
		click.pressed = true
		viewport.push_input(click, true)
		click.pressed = false
		viewport.push_input(click, true)
	assert_eq(geometry.selected, Vector2i(-1, -1))
	assert_eq(geometry.zoom, zoom)
	var tax: SpinBox = (view.get("_stats_panel") as StatsPanel).get("_tax") as SpinBox
	tax.get_line_edit().grab_focus()
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_1
	key.unicode = "1".unicode_at(0)
	key.pressed = true
	viewport.push_input(key, true)
	assert_eq(view.get("_building_type"), &"", "typing a tax value must not pick a building")
	var map_click: InputEventMouseButton = InputEventMouseButton.new()
	map_click.button_index = MOUSE_BUTTON_LEFT
	map_click.position = Vector2(200, 400)
	map_click.pressed = true
	viewport.push_input(map_click, true)
	assert_false(tax.get_line_edit().has_focus(), "clicking the map returns keyboard focus to it")
	assert_ne(geometry.selected, Vector2i(-1, -1))


func test_map_restart_replaces_simulation_and_resets_clock() -> void:
	var parts: Array = await _scene_ready(Vector2i(1152, 800))
	var view: Node2D = parts[1]
	var session: GameSession = view.get("session") as GameSession
	var clock: SimClock = view.get("clock") as SimClock
	var old: Simulation = session.simulation
	old.tick()
	view.call("_unhandled_input", _key(KEY_1))
	(view.get("_stats_panel") as StatsPanel).restart_requested.emit()
	assert_ne(session.simulation, old)
	assert_eq(clock.simulation, session.simulation)
	assert_eq(clock.speed, 1)
	assert_eq(session.get_snapshot()["tick_count"], 0)
	assert_eq(view.get("_building_type"), &"")


func _key(code: Key) -> InputEventKey:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = code
	key.pressed = true
	return key


func _scene_ready(size: Vector2i) -> Array:
	var parts: Array = _scene(size)
	await get_tree().process_frame
	await get_tree().process_frame
	return parts
