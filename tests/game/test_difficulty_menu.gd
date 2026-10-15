extends GutTest


func test_menu_uses_data_steps_and_only_checked_overrides() -> void:
	Strings.use_default_locale()
	var menu: DifficultyMenu = DifficultyMenu.new()
	menu.configuration = {"preset": "hard", "knobs": {"reaction_seconds": 120}, "mods": []}
	add_child_autofree(menu)
	assert_eq(menu._preset.selected, 2)
	assert_eq((menu._knobs["reaction_seconds"] as SpinBox).step, 30.0)
	assert_eq(menu.selection()["knobs"], {"reaction_seconds": 120.0})
	assert_true(menu._preview().is_ok())
	assert_string_contains(menu._details.text, "800")
	menu._overrides["defeat_enabled"].button_pressed = true
	(menu._knobs["defeat_enabled"] as CheckBox).button_pressed = false
	assert_eq(menu.selection()["knobs"]["defeat_enabled"], false)


func test_menu_reports_validation_error_without_starting_game() -> void:
	Strings.use_default_locale()
	var menu: DifficultyMenu = DifficultyMenu.new()
	menu.configuration = {"mods": []}
	add_child_autofree(menu)
	menu._overrides["reaction_seconds"].button_pressed = true
	var spin: SpinBox = menu._knobs["reaction_seconds"] as SpinBox
	spin.step = 1
	spin.value = 61
	assert_false(menu._preview().is_ok())
	assert_string_contains(menu._details.text, "reaction_seconds")


func test_menu_reorders_mods_and_omits_disabled_ones() -> void:
	var menu: DifficultyMenu = DifficultyMenu.new()
	add_child_autofree(menu)
	menu._mods.clear()
	for name: String in ["first", "second"]:
		var index: int = menu._mods.add_item(name)
		menu._mods.set_item_metadata(index, {"name": name, "enabled": true})
	menu._mods.select(0)
	menu._move(1)
	assert_eq(menu.selection()["mods"], ["second", "first"])
	var item: Dictionary = menu._mods.get_item_metadata(0)
	item["enabled"] = false
	assert_eq(menu.selection()["mods"], ["first"])


func test_map_menu_button_is_visible_and_pauses_until_cancel() -> void:
	var scene: PackedScene = load("res://src/game/map_view/map_view.tscn")
	var view: Node2D = scene.instantiate()
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1200, 900)
	add_child_autofree(viewport)
	viewport.add_child(view)
	var button: Button = view.find_child("DifficultyButton", true, false) as Button
	assert_not_null(button)
	assert_true(view.get_viewport_rect().encloses(button.get_global_rect()), str(button.get_global_rect()))
	button.pressed.emit()
	assert_eq(view.get("clock").speed, 0)
	var menu: DifficultyMenu
	for child: Node in button.get_parent().get_children():
		if child is DifficultyMenu:
			menu = child as DifficultyMenu
	assert_not_null(menu)
	menu.canceled.emit()
	assert_eq(view.get("clock").speed, 1)


func test_start_configuration_creates_new_session_with_selected_values() -> void:
	var scene: PackedScene = load("res://src/game/map_view/map_view.tscn")
	var view: Node2D = scene.instantiate()
	add_child_autofree(view)
	view.call("_start_configuration", {"preset": "hard", "mods": []})
	var replacement: Node = get_child(get_child_count() - 1)
	autofree(replacement)
	var session: GameSession = replacement.get("session")
	assert_eq(session.get_snapshot()["economy"]["money"], 800)
	assert_eq(replacement.get("configuration")["preset"], "hard")
