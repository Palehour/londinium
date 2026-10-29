extends GutTest

# Issue #186 (D-086): the cells below are the corners (2x, 2y) of the 2x2 blocks of the old cells of 50 m.


class FixtureView extends "res://src/game/map_view/map_view.gd":
	var fixture_catalog: DataLoadResult


	func _load_catalog() -> DataLoadResult:
		return fixture_catalog


# "%s (disabled: %s)" with an empty reason, without the closing parenthesis, so it matches the help prefix.
func _disabled_mark(building: String) -> String:
	return (Strings.text(Strings.DISABLED_BUILDING) % [building, ""]).trim_suffix(")").trim_suffix(" ")


func _fixture(has_cultivable_cells: bool, changed_tags: bool = false) -> Node2D:
	var documents: Dictionary[String, Dictionary] = {}
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "services"]:
		for file_name: String in DirAccess.open("res://data/" + folder).get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
	# The whole block, as a field of 2x2 needs (D-086).
	documents["maps/whitechapel_1850s.json"]["cultivable_cells"] = [[4, 4], [5, 4], [4, 5], [5, 5]] \
		if has_cultivable_cells else []
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
	var unavailable: String = Strings.text(Strings.NO_CULTIVABLE_CELLS)
	assert_string_contains(help, _disabled_mark(""))
	assert_string_contains(help, unavailable)
	_press(view, KEY_2)
	assert_eq(view.get("_building_type"), &"mill")
	_press(view, KEY_5)
	assert_eq(view.get("_building_type"), &"")
	var reason: String = (view.get("_status") as Label).text
	assert_eq(reason, unavailable)
	assert_string_contains(help, reason)
	var session: GameSession = view.get("session") as GameSession
	var geometry: MapGeometry = view.get("geometry") as MapGeometry
	var presentation: MapPresentation = view.get("presentation") as MapPresentation
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = geometry.cell_to_screen(Vector2i(4, 4)) + Vector2(0, presentation.layout["header_height"])
	view.call("_unhandled_input", click)
	session.simulation.tick()
	session.publish_tick()
	assert_true(session.get_snapshot()["economy"]["buildings"].is_empty())


func test_cultivable_cells_keep_normal_help_and_construction_mode() -> void:
	var view: Node2D = _fixture(true)
	var help: String = (view.get("_help") as Label).text
	assert_string_contains(help, "5 %s" % Strings.building_label("wheat_field"))
	assert_false(help.contains(_disabled_mark("")))
	assert_false(help.contains(Strings.text(Strings.NO_CULTIVABLE_CELLS)))
	_press(view, KEY_5)
	assert_eq(view.get("_building_type"), &"wheat_field")
	assert_ne((view.get("_status") as Label).text, Strings.text(Strings.NO_CULTIVABLE_CELLS))
	_click(view, Vector2i(4, 4))
	var session: GameSession = view.get("session") as GameSession
	var buildings: Array = session.get_snapshot()["economy"]["buildings"]
	assert_eq(buildings.size(), 1)
	if not buildings.is_empty():
		assert_eq(buildings[0]["definition_id"], &"wheat_field")
		assert_eq(buildings[0]["cell"], [4, 4])


func test_availability_tracks_changed_catalog_tags_instead_of_building_id() -> void:
	var view: Node2D = _fixture(false, true)
	var help: String = (view.get("_help") as Label).text
	assert_string_contains(help, "5 %s\n" % Strings.building_label("wheat_field"))
	assert_string_contains(help, "3 " + _disabled_mark(Strings.building_label("bakery")))
	_press(view, KEY_5)
	assert_eq(view.get("_building_type"), &"wheat_field")
	_press(view, KEY_3)
	assert_eq(view.get("_building_type"), &"")
	assert_eq((view.get("_status") as Label).text, Strings.text(Strings.NO_CULTIVABLE_CELLS))


# Issue #52: the housing of the artisans is the eighth building, so keys 1 to 7 keep their meaning.
func test_artisan_housing_is_built_from_key_eight() -> void:
	var view: Node2D = _fixture(false)
	var help: String = (view.get("_help") as Label).text
	assert_string_contains(help, "8 %s" % Strings.building_label("artisan_housing"))
	_press(view, KEY_8)
	assert_eq(view.get("_building_type"), &"artisan_housing")
	_click(view, Vector2i(8, 4))
	var buildings: Array = (view.get("session") as GameSession).get_snapshot()["economy"]["buildings"]
	assert_eq(buildings.size(), 1)
	assert_eq(buildings[0]["definition_id"], &"artisan_housing")


# Issue #51: the beer chain sits after wheat_field so keys 1 to 5 keep their meaning.
func test_malthouse_and_brewery_are_built_from_keys_six_and_seven() -> void:
	var view: Node2D = _fixture(false)
	var help: String = (view.get("_help") as Label).text
	assert_string_contains(help, "6 %s · 7 %s" % [Strings.building_label("malthouse"), Strings.building_label("brewery")])
	assert_false(help.contains("6 " + _disabled_mark(Strings.building_label("malthouse"))))
	_press(view, KEY_6)
	assert_eq(view.get("_building_type"), &"malthouse")
	_click(view, Vector2i(4, 4))
	_press(view, KEY_7)
	assert_eq(view.get("_building_type"), &"brewery")
	_click(view, Vector2i(6, 4))
	var buildings: Array = (view.get("session") as GameSession).get_snapshot()["economy"]["buildings"]
	assert_eq(buildings.size(), 2)
	assert_eq(buildings[0]["definition_id"], &"malthouse")
	assert_eq(buildings[1]["definition_id"], &"brewery")


func test_beer_buildings_availability_comes_from_the_catalog_tags_not_their_ids() -> void:
	var documents: Dictionary[String, Dictionary] = {}
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "services"]:
		for file_name: String in DirAccess.open("res://data/" + folder).get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
	documents["economy/buildings.json"]["brewery"]["tags"].append("river")
	# The river tag only explains the reason; where it stands now comes from the mask (D-149).
	documents["economy/buildings.json"]["brewery"]["terrain_mask"] = [["river", "river"], ["river", "river"]]
	documents["maps/whitechapel_1850s.json"]["river_cells"] = []
	var loaded: DataLoadResult = DataLoader.new().load_documents(documents)
	assert_true(loaded.is_ok(), str(loaded.errors))
	var context: EconomyContext = EconomyContext.new(loaded.catalog, loaded.catalog.maps[&"whitechapel_1850s"])
	assert_eq(context.building_unavailable_reason(&"malthouse"), &"")
	assert_eq(context.building_unavailable_reason(&"brewery"), &"requires_river")
