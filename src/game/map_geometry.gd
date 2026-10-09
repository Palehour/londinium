class_name MapGeometry
extends RefCounted

var map_size: Vector2
var cell_size: float
var viewport_size: Vector2
var center: Vector2
var zoom: float
var max_zoom_factor: float
var selected: Vector2i = Vector2i(-1, -1)


func _init(dimensions: Vector2i, tile_size: float, viewport: Vector2, zoom_limit: float) -> void:
	cell_size = tile_size
	map_size = Vector2(dimensions) * cell_size
	viewport_size = viewport
	center = map_size / 2.0
	zoom = minimum_zoom()
	max_zoom_factor = zoom_limit


func minimum_zoom() -> float:
	return minf(viewport_size.x / map_size.x, viewport_size.y / map_size.y)


func screen_to_world(screen: Vector2) -> Vector2:
	return (screen - viewport_size / 2.0) / zoom + center


func cell_to_screen(cell: Vector2i) -> Vector2:
	return ((Vector2(cell) + Vector2(0.5, 0.5)) * cell_size - center) * zoom + viewport_size / 2.0


func screen_to_cell(screen: Vector2) -> Vector2i:
	return Vector2i((screen_to_world(screen) / cell_size).floor())


func select_cell(screen: Vector2) -> Vector2i:
	selected = screen_to_cell(screen)
	if not Rect2(Vector2.ZERO, map_size / cell_size).has_point(Vector2(selected)):
		selected = Vector2i(-1, -1)
	return selected


func constrain() -> void:
	zoom = clampf(zoom, minimum_zoom(), minimum_zoom() * max_zoom_factor)
	var half: Vector2 = viewport_size / (2.0 * zoom)
	center.x = map_size.x / 2.0 if half.x * 2.0 >= map_size.x else clampf(center.x, half.x, map_size.x - half.x)
	center.y = map_size.y / 2.0 if half.y * 2.0 >= map_size.y else clampf(center.y, half.y, map_size.y - half.y)


func terrain_at(cell: Vector2i, map: MapDef) -> String:
	if cell in map.river_cells:
		return "river"
	return "cultivable" if cell in map.cultivable_cells else "land"
