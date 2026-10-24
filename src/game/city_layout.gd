class_name CityLayout
extends RefCounted

# The boxes of one building in the 3D greybox (issue #65, D-028). A footprint is a small block (2x2 cells of 25 m, D-093),
# so the building is its leading block in the middle, with a gable or flat roof and maybe a chimney, and filler houses
# along the edges of the block wherever the leading block leaves room. The silhouette and the proportion carry the
# history, so the boxes can turn into a more realistic kit later. Metres: x to the east, z to the south, y up.

const MAIN: StringName = &"main"
const ROOF: StringName = &"roof"
const CHIMNEY: StringName = &"chimney"
const FILLER: StringName = &"filler"
# The filler heights cycle through this many steps (lower, base, higher), so a row does not read as one wall.
const FILLER_HEIGHT_STEPS: int = 3


# Each piece is {kind, box: AABB, ridge_along_x: bool}. `area` is the footprint on the ground in metres, `base` the
# height of the ground under it, and `variation` shifts the filler heights so neighbouring blocks differ.
static func pieces(shape: Dictionary, filler: Dictionary[String, float], chimney_side: float, area: Rect2, base: float,
		variation: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var height: float = shape["height_m"]
	var size: Vector2 = area.size * Vector2(shape["width_ratio"], shape["depth_ratio"])
	var main: Rect2 = Rect2(area.get_center() - size / 2.0, size)
	result.append(_piece(MAIN, main, base, height))
	if shape["roof"] == "gable" and shape["roof_m"] > 0.0:
		result.append(_piece(ROOF, main, base + height, shape["roof_m"]))
	if shape["chimney_m"] > 0.0:
		var side: float = minf(chimney_side, minf(main.size.x, main.size.y))
		result.append(_piece(CHIMNEY, Rect2(Vector2(main.end.x - side, main.position.y), Vector2.ONE * side), base, shape["chimney_m"]))
	if shape["fillers"]:
		result.append_array(_fillers(filler, area, main, base, variation))
	return result


# The box that holds every piece, for picking a building with the mouse.
static func bounds(building_pieces: Array[Dictionary]) -> AABB:
	var box: AABB = building_pieces[0]["box"]
	for piece: Dictionary in building_pieces:
		box = box.merge(piece["box"])
	return box


static func _piece(kind: StringName, ground: Rect2, base: float, height: float) -> Dictionary:
	return {"kind": kind, "box": AABB(Vector3(ground.position.x, base, ground.position.y), Vector3(ground.size.x, height, ground.size.y)),
		"ridge_along_x": ground.size.x >= ground.size.y}


# Rows of houses along the north and south edges, then columns along the west and east edges between those rows;
# none touches the leading block.
static func _fillers(filler: Dictionary[String, float], area: Rect2, main: Rect2, base: float, variation: int) -> Array[Dictionary]:
	var gap: float = filler["gap_m"]
	var width: float = filler["width_m"]
	var depth: float = filler["depth_m"]
	var lots: Array[Rect2] = []
	var x: float = area.position.x + gap
	while x + width <= area.end.x - gap:
		lots.append(Rect2(x, area.position.y + gap, width, depth))
		lots.append(Rect2(x, area.end.y - gap - depth, width, depth))
		x += width + gap
	var z: float = area.position.y + 2.0 * gap + depth
	while z + width <= area.end.y - 2.0 * gap - depth:
		lots.append(Rect2(area.position.x + gap, z, depth, width))
		lots.append(Rect2(area.end.x - gap - depth, z, depth, width))
		z += width + gap
	var result: Array[Dictionary] = []
	var keep_clear: Rect2 = main.grow(gap)
	for lot: Rect2 in lots:
		if lot.intersects(keep_clear):
			continue
		var step: int = posmod(result.size() + variation, FILLER_HEIGHT_STEPS) - 1
		result.append(_piece(FILLER, lot, base, filler["height_m"] + step * filler["height_step_m"]))
	return result
