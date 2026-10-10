extends GutTest


class FixtureView extends "res://src/game/map_view/map_view.gd":
	var fixture_catalog: DataLoadResult


	func _load_catalog() -> DataLoadResult:
		return fixture_catalog


func _fixture(has_cultivable_cells: bool, changed_tags: bool = false) -> Node2D:
	var documents: Dictionary[String, Dictionary] = {}
	for folder: String in ["economy", "roles", "maps"]:
		for file_name: String in DirAccess.open("res://data/" + folder).get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
	documents["maps/whitechapel_1850s.json"]["cultivable_cells"] = [[2, 2]] if has_cultivable_cells else []
	if changed_tags:
		documents["economy/buildings.json"]["wheat_field"]["tags"].erase("cultivable")
		documents["economy/buildings.json"]["bakery"]["tags"].append("cultivable")
	var loaded: DataLoadResult = DataLoader.new().load_documents(documents)
	assert_true(loaded.is_ok(), str(loaded.errors))
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1152, 800)
	add_child_autofree(viewport)
	var view: FixtureView = FixtureView.new()
	view.fixture_catalog = loaded
	viewport.add_child(view)
	(view.get("clock") as SimClock).speed = 0
	return view


func _press(view: Node2D, key: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = key
	event.pressed = true
	view.call("_unhandled_input", event)


func _click(view: Node2D, cell: Vector2i) -> void:
	var geometry: MapGeometry = view.get("geometry") as MapGeometry
	var presentation: MapPresentation = view.get("presentation") as MapPresentation
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = geometry.cell_to_screen(cell) + Vector2(0, presentation.layout["header_height"])
	view.call("_unhandled_input", click)
	var session: GameSession = view.get("session") as GameSession
	session.simulation.tick()
	session.publish_tick()


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
	_click(view, Vector2i(2, 2))
	var session: GameSession = view.get("session") as GameSession
	var buildings: Array = session.get_snapshot()["economy"]["buildings"]
	assert_eq(buildings.size(), 1)
	if not buildings.is_empty():
		assert_eq(buildings[0]["definition_id"], &"wheat_field")
		assert_eq(buildings[0]["cell"], [2, 2])


func test_availability_tracks_changed_catalog_tags_instead_of_building_id() -> void:
	var view: Node2D = _fixture(false, true)
	var help: String = (view.get("_help") as Label).text
	assert_string_contains(help, "5 Campo de trigo\n")
	assert_string_contains(help, "3 Panadería (desactivado:")
	_press(view, KEY_5)
	assert_eq(view.get("_building_type"), &"wheat_field")
	_press(view, KEY_3)
	assert_eq(view.get("_building_type"), &"")
	assert_eq((view.get("_status") as Label).text, Strings.NO_CULTIVABLE_CELLS)
