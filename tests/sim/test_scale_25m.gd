extends GutTest

# Issue #186 (D-086): the map goes from cells of 50 m to cells of 25 m without changing the game. Each old cell (x, y) is
# now its block (2x, 2y)-(2x+1, 2y+1), every building and every street piece is 2x2, and the radii and the transport
# are in metres. So a building that had a street beside it still has one, one that had none still has none, and the
# metres along the streets between two buildings are the ones of before (D-070, D-080: 50 m a step).

# Cells of 25 m on each side of an old cell of 50 m (D-086).
const BLOCK: int = 2
const OLD_STEP_M: int = 50
const STRIP: StringName = &"riverside_strip"
const DEFAULT_MAP: StringName = &"whitechapel_1850s"
# The radii of D-070 and the threshold of D-080, in street steps of 50 m.
const OLD_RADII: Dictionary[StringName, int] = {&"wharf": 4, &"bakery": 8, &"brewery": 6}
const OLD_EXPENSIVE_STEPS: int = 10
const MOST_STEPS: int = 40
# Streets of the player on the strip, in old cells: the ones of the saved game of D-087.
const OLD_PLAYER_ROADS: Array[Vector2i] = [Vector2i(8, 4), Vector2i(14, 2)]

var _catalog: DataCatalog
var _params: Params


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])


func _block(cell: Vector2i) -> Array[Vector2i]:
	return EconomyContext.cells_of(Rect2i(cell - Vector2i(posmod(cell.x, BLOCK), posmod(cell.y, BLOCK)),
		Vector2i(BLOCK, BLOCK)))


func _whole_blocks(cells: Array[Vector2i]) -> bool:
	return cells.all(func(cell: Vector2i) -> bool:
		return _block(cell).all(func(other: Vector2i) -> bool: return other in cells))


func _on_block_corner(cell: Vector2i) -> bool:
	return posmod(cell.x, BLOCK) == 0 and posmod(cell.y, BLOCK) == 0


# The map of 50 m cells the blocks come from: an old cell is a street when its block is.
func _old_map(map: MapDef) -> MapDef:
	var old: MapDef = MapDef.new()
	old.width = map.width / BLOCK
	old.height = map.height / BLOCK
	for cell: Vector2i in map.road_cells:
		if _on_block_corner(cell):
			old.road_cells.append(cell / BLOCK)
	return old


func _player_roads(cells: Array[Vector2i], scale: int) -> Array[Dictionary]:
	var roads: Array[Dictionary] = []
	for cell: Vector2i in cells:
		roads.append({"cell": [cell.x * scale, cell.y * scale]})
	return roads


func test_the_maps_and_the_buildings_take_the_new_scale() -> void:
	assert_eq(int(_params.get_value(&"map.cell_size_m")), OLD_STEP_M / BLOCK)
	assert_eq(Vector2i(_catalog.maps[STRIP].width, _catalog.maps[STRIP].height), Vector2i(32, 24))
	assert_eq(Vector2i(_catalog.maps[DEFAULT_MAP].width, _catalog.maps[DEFAULT_MAP].height), Vector2i(16, 16))
	for id: StringName in _catalog.buildings:
		assert_eq(_catalog.buildings[id].footprint, Vector2i(BLOCK, BLOCK), String(id))
	assert_eq(_catalog.road_footprint, Vector2i(BLOCK, BLOCK), "A street is a 2x2 piece")


func test_every_layer_of_the_maps_is_made_of_whole_blocks() -> void:
	for id: StringName in [STRIP, DEFAULT_MAP]:
		var map: MapDef = _catalog.maps[id]
		var layers: Dictionary[String, Array] = {"river": map.river_cells, "dock": map.dock_cells,
			"road": map.road_cells, "existing": map.existing_cells, "cultivable": map.cultivable_cells}
		for label: StringName in [&"riverbank", &"marsh"]:
			layers[String(label)] = map.terrain.keys().filter(func(cell: Vector2i) -> bool:
				return map.terrain[cell] == label)
		for style: StringName in map.lot_styles.values():
			layers["lot " + String(style)] = map.lot_styles.keys().filter(func(cell: Vector2i) -> bool:
				return map.lot_styles[cell] == style)
		for layer: String in layers:
			var cells: Array[Vector2i] = []
			cells.assign(layers[layer])
			assert_true(_whole_blocks(cells), "%s: %s" % [id, layer])
		var places: Array[Vector2i] = []
		places.append_array(map.anchors.keys())
		places.append_array(map.named_sites.keys())
		places.append_array(map.period_houses)
		places.append_array(map.damaged_wharves)
		places.append_array(map.dense_housing_cells)
		for cell: Vector2i in places:
			assert_true(_on_block_corner(cell), "%s: %s starts its block" % [id, cell])


# Chronicler confirmed it for #186: with the streets as literal 2x2 blocks nobody gains or loses access (D-079).
func test_a_building_has_a_street_beside_it_exactly_where_it_had_one() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	var old: RoadNetwork = RoadNetwork.build(_old_map(map), _player_roads(OLD_PLAYER_ROADS, 1), Vector2i.ONE)
	var now: RoadNetwork = RoadNetwork.build(map, _player_roads(OLD_PLAYER_ROADS, BLOCK), _catalog.road_footprint)
	var with_access: int = 0
	for y: int in range(map.height / BLOCK):
		for x: int in range(map.width / BLOCK):
			var cell: Vector2i = Vector2i(x, y)
			var had: bool = old.has_access(Rect2i(cell, Vector2i.ONE))
			assert_eq(now.has_access(Rect2i(cell * BLOCK, Vector2i(BLOCK, BLOCK))), had, str(cell))
			with_access += int(had)
	assert_gt(with_access, 0, "Some cells touch a street")


func test_the_steps_between_two_buildings_are_the_ones_of_before() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	var old: RoadNetwork = RoadNetwork.build(_old_map(map), _player_roads(OLD_PLAYER_ROADS, 1), Vector2i.ONE)
	var now: RoadNetwork = RoadNetwork.build(map, _player_roads(OLD_PLAYER_ROADS, BLOCK), _catalog.road_footprint)
	var cells: Array[Vector2i] = []
	for y: int in range(map.height / BLOCK):
		for x: int in range(map.width / BLOCK):
			if old.has_access(Rect2i(Vector2i(x, y), Vector2i.ONE)):
				cells.append(Vector2i(x, y))
	var routes: int = 0
	for from: Vector2i in cells:
		for to: Vector2i in cells:
			var before: int = old.steps(Rect2i(from, Vector2i.ONE), Rect2i(to, Vector2i.ONE))
			var after: int = now.steps(Rect2i(from * BLOCK, Vector2i(BLOCK, BLOCK)),
				Rect2i(to * BLOCK, Vector2i(BLOCK, BLOCK)))
			if after != before:
				assert_eq(after, before, "%s -> %s" % [from, to])
				return
			routes += int(before != RoadNetwork.NO_ROUTE)
	assert_gt(routes, 0, "Some buildings are joined by the streets")


# A street piece is 50 m, so the radii and the threshold in metres reach as many pieces as the old ones reached steps.
func test_radii_and_the_expensive_threshold_reach_as_far_as_before() -> void:
	var context: EconomyContext = EconomyContext.new(_catalog, _catalog.maps[STRIP])
	var radius_keys: Array[StringName] = []
	for id: StringName in OLD_RADII:
		radius_keys.append(StringName("building.%s.service_radius_m" % id))
	var expensive: int = int(_params.get_value(&"transport.expensive_m"))
	for steps: int in range(1, MOST_STEPS + 1):
		var metres: int = RoadSystem.metres(_params, context, steps)
		assert_eq(metres, steps * OLD_STEP_M)
		for index: int in range(radius_keys.size()):
			var old_radius: int = OLD_RADII.values()[index]
			assert_eq(metres <= int(_params.get_value(radius_keys[index])), steps <= old_radius,
				"%s at %d steps" % [radius_keys[index], steps])
		assert_eq(metres >= expensive, steps >= OLD_EXPENSIVE_STEPS, "Expensive at %d steps" % steps)
