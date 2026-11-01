extends GutTest

# Summary view controls (issue #314, D-170): one cursor shared by the six cards. The D-pad ←/→ walks the buckets and
# stops at the edges, LT/RT or +/- change the window among the ranges of data/ui/stats.json, and the cursor starts
# on the newest bucket when the summary opens or the window changes. Every card reads the cursor's bucket on one
# line of 16 px, aggregated by the rule its series declares (D-066); fear and debt read "—". Everything is driven
# with the gamepad alone, at 1280×800.

const ROOT: String = "user://test_stats_summary_cursor"
# Seven minutes: 42 closed buckets of 10 s and 7 of a minute. The demo, left alone, is lost at 8 min and its history
# stops there, so the 10 min and 1 h windows hold the same 42 buckets.
const TICKS: int = 420
const MIN_FONT_SIZE: int = 16

var _viewport: SubViewport


func after_each() -> void:
	Strings.use_default_locale()


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


# A full pull of a trigger and its release.
func _pull(axis: JoyAxis) -> void:
	for value: float in [1.0, 0.0]:
		var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
		event.axis = axis
		event.axis_value = value
		_viewport.push_input(event)


func _key(keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_viewport.push_input(event)


# The screen open on the summary after TICKS seconds of play.
func _open_summary(view: Node2D) -> SummaryTab:
	var session: GameSession = view.get("session") as GameSession
	for tick: int in TICKS:
		session.simulation.tick()
	((view.get("_stats_panel") as StatsPanel).get("_stats_button") as Button).pressed.emit()
	session.publish_tick()
	await get_tree().process_frame
	var screen: StatsScreen = view.get("_stats_screen") as StatsScreen
	return (screen.get("_tabs") as TabContainer).get_current_tab_control() as SummaryTab


func _readings(tab: SummaryTab) -> PackedStringArray:
	var texts: PackedStringArray = []
	for label: Label in tab.readings:
		texts.append(label.text)
	return texts


# The field of a bucket that holds a series by its aggregation (D-066): the mean for averaged levels, the total
# (the sum for flows, the last value for stocks) otherwise.
func _field(def: Dictionary) -> String:
	return "mean" if def["aggregation"] == SeriesDef.AGGREGATION_MEAN else "total"


# One bucket of a series, counted from the oldest bucket of the window.
func _at(simulation: Simulation, def: Dictionary, entry: Dictionary, bucket: int) -> float:
	var values: PackedFloat32Array = StatsSummary.window(simulation.stats_series(def["id"], entry["tier"]),
		_field(def), entry["span_seconds"])
	return values[bucket]


func _sum(simulation: Simulation, metric: StringName, entry: Dictionary, bucket: int) -> float:
	var total: float = 0.0
	for def: Dictionary in simulation.stats_series_defs():
		if def["metric"] == metric:
			total += _at(simulation, def, entry, bucket)
	return total


func _def(simulation: Simulation, id: StringName) -> Dictionary:
	for def: Dictionary in simulation.stats_series_defs():
		if def["id"] == id:
			return def
	return {}


# What each card has to read at a bucket, worked out from the series themselves.
func _expected(simulation: Simulation, entry: Dictionary, bucket: int) -> PackedStringArray:
	var none: String = Strings.text(Strings.STATS_SCREEN_NO_READING)
	var population: float = _sum(simulation, &"population", entry, bucket)
	var seconds: int = int(simulation.stats_series(&"money", entry["tier"])["bucket_seconds"])
	var balance: float = (_sum(simulation, &"income", entry, bucket) - _sum(simulation, &"expense", entry, bucket)) \
		* 60.0 / float(seconds)
	var classes: PackedStringArray = []
	for def: Dictionary in simulation.stats_series_defs():
		if def["metric"] == &"satisfaction":
			classes.append(Strings.text(Strings.STATS_SCREEN_CLASS_VALUE) % [
				Strings.label(Strings.CLASS_LABELS, def["dimensions"][&"class"]), _at(simulation, def, entry, bucket)])
	var goods: PackedStringArray = []
	for good: StringName in StatsSummary.GOODS:
		var def: Dictionary = _def(simulation, StringName("coverage:%s" % good))
		goods.append(Strings.text(Strings.GOOD_COVERAGE) % [Strings.label(Strings.GOOD_LABELS, good),
			_at(simulation, def, entry, bucket) * 100.0])
	return PackedStringArray([
		none if is_nan(population) else str(roundi(population)),
		none if is_nan(balance) else Strings.money(roundi(balance)),
		" · ".join(classes), " · ".join(goods), none, none])


func _bucket_count(simulation: Simulation, entry: Dictionary) -> int:
	var first: Dictionary = simulation.stats_series_defs()[0]
	return StatsSummary.window(simulation.stats_series(first["id"], entry["tier"]), "mean", entry["span_seconds"]).size()


# The reading fits its card on one line of at least 16 px, nothing cut off.
func _assert_fits(tab: SummaryTab) -> void:
	for label: Label in tab.readings:
		var size: int = label.get_theme_font_size(&"font_size")
		assert_gte(size, MIN_FONT_SIZE, "Text of 16 px or more")
		assert_eq(label.get_line_count(), 1, "One line: %s" % label.text)
		var width: float = label.get_theme_font(&"font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			size).x
		assert_lte(width, label.size.x, "Fits its card: %s" % label.text)


func test_dpad_walks_every_bucket_of_the_three_windows_at_the_steam_deck_size() -> void:
	var view: Node2D = await _view()
	var tab: SummaryTab = await _open_summary(view)
	var screen: StatsScreen = view.get("_stats_screen") as StatsScreen
	var simulation: Simulation = (view.get("session") as GameSession).simulation
	var ranges: Array[Dictionary] = tab.presentation.history_ranges
	assert_eq(ranges.size(), 3, "10 min, 1 h and the chapter")
	var counts: Array[int] = []
	for index: int in ranges.size():
		if index > 0:
			_pull(JOY_AXIS_TRIGGER_LEFT)
		var entry: Dictionary = ranges[index]
		var count: int = _bucket_count(simulation, entry)
		counts.append(count)
		assert_eq(tab.cursor_index(), count - 1, "%s starts on its newest bucket" % entry["id"])
		await get_tree().process_frame
		assert_lte(screen.get_combined_minimum_size().y, 800.0, "Fits the height (%s)" % entry["id"])
		assert_lte(screen.get_combined_minimum_size().x, 1280.0, "Fits the width (%s)" % entry["id"])
		for bucket: int in range(count - 1, -1, -1):
			assert_eq(tab.cursor_index(), bucket)
			assert_eq(_readings(tab), _expected(simulation, entry, bucket), "%s, bucket %d" % [entry["id"], bucket])
			_pad(JOY_BUTTON_DPAD_LEFT)
		assert_eq(tab.cursor_index(), 0, "Stops at the oldest bucket")
		await get_tree().process_frame
		_assert_fits(tab)
		for bucket: int in count:
			_pad(JOY_BUTTON_DPAD_RIGHT)
		assert_eq(tab.cursor_index(), count - 1, "Stops at the newest bucket")
	assert_eq(counts, [42, 42, 7] as Array[int], "Every closed bucket of each window")


func test_the_window_goes_back_with_rt_and_stops_at_the_ends() -> void:
	var view: Node2D = await _view()
	var tab: SummaryTab = await _open_summary(view)
	var simulation: Simulation = (view.get("session") as GameSession).simulation
	var ranges: Array[Dictionary] = tab.presentation.history_ranges
	_pull(JOY_AXIS_TRIGGER_RIGHT)
	assert_eq(tab.cursor_index(), _bucket_count(simulation, ranges[0]) - 1, "RT on the narrowest stays there")
	for pull: int in ranges.size() + 1:
		_pull(JOY_AXIS_TRIGGER_LEFT)
	assert_eq(tab.cursor_index(), _bucket_count(simulation, ranges[-1]) - 1, "LT stops on the widest")
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pull(JOY_AXIS_TRIGGER_RIGHT)
	assert_eq(tab.cursor_index(), _bucket_count(simulation, ranges[1]) - 1, "A new window starts on its newest")


func test_plus_and_minus_change_the_window_too() -> void:
	var view: Node2D = await _view()
	var tab: SummaryTab = await _open_summary(view)
	var simulation: Simulation = (view.get("session") as GameSession).simulation
	var ranges: Array[Dictionary] = tab.presentation.history_ranges
	_key(KEY_MINUS)
	assert_eq(tab.cursor_index(), _bucket_count(simulation, ranges[1]) - 1)
	_key(KEY_PLUS)
	assert_eq(tab.cursor_index(), _bucket_count(simulation, ranges[0]) - 1)


func test_the_summary_opens_on_its_newest_bucket() -> void:
	var view: Node2D = await _view()
	var tab: SummaryTab = await _open_summary(view)
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pad(JOY_BUTTON_DPAD_LEFT)
	var newest: int = tab.cursor_index() + 2
	_pad(JOY_BUTTON_B)
	((view.get("_stats_panel") as StatsPanel).get("_stats_button") as Button).pressed.emit()
	assert_eq(tab.cursor_index(), newest, "Reopened on the newest bucket")
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	_pad(JOY_BUTTON_LEFT_SHOULDER)
	assert_eq(tab.cursor_index(), newest, "Back on the summary, on the newest bucket")


func test_fear_and_debt_read_a_dash_and_say_no_data() -> void:
	var view: Node2D = await _view()
	var tab: SummaryTab = await _open_summary(view)
	for id: StringName in [&"fear", &"debt"]:
		var index: int = StatsSummary.CARDS.find(id)
		for locale: String in ["es", "en"]:
			Strings.set_locale(locale)
			await get_tree().process_frame
			assert_eq(tab.readings[index].text, "—", "%s (%s)" % [id, locale])
			assert_eq(tab.values[index].text, Strings.text(Strings.STATS_SCREEN_NO_DATA))
			assert_true(tab.values[index].visible)
			assert_false(tab.charts[index].visible)


func test_cards_with_data_hide_the_no_data_line() -> void:
	var view: Node2D = await _view()
	var tab: SummaryTab = await _open_summary(view)
	for id: StringName in [&"population", &"balance", &"satisfaction", &"coverage"]:
		var index: int = StatsSummary.CARDS.find(id)
		assert_false(tab.values[index].visible, id)
		assert_true(tab.charts[index].visible, id)
		assert_ne(tab.readings[index].text, "—", id)


func test_walking_the_summary_leaves_the_game_unchanged() -> void:
	var view: Node2D = await _view()
	var tab: SummaryTab = await _open_summary(view)
	var simulation: Simulation = (view.get("session") as GameSession).simulation
	# Compared as bytes: an empty bucket holds NaN, which is never equal to itself.
	var before: PackedByteArray = var_to_bytes(simulation.to_save())
	_pad(JOY_BUTTON_DPAD_LEFT)
	_pull(JOY_AXIS_TRIGGER_LEFT)
	_pad(JOY_BUTTON_DPAD_LEFT)
	assert_eq(var_to_bytes(simulation.to_save()), before)
	assert_not_null(tab)
