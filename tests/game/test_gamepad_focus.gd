extends GutTest

# Focus navigation with a gamepad (issue #68, D-048): every control of the panel, the saves menu and the mods menu
# can be reached with the d-pad and used with A or left and right. The mouse keeps today's behaviour: buttons only
# take the focus while the player is in the panel with a gamepad.

const ROOT: String = "user://test_gamepad_focus"

var _viewport: SubViewport


func before_each() -> void:
	_remove(ROOT)


func after_each() -> void:
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


func _panel(view: Node2D) -> StatsPanel:
	return view.get("_stats_panel") as StatsPanel


func _session(view: Node2D) -> GameSession:
	return view.get("session") as GameSession


func _tick(view: Node2D) -> void:
	_session(view).simulation.tick()
	_session(view).publish_tick()


# Every control the d-pad reaches from `start`, following the same neighbours the engine uses.
func _reachable(start: Control) -> Array[Control]:
	var seen: Array[Control] = [start]
	var index: int = 0
	while index < seen.size():
		for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			var next: Control = seen[index].find_valid_focus_neighbor(side)
			if next != null and next not in seen:
				seen.append(next)
		index += 1
	return seen


func test_enter_focus_focuses_first_visible_control() -> void:
	var view: Node2D = await _view()
	var panel: StatsPanel = _panel(view)
	assert_null(_viewport.gui_get_focus_owner())
	panel.call("enter_focus")
	assert_true(panel.call("is_focused"))
	assert_eq(_viewport.gui_get_focus_owner(), panel.get("_locale_es"), "The first visible control takes the focus")


func test_enter_focus_starts_on_restart_when_defeated() -> void:
	var view: Node2D = await _view()
	var panel: StatsPanel = _panel(view)
	var restart: Button = panel.get("_restart") as Button
	restart.visible = true
	panel.call("enter_focus")
	assert_eq(_viewport.gui_get_focus_owner(), restart)


func test_every_panel_control_is_reachable() -> void:
	var view: Node2D = await _view()
	var panel: StatsPanel = _panel(view)
	panel.call("enter_focus")
	var reached: Array[Control] = _reachable(_viewport.gui_get_focus_owner())
	var expected: Array[Control] = []
	for field: String in ["_locale_es", "_locale_en", "_wheat", "_tea", "_flour", "_unloading", "_accumulate_on",
			"_limit_on", "_target", "_reserve", "_pause"]:
		expected.append(panel.get(field) as Control)
	for field: String in ["_tax", "_accumulate_price", "_limit_price"]:
		expected.append((panel.get(field) as SpinBox).get_line_edit())
	for button: Button in (panel.get("_speed_buttons") as Dictionary).values():
		expected.append(button)
	for button: Button in (panel.get("_difficulty_buttons") as Dictionary).values():
		expected.append(button)
	for node: Node in (panel.get("_saves_menu") as Node).find_children("*", "Button", true, false):
		expected.append(node as Control)
	for control: Control in expected:
		assert_true(control in reached, "The d-pad reaches %s" % control)


func test_leave_focus_restores_mouse_behaviour() -> void:
	var view: Node2D = await _view()
	var panel: StatsPanel = _panel(view)
	panel.call("enter_focus")
	panel.call("leave_focus")
	assert_false(panel.call("is_focused"))
	assert_null(_viewport.gui_get_focus_owner())
	for node: Node in panel.find_children("*", "BaseButton", true, false):
		assert_eq((node as Control).focus_mode, Control.FOCUS_NONE, "A click never keeps the focus: %s" % node)
	for field: String in ["_target", "_reserve", "_unloading"]:
		assert_eq((panel.get(field) as Control).focus_mode, Control.FOCUS_NONE)


func test_clicking_the_map_leaves_the_panel() -> void:
	var view: Node2D = await _view()
	var panel: StatsPanel = _panel(view)
	panel.call("enter_focus")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = Vector2(100, 400)
	click.pressed = true
	_viewport.push_input(click)
	assert_false(panel.call("is_focused"))


func test_a_presses_the_focused_button() -> void:
	var view: Node2D = await _view()
	var panel: StatsPanel = _panel(view)
	var clock: SimClock = view.get("clock") as SimClock
	clock.speed = 1
	panel.call("enter_focus")
	(panel.get("_pause") as Control).grab_focus()
	_pad(JOY_BUTTON_A)
	assert_eq(clock.speed, 0)


func test_dpad_on_sliders_submits_policy() -> void:
	var view: Node2D = await _view()
	var panel: StatsPanel = _panel(view)
	panel.call("enter_focus")
	var market: Dictionary = _session(view).get_snapshot()["market"]
	var target: int = int(market["wheat"]["target_stock"])
	var target_slider: HSlider = panel.get("_target") as HSlider
	target_slider.grab_focus()
	var expected: int = target + 1
	if target >= int(target_slider.max_value):
		expected = target - 1
		_pad(JOY_BUTTON_DPAD_LEFT)
	else:
		_pad(JOY_BUTTON_DPAD_RIGHT)
	(panel.get("_unloading") as Control).grab_focus()
	_pad(JOY_BUTTON_DPAD_RIGHT)
	_tick(view)
	market = _session(view).get_snapshot()["market"]
	assert_eq(int(market["wheat"]["target_stock"]), expected, "The target slider sends the new stock")
	assert_eq(int(market["barley"]["barley_percent"]), int(market["barley"]["step_percent"]), "The split moves one notch")


func test_dpad_on_tax_changes_tax() -> void:
	var view: Node2D = await _view()
	var panel: StatsPanel = _panel(view)
	panel.call("enter_focus")
	var tax: SpinBox = panel.get("_tax") as SpinBox
	var before: float = tax.value
	tax.get_line_edit().grab_focus()
	_pad(JOY_BUTTON_DPAD_RIGHT)
	_tick(view)
	var rate: float = float(_session(view).get_snapshot()["economy"]["tax_rate"])
	assert_almost_eq(rate * 100.0, before + tax.step, 0.001)
	assert_eq(_viewport.gui_get_focus_owner(), tax.get_line_edit(), "Right changes the number instead of moving away")


func _entry(path: String, tick: int) -> Dictionary:
	return {"path": path, "kind": &"manual", "slot": 0, "tick": tick, "saved_at": "2026-10-17 10:00"}


func test_saves_menu_keeps_focus_after_rebuild() -> void:
	var menu: SavesMenu = SavesMenu.new()
	add_child_autofree(menu)
	menu.set("focusable", true)
	var entries: Array[Dictionary] = [_entry("user://a.save", 60), _entry("user://b.save", 120)]
	menu.show_saves(entries)
	var buttons: Array[Node] = menu.find_children("*", "Button", true, false)
	(buttons[2] as Control).grab_focus()
	menu.show_saves(entries, "saved")
	await get_tree().process_frame
	buttons = menu.find_children("*", "Button", true, false)
	assert_eq(menu.get_viewport().gui_get_focus_owner(), buttons[2], "The focus stays on the same button")


func test_mods_menu_keeps_focus_after_reorder() -> void:
	var menu: ModsMenu = ModsMenu.new()
	add_child_autofree(menu)
	menu.set("focusable", true)
	var no_conflicts: Array[Dictionary] = []
	menu.show_mods([&"first", &"second"], no_conflicts, "")
	var buttons: Array[Node] = menu.find_children("*", "Button", true, false)
	(buttons[1] as Control).grab_focus()
	menu.show_mods([&"second", &"first"], no_conflicts, "")
	await get_tree().process_frame
	buttons = menu.find_children("*", "Button", true, false)
	var focused: Control = menu.get_viewport().gui_get_focus_owner()
	assert_not_null(focused)
	assert_true(focused in buttons, "The focus stays in the mods menu")


func test_menus_buttons_are_not_focusable_with_the_mouse() -> void:
	var menu: SavesMenu = SavesMenu.new()
	add_child_autofree(menu)
	menu.show_saves([_entry("user://a.save", 60)])
	for node: Node in menu.find_children("*", "Button", true, false):
		assert_eq((node as Control).focus_mode, Control.FOCUS_NONE)
