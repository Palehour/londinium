extends GutTest

# Gamepad on the map (issue #68, D-048): the d-pad moves a cell cursor, the bumpers pick the building, A builds,
# X demolishes, B goes back to selecting, Menu moves to the panel and View pauses. The stick and the triggers move
# and zoom the camera. The help shows the gamepad buttons while the player uses one.

const ROOT: String = "user://test_gamepad_map"

var _viewport: SubViewport


func before_each() -> void:
	_remove(ROOT)


func after_each() -> void:
	for action: StringName in [&"map_pan_right", &"map_zoom_in"]:
		Input.action_release(action)
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


func test_a_builds_at_cursor_and_x_demolishes() -> void:
	var view: Node2D = await _view()
	var cell: Vector2i = _free_land_cell(view)
	assert_ne(cell, Vector2i(-1, -1))
	_move_cursor_to(view, cell)
	_pick(view, &"housing")
	_pad(JOY_BUTTON_A)
	_tick(view)
	assert_eq(_building_at(view, cell), &"housing")
	_pad(JOY_BUTTON_X)
	_tick(view)
	assert_eq(_building_at(view, cell), &"")


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
