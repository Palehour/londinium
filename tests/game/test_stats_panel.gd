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
	assert_eq(Strings.money(1000), "£4 3s 4d")
	assert_eq(Strings.money(-25), "-£0 2s 1d")
	var treasury: int = _session.get_snapshot()["economy"]["money"]
	assert_string_contains(_text("_economy"), Strings.TREASURY % Strings.money(treasury))
	assert_string_contains(_text("_economy"), Strings.WINDOW_PARTIAL % [0, 60])
	assert_string_contains(_text("_bread"), Strings.STOCKS % [0, 0, 40])
	assert_string_contains(_text("_buildings"), Strings.NO_BUILDINGS)
	assert_string_contains(_text("_crises"), Strings.GRACE % 300)
	assert_false((_panel.get("_alert") as Label).visible)
	assert_false((_panel.get("_restart") as Button).visible)


func test_panel_shows_malt_and_beer_stock_with_their_caps() -> void:
	_panel.update_snapshot(_session.get_snapshot())
	var market: Dictionary = _session.get_snapshot()["market"]
	assert_eq(_text("_malt_beer_row"), Strings.MALT_BEER_ROW
		% [0, market["malt"]["capacity"], 0, market["beer"]["capacity"]])


# Issue #51 review: without this control the barley never reaches the malthouse in a normal game.
func test_the_unloading_slider_sends_the_split_and_follows_the_snapshot() -> void:
	_panel.update_snapshot(_session.get_snapshot())
	var slider: HSlider = _panel.get("_unloading") as HSlider
	assert_eq([slider.value, slider.max_value, slider.scrollable], [0.0, 100.0, false])
	assert_eq(_text("_unloading_label"), Strings.UNLOADING_LABEL % 0)
	slider.value = 30.0
	slider.drag_ended.emit(true)
	_tick()
	_session.publish_tick()
	assert_eq(_session.get_snapshot()["market"]["barley"]["barley_percent"], 30)
	assert_eq(slider.value, 30.0)
	assert_eq(_text("_unloading_label"), Strings.UNLOADING_LABEL % 30)
	assert_true(_session.get("_pending").is_empty(), "resyncing the slider does not resend the command")


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


func test_wheat_row_shows_stock_price_trend_and_minutes_of_mill() -> void:
	var snapshot: Dictionary = _session.get_snapshot()
	_panel.update_snapshot(snapshot)
	assert_eq(_text("_wheat_row"), Strings.WHEAT_ROW % [0, 100, Strings.money(2), Strings.TREND_FLAT, Strings.NO_MILL_COVERAGE])
	var market: Dictionary = snapshot["market"]["wheat"]
	market["stock"] = 60
	market["previous_price"] = 3
	market["minutes_covered"] = 6.0
	_panel.update_snapshot(snapshot)
	assert_eq(_text("_wheat_row"), Strings.WHEAT_ROW % [60, 100, Strings.money(2), Strings.TREND_DOWN, Strings.MINUTES_COVERED % 6.0])
	market["previous_price"] = 1
	market["blocked_by_price"] = true
	_panel.update_snapshot(snapshot)
	assert_string_contains(_text("_wheat_row"), Strings.TREND_UP)
	assert_string_contains(_text("_wheat_row"), Strings.WHEAT_BLOCKED_NOTE)


func _price_controls() -> Dictionary:
	return {"accumulate_on": _panel.get("_accumulate_on") as CheckBox, "accumulate": _panel.get("_accumulate_price") as SpinBox,
		"limit_on": _panel.get("_limit_on") as CheckBox, "limit": _panel.get("_limit_price") as SpinBox}


func test_policy_controls_send_the_whole_policy_and_resync_from_the_snapshot() -> void:
	_panel.update_snapshot(_session.get_snapshot())
	var controls: Dictionary = _price_controls()
	var accumulate_on: CheckBox = controls["accumulate_on"]
	var accumulate: SpinBox = controls["accumulate"]
	var limit_on: CheckBox = controls["limit_on"]
	var limit: SpinBox = controls["limit"]
	var target: HSlider = _panel.get("_target") as HSlider
	assert_false(accumulate_on.button_pressed, "the default policy does not stockpile")
	assert_false(limit_on.button_pressed, "and has no limit")
	assert_false(accumulate.editable, "a switched-off price cannot be edited")
	assert_eq([accumulate.min_value, accumulate.max_value], [1.0, 3.0], "the market's own prices")
	assert_eq(target.max_value, 100.0)
	assert_false(target.scrollable or (_panel.get("_reserve") as HSlider).scrollable, "the wheel would not send the command")
	accumulate_on.button_pressed = true
	assert_true(accumulate.editable, "editable at once: a paused game sends no snapshot to enable it")
	limit_on.button_pressed = true
	assert_true(limit.editable)
	limit.value = 2.0
	target.value = 60.0
	target.drag_ended.emit(true)
	var reserve: HSlider = _panel.get("_reserve") as HSlider
	assert_eq([reserve.value, reserve.max_value], [2.0, 10.0], "the default reserve, up to the ten minutes the rules allow")
	assert_string_contains(_text("_reserve_label"), Strings.RESERVE_LABEL % 2)
	reserve.value = 4.0
	reserve.drag_ended.emit(true)
	_tick()
	_session.publish_tick()
	var economy: Dictionary = _session.get_snapshot()["economy"]
	assert_eq([economy["wheat_accumulate_price"], economy["wheat_max_price"], economy["wheat_target_stock"],
		economy["wheat_reserve_minutes"]], [1, 2, 60, 4])
	assert_eq([accumulate_on.button_pressed, accumulate.value, limit_on.button_pressed, limit.value, target.value],
		[true, 1.0, true, 2.0, 60.0])
	assert_string_contains(_text("_target_label"), "60")
	assert_eq(_text("_reserve_label"), Strings.RESERVE_LABEL % 4)
	assert_true(_session.get("_pending").is_empty(), "resyncing the controls does not resend the command")
	limit_on.button_pressed = false
	_tick()
	assert_eq(_session.get_snapshot()["economy"]["wheat_max_price"], WheatPolicy.NO_LIMIT, "the switch turns the limit off")


func test_a_policy_that_accumulates_at_the_top_price_is_shown_and_kept() -> void:
	_panel.update_snapshot(_session.get_snapshot())
	_session.submit_command(SetWheatPolicyCommand.new(3, WheatPolicy.NO_LIMIT, 60, 2))
	_tick()
	_session.publish_tick()
	var controls: Dictionary = _price_controls()
	assert_true((controls["accumulate_on"] as CheckBox).button_pressed)
	assert_eq((controls["accumulate"] as SpinBox).value, 3.0, "the top price is shown as itself")
	var reserve: HSlider = _panel.get("_reserve") as HSlider
	reserve.value = 5.0
	reserve.drag_ended.emit(true)
	_tick()
	assert_eq(_session.get_snapshot()["economy"]["wheat_accumulate_price"], 3, "changing another control does not turn accumulating off")


func test_a_very_wide_market_keeps_its_whole_price_range_selectable() -> void:
	_session = _new_session([Modifier.new(&"market.wheat.max_price", &"set", 1000000)])
	_panel = _new_panel(_session)
	_panel.update_snapshot(_session.get_snapshot())
	var controls: Dictionary = _price_controls()
	var accumulate: SpinBox = controls["accumulate"]
	var limit: SpinBox = controls["limit"]
	assert_eq([accumulate.min_value, accumulate.max_value], [1.0, 1000000.0])
	_session.submit_command(SetWheatPolicyCommand.new(500, 700, 0, 2))
	_tick()
	_session.publish_tick()
	assert_eq([accumulate.value, limit.value], [500.0, 700.0], "an accepted policy is shown as it is")
	accumulate.value = 600.0
	_tick()
	assert_eq(_session.get_snapshot()["economy"]["wheat_accumulate_price"], 600, "any valid price can be chosen")
	assert_eq(_session.get_snapshot()["economy"]["wheat_max_price"], 700, "and the rest of the policy is kept")


func test_policy_controls_are_blocked_after_defeat() -> void:
	_session = _new_session([Modifier.new(&"defeat.grace_seconds", &"set", 0),
		Modifier.new(&"defeat.bankruptcy.duration_seconds", &"set", 2),
		Modifier.new(&"defeat.bankruptcy.threshold", &"set", 20000)])
	_panel = _new_panel(_session)
	_tick()
	_tick()
	var controls: Dictionary = _price_controls()
	assert_true((controls["accumulate_on"] as CheckBox).disabled)
	assert_true((controls["limit_on"] as CheckBox).disabled)
	assert_false((controls["accumulate"] as SpinBox).editable)
	assert_false((_panel.get("_target") as HSlider).editable)
	assert_false((_panel.get("_reserve") as HSlider).editable)


func test_releasing_the_unloading_slider_where_it_was_sends_nothing() -> void:
	_panel.update_snapshot(_session.get_snapshot())
	var slider: HSlider = _panel.get("_unloading") as HSlider
	slider.drag_ended.emit(false)
	assert_true(_session.get("_pending").is_empty(), "the value did not change")
	slider.value = 30.0
	slider.drag_ended.emit(true)
	assert_eq(_session.get("_pending").size(), 1, "a changed value is sent once")
	_tick()
	_session.publish_tick()
	slider.drag_ended.emit(false)
	assert_true(_session.get("_pending").is_empty(), "30 is now the current split: nothing to send")


func test_the_unloading_slider_is_blocked_after_defeat() -> void:
	_session = _new_session([Modifier.new(&"defeat.grace_seconds", &"set", 0),
		Modifier.new(&"defeat.bankruptcy.duration_seconds", &"set", 2),
		Modifier.new(&"defeat.bankruptcy.threshold", &"set", 20000)])
	_panel = _new_panel(_session)
	_tick()
	_tick()
	var slider: HSlider = _panel.get("_unloading") as HSlider
	assert_false(slider.editable)
	slider.value = 50.0
	slider.drag_ended.emit(true)
	assert_true(_session.get("_pending").is_empty(), "no command is sent once the game is lost")
	_tick()
	assert_eq(_session.get_snapshot()["market"]["barley"]["barley_percent"], 0)


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


func test_import_switches_send_commands_and_reflect_state() -> void:
	_panel.update_snapshot(_session.get_snapshot())
	var tea: CheckButton = _panel.get("_tea") as CheckButton
	var flour: CheckButton = _panel.get("_flour") as CheckButton
	assert_false(tea.button_pressed)
	assert_false(flour.button_pressed)
	tea.button_pressed = true
	flour.button_pressed = true
	_tick()
	var economy: Dictionary = _session.get_snapshot()["economy"]
	assert_true(economy["tea_imports_enabled"])
	assert_true(economy["flour_imports_enabled"])
	assert_true(tea.button_pressed)
	assert_true(flour.button_pressed)


func test_import_rows_show_tea_stock_and_coverage_flour_price_and_why_there_is_none() -> void:
	_panel.update_snapshot(_session.get_snapshot())
	var imports: Dictionary = _session.get_snapshot()["imports"]
	assert_string_contains(_text("_tea_row"), Strings.reason(&"tea_imports_disabled"))
	assert_string_contains(_text("_tea_row"), "cobertura 0 %")
	var flour: Dictionary = imports["flour"]
	assert_string_contains(_text("_flour_row"), Strings.money(flour["lot_price"]))
	assert_string_contains(_text("_flour_row"), Strings.UNIT_PRICE % flour["unit_price"])
	assert_string_contains(_text("_flour_row"), Strings.reason(&"flour_imports_disabled"))
	(_panel.get("_tea") as CheckButton).button_pressed = true
	_tick()
	assert_string_contains(_text("_tea_row"), Strings.reason(&"no_wharf_for_imports"))


func test_satisfaction_line_adds_the_tea_component_so_the_parts_match_the_total() -> void:
	var snapshot: Dictionary = _session.get_snapshot()
	snapshot["economy"]["satisfaction_breakdown"]["tea"] = 15.0
	_panel.update_snapshot(snapshot)
	assert_string_contains(_text("_economy"), "té +15")


func test_barley_row_shows_the_stock_the_price_and_the_split_of_the_wharf() -> void:
	_session.submit_command(SetUnloadingSplitCommand.new(30))
	_tick()
	var barley: Dictionary = _session.get_snapshot()["market"]["barley"]
	assert_string_contains(_text("_barley_row"), "Cebada: 0/%d" % barley["capacity"])
	assert_string_contains(_text("_barley_row"), Strings.money(barley["price"]))
	assert_string_contains(_text("_barley_row"), "30 % cebada, 70 % trigo")


func test_balance_breakdown_lists_the_barley_so_the_parts_match_the_total() -> void:
	_session.submit_command(SetUnloadingSplitCommand.new(100))
	_tick()
	assert_string_contains(_text("_economy"), "cebada")


func test_panel_names_the_need_category_that_is_missing() -> void:
	var snapshot: Dictionary = _session.get_snapshot()
	snapshot["needs"] = {"classes": {&"worker": {
		"categories": [
			{"category": &"sustento", "value": 50.0, "threshold": 75.0, "met": false,
				"reason": &"below_threshold", "goods": [{"good": &"bread", "coverage": 0.5}], "missing_goods": [&"bread"]},
			{"category": &"comunidad", "value": 100.0, "threshold": 50.0, "met": true,
				"reason": &"ok", "goods": [{"good": &"tea", "coverage": 1.0}], "missing_goods": []},
		],
		"housing": {"building": &"housing", "base": 20, "bonus": 0, "max_bonus": 0},
		"population": 0, "satisfaction": {"current": 0.0}, "mobility": {},
	}}}
	_panel.update_snapshot(snapshot)
	var needs: String = _text("_needs")
	assert_string_contains(needs, Strings.NEEDS_TITLE)
	assert_string_contains(needs, Strings.NEEDS_SHORT % ["Trabajadores", "Sustento", 50.0, 75.0, "pan"])
	assert_string_contains(needs, Strings.NEEDS_MET % ["Trabajadores", "Comunidad o fe", 100.0, 50.0])
	assert_string_contains(needs, Strings.HOUSING_ROW % ["Trabajadores", 20, 0, 0])


func test_panel_gives_the_reason_when_a_covered_category_is_still_short() -> void:
	var snapshot: Dictionary = _session.get_snapshot()
	snapshot["needs"] = {"classes": {&"worker": {
		"categories": [{"category": &"sustento", "value": 50.0, "threshold": 75.0, "met": false,
			"reason": &"below_threshold", "goods": [{"good": &"bread", "coverage": 1.0}], "missing_goods": []}],
		"housing": {"building": &"housing", "base": 20, "bonus": 0, "max_bonus": 0},
		"population": 0, "satisfaction": {"current": 0.0}, "mobility": {},
	}}}
	_panel.update_snapshot(snapshot)
	assert_string_contains(_text("_needs"), Strings.NEEDS_SHORT_REASON
		% ["Trabajadores", "Sustento", 50.0, 75.0, Strings.reason(&"below_threshold")])


func test_panel_keeps_a_score_just_under_its_threshold_visibly_under() -> void:
	var snapshot: Dictionary = _session.get_snapshot()
	snapshot["needs"] = {"classes": {&"worker": {
		"categories": [{"category": &"sustento", "value": 74.96, "threshold": 75.0, "met": false,
			"reason": &"below_threshold", "goods": [{"good": &"bread", "coverage": 0.7496}], "missing_goods": [&"bread"]}],
		"housing": {"building": &"housing", "base": 20, "bonus": 0, "max_bonus": 0},
		"population": 0, "satisfaction": {"current": 0.0}, "mobility": {},
	}}}
	_panel.update_snapshot(snapshot)
	assert_string_contains(_text("_needs"), Strings.NEEDS_SHORT % ["Trabajadores", "Sustento", 74.9, 75.0, "pan"])


func test_panel_keeps_a_fractional_threshold_above_the_score() -> void:
	var snapshot: Dictionary = _session.get_snapshot()
	snapshot["needs"] = {"classes": {&"worker": {
		"categories": [{"category": &"sustento", "value": 74.95, "threshold": 74.96, "met": false,
			"reason": &"below_threshold", "goods": [{"good": &"bread", "coverage": 0.7495}], "missing_goods": [&"bread"]}],
		"housing": {"building": &"housing", "base": 20, "bonus": 0, "max_bonus": 0},
		"population": 0, "satisfaction": {"current": 0.0}, "mobility": {},
	}}}
	_panel.update_snapshot(snapshot)
	assert_string_contains(_text("_needs"), Strings.NEEDS_SHORT % ["Trabajadores", "Sustento", 74.9, 75.0, "pan"])


func test_panel_says_the_threshold_is_unreachable_instead_of_naming_a_good() -> void:
	var snapshot: Dictionary = _session.get_snapshot()
	snapshot["needs"] = {"classes": {&"worker": {
		"categories": [{"category": &"sustento", "value": 25.0, "threshold": 75.0, "met": false,
			"reason": &"unreachable_threshold", "goods": [{"good": &"bread", "coverage": 0.5}],
			"missing_goods": [&"bread"]}],
		"housing": {"building": &"housing", "base": 20, "bonus": 0, "max_bonus": 0},
		"population": 0, "satisfaction": {"current": 0.0}, "mobility": {},
	}}}
	_panel.update_snapshot(snapshot)
	assert_string_contains(_text("_needs"), Strings.NEEDS_SHORT_REASON
		% ["Trabajadores", "Sustento", 25.0, 75.0, Strings.reason(&"unreachable_threshold")])
	assert_false(_text("_needs").contains("falta pan"))


func test_panel_shows_a_met_score_with_float_drift_as_the_threshold() -> void:
	var snapshot: Dictionary = _session.get_snapshot()
	snapshot["needs"] = {"classes": {&"worker": {
		"categories": [{"category": &"sustento", "value": 62.99999999999999, "threshold": 63.0, "met": true,
			"reason": &"ok", "goods": [{"good": &"bread", "coverage": 0.7}], "missing_goods": [&"bread"]}],
		"housing": {"building": &"housing", "base": 20, "bonus": 0, "max_bonus": 0},
		"population": 0, "satisfaction": {"current": 0.0}, "mobility": {},
	}}}
	_panel.update_snapshot(snapshot)
	assert_string_contains(_text("_needs"), Strings.NEEDS_MET % ["Trabajadores", "Sustento", 63.0, 63.0])


# Issue #53: a notice at the top of the panel while anyone rose or fell between classes in the last minute.
func test_mobility_notice_uses_strings() -> void:
	var snapshot: Dictionary = _session.get_snapshot()
	_panel.update_snapshot(snapshot)
	assert_false(_panel.get("_notice").visible, "Nobody moved: no notice")
	snapshot["stats"]["promotions_in_window"] = 2
	_panel.update_snapshot(snapshot)
	var workers: String = Strings.CLASS_LABELS[&"worker"]
	var artisans: String = Strings.CLASS_LABELS[&"artisan"]
	assert_true(_panel.get("_notice").visible)
	assert_eq(_text("_notice"), Strings.MOBILITY_PROMOTED % [2, workers, artisans])
	snapshot["stats"]["demotions_in_window"] = 1
	_panel.update_snapshot(snapshot)
	assert_eq(_text("_notice"), "\n".join([Strings.MOBILITY_PROMOTED % [2, workers, artisans],
		Strings.MOBILITY_DEMOTED % [1, artisans, workers]]))


# --- Issue #54: one block per class, the promotion diagnosis and the split in notches -----------------

# A city with both housings, scored like the simulation does it; worker satisfaction is the smoothed one.
func _class_state(workers: int, artisans: int, beer: float, worker_satisfaction: float) -> Array:
	var context: EconomyContext = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	var params: Params = Params.new(_catalog, RoleDef.new())
	var state: EconomyState = EconomyState.new()
	state.tax_rate = 0.25
	state.buildings.append({"definition_id": &"housing"})
	state.buildings.append({"definition_id": &"artisan_housing"})
	ClassStates.ensure(state, context)
	state.population = workers + artisans
	state.class_states[&"artisan"].population = artisans
	state.hunger_smoothed_coverage = 1.0
	state.bread_coverage = 1.0
	state.tea_coverage = 0.5
	state.beer_coverage = beer
	SatisfactionSystem.new().update_target(state, params, context)
	state.satisfaction = worker_satisfaction
	return [state, params, context]


func _show_classes(city: Array) -> String:
	var snapshot: Dictionary = _session.get_snapshot()
	snapshot["needs"] = NeedsDiagnostics.build(city[0], city[1], city[2])
	_panel.update_snapshot(snapshot)
	return _text("_needs")


func test_panel_shows_population_coverage_and_satisfaction_per_class() -> void:
	var city: Array = _class_state(18, 2, 0.5, 72.6)
	var artisan_satisfaction: float = (city[0] as EconomyState).class_states[&"artisan"].satisfaction
	var needs: String = _show_classes(city)
	assert_string_contains(needs, Strings.CLASS_HEADER % ["Trabajadores", 18, 72.0])
	assert_string_contains(needs, Strings.CLASS_HEADER % ["Artesanos", 2, floorf(artisan_satisfaction)])
	assert_string_contains(needs, Strings.COVERAGE_ROW % ["Trabajadores", " · ".join(
		[Strings.GOOD_COVERAGE % ["pan", 100.0], Strings.GOOD_COVERAGE % ["té", 50.0]])])
	assert_string_contains(needs, Strings.COVERAGE_ROW % ["Artesanos", " · ".join(
		[Strings.GOOD_COVERAGE % ["pan", 100.0], Strings.GOOD_COVERAGE % ["cerveza", 50.0]])])


func test_coverage_just_under_full_never_reads_as_100() -> void:
	var city: Array = _class_state(20, 0, 0.996, 100.0)
	assert_string_contains(_show_classes(city), Strings.GOOD_COVERAGE % ["cerveza", 99.0])


func test_promotion_diagnosis_names_missing_beer() -> void:
	var needs: String = _show_classes(_class_state(20, 0, 0.5, 100.0))
	assert_string_contains(needs, Strings.PROMOTION_BLOCKED % "Artesanos")
	assert_string_contains(needs, Strings.PROMOTION_BLOCKER
		% (Strings.PROMOTION_CATEGORY_BELOW % ["Comunidad o fe", 50.0, 80.0, "cerveza"]))
	assert_false(needs.contains(Strings.reason(&"no_free_housing")), "There is room: housing is not blamed")


func test_promotion_diagnosis_names_full_artisan_housing() -> void:
	var city: Array = _class_state(20, 0, 1.0, 100.0)
	var artisans: ClassState = (city[0] as EconomyState).class_states[&"artisan"]
	artisans.population = artisans.housing_capacity
	var needs: String = _show_classes(city)
	assert_string_contains(needs, Strings.PROMOTION_BLOCKED % "Artesanos")
	assert_string_contains(needs, Strings.PROMOTION_BLOCKER % Strings.reason(&"no_free_housing"))
	assert_false(needs.contains("falta cerveza"), "The beer is covered: it is not blamed")


func test_promotion_diagnosis_names_low_worker_satisfaction() -> void:
	var needs: String = _show_classes(_class_state(20, 0, 1.0, 69.6))
	# 69.6 is under 70: it must not read as 70/70.
	assert_string_contains(needs, Strings.PROMOTION_BLOCKER % (Strings.PROMOTION_SATISFACTION_LOW % ["Trabajadores", 69.0, 70.0]))


func test_promotion_diagnosis_shows_the_rate_when_nothing_blocks() -> void:
	var city: Array = _class_state(20, 0, 1.0, 100.0)
	var artisan: ClassDef = (city[2] as EconomyContext).classes[&"artisan"]
	var rate: float = (city[1] as Params).get_value(artisan.promotion_per_minute_key)
	var needs: String = _show_classes(city)
	assert_string_contains(needs, Strings.PROMOTION_ACTIVE % ["Artesanos", rate])
	assert_false(needs.contains(Strings.PROMOTION_BLOCKED % "Artesanos"))


func test_the_unloading_slider_moves_in_steps_from_data_and_starts_all_wheat() -> void:
	_panel.update_snapshot(_session.get_snapshot())
	var slider: HSlider = _panel.get("_unloading") as HSlider
	assert_eq([slider.value, slider.step, slider.max_value], [0.0, 10.0, 100.0], "0-100 % in notches of 10, all wheat")
	slider.value = 37.0
	assert_eq(slider.value, 40.0, "the control snaps to its notch")
	slider.drag_ended.emit(true)
	_tick()
	_session.publish_tick()
	assert_eq(_session.get_snapshot()["market"]["barley"]["barley_percent"], 40)
	_session = _new_session([Modifier.new(&"policy.unloading.step_percent", &"set", 25)])
	_panel = _new_panel(_session)
	_panel.update_snapshot(_session.get_snapshot())
	assert_eq((_panel.get("_unloading") as HSlider).step, 25.0, "the notch is read from data, not from code")


func test_buildings_show_why_malthouse_and_brewery_stop() -> void:
	var context: EconomyContext = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	var params: Params = Params.new(_catalog, RoleDef.new())
	var state: EconomyState = EconomyState.new()
	state.buildings.append({"definition_id": &"malthouse", "cell": [1, 1], "workers": 1})
	state.buildings.append({"definition_id": &"brewery", "cell": [2, 1], "workers": 1})
	var snapshot: Dictionary = _session.get_snapshot()
	snapshot["diagnostics"] = BreadDiagnostics.build(state, params, context)
	_panel.update_snapshot(snapshot)
	var buildings: String = _text("_buildings")
	var jobs: Array[int] = [WorkersSystem.job_capacity(params, &"malthouse"), WorkersSystem.job_capacity(params, &"brewery")]
	assert_string_contains(buildings, Strings.BUILDING_STATUS % ["Maltería", 1, 1, 1, jobs[0], Strings.reason(&"no_barley")])
	assert_string_contains(buildings, Strings.BUILDING_STATUS % ["Cervecería", 2, 1, 1, jobs[1], Strings.reason(&"no_malt")])


# Bailey's review of #115: a split off the notch (a scenario's 15 %) is shown as it is, and a release without
# moving the slider does not round it to the notch.
func test_a_split_off_the_notch_shows_as_it_is_until_the_slider_moves() -> void:
	_session.submit_command(SetUnloadingSplitCommand.new(15))
	_tick()
	_session.publish_tick()
	_panel.update_snapshot(_session.get_snapshot())
	var slider: HSlider = _panel.get("_unloading") as HSlider
	assert_eq(slider.value, 15.0, "not rounded to 10 or 20")
	assert_eq(_text("_unloading_label"), Strings.UNLOADING_LABEL % 15)
	slider.drag_started.emit()
	slider.drag_ended.emit(false)
	assert_true(_session.get("_pending").is_empty(), "released where it was: nothing to send")
	assert_eq(slider.value, 15.0)
	slider.drag_started.emit()
	slider.value = 37.0
	assert_eq(slider.value, 40.0, "once moved, the slider goes in notches")
	slider.drag_ended.emit(true)
	_tick()
	_session.publish_tick()
	assert_eq(_session.get_snapshot()["market"]["barley"]["barley_percent"], 40)
