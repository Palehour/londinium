extends GutTest

# The camera of the 3D greybox (issue #65): tilted at ~50°, free rotation (not 90° steps) and continuous zoom from a
# street to the district, over the 48x80 map of 25 m cells (D-093).

const MAP: Vector2i = Vector2i(48, 80)
const CELL_M: float = 25.0


func _settings() -> Dictionary[String, float]:
	var style: CityPresentation = CityPresentation.new()
	style.load_data([])
	assert_eq(style.errors, [] as Array[String])
	return style.camera


func _camera() -> CityCamera:
	return CityCamera.new(MAP, CELL_M, _settings())


func test_the_map_is_one_point_two_by_two_kilometres_and_the_camera_starts_on_its_middle() -> void:
	var camera: CityCamera = _camera()
	assert_eq(camera.map_size, Vector2(1200, 2000), "48x80 cells of 25 m (D-093)")
	assert_eq(camera.focus, Vector3(600, 0, 1000))
	assert_eq(camera.cell_center(Vector2i(1, 2)), Vector3(37.5, 0, 62.5))


func test_the_camera_looks_down_at_about_fifty_degrees_and_north_is_up() -> void:
	var camera: CityCamera = _camera()
	var view: Transform3D = camera.camera_transform()
	var forward: Vector3 = -view.basis.z
	assert_almost_eq(rad_to_deg(asin(-forward.y)), 50.0, 0.01, "Tilted at 50°")
	assert_lt(forward.z, 0.0, "At rest it looks north, like the 2D map")
	assert_almost_eq(view.origin.distance_to(camera.focus), camera.distance, 0.01)


func test_the_rotation_is_free_and_not_in_quarter_steps() -> void:
	var camera: CityCamera = _camera()
	camera.rotate(deg_to_rad(10.0))
	assert_almost_eq(rad_to_deg(camera.yaw), 10.0, 0.001)
	var forward: Vector3 = -camera.camera_transform().basis.z
	assert_almost_eq(absf(rad_to_deg(Vector2(forward.x, forward.z).angle_to(Vector2(0, -1)))), 10.0, 0.01)
	camera.rotate(deg_to_rad(-30.0))
	assert_almost_eq(rad_to_deg(camera.yaw), 340.0, 0.001, "It wraps around")


func test_the_zoom_is_continuous_and_stays_between_a_street_and_the_district() -> void:
	var settings: Dictionary[String, float] = _settings()
	var camera: CityCamera = _camera()
	var start: float = camera.distance
	camera.zoom_by(1.15)
	camera.update(0.016)
	assert_lt(camera.distance, start, "It moves toward the target")
	assert_gt(camera.distance, camera.target_distance, "It glides, it does not jump")
	for step: int in range(100):
		camera.zoom_by(1.15)
	camera.update(10.0)
	assert_eq(camera.distance, settings["min_distance_m"])
	for step: int in range(100):
		camera.zoom_by(1.0 / 1.15)
	camera.update(10.0)
	assert_eq(camera.distance, settings["max_distance_m"])
	assert_lt(settings["min_distance_m"], 4.0 * CELL_M, "The nearest zoom shows a street")
	assert_gt(settings["max_distance_m"], 2000.0, "The farthest zoom shows the whole district")


func test_the_focus_stays_on_the_map_and_pans_along_the_screen() -> void:
	var camera: CityCamera = _camera()
	camera.pan(Vector2(0, -100))
	assert_eq(camera.focus, Vector3(600, 0, 900), "Up on the screen is north at rest")
	camera.rotate(PI / 2.0)
	camera.pan(Vector2(0, -100))
	assert_almost_eq(camera.focus.x, 500.0, 0.01, "A quarter turn left: up is west")
	camera.pan(Vector2(-1e6, 1e6))
	assert_true(Rect2(Vector2.ZERO, camera.map_size).grow(0.01).has_point(Vector2(camera.focus.x, camera.focus.z)))


func test_a_ray_from_the_camera_finds_the_cell_under_it() -> void:
	var camera: CityCamera = _camera()
	for yaw: float in [0.0, 0.7, 2.0, 4.1]:
		camera.yaw = yaw
		var origin: Vector3 = camera.camera_transform().origin
		for cell: Vector2i in [Vector2i(0, 0), Vector2i(20, 41), Vector2i(47, 79)]:
			assert_eq(camera.ground_cell(origin, origin.direction_to(camera.cell_center(cell))), cell)
	assert_eq(camera.ground_cell(Vector3(0, 10, 0), Vector3.UP), CityCamera.NONE, "A ray to the sky meets no cell")


func test_the_dpad_moves_in_screen_directions_whatever_the_rotation() -> void:
	var camera: CityCamera = _camera()
	assert_eq(camera.grid_step(Vector2i.UP), Vector2i(0, -1))
	assert_eq(camera.grid_step(Vector2i.RIGHT), Vector2i(1, 0))
	camera.rotate(PI)
	assert_eq(camera.grid_step(Vector2i.UP), Vector2i(0, 1), "Turned around, up on the screen is south")
	camera.yaw = deg_to_rad(80.0)
	assert_eq(camera.grid_step(Vector2i.UP), Vector2i(-1, 0), "Nearly a quarter turn: the nearest grid axis")
