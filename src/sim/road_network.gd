class_name RoadNetwork
extends RefCounted

# The streets a building can use (issue #67, D-034, D-058, D-080): the historic streets of the map, the player's
# streets that join them side by side, and the diagonal edges the map lists (diagonals are never guessed from the
# cells). A building is connected when a street of the network touches a side of its footprint
# (issue #184, D-086): of any cell on its edge, which for a 1x1 building is one of its four sides. Streets are pieces of
# road_footprint cells (issue #186, D-086): the historic ones lie on the grid of pieces, a player's starts at its cell.
# Steps are the pieces walked from one building to another, both ends included: two buildings beside one piece are one
# step apart. So a piece of 2x2 cells of 25 m is a step of 50 m, the old cell, and a route measures what it measured.

const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const NO_ROUTE: int = -1

var _historic: Dictionary[Vector2i, bool] = {}
# Every street cell, historic or the player's, to the piece it is part of.
var _pieces: Dictionary[Vector2i, Rect2i] = {}
# The pieces joined to the historic streets.
var _network: Dictionary[Rect2i, bool] = {}
var _diagonals: Dictionary[Rect2i, Array] = {}
# Steps from a building's footprint to every piece it can reach, filled the first time a route starts there.
var _distances: Dictionary[Rect2i, Dictionary] = {}


static func build(map: MapDef, player_roads: Array[Dictionary], piece: Vector2i) -> RoadNetwork:
	var network: RoadNetwork = RoadNetwork.new()
	# The network grows from the historic streets: a player street that reaches none of them serves nobody.
	var frontier: Array[Rect2i] = []
	for cell: Vector2i in map.road_cells:
		network._historic[cell] = true
		network._pieces[cell] = Rect2i(piece_origin(cell, piece), piece)
		if not network._network.has(network._pieces[cell]):
			network._network[network._pieces[cell]] = true
			frontier.append(network._pieces[cell])
	for road: Dictionary in player_roads:
		for cell: Vector2i in EconomyContext.cells_of(Rect2i(cell_of(road), piece)):
			network._pieces[cell] = Rect2i(cell_of(road), piece)
	for edge: Vector4i in map.road_diagonals:
		network._link(Vector2i(edge.x, edge.y), Vector2i(edge.z, edge.w))
		network._link(Vector2i(edge.z, edge.w), Vector2i(edge.x, edge.y))
	var next: int = 0
	while next < frontier.size():
		for neighbour: Rect2i in network._neighbours(frontier[next]):
			if not network._network.has(neighbour):
				network._network[neighbour] = true
				frontier.append(neighbour)
		next += 1
	return network


# A building or a street as the state keeps it: {"cell": [x, y], ...}.
static func cell_of(entry: Dictionary) -> Vector2i:
	return Vector2i(int(entry["cell"][0]), int(entry["cell"][1]))


# The north-west cell of the piece of the grid of pieces that holds the cell.
static func piece_origin(cell: Vector2i, piece: Vector2i) -> Vector2i:
	return cell - Vector2i(posmod(cell.x, piece.x), posmod(cell.y, piece.y))


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
			if _pieces.has(street) and _network.has(_pieces[street]) and not area.has_point(street) \
					and street not in found:
				found.append(street)
	return found


# Fewest street pieces from one building to another, or NO_ROUTE when no street joins them.
func steps(from_area: Rect2i, to_area: Rect2i) -> int:
	var distances: Dictionary = _distances_from(from_area)
	var best: int = NO_ROUTE
	for access: Vector2i in access_cells(to_area):
		var piece: Rect2i = _pieces[access]
		if distances.has(piece) and (best == NO_ROUTE or int(distances[piece]) < best):
			best = int(distances[piece])
	return best


func _distances_from(area: Rect2i) -> Dictionary:
	if _distances.has(area):
		return _distances[area]
	var distances: Dictionary = {}
	var queue: Array[Rect2i] = []
	for access: Vector2i in access_cells(area):
		if not distances.has(_pieces[access]):
			distances[_pieces[access]] = 1
			queue.append(_pieces[access])
	var next: int = 0
	while next < queue.size():
		var current: Rect2i = queue[next]
		for neighbour: Rect2i in _neighbours(current):
			if _network.has(neighbour) and not distances.has(neighbour):
				distances[neighbour] = int(distances[current]) + 1
				queue.append(neighbour)
		next += 1
	_distances[area] = distances
	return distances


# The pieces that touch a side of this one, in the order of its cells and of SIDES, then the diagonal ones.
func _neighbours(piece: Rect2i) -> Array[Rect2i]:
	var found: Array[Rect2i] = []
	for cell: Vector2i in EconomyContext.cells_of(piece):
		for side: Vector2i in SIDES:
			var other: Rect2i = _pieces.get(cell + side, piece)
			if other != piece and other not in found:
				found.append(other)
	for diagonal: Rect2i in _diagonals.get(piece, []):
		if diagonal not in found:
			found.append(diagonal)
	return found


# A diagonal edge joins the pieces of its two cells (D-058).
func _link(from: Vector2i, to: Vector2i) -> void:
	var linked: Array = _diagonals.get(_pieces[from], [])
	linked.append(_pieces[to])
	_diagonals[_pieces[from]] = linked
