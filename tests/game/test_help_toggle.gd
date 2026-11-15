extends GutTest

# The help and the two legends fold away (issue #382): closed by default, H or the panel's Help button opens and closes
# them, and the mode, the status and the credits never hide.

const ROOT: String = "user://test_help_toggle"

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


func _press_h() -> void:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_H
	key.pressed = true
	_viewport.push_input(key)


func _always_visible(view: Node2D) -> void:
	for name: String in ["_mode", "_status", "_credits", "_help_hint"]:
		assert_true((view.get(name) as Label).is_visible_in_tree(), "%s stays visible" % name)


func test_help_and_legends_start_closed() -> void:
	var view: Node2D = await _view()
	assert_false((view.get("_help") as Label).is_visible_in_tree())
	assert_false((view.get("_legend_caption") as Label).is_visible_in_tree())
	assert_false((view.get("_lots_caption") as Label).is_visible_in_tree())
	_always_visible(view)
	assert_ne((view.get("_help_hint") as Label).text, "")


func test_h_opens_and_closes_the_help() -> void:
	var view: Node2D = await _view()
	_press_h()
	assert_true((view.get("_help") as Label).is_visible_in_tree())
	assert_true((view.get("_legend_caption") as Label).is_visible_in_tree())
	assert_true((view.get("_lots_caption") as Label).is_visible_in_tree())
	_always_visible(view)
	_press_h()
	assert_false((view.get("_help") as Label).is_visible_in_tree())


func test_the_panel_button_opens_and_closes_the_help() -> void:
	var view: Node2D = await _view()
	var panel: StatsPanel = view.get("_stats_panel") as StatsPanel
	var button: Button = panel.get("_help_button") as Button
	assert_eq(button.text, Strings.text(Strings.HELP_BUTTON))
	button.pressed.emit()
	assert_true((view.get("_help") as Label).is_visible_in_tree())
	_always_visible(view)
	button.pressed.emit()
	assert_false((view.get("_help") as Label).is_visible_in_tree())


func test_hint_fits_one_line_in_both_languages_and_inputs() -> void:
	var view: Node2D = await _view()
	var presentation: MapPresentation = view.get("presentation") as MapPresentation
	var room: float = 1280.0 - presentation.layout["panel_width"] - presentation.layout["help_x"]
	var hint: Label = view.get("_help_hint") as Label
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		for gamepad: bool in [false, true]:
			view.set("_gamepad", gamepad)
			view.call("_update_help")
			await get_tree().process_frame
			assert_lte(hint.get_minimum_size().x, room, "Hint width (%s, gamepad %s)" % [locale, gamepad])
			assert_eq(hint.get_line_count(), 1, "Hint is one line")


func test_the_gamepad_help_names_water_and_cemetery() -> void:
	var view: Node2D = await _view()
	view.set("_gamepad", true)
	view.call("_toggle_help")
	for pair: Array in [["es", "Agua", "Cementerio"], ["en", "Water", "Cemetery"]]:
		Strings.set_locale(str(pair[0]))
		view.call("_update_help")
		var text: String = (view.get("_help") as Label).text
		assert_string_contains(text, str(pair[1]))
		assert_string_contains(text, str(pair[2]))
