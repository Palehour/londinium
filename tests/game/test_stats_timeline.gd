extends GutTest

# Statistics screen, history view (issue #316, D-168): one series of the D-066 registry over 10 min, 1 h or the
# chapter. LB/RB change the series. Markers are only kinds the simulation has already emitted. The D-pad walks
# the buckets and the triggers change the range.

const ROOT: String = "user://test_stats_timeline"
# Seven minutes: 42 closed buckets of the medium level and 7 of the chapter's. The demo, left alone, is lost to
# depopulation at 8 min: its warning comes at 301 s and the defeat at 480 s.
const TICKS: int = 420
const DEFEAT_TICKS: int = 900
const TAX_TICK: int = 61
const TAX_RATE: float = 0.37

var _catalog: DataCatalog
var _viewport: SubViewport


func before_all() -> void:
	_catalog = DataLoader.new().load_all().catalog


func after_each() -> void:
	Strings.use_default_locale()


func _session() -> GameSession:
	return GameSession.new(_catalog, Params.new(_catalog, RoleDef.new()))


func _simulation(ticks: int) -> Simulation:
	var simulation: Simulation = _session().simulation
	for tick: int in ticks:
		simulation.tick()
	return simulation


func _ranges() -> Array[Dictionary]:
	var look: StatsPresentation = StatsPresentation.new()
	look.load_data()
	return look.history_ranges


func _look() -> StatsPresentation:
	var look: StatsPresentation = StatsPresentation.new()
	look.load_data()
	return look


func _chart(simulation: Simulation, series_id: StringName, range_index: int) -> Dictionary:
	var entry: Dictionary = _ranges()[range_index]
	return StatsTimeline.chart(simulation, series_id, entry["tier"], entry["span_seconds"], _look().history_markers)


func _bucket_count(chart: Dictionary) -> int:
	return (chart["lines"][0]["values"] as PackedFloat32Array).size()


func test_ranges_are_ten_minutes_an_hour_and_the_chapter() -> void:
	var look: StatsPresentation = StatsPresentation.new()
	look.load_data()
	assert_eq(look.errors, [] as Array[String])
	var ids: Array[StringName] = []
	for entry: Dictionary in look.history_ranges:
		ids.append(entry["id"])
	assert_eq(ids, [&"ten_minutes", &"hour", &"chapter"] as Array[StringName])
	assert_eq(look.history_ranges[0]["span_seconds"], 600)
	assert_eq(look.history_ranges[1]["span_seconds"], 3600)
	assert_eq(look.history_ranges[2]["tier"], StatsHistory.TIER_CHAPTER, "The whole chapter is the minute level")
	assert_eq(look.history_ranges[2]["span_seconds"], 0, "0 = every bucket")


func test_presentation_rejects_bad_ranges() -> void:
	var look: StatsPresentation = StatsPresentation.new()
	look.validate({"summary": {}, "layout": {}, "colors": {}, "strokes": [{"color": "#ffffff", "dash": 0}],
		"history": {"ranges": [{"id": "x", "tier": "fine", "span_seconds": 10}, {"id": "y", "tier": "medium",
			"span_seconds": -1}]}})
	assert_true(look.errors.has("data/ui/stats.json.history.ranges.0: expected an id and a tier, medium or chapter"))
	assert_true(look.errors.has("data/ui/stats.json.history.ranges.1.span_seconds: expected 0 or more"))
	assert_eq(look.history_ranges.size(), 0)


func test_history_draws_every_summary_metric_that_has_series() -> void:
	var simulation: Simulation = _simulation(0)
	var expected: Array[StringName] = []
	for def: Dictionary in simulation.stats_series_defs():
		expected.append(def["id"])
	expected.append(&"fear")
	expected.append(&"debt")
	assert_eq(_look().history_series, expected, "stats.json follows the registry, then fear and debt")


func test_each_range_reads_its_level_over_its_span() -> void:
	var simulation: Simulation = _simulation(TICKS)
	var medium: Dictionary = simulation.stats_series(&"money", StatsHistory.TIER_MEDIUM)
	var chapter: Dictionary = simulation.stats_series(&"population:worker", StatsHistory.TIER_CHAPTER)
	var five: Dictionary = StatsTimeline.chart(simulation, &"money", StatsHistory.TIER_MEDIUM, 300, _look().history_markers)
	assert_eq(_bucket_count(five), 30, "5 min of 10 s buckets")
	assert_eq(int(five["first_bucket"]) + 30, int(medium["first_bucket"]) + medium["total"].size(), "Ends on the newest")
	assert_eq(_bucket_count(_chart(simulation, &"money", 0)), 42, "7 min of the 10 so far")
	assert_eq(_bucket_count(_chart(simulation, &"money", 1)), 42, "7 min of the hour, not 360 padded buckets")
	var whole: Dictionary = _chart(simulation, &"population:worker", 2)
	assert_eq(_bucket_count(whole), chapter["mean"].size())
	assert_eq(whole["bucket_seconds"], 60)
	assert_eq(whole["first_bucket"], 0, "The chapter from its first minute")


func test_the_chapter_range_reads_the_minute_level() -> void:
	var simulation: Simulation = _simulation(TICKS)
	var series: Dictionary = simulation.stats_series(&"population:worker", StatsHistory.TIER_CHAPTER)
	var chart: Dictionary = _chart(simulation, &"population:worker", 2)
	assert_almost_eq(chart["lines"][0]["values"][-1], series["mean"][-1], 0.01, "The registry mean, not a sum")
	assert_eq(StatsTimeline.format_value(chart["lines"][0]["values"][0], &"people"),
		Strings.text(Strings.STATS_SCREEN_HISTORY_VALUE) % chart["lines"][0]["values"][0],
		"Reads any bucket, not only the newest")


func test_a_policy_change_is_marked_on_its_bucket() -> void:
	var simulation: Simulation = _simulation(TAX_TICK - 1)
	simulation.apply_command(SetTaxCommand.new(TAX_RATE))
	for tick: int in 120 - TAX_TICK + 1:
		simulation.tick()
	_assert_history_hides(simulation, 0, "A tax change is logged, and Historia does not mark it")


func test_starting_policies_are_not_markers() -> void:
	_assert_history_hides(_simulation(120), 0, "Starting policies are logged, and Historia does not mark them")


func test_the_lost_demo_marks_its_warnings_and_defeat() -> void:
	_assert_history_hides(_simulation(DEFEAT_TICKS), 2, "The lost demo logs warnings and a defeat; Historia does not mark them")


func test_marks_warnings_defeats_and_completed_stages_only() -> void:
	var warning: Dictionary = {"second": 30, "kind": &"defeat", "subject": &"bankruptcy", "cause": &"warning"}
	assert_eq(StatsTimeline.marker_text(warning), Strings.text(Strings.STATS_SCREEN_MARKER_WARNING)
		% Strings.label(Strings.CONDITION_LABELS, &"bankruptcy"))
	var defeat: Dictionary = {"second": 30, "kind": &"defeat", "subject": &"hunger", "cause": &"defeat"}
	assert_eq(StatsTimeline.marker_text(defeat), Strings.text(Strings.STATS_SCREEN_MARKER_DEFEAT)
		% Strings.label(Strings.CONDITION_LABELS, &"hunger"))
	assert_eq(StatsTimeline.marker_text({"second": 30, "kind": &"victory", "subject": &"population",
		"cause": &"completed"}), Strings.text(Strings.STATS_SCREEN_MARKER_STAGE))
	for quiet: Dictionary in [
		{"second": 30, "kind": &"defeat", "subject": &"hunger", "cause": &"ok"},
		{"second": 30, "kind": &"victory", "subject": &"population", "cause": &"pending"},
		{"second": 30, "kind": &"command", "subject": &"BuildCommand", "cause": &"accepted"},
		{"second": 30, "kind": &"building", "subject": &"bakery@3,4", "cause": &"no_input"},
	]:
		assert_eq(StatsTimeline.marker_text(quiet), "", str(quiet))


func test_building_the_history_leaves_the_game_unchanged() -> void:
	var simulation: Simulation = _simulation(120)
	# Compared as bytes: an empty bucket holds NaN, which is never equal to itself.
	var before: PackedByteArray = var_to_bytes(simulation.to_save())
	for series_id: StringName in _look().history_series:
		for range_index: int in _ranges().size():
			_chart(simulation, series_id, range_index)
	assert_eq(var_to_bytes(simulation.to_save()), before)


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


func _trigger(axis: JoyAxis, value: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	_viewport.push_input(event)


# The screen on its history tab, after two minutes of play.
func _history(view: Node2D) -> TimelineTab:
	((view.get("_stats_panel") as StatsPanel).get("_stats_button") as Button).pressed.emit()
	var session: GameSession = view.get("session") as GameSession
	for tick: int in 120:
		session.simulation.tick()
	session.publish_tick()
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	return (view.get("_stats_screen") as StatsScreen).get("_history") as TimelineTab


func test_rb_goes_to_the_history_and_the_dpad_walks_the_buckets() -> void:
	var view: Node2D = await _view()
	var history: TimelineTab = _history(view)
	var tabs: TabContainer = (view.get("_stats_screen") as StatsScreen).get("_tabs") as TabContainer
	assert_eq(tabs.current_tab, StatsScreen.HISTORY_TAB)
	assert_eq(history.cursor_index(), 11, "On the newest of twelve buckets")
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pad(JOY_BUTTON_DPAD_LEFT)
	assert_eq(history.cursor_index(), 9)
	var session: GameSession = view.get("session") as GameSession
	var money: PackedFloat32Array = StatsSummary.window(session.simulation.stats_series(&"money",
		StatsHistory.TIER_MEDIUM), "total", 600)
	assert_eq((history.get("_reading") as Label).text, Strings.text(Strings.STATS_SCREEN_HISTORY_READING)
		% ["1:40", StatsTimeline.format_value(money[9], &"pence")], "Reads money at the bucket that ends at 1:40")
	for tick: int in 10:
		session.simulation.tick()
	session.publish_tick()
	assert_eq(history.cursor_index(), 9, "A moved cursor stays on its bucket while new ones come")
	_pad(JOY_BUTTON_DPAD_RIGHT)
	_pad(JOY_BUTTON_DPAD_RIGHT)
	_pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(history.cursor_index(), 12, "Back on the newest")


func test_dpad_up_and_down_change_the_metric() -> void:
	var view: Node2D = await _view()
	var history: TimelineTab = _history(view)
	var screen: StatsScreen = view.get("_stats_screen") as StatsScreen
	var tabs: TabContainer = screen.get("_tabs") as TabContainer
	var first: StringName = (history.get("_chart") as Dictionary)["id"]
	_pad(JOY_BUTTON_DPAD_DOWN)
	_pad(JOY_BUTTON_DPAD_UP)
	assert_eq((history.get("_chart") as Dictionary)["id"], first, "Up and down no longer change the series")
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_eq(tabs.current_tab, StatsScreen.HISTORY_TAB, "RB stays on Historia")
	assert_eq((history.get("_chart") as Dictionary)["id"], &"income:tax:worker")
	_pad(JOY_BUTTON_LEFT_SHOULDER)
	assert_eq((history.get("_chart") as Dictionary)["id"], first)
	_pad(JOY_BUTTON_LEFT_SHOULDER)
	assert_eq((history.get("_chart") as Dictionary)["id"], &"debt", "LB wraps to the last series")
	assert_eq(tabs.current_tab, StatsScreen.HISTORY_TAB)
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_eq((history.get("_chart") as Dictionary)["id"], first, "RB wraps back to the first")
	assert_eq((screen.get("_hint") as Label).text, Strings.text(Strings.STATS_SCREEN_HISTORY_HEADER))
	assert_false((history.get("_hint") as Label).text.contains("métrica"))


func test_a_trigger_pull_changes_the_range_once() -> void:
	var view: Node2D = await _view()
	var history: TimelineTab = _history(view)
	_trigger(JOY_AXIS_TRIGGER_LEFT, 1.0)
	_trigger(JOY_AXIS_TRIGGER_LEFT, 0.9)
	assert_eq(history.get("_range"), 1, "LT widens to an hour, once while held")
	_trigger(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_trigger(JOY_AXIS_TRIGGER_LEFT, 1.0)
	assert_eq(history.get("_range"), 2, "A second pull: the whole chapter")
	assert_eq((history.get("_chart") as Dictionary)["bucket_seconds"], 60)
	_trigger(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	assert_eq(history.get("_range"), 1, "RT narrows")
	assert_eq(view.get("_building_type"), &"", "The map behind does not take them")


func test_history_fits_the_steam_deck_screen() -> void:
	var view: Node2D = await _view()
	var screen: StatsScreen = view.get("_stats_screen") as StatsScreen
	var history: TimelineTab = _history(view)
	assert_gte(screen.theme.default_font_size, 16)
	var series: Array[StringName] = history.presentation.history_series
	var shown: StringName = (history.get("_chart") as Dictionary)["id"]
	for series_id: StringName in [&"need_score:artisan:comunidad", &"expense:imported_flour", &"fear", &"debt"]:
		history.change_series(series.find(series_id) - series.find(shown))
		shown = series_id
		if series_id == &"fear" or series_id == &"debt":
			assert_true((history.get("_chart") as Dictionary)["lines"].is_empty())
			assert_eq((history.get("_reading") as Label).text, Strings.text(Strings.STATS_SCREEN_NO_DATA))
		for locale: String in ["es", "en"]:
			Strings.set_locale(locale)
			await get_tree().process_frame
			assert_lte(screen.get_combined_minimum_size().x, 1280.0, "Width (%s, %s)" % [locale, series_id])
			assert_lte(screen.get_combined_minimum_size().y, 800.0, "Height (%s, %s)" % [locale, series_id])
	assert_true(history.visible)


# D-168: the cursor reads the registry field of one series (mean when the series averages, total otherwise).
func test_the_cursor_reads_the_registry_field_not_a_derived_metric() -> void:
	var simulation: Simulation = _simulation(TICKS)
	var look: StatsPresentation = StatsPresentation.new()
	look.load_data()
	for sample: StringName in [&"money", &"income:tax:worker", &"population:worker", &"coverage:bread"]:
		var def: Dictionary = _def(simulation, sample)
		var field: String = "mean" if def["aggregation"] == &"mean" else "total"
		for range_index: int in _ranges().size():
			var entry: Dictionary = _ranges()[range_index]
			var chart: Dictionary = StatsTimeline.chart(simulation, sample, entry["tier"], entry["span_seconds"],
				look.history_markers)
			var expected: PackedFloat32Array = StatsSummary.window(simulation.stats_series(sample, entry["tier"]),
				field, entry["span_seconds"])
			var got: PackedFloat32Array = (chart["lines"][0]["values"] as PackedFloat32Array)
			assert_eq(got.size(), expected.size(), "%s %s" % [sample, entry["id"]])
			assert_ne(got.size(), 360, "An hour with 7 min of play is not padded to 360 buckets")
			for index: int in got.size():
				if is_nan(expected[index]):
					assert_true(is_nan(got[index]), "%s[%d]" % [sample, index])
				else:
					assert_almost_eq(got[index], expected[index], 0.001, "%s %s [%d]" % [sample, field, index])


func test_an_unregistered_marker_kind_is_not_drawn_and_two_stack() -> void:
	var candidates: Array[Dictionary] = [
		{"kind": &"crisis", "icon": "!", "label_key": &"ui.stats_screen.marker.crisis"},
		{"kind": &"invented", "icon": "?", "label_key": &"ui.stats_screen.marker.crisis"},
		{"kind": &"decree", "icon": "D", "label_key": &"ui.stats_screen.marker.decree"},
	]
	var events: Array[Dictionary] = [
		{"second": 15, "kind": &"invented", "subject": &"x", "cause": &"y"},
		{"second": 21, "kind": &"crisis", "subject": &"bread", "cause": &"started"},
		{"second": 25, "kind": &"decree", "subject": &"tea", "cause": &"issued"},
	]
	var markers: Array[Dictionary] = StatsTimeline.history_markers(events, 0, 5, 10, candidates, [&"crisis", &"decree"])
	var kinds: Array = []
	for marker: Dictionary in markers:
		kinds.append_array(marker["kinds"])
	assert_false(kinds.has(&"invented"), "A candidate the simulation never emitted is not drawn")
	assert_true(kinds.has(&"crisis"), "A candidate that was emitted is drawn")
	assert_eq(markers.size(), 1, "Both land in bucket 2 and stack")
	assert_eq(markers[0]["count"], 2)
	var crisis: String = Strings.text(Strings.STATS_SCREEN_MARKER_LINE) % ["!", Strings.text(&"ui.stats_screen.marker.crisis")]
	var decree: String = Strings.text(Strings.STATS_SCREEN_MARKER_LINE) % ["D", Strings.text(&"ui.stats_screen.marker.decree")]
	assert_eq(markers[0]["text"], Strings.text(Strings.STATS_SCREEN_MARKER_STACK) % [" · ".join([crisis, decree]), 2])


func test_fear_and_debt_have_no_line() -> void:
	var simulation: Simulation = _simulation(TICKS)
	for series_id: StringName in [&"fear", &"debt"]:
		var chart: Dictionary = _chart(simulation, series_id, 0)
		assert_eq(chart["lines"], [] as Array[Dictionary], String(series_id))
		assert_eq(chart["label"], Strings.text(Strings.STATS_SCREEN_CARDS[series_id]))


func test_strokes_are_one_unique_pair_per_series() -> void:
	var look: StatsPresentation = _look()
	assert_eq(look.errors, [] as Array[String])
	assert_eq(look.stroke_colors[0], Color.html("#e69f00"))
	assert_almost_eq(look.stroke_dashes[0], 0.0, 0.001)
	assert_eq(look.stroke_colors[1], Color.html("#56b4e9"))
	assert_almost_eq(look.stroke_dashes[1], 8.0, 0.001)
	assert_eq(look.stroke_colors[2], Color.html("#009e73"))
	assert_almost_eq(look.stroke_dashes[2], 3.0, 0.001)
	assert_eq(look.stroke_colors[3], Color.html("#cc79a7"))
	assert_almost_eq(look.stroke_dashes[3], 14.0, 0.001)
	assert_eq(look.stroke_colors.size(), look.history_series.size(), "One stroke per series")
	var pairs: Dictionary = {}
	for index: int in look.stroke_colors.size():
		var color: Color = look.stroke_colors[index]
		assert_ne(color, Color.html("#f0e442"), "Yellow is the cursor")
		assert_ne(color, Color.html("#000000"), "Black disappears on the background")
		var pair: String = "%s|%s" % [color.to_html(false), look.stroke_dashes[index]]
		assert_false(pairs.has(pair), pair)
		pairs[pair] = true


func test_series_labels_do_not_show_raw_ids() -> void:
	var simulation: Simulation = _simulation(0)
	for series_id: StringName in _look().history_series:
		var label: String = StatsTimeline.series_label(series_id, _def(simulation, series_id))
		assert_false(label.contains("imported_flour"), label)
		assert_false(label.contains("upkeep"), label)
		assert_false(label.contains("hunger"), label)
		assert_false(label.contains(":"), label)
	var hunger: String = StatsTimeline.series_label(&"emigration:worker:hunger",
		_def(simulation, &"emigration:worker:hunger"))
	assert_false(hunger.contains(Strings.text(Strings.CONDITION_LABELS[&"hunger"])), "Not the riot")


func _assert_history_hides(simulation: Simulation, range_index: int, message: String) -> void:
	var chart: Dictionary = _chart(simulation, &"money", range_index)
	assert_false(chart["lines"].is_empty(), message)
	for marker: Dictionary in chart["markers"]:
		for kind: StringName in marker["kinds"]:
			assert_false(StatsTimeline.HIDDEN_KINDS.has(kind), "%s: %s" % [message, kind])


func _def(simulation: Simulation, id: StringName) -> Dictionary:
	for def: Dictionary in simulation.stats_series_defs():
		if def["id"] == id:
			return def
	return {}
