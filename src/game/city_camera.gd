class_name CityCamera
extends RefCounted

# The camera of the 3D greybox (issue #65, D-028): tilted, with free rotation and continuous zoom, like Anno (Cristian,
# 2026-10-11, in the issue; it replaces the 90° steps of the first plan). It orbits a focus point on the ground.
# Metres on the ground plane: x to the east, z to the south (the map's y), y up. Only maths, so tests need no renderer.

const NONE: Vector2i = Vector2i(-1, -1)

var focus: Vector3
# Radians around the vertical; 0 looks north, so the map reads as in 2D.
var yaw: float = 0.0
# Radians below the horizon.
var pitch: float
var fov: float
var distance: float
# The zoom eases toward this distance, so a wheel step is a glide and not a jump.
var target_distance: float
var min_distance: float
var max_distance: float
var map_size: Vector2
var cell_size: float
var _smoothing: float


func _init(map_cells: Vector2i, cell_size_m: float, settings: Dictionary[String, float]) -> void:
	cell_size = cell_size_m
	map_size = Vector2(map_cells) * cell_size
	pitch = deg_to_rad(settings["pitch_deg"])
	fov = settings["fov_deg"]
	min_distance = settings["min_distance_m"]
	max_distance = settings["max_distance_m"]
	_smoothing = settings["zoom_smoothing"]
	reset(settings["start_distance_m"])


func reset(start_distance: float) -> void:
	focus = Vector3(map_size.x / 2.0, 0.0, map_size.y / 2.0)
	yaw = 0.0
	target_distance = clampf(start_distance, min_distance, max_distance)
	distance = target_distance


func camera_transform() -> Transform3D:
	var back: Vector3 = Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw) * distance
	return Transform3D(Basis.IDENTITY, focus + back).looking_at(focus, Vector3.UP)


# Ground directions of the screen's right and up at the current rotation.
func screen_right() -> Vector3:
	return Vector3.RIGHT.rotated(Vector3.UP, yaw)


func screen_up() -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, yaw)


# Moves the focus by metres along the screen's axes (y grows downwards, as on the screen).
func pan(screen_metres: Vector2) -> void:
	focus += screen_right() * screen_metres.x - screen_up() * screen_metres.y
	constrain()


# Ground metres one pixel covers at the focus for a view this many pixels tall; the zoom changes it.
func metres_per_pixel(view_height: float) -> float:
	return 2.0 * distance * tan(deg_to_rad(fov) / 2.0) / maxf(view_height, 1.0)


# Above 1 zooms in, like the 2D map's factor.
func zoom_by(factor: float) -> void:
	target_distance = clampf(target_distance / factor, min_distance, max_distance)


func rotate(radians: float) -> void:
	yaw = fposmod(yaw + radians, TAU)


# Eases the distance toward the target; frame time, so it also glides with the game paused.
func update(delta: float) -> void:
	distance = lerpf(distance, target_distance, 1.0 - exp(-_smoothing * delta))
	if is_equal_approx(distance, target_distance):
		distance = target_distance


func constrain() -> void:
	focus.x = clampf(focus.x, 0.0, map_size.x)
	focus.z = clampf(focus.z, 0.0, map_size.y)
	focus.y = 0.0


func cell_center(cell: Vector2i, height: float = 0.0) -> Vector3:
	return Vector3((cell.x + 0.5) * cell_size, height, (cell.y + 0.5) * cell_size)


# The cell a ray meets on the ground, or NONE when it points away from it.
func ground_cell(origin: Vector3, direction: Vector3) -> Vector2i:
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if hit == null:
		return NONE
	return cell_of(hit as Vector3)


func cell_of(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / cell_size), floori(point.z / cell_size))


func has_cell(cell: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, Vector2i(map_size / cell_size)).has_point(cell)


# A d-pad step in screen directions as a step of one cell on the grid: up moves the cursor away from the camera
# whatever the rotation, along the grid axis closest to it.
func grid_step(screen_step: Vector2i) -> Vector2i:
	var ground: Vector3 = screen_right() * screen_step.x - screen_up() * screen_step.y
	if absf(ground.x) >= absf(ground.z):
		return Vector2i(int(signf(ground.x)), 0)
	return Vector2i(0, int(signf(ground.z)))
