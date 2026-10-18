extends GutTest

# Gamepad on the map (issue #68, D-048; hold to demolish, issue #164, D-078): the d-pad moves a cell cursor, the
# bumpers pick the building, A builds, holding X demolishes, B goes back to selecting, Menu moves to the panel and
# View pauses. The stick and the triggers move and zoom the camera. The help shows the gamepad buttons while the
# player uses one.

const ROOT: String = "user://test_gamepad_map"

var _viewport: SubViewport
var _resolved: int = 0
var _accepted: int = 0


func before_each() -> void:
	_remove(ROOT)
	_resolved = 0
	_accepted = 0


func after_each() -> void:
	for action: StringName in [&"map_pan_right", &"map_zoom_in", &"map_demolish"]:
		Input.action_release(action)
	Strings.use_default_locale()
	_remove(ROOT)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


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


func _geometry(view: Node2D) -> MapGeometry:
	return view.get("geometry") as MapGeometry


func _session(view: Node2D) -> GameSession:
	return view.get("session") as GameSession


func _panel(view: Node2D) -> StatsPanel:
	return view.get("_stats_panel") as StatsPanel


func _tick(view: Node2D) -> void:
	_session(view).simulation.tick()
	_session(view).publish_tick()


func _building_at(view: Node2D, cell: Vector2i) -> StringName:
	for building: Dictionary in _session(view).get_snapshot()["economy"]["buildings"]:
		if building["cell"] == [cell.x, cell.y]:
			return StringName(building["definition_id"])
	return &""


# A land cell with nothing on it, so a house can go there.
func _free_land_cell(view: Node2D) -> Vector2i:
	var map: MapDef = _session(view).context.map
	for y: int in range(map.height):
		for x: int in range(map.width):
			var cell: Vector2i = Vector2i(x, y)
			if _geometry(view).terrain_at(cell, map) == "land" and _building_at(view, cell) == &"":
				return cell
	return Vector2i(-1, -1)


# Bounded, so a cursor that does not move fails the test instead of hanging it.
func _move_cursor_to(view: Node2D, target: Vector2i) -> void:
	var map: MapDef = _session(view).context.map
	_pad(JOY_BUTTON_DPAD_UP)
	for press: int in range(map.width + map.height):
		var selected: Vector2i = _geometry(view).selected
		if selected.x < target.x:
			_pad(JOY_BUTTON_DPAD_RIGHT)
		elif selected.x > target.x:
			_pad(JOY_BUTTON_DPAD_LEFT)
		elif selected.y < target.y:
			_pad(JOY_BUTTON_DPAD_DOWN)
		elif selected.y > target.y:
			_pad(JOY_BUTTON_DPAD_UP)
	assert_eq(_geometry(view).selected, target)


func _build_housing(view: Node2D) -> Vector2i:
	var cell: Vector2i = _free_land_cell(view)
	assert_ne(cell, Vector2i(-1, -1))
	_move_cursor_to(view, cell)
	_pick(view, &"housing")
	_pad(JOY_BUTTON_A)
	_tick(view)
	assert_eq(_building_at(view, cell), &"housing")
	return cell


func _money(view: Node2D) -> int:
	return int(_session(view).get_snapshot()["economy"]["money"])


func _listen(view: Node2D) -> void:
	_resolved = 0
	_accepted = 0
	_session(view).command_resolved.connect(_count_resolved)


func _count_resolved(accepted: bool, _reason: StringName) -> void:
	_resolved += 1
	if accepted:
		_accepted += 1


func _press_x() -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_X
	event.pressed = true
	_viewport.push_input(event)
	Input.action_press(&"map_demolish")


func _release_x() -> void:
	Input.action_release(&"map_demolish")
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_X
	event.pressed = false
	_viewport.push_input(event)


func _hold_seconds(view: Node2D) -> float:
	var input: Variant = (view.get("presentation") as MapPresentation).get("input")
	assert_true(input is Dictionary, "demolish_hold_seconds is loaded from data/ui/map.json")
	if not input is Dictionary:
		return 1.0
	return float((input as Dictionary)["demolish_hold_seconds"])


func _set_hold_seconds(view: Node2D, seconds: float) -> void:
	var input: Variant = (view.get("presentation") as MapPresentation).get("input")
	assert_true(input is Dictionary, "demolish_hold_seconds is loaded from data/ui/map.json")
	if input is Dictionary:
		(input as Dictionary)["demolish_hold_seconds"] = seconds


func _progress(view: Node2D) -> float:
	var progress: Variant = view.get("_demolish_progress")
	assert_eq(typeof(progress), TYPE_FLOAT, "The ring reads _demolish_progress")
	if typeof(progress) != TYPE_FLOAT:
		return -1.0
	return float(progress)


func _pick(view: Node2D, type: StringName) -> void:
	for press: int in range(view.get("TYPES").size() + 1):
		if view.get("_building_type") == type:
			return
		_pad(JOY_BUTTON_RIGHT_SHOULDER)


func test_dpad_moves_cursor_and_camera_follows() -> void:
	var view: Node2D = await _view()
	var geometry: MapGeometry = _geometry(view)
	assert_eq(geometry.selected, Vector2i(-1, -1))
	_pad(JOY_BUTTON_DPAD_RIGHT)
	var start: Vector2i = geometry.screen_to_cell(geometry.viewport_size / 2.0)
	assert_eq(geometry.selected, start, "The first press puts the cursor in the middle of the view")
	_pad(JOY_BUTTON_DPAD_RIGHT)
	_pad(JOY_BUTTON_DPAD_DOWN)
	assert_eq(geometry.selected, start + Vector2i(1, 1))
	geometry.zoom = geometry.minimum_zoom() * geometry.max_zoom_factor
	geometry.constrain()
	for press: int in range(16):
		_pad(JOY_BUTTON_DPAD_LEFT)
	assert_eq(geometry.selected.x, 0, "The cursor stops at the edge of the map")
	var screen: Vector2 = geometry.cell_to_screen(geometry.selected)
	assert_true(Rect2(Vector2.ZERO, geometry.viewport_size).has_point(screen), "The camera follows the cursor")


func test_bumpers_cycle_available_buildings() -> void:
	var view: Node2D = await _view()
	var session: GameSession = _session(view)
	var seen: Array[StringName] = []
	for press: int in range(view.get("TYPES").size() + 1):
		_pad(JOY_BUTTON_RIGHT_SHOULDER)
		seen.append(view.get("_building_type"))
	assert_true(&"housing" in seen)
	for type: StringName in seen:
		if type != &"":
			assert_eq(session.get_building_unavailable_reason(type), &"", "Unavailable buildings are skipped: %s" % type)
	assert_true(&"" in seen, "The cycle passes through selecting")
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	var forward: StringName = view.get("_building_type")
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	_pad(JOY_BUTTON_LEFT_SHOULDER)
	assert_eq(view.get("_building_type"), forward, "LB goes back one")


func test_a_builds_at_cursor() -> void:
	var view: Node2D = await _view()
	var cell: Vector2i = _free_land_cell(view)
	assert_ne(cell, Vector2i(-1, -1))
	_move_cursor_to(view, cell)
	_pick(view, &"housing")
	_pad(JOY_BUTTON_A)
	_tick(view)
	assert_eq(_building_at(view, cell), &"housing")


func test_releasing_x_before_the_hold_demolishes_nothing() -> void:
	var view: Node2D = await _view()
	view.set_process(false)
	var cell: Vector2i = _build_housing(view)
	var money: int = _money(view)
	_listen(view)
	_press_x()
	assert_false(_session(view).simulation.has_queued_commands(), "Pressing X does not demolish")
	var seconds: float = _hold_seconds(view)
	view.call("_process", seconds * 0.4)
	assert_false(_session(view).simulation.has_queued_commands())
	assert_almost_eq(_progress(view), 0.4, 0.001)
	_release_x()
	view.call("_process", seconds)
	assert_eq(_progress(view), 0.0)
	_tick(view)
	assert_eq(_building_at(view, cell), &"housing")
	assert_eq(_money(view), money)
	assert_eq(_resolved, 0)


func test_holding_x_demolishes_once() -> void:
	var view: Node2D = await _view()
	view.set_process(false)
	var cell: Vector2i = _build_housing(view)
	_listen(view)
	_press_x()
	assert_false(_session(view).simulation.has_queued_commands(), "Pressing X does not demolish")
	var seconds: float = _hold_seconds(view)
	view.call("_process", seconds * 3.0)
	assert_eq(_progress(view), 0.0, "The ring clears once the demolish is sent")
	assert_true(_session(view).simulation.has_queued_commands())
	view.call("_process", seconds * 3.0)
	_tick(view)
	assert_eq(_building_at(view, cell), &"")
	assert_eq(_resolved, 1, "Holding longer still demolishes once")
	assert_eq(_accepted, 1)
	assert_false(_session(view).simulation.has_queued_commands())
	view.call("_process", seconds * 3.0)
	assert_false(_session(view).simulation.has_queued_commands(), "Keeping X down does not demolish again")
	_release_x()
	view.call("_process", 0.0)
	_press_x()
	view.call("_process", seconds)
	assert_true(_session(view).simulation.has_queued_commands(), "A new press can demolish again")


func test_moving_the_cursor_while_holding_x_cancels() -> void:
	var view: Node2D = await _view()
	view.set_process(false)
	var cell: Vector2i = _build_housing(view)
	var money: int = _money(view)
	_listen(view)
	_press_x()
	assert_false(_session(view).simulation.has_queued_commands(), "Pressing X does not demolish")
	var seconds: float = _hold_seconds(view)
	view.call("_process", seconds * 0.4)
	var geometry: MapGeometry = _geometry(view)
	var selected: Vector2i = geometry.selected
	_pad(JOY_BUTTON_DPAD_RIGHT)
	if geometry.selected == selected:
		_pad(JOY_BUTTON_DPAD_LEFT)
	assert_ne(geometry.selected, selected, "The cursor has to move for this test")
	view.call("_process", seconds)
	_tick(view)
	assert_eq(_building_at(view, cell), &"housing")
	assert_eq(_money(view), money)
	assert_eq(_resolved, 0)
	assert_eq(_progress(view), 0.0)


func test_panning_while_holding_x_still_demolishes() -> void:
	var view: Node2D = await _view()
	view.set_process(false)
	var cell: Vector2i = _build_housing(view)
	_listen(view)
	_press_x()
	assert_false(_session(view).simulation.has_queued_commands(), "Pressing X does not demolish")
	Input.action_press(&"map_pan_right")
	view.call("_process", _hold_seconds(view))
	_tick(view)
	assert_eq(_building_at(view, cell), &"")
	assert_eq(_resolved, 1)
	assert_eq(_accepted, 1)


func test_opening_the_panel_while_holding_x_cancels() -> void:
	var view: Node2D = await _view()
	view.set_process(false)
	var cell: Vector2i = _build_housing(view)
	var money: int = _money(view)
	_listen(view)
	_press_x()
	assert_false(_session(view).simulation.has_queued_commands(), "Pressing X does not demolish")
	var seconds: float = _hold_seconds(view)
	view.call("_process", seconds * 0.4)
	_pad(JOY_BUTTON_START)
	view.call("_process", seconds)
	_tick(view)
	assert_eq(_building_at(view, cell), &"housing")
	assert_eq(_money(view), money)
	assert_eq(_resolved, 0)
	assert_eq(_progress(view), 0.0)


func test_hold_duration_comes_from_data() -> void:
	var view: Node2D = await _view()
	view.set_process(false)
	var cell: Vector2i = _build_housing(view)
	_listen(view)
	_press_x()
	assert_false(_session(view).simulation.has_queued_commands(), "Pressing X does not demolish")
	_set_hold_seconds(view, 2.0)
	view.call("_process", 1.9)
	assert_false(_session(view).simulation.has_queued_commands(), "1.9 s is short of the 2 s set for this test")
	assert_eq(_building_at(view, cell), &"housing")
	view.call("_process", 0.2)
	assert_true(_session(view).simulation.has_queued_commands())
	view.call("_process", 5.0)
	_tick(view)
	assert_eq(_resolved, 1, "A longer hold still sends one demolish")
	assert_eq(_accepted, 1)
	assert_eq(_building_at(view, cell), &"")


func test_delete_still_demolishes_on_press() -> void:
	var view: Node2D = await _view()
	view.set_process(false)
	var cell: Vector2i = _build_housing(view)
	_listen(view)
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_DELETE
	key.pressed = true
	_viewport.push_input(key)
	assert_true(_session(view).simulation.has_queued_commands(), "Delete demolishes without waiting")
	_tick(view)
	assert_eq(_building_at(view, cell), &"")
	assert_eq(_resolved, 1)
	assert_eq(_accepted, 1)


func test_gamepad_help_says_to_hold_x() -> void:
	Strings.set_locale("es")
	assert_string_contains(Strings.text(Strings.HELP_GAMEPAD), "mantener X")
	assert_string_contains(Strings.text(Strings.HELP), "Supr: demoler")
	Strings.set_locale("en")
	assert_string_contains(Strings.text(Strings.HELP_GAMEPAD), "hold X")
	assert_string_contains(Strings.text(Strings.HELP), "Del: demolish")


func test_b_clears_building_type() -> void:
	var view: Node2D = await _view()
	_pick(view, &"housing")
	_pad(JOY_BUTTON_B)
	assert_eq(view.get("_building_type"), &"")


func test_menu_enters_panel_and_b_returns() -> void:
	var view: Node2D = await _view()
	var panel: StatsPanel = _panel(view)
	_pad(JOY_BUTTON_START)
	var focused: Control = _viewport.gui_get_focus_owner()
	assert_not_null(focused)
	assert_true(focused != null and panel.is_ancestor_of(focused), "Menu puts the focus in the panel")
	_pad(JOY_BUTTON_B)
	assert_null(_viewport.gui_get_focus_owner(), "B goes back to the map")
	_pad(JOY_BUTTON_START)
	_pad(JOY_BUTTON_START)
	assert_null(_viewport.gui_get_focus_owner(), "Menu again goes back to the map")


func test_view_toggles_pause() -> void:
	var view: Node2D = await _view()
	var clock: SimClock = view.get("clock") as SimClock
	clock.speed = 1
	_pad(JOY_BUTTON_BACK)
	assert_eq(clock.speed, 0)
	_pad(JOY_BUTTON_BACK)
	assert_eq(clock.speed, 1)


func test_stick_pans_and_triggers_zoom() -> void:
	var view: Node2D = await _view()
	view.set_process(false)
	var geometry: MapGeometry = _geometry(view)
	var zoom: float = geometry.zoom
	Input.action_press(&"map_zoom_in")
	view.call("_process", 0.0)
	Input.action_release(&"map_zoom_in")
	assert_gt(geometry.zoom, zoom, "RT zooms in")
	# At the widest zoom the whole map is in view and the camera has nowhere to go.
	geometry.zoom = geometry.minimum_zoom() * geometry.max_zoom_factor
	geometry.constrain()
	var center: Vector2 = geometry.center
	Input.action_press(&"map_pan_right")
	view.call("_process", 0.5)
	Input.action_release(&"map_pan_right")
	assert_gt(geometry.center.x, center.x, "The stick moves the camera")


func _labels(view: Node2D) -> Array[String]:
	var presentation: MapPresentation = view.get("presentation") as MapPresentation
	var labels: Array[String] = []
	for id: StringName in view.get("TYPES"):
		var reason: String = presentation.building_unavailable_reason(_session(view).get_building_unavailable_reason(id))
		labels.append(presentation.labels[id] if reason.is_empty() else Strings.text(Strings.DISABLED_BUILDING) % [presentation.labels[id], reason])
	return labels


func test_help_switches_to_gamepad_glyphs_and_back() -> void:
	var view: Node2D = await _view()
	var help: Label = view.get("_help") as Label
	assert_eq(help.text, Strings.text(Strings.HELP) % _labels(view))
	_pad(JOY_BUTTON_DPAD_UP)
	assert_eq(help.text, Strings.text(&"ui.help_gamepad") % _labels(view))
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_W
	key.pressed = true
	_viewport.push_input(key)
	assert_eq(help.text, Strings.text(Strings.HELP) % _labels(view))


# The player's streets (issue #168, D-080): one more entry of the LB/RB cycle on a map with streets; A puts one cell
# down and holding X takes it away like a building.
func _street_at(view: Node2D, cell: Vector2i) -> bool:
	return [cell.x, cell.y] in _session(view).get_snapshot()["distance"]["player_roads"]


func _pick_street(view: Node2D) -> void:
	for press: int in range(view.get("TYPES").size() + 2):
		if view.get("_building_type") == view.get("ROAD"):
			return
		_pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_eq(view.get("_building_type"), view.get("ROAD"), "The cycle reaches the street")


func _place_street(view: Node2D) -> Vector2i:
	var cell: Vector2i = _free_land_cell(view)
	assert_ne(cell, Vector2i(-1, -1))
	_move_cursor_to(view, cell)
	_pick_street(view)
	_pad(JOY_BUTTON_A)
	_tick(view)
	assert_true(_street_at(view, cell), "A puts a street on the cursor")
	return cell


func test_bumpers_cycle_includes_the_street() -> void:
	var view: Node2D = await _view()
	assert_true(_session(view).context.map.roads_enabled, "The game plays the strip, which has streets")
	_pick_street(view)
	var mode: Label = view.get("_mode") as Label
	assert_string_contains(mode.text, Strings.text(Strings.ROAD))
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_eq(view.get("_building_type"), &"", "After the street the cycle goes back to selecting")
	_pad(JOY_BUTTON_LEFT_SHOULDER)
	assert_eq(view.get("_building_type"), view.get("ROAD"), "LB from selecting goes back to the street")


func test_a_places_a_street_at_cursor() -> void:
	var view: Node2D = await _view()
	_listen(view)
	var cell: Vector2i = _place_street(view)
	assert_eq(_accepted, 1)
	assert_eq(_building_at(view, cell), &"", "A street is not a building")


func test_holding_x_demolishes_a_player_street() -> void:
	var view: Node2D = await _view()
	view.set_process(false)
	var cell: Vector2i = _place_street(view)
	_listen(view)
	_press_x()
	view.call("_process", _hold_seconds(view) * 2.0)
	_release_x()
	_tick(view)
	assert_false(_street_at(view, cell), "Holding X demolishes the player's street")
	assert_eq(_accepted, 1)


func test_key_9_and_click_place_a_street() -> void:
	var view: Node2D = await _view()
	var cell: Vector2i = _free_land_cell(view)
	assert_ne(cell, Vector2i(-1, -1))
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_9
	key.pressed = true
	_viewport.push_input(key)
	assert_eq(view.get("_building_type"), view.get("ROAD"), "9 picks the street")
	var presentation: MapPresentation = view.get("presentation") as MapPresentation
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = _geometry(view).cell_to_screen(cell) + Vector2(0, presentation.layout["header_height"])
	_viewport.push_input(click)
	_tick(view)
	assert_true(_street_at(view, cell), "A click puts the street down")


func test_help_names_the_street() -> void:
	var view: Node2D = await _view()
	var help: Label = view.get("_help") as Label
	assert_string_contains(help.text, Strings.text(Strings.ROAD))
	_pad(JOY_BUTTON_DPAD_UP)
	assert_string_contains(help.text, Strings.text(Strings.ROAD))


# D-082: with the keyboard, Delete takes a player street away at once, like a building.
func test_delete_demolishes_a_player_street() -> void:
	var view: Node2D = await _view()
	view.set_process(false)
	var cell: Vector2i = _place_street(view)
	_listen(view)
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_DELETE
	key.pressed = true
	_viewport.push_input(key)
	_tick(view)
	assert_false(_street_at(view, cell), "Delete demolishes the player's street")
	assert_eq(_accepted, 1)
