class_name RoadTestMap
extends RefCounted

# Small maps for the distance model (issue #67): a strip of land at y = 0, a historic street along y = 1 and the
# river at y = 2, so every building on y = 0 or on the river touches the street. Steps between two buildings are
# the street pieces walked from one to the other, both ends included.
# Since issue #186 (D-086) these rows are of old cells of 50 m: each one is drawn as its block of BLOCK x BLOCK cells of
# 25 m, the size of a building and of a street piece, so the steps between two buildings are the ones of before.
# `cell` takes an old cell to the cell of its block where a building stands.

const LAND_ROW: int = 0
const ROAD_ROW: int = 1
const RIVER_ROW: int = 2
const BLOCK: int = 2


static func street(catalog: DataCatalog, width: int, diagonals: Array[Vector4i] = []) -> EconomyContext:
	var roads: Array[Vector2i] = []
	for x: int in range(width):
		roads.append(Vector2i(x, ROAD_ROW))
	return blocks(catalog, Vector2i(width, RIVER_ROW + 1), roads, diagonals)


# Any layout in old cells: the given streets on a land map of the given size, with the river on its last row, each old
# cell a block. A diagonal edge joins the two cells where its blocks touch.
static func blocks(catalog: DataCatalog, size: Vector2i, roads: Array[Vector2i],
		diagonals: Array[Vector4i] = []) -> EconomyContext:
	var map: MapDef = MapDef.new()
	map.id = &"road_test"
	map.width = size.x * BLOCK
	map.height = size.y * BLOCK
	map.roads_enabled = true
	for road: Vector2i in roads:
		map.road_cells.append_array(_block(road))
	# The first row of the river block is riverbank and its second row is water, so a wharf (riverbank over river,
	# D-149) stands on the block of the old river cell, as before.
	for x: int in range(size.x):
		for cell_in_block: Vector2i in _block(Vector2i(x, size.y - 1)):
			if cell_in_block.y == cell(Vector2i(0, size.y - 1)).y:
				map.terrain[cell_in_block] = &"riverbank"
			else:
				map.river_cells.append(cell_in_block)
	for edge: Vector4i in diagonals:
		var from: Vector2i = Vector2i(edge.x, edge.y)
		var to: Vector2i = Vector2i(edge.z, edge.w)
		var near_from: Vector2i = cell(from) + (to - from).clamp(Vector2i.ZERO, Vector2i.ONE)
		var near_to: Vector2i = cell(to) + (from - to).clamp(Vector2i.ZERO, Vector2i.ONE)
		map.road_diagonals.append(Vector4i(near_from.x, near_from.y, near_to.x, near_to.y))
	return EconomyContext.new(catalog, map)


# Any layout cell by cell: the given streets on a land map of the given size, with the river on its last row.
static func custom(catalog: DataCatalog, size: Vector2i, roads: Array[Vector2i],
		diagonals: Array[Vector4i] = []) -> EconomyContext:
	var map: MapDef = MapDef.new()
	map.id = &"road_test"
	map.width = size.x
	map.height = size.y
	map.roads_enabled = true
	map.road_cells.assign(roads)
	for x: int in range(size.x):
		map.river_cells.append(Vector2i(x, size.y - 1))
	map.road_diagonals.assign(diagonals)
	return EconomyContext.new(catalog, map)


# The north-west cell of the block of an old cell.
static func cell(old: Vector2i) -> Vector2i:
	return old * BLOCK


# The cell of an old cell as the state writes it, [x, y].
static func at(old: Vector2i) -> Array:
	return [cell(old).x, cell(old).y]


# The land cell beside the street at `steps` street pieces from x = 0, where the first building stands.
static func land(steps: int) -> Vector2i:
	return cell(Vector2i(steps - 1, LAND_ROW))


static func river(steps: int) -> Vector2i:
	return cell(Vector2i(steps - 1, RIVER_ROW))


static func entry(snapshot: Dictionary, list: String, at: Vector2i, good: StringName = &"") -> Dictionary:
	for item: Dictionary in snapshot["distance"][list]:
		if item["cell"] == [at.x, at.y] and (good == &"" or StringName(item.get("good", &"")) == good):
			return item
	return {}


static func _block(old: Vector2i) -> Array[Vector2i]:
	return EconomyContext.cells_of(Rect2i(cell(old), Vector2i(BLOCK, BLOCK)))
