extends GutTest

# The narrator on the map (issue #73, D-137, D-145): its notices show under the layer picker, a notice that asks for
# it pauses the clock, "why?" opens that notice's chain in the cause log and "see on the map" selects its building.

const ROOT: String = "user://test_narrator_feed"
const HISTORY_SECONDS: int = 130

var _viewport: SubViewport


func after_each() -> void:
	Strings.use_default_locale()


func _view() -> MapView:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 800)
	add_child_autofree(_viewport)
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var view: MapView = scene.get_node("Map") as MapView
	view.mods_root = ROOT
	view.saves_root = ROOT
	_viewport.add_child(scene)
	view.clock.speed = 0
	await get_tree().process_frame
	return view


func _build(view: MapView, id: StringName) -> Vector2i:
	var map: MapDef = view.session.context.map
	for y: int in range(map.height):
		for x: int in range(map.width):
			var build: BuildCommand = BuildCommand.new(view.session.context, id, Vector2i(x, y))
			view.session.simulation.apply_command(build)
			view.session.simulation.tick()
			if build.accepted:
				view.session.publish_tick()
				return Vector2i(x, y)
	fail_test("No cell takes a %s" % id)
	return Vector2i(-1, -1)


# A change of one subject, numbered after what the log already holds, as if logged now. A subject the log has not
# seen gets its starting cause first: a first cause waits the grace of D-198 before it is announced, so a test that
# needs the notice now marks the subject as known.
func _announce(view: MapView, kind: StringName, subject: StringName, cause: StringName, known: bool = false) -> void:
	var serial: int = view.narrator.read_from()
	var second: int = view.session.simulation.stats_seconds()
	var entries: Array[Dictionary] = []
	if not known:
		entries.append({"serial": serial, "event": {"second": second, "kind": kind, "subject": subject, "cause": &"starting"}})
	entries.append({"serial": serial + entries.size(), "event": {"second": second, "kind": kind, "subject": subject,
		"cause": cause}})
	view.narrator.feed(entries, second)
	view.call("_show_notices")


func _feed(view: MapView) -> NarratorFeed:
	return view.get("_feed") as NarratorFeed


func _button(view: MapView, name: String) -> Button:
	var found: Array[Node] = _feed(view).find_children(name, "Button", true, false)
	return found[0] as Button if not found.is_empty() else null


func test_a_defeat_warning_shows_and_pauses_the_clock() -> void:
	var view: MapView = await _view()
	view.clock.speed = 1
	_announce(view, &"defeat", &"bankruptcy", &"warning")
	view.call("_narrate")
	assert_eq(view.clock.speed, 0, "D-145: the game pauses")
	var texts: Array[String] = _feed(view).texts
	assert_eq(texts.size(), 1)
	assert_eq(texts[0], Strings.text(&"narrator.defeat.warning") % Strings.label(Strings.CONDITION_LABELS, &"bankruptcy"))
	(_button(view, "Close") as Button).pressed.emit()
	assert_eq(_feed(view).texts.size(), 0, "closing takes it away")


func test_see_on_the_map_selects_the_building_and_why_opens_its_chain() -> void:
	var view: MapView = await _view()
	var cell: Vector2i = _build(view, &"mill")
	for second: int in 3:
		view.session.simulation.tick()
	view.session.publish_tick()
	var subject: StringName = StatsHistory.building_subject(view.call("_building_at", cell))
	_announce(view, &"building", subject, &"no_workers", true)
	assert_eq(_feed(view).texts.size(), 1)
	(_button(view, "Map") as Button).pressed.emit()
	assert_eq(view.geometry.selected, cell, "the notice's building is selected")
	view.geometry.selected = Vector2i(-1, -1)
	view.call("_update_mode")
	(_button(view, "Why") as Button).pressed.emit()
	var panel: WhyPanel = view.get("_why_panel") as WhyPanel
	assert_true(panel.visible)
	assert_true(panel.expanded)
	var expected: Array[String] = []
	for event: Dictionary in view.session.simulation.stats_cause_chain(&"building", subject):
		expected.append(WhyPanel.line(event))
	assert_false(expected.is_empty())
	assert_eq(panel.lines, expected, "the chain of that kind and subject, as stored")


func test_a_notice_without_a_building_has_no_map_button() -> void:
	var view: MapView = await _view()
	_announce(view, &"import", &"tea", &"no_wharf_for_imports")
	assert_not_null(_button(view, "Why"))
	assert_null(_button(view, "Map"), "nothing on the map to go to")
	_announce(view, &"building", &"mill@0,0", &"no_workers")
	assert_eq(_feed(view).texts.size(), 2)
	assert_eq(_feed(view).find_children("Map", "Button", true, false).size(), 1, "a demolished building: its tile")
	_announce(view, &"building", &"mill@900,900", &"no_workers")
	assert_eq(_feed(view).find_children("Map", "Button", true, false).size(), 1, "off the map: nothing to go to")


# Each rule's words, filled the way the feed fills them, read whole in both languages.
func test_every_rule_reads_without_a_bare_placeholder_in_both_languages() -> void:
	var config: NarratorConfig = NarratorConfig.new()
	config.load_data()
	var subjects: Dictionary[StringName, StringName] = {&"defeat": &"bankruptcy", &"victory": &"stage_1",
		&"emigration": &"worker", &"building": &"bakery@3,0", &"import": &"tea", &"policy": &"tax_rate"}
	var labels: Dictionary = {&"bakery": Strings.building_label("bakery")}
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		for rule: Dictionary in config.rules:
			if rule["silent"]:
				continue
			var notice: Dictionary = {"kind": rule["kind"], "subject": subjects[rule["kind"]],
				"cause": rule["cause"] if rule["cause"] != &"" else &"no_workers", "key": rule["key"], "merged": 2,
				"count": 4, "priority": rule["priority"]}
			var text: String = NarratorText.text(notice, labels)
			assert_false(text.contains("%s") or text.contains("%d"), "%s (%s): %s" % [rule["key"], locale, text])
			assert_false(text.contains(String(rule["key"])), "%s has its words" % rule["key"])
		var digest: Dictionary = {"kind": Narrator.DIGEST_KIND, "items": [{"count": 3, "notice": {"kind": &"import",
			"subject": &"tea", "cause": &"no_wharf_for_imports", "key": &"narrator.import.stopped", "merged": 1}}]}
		assert_string_contains(NarratorText.text(digest, labels), "3")
	var target: Dictionary = NarratorText.map_target(&"bakery@3,7", NarratorConfig.TARGET_SUBJECT_CELL)
	assert_eq(NarratorText.cell_of({"map_target": target}), Vector2i(3, 7))
	assert_eq(NarratorText.cell_of({"map_target": NarratorText.map_target(&"tea", NarratorConfig.TARGET_SUBJECT_CELL)}),
		NarratorText.NO_CELL)


func _mill_notice(view: MapView) -> Vector2i:
	var cell: Vector2i = _build(view, &"mill")
	# Enough seconds for the history to close a bucket of its medium tier.
	for second: int in HISTORY_SECONDS:
		view.session.simulation.tick()
	view.session.publish_tick()
	# The history the scene made while it ran is a starting state, as after a load (D-198): start the narrator on it
	# the way the map does, so only the mill's own change is announced and no first cause is waiting in the grace.
	var simulation: Simulation = view.session.simulation
	view.narrator.start(simulation.stats_cause_entries(0), simulation.stats_cause_count(), simulation.stats_seconds())
	var subject: StringName = StatsHistory.building_subject(view.call("_building_at", cell))
	_announce(view, &"building", subject, &"no_workers", true)
	return cell


func test_see_on_the_chart_opens_history_on_the_series_and_the_second() -> void:
	var view: MapView = await _view()
	_mill_notice(view)
	var notice: Dictionary = view.narrator.visible()[0]
	assert_eq(notice["graph_link"]["series"], &"jobs_filled:mill")
	assert_not_null(_button(view, "Graph"))
	# The bucket of the event has closed by the time it is looked at.
	for later: int in HISTORY_SECONDS:
		view.session.simulation.tick()
	(_button(view, "Graph") as Button).pressed.emit()
	var screen: StatsScreen = view.get("_stats_screen") as StatsScreen
	assert_true(screen.visible, "the statistics screen opened")
	assert_eq(screen.current_series(), &"jobs_filled:mill")
	var history: TimelineTab = screen.get("_history") as TimelineTab
	var second: int = notice["graph_link"]["second"]
	var bucket: int = int(history.get("_chart")["bucket_seconds"])
	assert_gte(history.cursor_second(), second, "the cursor is on the bucket of the event")
	assert_lt(history.cursor_second() - bucket, second)


func test_see_on_the_map_turns_on_the_overlay_of_its_rule() -> void:
	var view: MapView = await _view()
	var cell: Vector2i = _mill_notice(view)
	var notice: Dictionary = view.narrator.visible()[0].duplicate(true)
	notice["overlay"] = "bread"
	view.call("_go_to", notice, NarratorText.map_target(&"mill@%d,%d" % [cell.x, cell.y], NarratorConfig.TARGET_SUBJECT_CELL))
	var bar: OverlayBar = view.get("_overlay_bar") as OverlayBar
	assert_eq(bar.selected, &"bread", "the layer of that need is on")


func _press(action: StringName) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func test_the_gamepad_has_a_why_b_close_x_map_y_graph_with_16_px_buttons() -> void:
	var view: MapView = await _view()
	var cell: Vector2i = _mill_notice(view)
	view.set("_gamepad", true)
	view.call("_why_pressed")
	assert_ne(view.get("_narrator_focus"), 0, "R3 gives the newest notice the face buttons")
	for name: String in ["Why", "Map", "Graph", "Close"]:
		var button: Button = _button(view, name)
		assert_not_null(button, name)
		assert_gte(button.custom_minimum_size.x, 16.0, "%s is at least 16 px" % name)
		assert_gte(button.custom_minimum_size.y, 16.0)
	assert_string_contains(_button(view, "Map").text, "(X)")
	assert_string_contains(_button(view, "Graph").text, "(Y)")
	view.geometry.selected = Vector2i(-1, -1)
	view.call("_gamepad_command", _press(&"map_demolish"))
	assert_eq(view.geometry.selected, cell, "X goes to the map")
	view.call("_gamepad_command", _press(&"map_place"))
	assert_true((view.get("_why_panel") as WhyPanel).expanded, "A opens the why")
	view.call("_gamepad_command", _press(&"map_repair"))
	assert_true((view.get("_stats_screen") as StatsScreen).visible, "Y opens the chart")
	(view.get("_stats_screen") as StatsScreen).close()
	view.set("_narrator_focus", view.narrator.visible()[0]["id"])
	view.call("_gamepad_command", _press(&"ui_cancel"))
	assert_eq(_feed(view).texts.size(), 0, "B closes the notice")
	assert_eq(view.get("_narrator_focus"), 0)
