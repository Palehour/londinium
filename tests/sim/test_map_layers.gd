extends GutTest

const STRIP: StringName = &"riverside_strip"
const SMALL: StringName = &"whitechapel_1850s"

var _catalog: DataCatalog


func before_all() -> void:
	_catalog = DataLoader.new().load_all().catalog


func _context(map_id: StringName) -> EconomyContext:
	return EconomyContext.new(_catalog, _catalog.maps[map_id])


func _all_cells(map: MapDef) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(map.height):
		for x: int in range(map.width):
			cells.append(Vector2i(x, y))
	return cells


func test_the_strip_is_16_by_12_with_every_layer() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	assert_eq(Vector2i(map.width, map.height), Vector2i(16, 12))
	for layer: Array[Vector2i] in [map.river_cells, map.dock_cells, map.road_cells, map.existing_cells]:
		assert_false(layer.is_empty())
	assert_true(map.terrain.values().has(&"riverbank"))


func test_the_strip_keeps_the_river_cells_of_the_small_map() -> void:
	var strip: MapDef = _catalog.maps[STRIP]
	for cell: Vector2i in _catalog.maps[SMALL].river_cells:
		assert_true(cell in strip.river_cells, str(cell))


func test_the_wharf_goes_only_on_the_river() -> void:
	for map_id: StringName in [STRIP, SMALL]:
		var context: EconomyContext = _context(map_id)
		for cell: Vector2i in _all_cells(context.map):
			var expected: StringName = &"" if cell in context.map.river_cells else &"requires_river"
			assert_eq(context.terrain_placement_reason(&"wharf", cell), expected, "%s %s" % [map_id, cell])


# Dock basins are water that is not a grain source (D-020): nothing is built on them.
func test_nothing_is_built_on_a_dock_basin() -> void:
	var context: EconomyContext = _context(STRIP)
	for cell: Vector2i in context.map.dock_cells:
		for id: StringName in [&"housing", &"mill", &"bakery"]:
			assert_eq(context.terrain_placement_reason(id, cell), &"requires_land", "%s %s" % [id, cell])


# Streets and terrain labels carry no rule yet (#67, #88).
func test_streets_and_terrain_labels_do_not_block_building() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	var context: EconomyContext = _context(STRIP)
	var dry: Array[Vector2i] = []
	dry.append_array(map.road_cells)
	dry.append_array(map.terrain.keys())
	for cell: Vector2i in dry:
		if cell in map.river_cells or cell in map.dock_cells or cell in map.existing_cells:
			continue
		assert_eq(context.terrain_placement_reason(&"housing", cell), &"", str(cell))


# Standing buildings block building until the tracing of #152 (issue #154, D-075).
func test_standing_buildings_block_building() -> void:
	var context: EconomyContext = _context(STRIP)
	for cell: Vector2i in context.map.existing_cells:
		assert_eq(context.terrain_placement_reason(&"housing", cell), &"existing_building", str(cell))


func test_the_small_map_has_no_new_layers() -> void:
	var map: MapDef = _catalog.maps[SMALL]
	assert_eq(Vector2i(map.width, map.height), Vector2i(8, 8))
	assert_true(map.dock_cells.is_empty() and map.road_cells.is_empty() and map.existing_cells.is_empty())
	assert_true(map.terrain.is_empty())


func test_a_copied_context_keeps_the_layers() -> void:
	var copy: EconomyContext = _context(STRIP).copy()
	var map: MapDef = _catalog.maps[STRIP]
	assert_eq(copy.map.dock_cells, map.dock_cells)
	assert_eq(copy.map.road_cells, map.road_cells)
	assert_eq(copy.map.existing_cells, map.existing_cells)
	assert_eq(copy.map.terrain, map.terrain)
