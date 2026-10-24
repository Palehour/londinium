extends GutTest

# The 3D greybox on the full map (issue #65, D-028, D-093): the city plays whitechapel_full (48x80 cells of 25 m), and
# placing, demolishing and the panel work as on the 2D map, because the view only changes how the map is drawn and how
# a click finds its cell.

const ROOT: String = "user://test_city_view"
const HOUSE: Vector2i = Vector2i(12, 22)
const MILL: Vector2i = Vector2i(24, 40)

var _viewport: SubViewport


func before_each() -> void:
	_remove(ROOT)


func after_each() -> void:
	Strings.use_default_locale()
	_remove(ROOT)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func _view() -> CityView:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 800)
	add_child_autofree(_viewport)
	var scene: Node = (load("res://scenes/city.tscn") as PackedScene).instantiate()
	var view: CityView = scene.get_node("Map") as CityView
	view.mods_root = ROOT
	view.saves_root = ROOT
	_viewport.add_child(scene)
	view.clock.speed = 0
	await get_tree().process_frame
	return view


func _tick(view: CityView) -> void:
	view.session.simulation.tick()
	view.session.publish_tick()
	await get_tree().process_frame


func geometry_kind(view: CityView, cell: Vector2i) -> String:
	return view.geometry.terrain_at(cell, view.session.context.map)


# Where the centre of a cell is on screen.
func _screen(view: CityView, cell: Vector2i) -> Vector2:
	return _screen_point(view, view.camera.cell_center(cell))


func _screen_point(view: CityView, point: Vector3) -> Vector2:
	var camera_3d: Camera3D = view.get("_camera_3d") as Camera3D
	camera_3d.transform = view.camera.camera_transform()
	var container: Control = view.get("_container") as Control
	return container.position + camera_3d.unproject_position(point)


func _key(view: CityView, keycode: Key) -> void:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	view._unhandled_input(key)


func _click(view: CityView, position: Vector2) -> void:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = position
	view._unhandled_input(click)


func _building_at(view: CityView, cell: Vector2i) -> StringName:
	for building: Dictionary in view.session.get_snapshot()["economy"]["buildings"]:
		if view.session.context.area_of(building).has_point(cell):
			return StringName(building["definition_id"])
	return &""


func _instances(view: CityView, node_name: String) -> int:
	return (view.get(node_name) as MultiMeshInstance3D).multimesh.instance_count


# Close enough that a 2x2 block covers many pixels, so a click lands where it is aimed.
func _zoom_in(view: CityView, cell: Vector2i) -> void:
	view.camera.focus = view.camera.cell_center(cell)
	view.camera.target_distance = view.camera.min_distance * 3.0
	view.camera.distance = view.camera.target_distance


func test_the_city_plays_the_full_map_at_twenty_five_metres_a_cell() -> void:
	var view: CityView = await _view()
	var map: MapDef = view.session.context.map
	assert_eq(view.session.scenario_id(), &"whitechapel_full")
	assert_eq(Vector2i(map.width, map.height), Vector2i(48, 80))
	assert_eq(view.camera.cell_size, 25.0, "D-093: 25 m a cell, not 50")
	assert_eq(_instances(view, "_terrain"), 48 * 80, "One ground slab per cell")
	var terrain: Array = (view.get("_items") as Dictionary)[&"Terrain"]
	var river: Vector2i = map.river_cells[0]
	var water: Transform3D = terrain[river.y * map.width + river.x]["transform"]
	var land: Transform3D = terrain[0]["transform"]
	assert_eq(geometry_kind(view, Vector2i.ZERO), "land")
	assert_lt(water.origin.y, land.origin.y, "The river lies under the land")
	assert_almost_eq(land.basis.get_scale().x, 25.0 - view.style.ground["gap_m"], 0.001, "A slab is one 25 m cell")


func test_the_legend_shows_the_city_palette() -> void:
	var view: CityView = await _view()
	assert_eq(view.presentation.terrain["land"], view.style.terrain["land"])
	assert_eq(view.presentation.colors[&"bakery"], view.style.colors[&"bakery"])


func test_a_click_builds_on_the_cell_under_the_mouse_and_draws_its_boxes() -> void:
	var view: CityView = await _view()
	_zoom_in(view, HOUSE)
	assert_eq(_instances(view, "_boxes"), 0)
	_key(view, KEY_4)
	_click(view, _screen(view, HOUSE))
	assert_eq(view.geometry.selected, HOUSE)
	await _tick(view)
	assert_eq(_building_at(view, HOUSE), &"housing")
	assert_gt(_instances(view, "_boxes"), 1, "The house and its filler houses")
	assert_eq(_instances(view, "_roofs"), 1)


func test_a_click_on_a_roof_selects_that_building_not_the_ground_behind() -> void:
	var view: CityView = await _view()
	_zoom_in(view, MILL)
	_key(view, KEY_2)
	_click(view, _screen(view, MILL))
	await _tick(view)
	assert_eq(_building_at(view, MILL), &"mill")
	_key(view, KEY_ESCAPE)
	# Just inside the north edge of the mill's top: the ground behind it on that line of sight is north of the block.
	var shape: Dictionary = view.style.shapes[&"mill"]
	var block: Rect2 = Rect2(Vector2(MILL) * 25.0, Vector2(50, 50))
	var top: Vector3 = Vector3(block.get_center().x, shape["height_m"] - 0.5, block.get_center().y - 25.0 * shape["depth_ratio"] + 0.5)
	var camera: CityCamera = view.camera
	var origin: Vector3 = camera.camera_transform().origin
	assert_false(block.has_point(Vector2(camera.ground_cell(origin, origin.direction_to(top)) * 25)), "The ground behind is outside")
	_click(view, _screen_point(view, top))
	var area: Rect2i = Rect2i(MILL, Vector2i(2, 2))
	assert_true(area.has_point(view.geometry.selected), "Selected %s, inside the mill" % view.geometry.selected)


func test_delete_demolishes_the_selected_building_and_its_boxes_go() -> void:
	var view: CityView = await _view()
	_zoom_in(view, HOUSE)
	_key(view, KEY_4)
	_click(view, _screen(view, HOUSE))
	await _tick(view)
	_key(view, KEY_ESCAPE)
	_click(view, _screen(view, HOUSE))
	_key(view, KEY_DELETE)
	await _tick(view)
	assert_eq(_building_at(view, HOUSE), &"")
	assert_eq(_instances(view, "_boxes"), 0)


func test_the_panel_is_the_two_d_maps_panel() -> void:
	var view: CityView = await _view()
	var panel: StatsPanel = view.find_child("StatsPanel", true, false) as StatsPanel
	assert_not_null(panel)
	assert_eq(view.get("_stats_panel"), panel)


func test_dragging_with_the_right_button_turns_the_city_freely() -> void:
	var view: CityView = await _view()
	var drag: InputEventMouseMotion = InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_RIGHT
	drag.relative = Vector2(-10, 0)
	view._unhandled_input(drag)
	assert_almost_eq(rad_to_deg(view.camera.yaw), 10.0 * view.style.camera["drag_rotate_deg_per_px"], 0.001)


func test_the_wheel_zooms_toward_a_street() -> void:
	var view: CityView = await _view()
	var start: float = view.camera.target_distance
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(300, 600)
	view._unhandled_input(wheel)
	assert_lt(view.camera.target_distance, start)


func test_the_gamepad_cursor_starts_in_the_view_and_follows_the_rotation() -> void:
	var view: CityView = await _view()
	view._move_cursor(Vector2i.UP)
	var start: Vector2i = view.geometry.selected
	assert_true(view.camera.has_cell(start), "The first press puts the cursor on the map")
	view._move_cursor(Vector2i.UP)
	assert_eq(view.geometry.selected, start + Vector2i(0, -1), "Up is north at rest")
	view.camera.rotate(PI)
	view._move_cursor(Vector2i.UP)
	assert_eq(view.geometry.selected, start, "Turned around, up is south")


func test_the_demolish_ring_draws_over_the_city() -> void:
	var view: CityView = await _view()
	var container: CanvasItem = view.get("_container") as CanvasItem
	assert_true(container.show_behind_parent, "The 3D city is drawn behind the view's own 2D drawing")
