class_name RoadNetwork
extends RefCounted

# The streets a building can use (issue #67, D-034, D-058, D-080): the historic streets of the map, the player's
# streets that join them side by side, and the diagonal edges the map lists (diagonals are never guessed from the
# cells). A building is connected when a street of the network touches a side of its footprint
# (issue #184, D-086): of any cell on its edge, which for a 1x1 building is one of its four sides. Steps are the
# street cells walked from one building to another, both ends included: two buildings on one street cell are one
# step apart.

const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const NO_ROUTE: int = -1

var _historic: Dictionary[Vector2i, bool] = {}
var _network: Dictionary[Vector2i, bool] = {}
var _diagonals: Dictionary[Vector2i, Array] = {}
# Steps from a building's footprint to every street it can reach, filled the first time a route starts there.
var _distances: Dictionary[Rect2i, Dictionary] = {}


static func build(map: MapDef, player_roads: Array[Dictionary]) -> RoadNetwork:
	var network: RoadNetwork = RoadNetwork.new()
	var streets: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in map.road_cells:
		network._historic[cell] = true
		streets[cell] = true
	for road: Dictionary in player_roads:
		streets[cell_of(road)] = true
	for edge: Vector4i in map.road_diagonals:
		network._link(Vector2i(edge.x, edge.y), Vector2i(edge.z, edge.w))
		network._link(Vector2i(edge.z, edge.w), Vector2i(edge.x, edge.y))
	# The network grows from the historic streets: a player street that reaches none of them serves nobody.
	var frontier: Array[Vector2i] = map.road_cells.duplicate()
	for cell: Vector2i in frontier:
		network._network[cell] = true
	var next: int = 0
	while next < frontier.size():
		for neighbour: Vector2i in network._neighbours(frontier[next], streets):
			if not network._network.has(neighbour):
				network._network[neighbour] = true
				frontier.append(neighbour)
		next += 1
	return network


# A building or a street as the state keeps it: {"cell": [x, y], ...}.
static func cell_of(entry: Dictionary) -> Vector2i:
	return Vector2i(int(entry["cell"][0]), int(entry["cell"][1]))


func is_historic(cell: Vector2i) -> bool:
	return _historic.has(cell)


func has_access(area: Rect2i) -> bool:
	return not access_cells(area).is_empty()


# Streets of the network beside the footprint: on a side of one of its cells, outside it. Each street once, in the
# order of the cells (EconomyContext.cells_of) and of SIDES.
func access_cells(area: Rect2i) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for cell: Vector2i in EconomyContext.cells_of(area):
		for side: Vector2i in SIDES:
			var street: Vector2i = cell + side
			if _network.has(street) and not area.has_point(street) and street not in found:
				found.append(street)
	return found


# Fewest street cells from one building to another, or NO_ROUTE when no street joins them.
func steps(from_area: Rect2i, to_area: Rect2i) -> int:
	var distances: Dictionary = _distances_from(from_area)
	var best: int = NO_ROUTE
	for access: Vector2i in access_cells(to_area):
		if distances.has(access) and (best == NO_ROUTE or int(distances[access]) < best):
			best = int(distances[access])
	return best


func _distances_from(area: Rect2i) -> Dictionary:
	if _distances.has(area):
		return _distances[area]
	var distances: Dictionary = {}
	var queue: Array[Vector2i] = access_cells(area)
	for start: Vector2i in queue:
		distances[start] = 1
	var next: int = 0
	while next < queue.size():
		var current: Vector2i = queue[next]
		for neighbour: Vector2i in _neighbours(current, _network):
			if not distances.has(neighbour):
				distances[neighbour] = int(distances[current]) + 1
				queue.append(neighbour)
		next += 1
	_distances[area] = distances
	return distances


func _neighbours(cell: Vector2i, streets: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for side: Vector2i in SIDES:
		if streets.has(cell + side):
			found.append(cell + side)
	for diagonal: Vector2i in _diagonals.get(cell, []):
		if streets.has(diagonal):
			found.append(diagonal)
	return found


func _link(from: Vector2i, to: Vector2i) -> void:
	var linked: Array = _diagonals.get(from, [])
	linked.append(to)
	_diagonals[from] = linked
