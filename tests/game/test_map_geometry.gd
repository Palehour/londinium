extends GutTest


func test_round_trip_with_pan_zoom_and_boundaries() -> void:
	var geometry: MapGeometry = MapGeometry.new(Vector2i(8, 8), 100, Vector2(800, 600), 4.0)
	geometry.zoom = 2.0
	geometry.center = Vector2(350, 420)
	for cell: Vector2i in [Vector2i.ZERO, Vector2i(7, 7), Vector2i(3, 5)]:
		assert_eq(geometry.screen_to_cell(geometry.cell_to_screen(cell)), cell)
	assert_eq(geometry.screen_to_cell((Vector2.ZERO - geometry.center) * geometry.zoom + geometry.viewport_size / 2), Vector2i.ZERO)
	assert_eq(geometry.screen_to_cell((Vector2(-0.01, -0.01) - geometry.center) * geometry.zoom + geometry.viewport_size / 2), Vector2i(-1, -1))
	assert_eq(geometry.screen_to_cell((geometry.map_size - geometry.center) * geometry.zoom + geometry.viewport_size / 2), Vector2i(8, 8))


func test_selection_clears_outside_map() -> void:
	var geometry: MapGeometry = MapGeometry.new(Vector2i(8, 8), 100, Vector2(800, 600), 4.0)
	assert_eq(geometry.select_cell(geometry.cell_to_screen(Vector2i(2, 3))), Vector2i(2, 3))
	assert_eq(geometry.select_cell(geometry.cell_to_screen(Vector2i(8, 3))), Vector2i(-1, -1))
	assert_eq(geometry.selected, Vector2i(-1, -1))
	assert_eq(geometry.select_cell(geometry.cell_to_screen(Vector2i(-1, 3))), Vector2i(-1, -1))


func test_camera_clamps_visible_extent_and_resize() -> void:
	var geometry: MapGeometry = MapGeometry.new(Vector2i(8, 8), 100, Vector2(800, 600), 4.0)
	geometry.zoom = 2
	geometry.center = Vector2(-1000, 1000)
	geometry.constrain()
	assert_eq(geometry.center, Vector2(200, 650))
	geometry.zoom = 100
	geometry.constrain()
	assert_eq(geometry.zoom, 3.0)
	geometry.zoom = 0.01
	geometry.constrain()
	assert_eq(geometry.zoom, 0.75)
	assert_eq(geometry.center, Vector2(400, 400))
	geometry.viewport_size = Vector2(1600, 400)
	geometry.constrain()
	assert_eq(geometry.center.x, 400.0)
	geometry.viewport_size = Vector2(400, 1600)
	geometry.constrain()
	assert_eq(geometry.center.y, 400.0)


func test_terrain_from_real_map_and_cultivable_fixture() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	var map: MapDef = loaded.catalog.maps[&"whitechapel_1850s"]
	var geometry: MapGeometry = MapGeometry.new(Vector2i(8, 8), 100, Vector2(800, 600), 4.0)
	assert_true(map.cultivable_cells.is_empty())
	assert_eq(geometry.terrain_at(Vector2i(0, 7), map), "river")
	assert_eq(geometry.terrain_at(Vector2i(0, 0), map), "land")
	var fixture: MapDef = MapDef.new()
	fixture.cultivable_cells.append(Vector2i(2, 2))
	assert_eq(geometry.terrain_at(Vector2i(2, 2), fixture), "cultivable")


func test_zoom_limit_is_supplied_by_configuration() -> void:
	var geometry: MapGeometry = MapGeometry.new(Vector2i(8, 8), 100, Vector2(800, 600), 2.0)
	geometry.zoom = 100
	geometry.constrain()
	assert_eq(geometry.zoom, 1.5)


func test_move_selection_starts_in_the_middle_and_clamps_to_map() -> void:
	var geometry: MapGeometry = MapGeometry.new(Vector2i(8, 8), 100, Vector2(800, 600), 4.0)
	var middle: Vector2i = geometry.screen_to_cell(geometry.viewport_size / 2.0)
	assert_eq(geometry.move_selection(Vector2i.RIGHT), middle, "Without a selection the cursor starts mid-view")
	assert_eq(geometry.move_selection(Vector2i.RIGHT), middle + Vector2i.RIGHT)
	for step: int in range(10):
		geometry.move_selection(Vector2i(1, 1))
	assert_eq(geometry.selected, Vector2i(7, 7))
	for step: int in range(10):
		geometry.move_selection(Vector2i(-1, -1))
	assert_eq(geometry.selected, Vector2i.ZERO)


func test_follow_selection_recenters_only_when_out_of_view() -> void:
	var geometry: MapGeometry = MapGeometry.new(Vector2i(8, 8), 100, Vector2(800, 600), 4.0)
	geometry.zoom = 4.0
	geometry.center = Vector2(400, 400)
	geometry.constrain()
	geometry.selected = Vector2i(4, 4)
	var center: Vector2 = geometry.center
	geometry.follow_selection()
	assert_eq(geometry.center, center, "A cell already in view keeps the camera still")
	geometry.selected = Vector2i(0, 0)
	geometry.follow_selection()
	assert_true(Rect2(Vector2.ZERO, geometry.viewport_size).has_point(geometry.cell_to_screen(geometry.selected)))
