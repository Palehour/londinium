extends GutTest

# The "why?" from a statistics chart (issue #319, D-052, D-168): A opens it on the bucket under the cursor, the D-pad
# walks the buckets, B goes back. It lists the causes the cause log holds for that bucket's seconds and "see on the
# map" moves the map's cursor to the building they are about. Driven with the gamepad alone, at 1280×800.

const ROOT: String = "user://test_stats_why"
const TICKS: int = 120
const MIN_FONT_SIZE: int = 16
const SCREEN: Vector2 = Vector2(1280.0, 800.0)

var _viewport: SubViewport


func after_each() -> void:
	Strings.use_default_locale()


func _view() -> Node2D:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SCREEN)
	add_child_autofree(_viewport)
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var view: Node2D = scene.get_node("Map") as Node2D
	view.set("mods_root", ROOT)
	view.set("saves_root", ROOT)
	_viewport.add_child(scene)
	(view.get("clock") as SimClock).speed = 0
	await get_tree().process_frame
	return view


func _pad(button: JoyButton) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	_viewport.push_input(event)
	event = event.duplicate() as InputEventJoypadButton
	event.pressed = false
	_viewport.push_input(event)


# The screen open after two minutes of play, on the history tab (chains sits between summary and history).
func _history(view: Node2D) -> StatsScreen:
	((view.get("_stats_panel") as StatsPanel).get("_stats_button") as Button).pressed.emit()
	var session: GameSession = view.get("session") as GameSession
	for tick: int in TICKS:
		session.simulation.tick()
	session.publish_tick()
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	return view.get("_stats_screen") as StatsScreen


func _walk_to_first_bucket() -> void:
	for step: int in 12:
		_pad(JOY_BUTTON_DPAD_LEFT)


func _why_of(screen: StatsScreen) -> StatsWhyView:
	return screen.get("_why") as StatsWhyView


func _causes_of(why: StatsWhyView) -> WhyPanel:
	return why.get("_causes") as WhyPanel


func test_a_bucket_with_causes_lists_them() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = _history(view)
	_walk_to_first_bucket()
	_pad(JOY_BUTTON_A)
	var why: StatsWhyView = _why_of(screen)
	assert_true(why.visible, "A opens the why")
	assert_false((screen.get("_tabs") as TabContainer).visible, "It takes the chart's place")
	var simulation: Simulation = (view.get("session") as GameSession).simulation
	var tab: ChartTab = (screen.get("_tabs") as TabContainer).get_current_tab_control() as ChartTab
	var composed: Dictionary = StatsWhy.compose(simulation, tab.why_chart(), tab.cursor_index(), tab.why_parts())
	var events: Array[Dictionary] = composed["events"]
	assert_gt(events.size(), 0, "The first seconds log each subject's starting cause")
	var expected: Array[String] = []
	for event: Dictionary in events:
		assert_lte(int(event["second"]), 10, "Only the seconds of the bucket")
		expected.append(WhyPanel.line(event, true))
	var causes: WhyPanel = _causes_of(why)
	assert_true(causes.visible)
	assert_true(causes.expanded)
	assert_eq(causes.lines.slice(0, expected.size()), expected)


func test_a_bucket_without_data_says_no_data() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = _history(view)
	# Fear has no series: the chart has no line, so there is no bucket to explain.
	((screen.get("_history") as TimelineTab)).change_series(-2)
	_pad(JOY_BUTTON_A)
	var why: StatsWhyView = _why_of(screen)
	assert_true(why.visible)
	assert_eq((why.get("_breakdown") as Label).text, Strings.text(Strings.STATS_SCREEN_NO_DATA))
	assert_true((why.get("_no_causes") as Label).visible)
	assert_false(_causes_of(why).visible)


func test_an_empty_bucket_has_no_value_to_explain() -> void:
	var simulation: Simulation = GameSession.new(DataLoader.new().load_all().catalog,
		Params.new(DataLoader.new().load_all().catalog, RoleDef.new())).simulation
	var chart: Dictionary = {"first_bucket": 0, "bucket_seconds": 10}
	var parts: Array[Dictionary] = [{"label": "x", "values": PackedFloat32Array([NAN]), "unit": &""}]
	assert_false(StatsWhy.compose(simulation, chart, 0, parts)["available"])
	assert_false(StatsWhy.compose(simulation, chart, -1, parts)["available"])


func test_the_breakdown_is_the_change_against_the_bucket_before() -> void:
	var simulation: Simulation = GameSession.new(DataLoader.new().load_all().catalog,
		Params.new(DataLoader.new().load_all().catalog, RoleDef.new())).simulation
	var chart: Dictionary = {"first_bucket": 0, "bucket_seconds": 10}
	var parts: Array[Dictionary] = [{"label": "Pan", "values": PackedFloat32Array([10.0, 4.0]), "unit": &""}]
	assert_eq(StatsWhy.compose(simulation, chart, 1, parts)["lines"],
		[Strings.text(Strings.STATS_SCREEN_WHY_PART) % ["Pan", "10", "4", "-6"]] as Array[String])
	assert_eq(StatsWhy.compose(simulation, chart, 0, parts)["lines"],
		[Strings.text(Strings.STATS_SCREEN_WHY_FIRST) % ["Pan", "10"]] as Array[String])


func test_the_cell_comes_from_a_building_subject_only() -> void:
	var subject: StringName = StatsHistory.building_subject({"definition_id": &"mill", "cell": [3, 4]})
	assert_eq(StatsWhy.cell_of({"kind": &"building", "subject": subject}), Vector2i(3, 4))
	assert_eq(StatsWhy.cell_of({"kind": &"policy", "subject": &"tax_rate"}), StatsWhy.NO_CELL)
	assert_eq(StatsWhy.cell_of({"kind": &"building", "subject": &"mill"}), StatsWhy.NO_CELL)


func test_opening_the_why_leaves_the_game_unchanged() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = _history(view)
	var simulation: Simulation = (view.get("session") as GameSession).simulation
	var before: PackedByteArray = var_to_bytes(simulation.to_save())
	_walk_to_first_bucket()
	_pad(JOY_BUTTON_A)
	_pad(JOY_BUTTON_DPAD_RIGHT)
	_pad(JOY_BUTTON_B)
	assert_false(_why_of(screen).visible)
	assert_eq(var_to_bytes(simulation.to_save()), before)


func test_the_dpad_walks_the_buckets_and_b_goes_back_to_the_chart() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = _history(view)
	var history: TimelineTab = screen.get("_history") as TimelineTab
	var why: StatsWhyView = _why_of(screen)
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pad(JOY_BUTTON_A)
	assert_eq(history.cursor_index(), 10)
	var title: String = (why.get("_title") as Label).text
	_pad(JOY_BUTTON_DPAD_LEFT)
	assert_eq(history.cursor_index(), 9, "The D-pad walks the buckets as in D-170")
	assert_ne((why.get("_title") as Label).text, title, "The title follows the bucket")
	_pad(JOY_BUTTON_B)
	assert_false(why.visible, "B returns to the chart")
	assert_true(screen.visible, "and does not leave the screen")
	assert_true((screen.get("_tabs") as TabContainer).visible)
	assert_eq(history.cursor_index(), 9, "on the same bucket")
	_pad(JOY_BUTTON_B)
	assert_false(screen.visible, "A second B leaves the screen")


func test_the_summary_and_the_chains_do_not_open_it() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = _history(view)
	# LB/RB change the series on the history, so the tab is picked directly.
	for tab: int in [StatsScreen.SUMMARY_TAB, StatsScreen.CHAINS_TAB]:
		(screen.get("_tabs") as TabContainer).current_tab = tab
		_pad(JOY_BUTTON_A)
		assert_false(_why_of(screen).visible, "Tab %d" % tab)


func test_the_classes_chart_breaks_down_each_class() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = _history(view)
	(screen.get("_tabs") as TabContainer).current_tab = StatsScreen.CLASSES_TAB
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pad(JOY_BUTTON_A)
	var why: StatsWhyView = _why_of(screen)
	assert_true(why.visible)
	var text: String = (why.get("_breakdown") as Label).text
	assert_true(text.contains(Strings.text(Strings.CLASS_LABELS[&"worker"])), "One line per class: " + text)


func test_see_on_the_map_goes_to_the_building_of_the_cause() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = _history(view)
	_walk_to_first_bucket()
	_pad(JOY_BUTTON_A)
	var why: StatsWhyView = _why_of(screen)
	assert_ne(why.cell, StatsWhy.NO_CELL, "A building's starting cause is in the first bucket")
	assert_true((why.get("_map") as Button).visible)
	var cell: Vector2i = why.cell
	_pad(JOY_BUTTON_A)
	assert_false(screen.visible, "The screen closes")
	var geometry: Object = view.get("geometry") as Object
	assert_eq(geometry.get("selected"), cell, "and the map's cursor is on the building")


func test_the_why_fits_1280_by_800_in_both_languages() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = _history(view)
	_walk_to_first_bucket()
	_pad(JOY_BUTTON_A)
	var why: StatsWhyView = _why_of(screen)
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		await get_tree().process_frame
		why.refresh()
		assert_lte(screen.get_combined_minimum_size().x, SCREEN.x, "Width (%s)" % locale)
		assert_lte(screen.get_combined_minimum_size().y, SCREEN.y, "Height (%s)" % locale)
	for name: String in ["_title", "_breakdown", "_no_causes", "_hint"]:
		assert_gte((why.get(name) as Label).get_theme_font_size(&"font_size"), MIN_FONT_SIZE, name)
	assert_gte(_causes_of(why).get_child(0).get_child(0).get_theme_font_size(&"font_size"), MIN_FONT_SIZE)
