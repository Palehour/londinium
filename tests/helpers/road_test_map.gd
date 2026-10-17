class_name RoadTestMap
extends RefCounted

# Small maps for the distance model (issue #67): a strip of land at y = 0, a historic street along y = 1 and the
# river at y = 2, so every building on y = 0 or on the river touches the street. Steps between two buildings are
# the street cells walked from one to the other, both ends included.

const LAND_ROW: int = 0
const ROAD_ROW: int = 1
const RIVER_ROW: int = 2


static func street(catalog: DataCatalog, width: int, diagonals: Array[Vector4i] = []) -> EconomyContext:
	var map: MapDef = MapDef.new()
	map.id = &"road_test"
	map.width = width
	map.height = RIVER_ROW + 1
	map.roads_enabled = true
	for x: int in range(width):
		map.road_cells.append(Vector2i(x, ROAD_ROW))
		map.river_cells.append(Vector2i(x, RIVER_ROW))
	map.road_diagonals.assign(diagonals)
	return EconomyContext.new(catalog, map)


# Any layout: the given streets on a land map of the given size, with the river on its last row.
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


# The land cell beside the street at `steps` street cells from x = 0, where the first building stands.
static func land(steps: int) -> Vector2i:
	return Vector2i(steps - 1, LAND_ROW)


static func river(steps: int) -> Vector2i:
	return Vector2i(steps - 1, RIVER_ROW)


static func entry(snapshot: Dictionary, list: String, cell: Vector2i, good: StringName = &"") -> Dictionary:
	for item: Dictionary in snapshot["distance"][list]:
		if item["cell"] == [cell.x, cell.y] and (good == &"" or StringName(item.get("good", &"")) == good):
			return item
	return {}
