extends GutTest

# Statistics screen, history view (issue #83, D-052): one metric over 10 min, 1 h or the whole chapter, read from
# the series of #82 (D-066) without adding any, with markers from the cause log. The D-pad walks the buckets and
# picks the metric, and the triggers change the range.

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


func _build(simulation: Simulation, metric: StringName, range_index: int) -> Dictionary:
	var entry: Dictionary = _ranges()[range_index]
	return StatsTimeline.build(simulation, metric, entry["tier"], entry["span_seconds"])


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
	var expected: Array[StringName] = StatsSummary.CARDS.duplicate()
	expected.erase(&"fear")
	expected.erase(&"debt")
	assert_eq(StatsTimeline.METRICS, expected)


func test_each_range_reads_its_level_over_its_span() -> void:
	var simulation: Simulation = _simulation(TICKS)
	var medium: Dictionary = simulation.stats_series(&"money", StatsHistory.TIER_MEDIUM)
	var chapter: Dictionary = simulation.stats_series(&"money", StatsHistory.TIER_CHAPTER)
	var five: Dictionary = StatsTimeline.build(simulation, &"population", StatsHistory.TIER_MEDIUM, 300)
	assert_eq(_bucket_count(five), 30, "5 min of 10 s buckets")
	assert_eq(int(five["first_bucket"]) + 30, int(medium["first_bucket"]) + medium["mean"].size(), "Ends on the newest")
	assert_eq(_bucket_count(_build(simulation, &"population", 0)), 42, "7 min of the 10 so far")
	assert_eq(_bucket_count(_build(simulation, &"population", 1)), 42, "7 min of the hour so far")
	var whole: Dictionary = _build(simulation, &"population", 2)
	assert_eq(_bucket_count(whole), chapter["mean"].size())
	assert_eq(whole["bucket_seconds"], 60)
	assert_eq(whole["first_bucket"], 0, "The chapter from its first minute")


func test_the_chapter_range_reads_the_minute_level() -> void:
	var simulation: Simulation = _simulation(TICKS)
	var expected: float = 0.0
	for def: Dictionary in simulation.stats_series_defs():
		if def["metric"] == &"population":
			expected += simulation.stats_series(def["id"], StatsHistory.TIER_CHAPTER)["mean"][-1]
	var chart: Dictionary = _build(simulation, &"population", 2)
	assert_almost_eq(chart["lines"][0]["values"][-1], expected, 0.01)
	assert_eq(StatsSummary.reading(&"population", chart["lines"], 0),
		str(roundi(chart["lines"][0]["values"][0])), "Reads any bucket, not only the newest")


func test_a_policy_change_is_marked_on_its_bucket() -> void:
	var simulation: Simulation = _simulation(TAX_TICK - 1)
	simulation.apply_command(SetTaxCommand.new(TAX_RATE))
	for tick: int in 120 - TAX_TICK + 1:
		simulation.tick()
	var chart: Dictionary = _build(simulation, &"population", 0)
	var policies: Array[Dictionary] = []
	for marker: Dictionary in chart["markers"]:
		if marker["text"] == Strings.text(Strings.STATS_SCREEN_MARKER_POLICY) % Strings.text(&"ui.stats_screen.policy.tax_rate"):
			policies.append(marker)
	assert_eq(policies.size(), 1, "One marker for the new tax")
	@warning_ignore("integer_division")
	assert_eq(policies[0]["bucket"], (TAX_TICK - 1) / 10 - int(chart["first_bucket"]))


func test_starting_policies_are_not_markers() -> void:
	var chart: Dictionary = _build(_simulation(120), &"population", 0)
	var policy: String = Strings.text(Strings.STATS_SCREEN_MARKER_POLICY).split("%s")[0]
	for marker: Dictionary in chart["markers"]:
		assert_false(String(marker["text"]).begins_with(policy), "Every policy starts logged: %s" % marker)


func test_the_lost_demo_marks_its_warnings_and_defeat() -> void:
	var chart: Dictionary = _build(_simulation(DEFEAT_TICKS), &"population", 2)
	var depopulation: String = Strings.label(Strings.CONDITION_LABELS, &"depopulation")
	var found: Array[String] = []
	for marker: Dictionary in chart["markers"]:
		found.append("%d %s" % [marker["bucket"], marker["text"]])
	assert_has(found, "0 " + Strings.text(Strings.STATS_SCREEN_MARKER_WARNING) % Strings.label(Strings.CONDITION_LABELS,
		&"hunger"), "The demo starts without bread")
	assert_has(found, "5 " + Strings.text(Strings.STATS_SCREEN_MARKER_WARNING) % depopulation, "301 s: minute 6")
	assert_has(found, "7 " + Strings.text(Strings.STATS_SCREEN_MARKER_DEFEAT) % depopulation, "480 s: minute 8")


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
	for metric: StringName in StatsTimeline.METRICS:
		for range_index: int in _ranges().size():
			_build(simulation, metric, range_index)
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
	var lines: Array[Dictionary] = (history.get("_chart") as Dictionary)["lines"]
	assert_eq((history.get("_reading") as Label).text, Strings.text(Strings.STATS_SCREEN_HISTORY_READING)
		% ["1:40", StatsSummary.reading(&"population", lines, 9)], "Reads the bucket that ends at 1:40")
	var session: GameSession = view.get("session") as GameSession
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
	_pad(JOY_BUTTON_DPAD_DOWN)
	assert_eq((history.get("_chart") as Dictionary)["id"], StatsTimeline.METRICS[1])
	_pad(JOY_BUTTON_DPAD_UP)
	_pad(JOY_BUTTON_DPAD_UP)
	assert_eq((history.get("_chart") as Dictionary)["id"], StatsTimeline.METRICS[-1], "Wraps around")


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
	for metric: int in StatsTimeline.METRICS.size():
		for locale: String in ["es", "en"]:
			Strings.set_locale(locale)
			await get_tree().process_frame
			assert_lte(screen.get_combined_minimum_size().x, 1280.0, "Width (%s, %d)" % [locale, metric])
			assert_lte(screen.get_combined_minimum_size().y, 800.0, "Height (%s, %d)" % [locale, metric])
		_pad(JOY_BUTTON_DPAD_DOWN)
	assert_true(history.visible)
