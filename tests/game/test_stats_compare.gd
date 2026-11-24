extends GutTest

# Statistics screen, compare view (issue #318, D-168): two moments of the chapter, A and B, and a table of what
# changed between them. It reads the summary's cards without adding series, so a bucket with no data stays "—".
# Y marks A then B, the D-pad walks the buckets, ↑/↓ pick the chart. By moments only: there are no districts in
# the history yet.

const ROOT: String = "user://test_stats_compare"
# Two minutes: twelve closed buckets of the medium level, ten seconds each.
const TICKS: int = 120
const BUCKET_SECONDS: int = 10

var _catalog: DataCatalog
var _viewport: SubViewport


func before_all() -> void:
	_catalog = DataLoader.new().load_all().catalog


func after_each() -> void:
	Strings.use_default_locale()


func _cards(population: Array, balance: Array) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for id: StringName in StatsSummary.CARDS:
		cards.append({"id": id, "lines": [] as Array[Dictionary], "value": ""})
	cards[StatsSummary.CARDS.find(&"population")]["lines"] = [{"label": "", "values": PackedFloat32Array(population)}]
	cards[StatsSummary.CARDS.find(&"balance")]["lines"] = [{"label": "", "values": PackedFloat32Array(balance)}]
	return cards


func test_a_row_is_b_minus_a() -> void:
	var rows: Array[Dictionary] = StatsCompare.rows(_cards([10.0, 14.0, 9.0], [100.0, 40.0, 100.0]), 0, 1)
	assert_eq(rows.size(), 2, "Only the cards that have lines are rows")
	assert_eq(rows[0]["card"], &"population")
	assert_eq(rows[0]["a"], 10.0)
	assert_eq(rows[0]["b"], 14.0)
	assert_eq(rows[0]["diff"], 4.0)
	assert_eq(rows[1]["diff"], -60.0, "A fall is a negative difference")


func test_an_unset_or_hidden_moment_has_no_difference() -> void:
	var rows: Array[Dictionary] = StatsCompare.rows(_cards([10.0, 14.0], [1.0, 2.0]), 1, -1)
	assert_eq(rows[0]["b"] == rows[0]["b"], false, "B is unknown, not a made-up 0")
	assert_true(is_nan(rows[0]["diff"]))
	assert_true(is_nan(StatsCompare.rows(_cards([10.0], [1.0]), 0, 5)[0]["b"]), "Outside the window is unknown too")


func test_a_gap_in_the_history_is_not_a_zero() -> void:
	var rows: Array[Dictionary] = StatsCompare.rows(_cards([NAN, 14.0], [1.0, 2.0]), 0, 1)
	assert_true(is_nan(rows[0]["diff"]))


func test_a_difference_writes_its_sign_in_both_languages() -> void:
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		assert_eq(StatsCompare.format_diff(&"population", 4.0), Strings.text(Strings.STATS_SCREEN_COMPARE_UP) % "4")
		assert_eq(StatsCompare.format_diff(&"population", -4.0), Strings.text(Strings.STATS_SCREEN_COMPARE_DOWN) % "4")
		assert_eq(StatsCompare.format_diff(&"population", 0.0), "0", "No change has no sign")
		assert_eq(StatsCompare.format_diff(&"balance", -240.0),
			Strings.text(Strings.STATS_SCREEN_COMPARE_DOWN) % Strings.money(240), "Money keeps its format")
		assert_eq(StatsCompare.format_diff(&"debt", NAN), Strings.text(Strings.STATS_SCREEN_NO_READING))


func test_a_line_of_a_card_with_several_names_its_row_after_both() -> void:
	var cards: Array[Dictionary] = _cards([1.0], [1.0])
	cards[StatsSummary.CARDS.find(&"satisfaction")]["lines"] = [
		{"label": "Obreros", "values": PackedFloat32Array([60.0, 50.0])},
		{"label": "Artesanos", "values": PackedFloat32Array([70.0, 80.0])}]
	var rows: Array[Dictionary] = StatsCompare.rows(cards, 0, 1)
	var title: String = Strings.text(Strings.STATS_SCREEN_CARDS[&"satisfaction"])
	assert_eq(rows[2]["label"], Strings.text(Strings.STATS_SCREEN_COMPARE_ROW) % [title, "Obreros"])
	assert_eq(rows[3]["label"], Strings.text(Strings.STATS_SCREEN_COMPARE_ROW) % [title, "Artesanos"])


func test_a_marker_is_found_in_the_bucket_that_holds_its_second() -> void:
	var chart: Dictionary = {"first_bucket": 3, "bucket_seconds": 10}
	assert_eq(StatsCompare.bucket_of(chart, 40, 5), 0, "Second 40 closes bucket 3, the first shown")
	assert_eq(StatsCompare.bucket_of(chart, 80, 5), 4)
	assert_eq(StatsCompare.bucket_of(chart, 30, 5), -1, "Before the window")
	assert_eq(StatsCompare.bucket_of(chart, 90, 5), -1, "After the window")
	assert_eq(StatsCompare.bucket_of(chart, -1, 5), -1, "Unset")


func test_building_the_rows_leaves_the_game_unchanged() -> void:
	var session: GameSession = GameSession.new(_catalog, Params.new(_catalog, RoleDef.new()))
	for tick: int in TICKS:
		session.simulation.tick()
	var before: PackedByteArray = var_to_bytes(session.simulation.to_save())
	StatsCompare.rows(StatsSummary.build(session.simulation, 600), 0, 5)
	assert_eq(var_to_bytes(session.simulation.to_save()), before)


func _view() -> Node2D:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 800)
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


# The screen on its compare tab, after two minutes of play.
func _open_compare(view: Node2D) -> CompareTab:
	((view.get("_stats_panel") as StatsPanel).get("_stats_button") as Button).pressed.emit()
	var session: GameSession = view.get("session") as GameSession
	for tick: int in TICKS:
		session.simulation.tick()
	session.publish_tick()
	var screen: StatsScreen = view.get("_stats_screen") as StatsScreen
	(screen.get("_tabs") as TabContainer).current_tab = StatsScreen.COMPARE_TAB
	return screen.get("_compare") as CompareTab


func test_y_marks_a_then_b_then_a_again_on_the_bucket_of_the_cursor() -> void:
	var view: Node2D = await _view()
	var compare: CompareTab = _open_compare(view)
	assert_eq(compare.marker_seconds(), [CompareTab.NO_MARKER, CompareTab.NO_MARKER] as Array[int], "Nothing marked yet")
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pad(JOY_BUTTON_Y)
	assert_eq(compare.marker_seconds(), [TICKS - 2 * BUCKET_SECONDS, CompareTab.NO_MARKER] as Array[int], "A: two buckets back")
	_pad(JOY_BUTTON_DPAD_RIGHT)
	_pad(JOY_BUTTON_DPAD_RIGHT)
	_pad(JOY_BUTTON_Y)
	assert_eq(compare.marker_seconds(), [TICKS - 2 * BUCKET_SECONDS, TICKS] as Array[int], "B: the newest bucket")
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pad(JOY_BUTTON_Y)
	assert_eq(compare.marker_seconds(), [TICKS - BUCKET_SECONDS, TICKS] as Array[int], "A again, B stays")


func test_the_table_reads_the_two_moments_from_the_history() -> void:
	var view: Node2D = await _view()
	var compare: CompareTab = _open_compare(view)
	var session: GameSession = view.get("session") as GameSession
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pad(JOY_BUTTON_Y)
	_pad(JOY_BUTTON_DPAD_RIGHT)
	_pad(JOY_BUTTON_DPAD_RIGHT)
	_pad(JOY_BUTTON_Y)
	var population: float = 0.0
	var at_a: float = 0.0
	for def: Dictionary in session.simulation.stats_series_defs():
		if def["metric"] != &"population":
			continue
		var mean: PackedFloat32Array = session.simulation.stats_series(def["id"], StatsHistory.TIER_MEDIUM)["mean"]
		population += mean[-1]
		at_a += mean[-3]
	var row: Dictionary = compare.rows()[0]
	assert_eq(row["card"], &"population")
	assert_almost_eq(row["a"], at_a, 0.01)
	assert_almost_eq(row["b"], population, 0.01)
	assert_almost_eq(row["diff"], population - at_a, 0.01)


func test_a_marker_outside_the_range_reads_unknown() -> void:
	var view: Node2D = await _view()
	var compare: CompareTab = _open_compare(view)
	_pad(JOY_BUTTON_Y)
	var screen: StatsScreen = view.get("_stats_screen") as StatsScreen
	screen.handle(_trigger_event(JOY_AXIS_TRIGGER_LEFT, 1.0))
	assert_ne(compare.get("_range"), 0, "The range changed")
	var rows: Array[Dictionary] = compare.rows()
	assert_false(is_nan(rows[0]["a"]), "The chapter range still shows second %d" % TICKS)
	compare.set("_second_a", 10000)
	compare.refresh()
	assert_true(is_nan(compare.rows()[0]["a"]), "A second the range does not show is unknown")


func _trigger_event(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func test_up_and_down_pick_the_chart_and_stop_at_the_ends() -> void:
	var view: Node2D = await _view()
	var compare: CompareTab = _open_compare(view)
	_pad(JOY_BUTTON_DPAD_UP)
	assert_eq(compare.get("_card"), 0, "Does not wrap above the first")
	for press: int in StatsCompare.CARDS.size() + 2:
		_pad(JOY_BUTTON_DPAD_DOWN)
	assert_eq(compare.get("_card"), StatsCompare.CARDS.size() - 1, "Stops on the last")


func test_opening_the_screen_again_clears_the_markers() -> void:
	var view: Node2D = await _view()
	var compare: CompareTab = _open_compare(view)
	_pad(JOY_BUTTON_Y)
	assert_ne(compare.marker_seconds()[0], CompareTab.NO_MARKER)
	var screen: StatsScreen = view.get("_stats_screen") as StatsScreen
	screen.open()
	assert_eq(compare.marker_seconds()[0], CompareTab.NO_MARKER)


func test_compare_fits_the_steam_deck_screen_with_both_moments_set() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = view.get("_stats_screen") as StatsScreen
	_open_compare(view)
	_pad(JOY_BUTTON_Y)
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pad(JOY_BUTTON_Y)
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		await get_tree().process_frame
		assert_lte(screen.get_combined_minimum_size().x, 1280.0, "Width (%s)" % locale)
		assert_lte(screen.get_combined_minimum_size().y, 800.0, "Height (%s)" % locale)


func test_compare_texts_are_translated_and_at_least_16_px() -> void:
	var look: StatsPresentation = StatsPresentation.new()
	look.load_data()
	assert_gte(look.layout["font_size"], 16.0)
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		for key: StringName in [Strings.STATS_SCREEN_COMPARE, Strings.STATS_SCREEN_COMPARE_HINT,
				Strings.STATS_SCREEN_COMPARE_METRIC, Strings.STATS_SCREEN_COMPARE_DIFF,
				Strings.STATS_SCREEN_COMPARE_NEXT]:
			assert_ne(Strings.text(key), String(key), "%s has a %s text" % [key, locale])
