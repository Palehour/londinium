extends GutTest


func _fixture(has_cultivable_cells: bool) -> Node2D:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1152, 800)
	add_child_autofree(viewport)
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	viewport.add_child(scene)
	var view: Node2D = scene.get_node("Map") as Node2D
	(view.get("clock") as SimClock).speed = 0
	var session: GameSession = view.get("session") as GameSession
	var map: MapDef = MapDef.new()
	map.width = 8
	map.height = 8
	if has_cultivable_cells:
		map.cultivable_cells.append(Vector2i(2, 2))
	session.context.map = map
	view.call("_update_help")
	return view


func _press(view: Node2D, key: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = key
	event.pressed = true
	view.call("_unhandled_input", event)


func test_no_cultivable_cells_disables_help_and_shortcut_with_same_reason() -> void:
	var view: Node2D = _fixture(false)
	var help: String = (view.get("_help") as Label).text
	assert_string_contains(help, "desactivado")
	assert_string_contains(help, "Este mapa no tiene casillas cultivables.")
	_press(view, KEY_2)
	assert_eq(view.get("_building_type"), &"mill")
	_press(view, KEY_5)
	assert_eq(view.get("_building_type"), &"")
	var reason: String = (view.get("_status") as Label).text
	assert_eq(reason, "Este mapa no tiene casillas cultivables.")
	assert_string_contains(help, reason)
	var session: GameSession = view.get("session") as GameSession
	var geometry: MapGeometry = view.get("geometry") as MapGeometry
	var presentation: MapPresentation = view.get("presentation") as MapPresentation
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = geometry.cell_to_screen(Vector2i(2, 2)) + Vector2(0, presentation.layout["header_height"])
	view.call("_unhandled_input", click)
	session.simulation.tick()
	session.publish_tick()
	assert_true(session.get_snapshot()["economy"]["buildings"].is_empty())


func test_cultivable_cells_keep_normal_help_and_construction_mode() -> void:
	var view: Node2D = _fixture(true)
	var help: String = (view.get("_help") as Label).text
	assert_string_contains(help, "5 Campo de trigo")
	assert_false(help.contains("desactivado"))
	assert_false(help.contains("Este mapa no tiene casillas cultivables."))
	_press(view, KEY_5)
	assert_eq(view.get("_building_type"), &"wheat_field")
	assert_ne((view.get("_status") as Label).text, "Este mapa no tiene casillas cultivables.")
