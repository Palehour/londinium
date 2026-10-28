extends GutTest

# The "why?" (issue #73, D-137): the chain of causes of the selected building exactly as the cause log of #82 keeps
# it, newest first, with no filter and nothing left out. I (R3 on the gamepad) opens and folds it.

const ROOT: String = "user://test_why_panel"

var _viewport: SubViewport


func after_each() -> void:
	Strings.use_default_locale()


func _panel() -> WhyPanel:
	var panel: WhyPanel = WhyPanel.new()
	panel.setup()
	add_child_autofree(panel)
	return panel


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


func _key(keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_viewport.push_input(event)


# The first cell, row by row, that takes the building, after one published tick.
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


func _select(view: MapView, cell: Vector2i) -> void:
	view.geometry.selected = cell
	view.call("_update_mode")


func test_the_panel_shows_every_event_of_the_chain_in_its_order() -> void:
	var panel: WhyPanel = _panel()
	var chain: Array[Dictionary] = [
		{"second": 125, "kind": &"building", "subject": &"mill@1,1", "cause": &"no_workers"},
		{"second": 70, "kind": &"building", "subject": &"mill@1,1", "cause": CauseLog.INTERMITTENT, "count": 7},
		{"second": 3, "kind": &"building", "subject": &"mill@1,1", "cause": &"not_a_known_reason"},
	]
	panel.show_chain(&"mill@1,1", "title", chain, false, false)
	assert_true(panel.visible)
	assert_eq(panel.lines.size(), chain.size(), "one line per stored event, none filtered")
	for index: int in chain.size():
		assert_eq(panel.lines[index], WhyPanel.line(chain[index]))
	assert_string_contains(panel.lines[0], "2:05")
	assert_string_contains(panel.lines[0], Strings.reason(&"no_workers"))
	assert_string_contains(panel.lines[1], "7", "an intermittent event shows its count")
	assert_string_contains(panel.lines[2], "not_a_known_reason", "a cause without text shows its id, not nothing")


func test_dropped_events_are_said_and_an_empty_chain_hides_the_panel() -> void:
	var panel: WhyPanel = _panel()
	var chain: Array[Dictionary] = [{"second": 1, "kind": &"building", "subject": &"mill@1,1", "cause": &"ok"}]
	panel.show_chain(&"mill@1,1", "title", chain, true, false)
	assert_eq(panel.lines[-1], Strings.text(Strings.WHY_PRUNED))
	panel.show_chain(&"house@2,2", "title", [] as Array[Dictionary], true, false)
	assert_false(panel.visible)


func test_the_selected_building_shows_its_chain_from_the_simulation() -> void:
	var view: MapView = await _view()
	var cell: Vector2i = _build(view, &"mill")
	var panel: WhyPanel = view.get("_why_panel") as WhyPanel
	assert_false(panel.visible, "nothing selected")
	_select(view, cell)
	assert_true(panel.visible)
	var subject: StringName = StatsHistory.building_subject(view.call("_building_at", cell))
	var chain: Array[Dictionary] = view.session.simulation.stats_cause_chain(&"building", subject)
	assert_false(chain.is_empty())
	var expected: Array[String] = []
	for event: Dictionary in chain:
		expected.append(WhyPanel.line(event))
	assert_eq(panel.lines, expected, "exactly the stored chain")
	assert_false(panel.expanded, "folded until asked")
	_key(KEY_I)
	assert_true(panel.expanded)
	_key(KEY_I)
	assert_false(panel.expanded)


func test_a_building_the_log_does_not_follow_hides_the_panel() -> void:
	var view: MapView = await _view()
	var cell: Vector2i = _build(view, &"housing")
	_select(view, cell)
	assert_false((view.get("_why_panel") as WhyPanel).visible, "a house has no jobs, so no cause events")


func test_the_why_texts_are_translated_in_both_languages() -> void:
	var event: Dictionary = {"second": 1, "kind": &"building", "subject": &"mill@1,1", "cause": CauseLog.INTERMITTENT,
		"count": 3}
	var lines: Array[String] = []
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		for key: StringName in [Strings.WHY_PRUNED, Strings.WHY_BUTTON, Strings.OVERLAY_CAPTION, &"ui.reason.gone"]:
			assert_ne(Strings.text(key), String(key), "%s has a %s text" % [key, locale])
		lines.append(WhyPanel.line(event))
	assert_ne(lines[0], lines[1])
