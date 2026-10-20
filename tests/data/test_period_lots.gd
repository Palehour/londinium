extends GutTest

# Issue #176 (D-083, task 1 of Mason's breakdown of #171): the free land of the Wapping strip is drawn as 1870 lots,
# four 1870 houses are listed around the street at (4,4)-(4,5) and one damaged wharf waits on the river. Repairing the
# wharf is #177. The simulation places the houses as empty dense housing since issue #180 (D-085).
# Issue #186 (D-086): cells of 25 m. Each old cell (x, y) is its block from (2x, 2y), so the street of the houses is at
# (8,8)-(8,11), a house covers its whole 2x2 block and the counts of #152 are four times as many cells.

const STRIP: StringName = &"riverside_strip"
const HOUSES: Array[Vector2i] = [Vector2i(8, 6), Vector2i(6, 8), Vector2i(10, 8), Vector2i(10, 10)]
# Only (8,6) is in the corner of sheet VII.77; the other three cells are on sheet VII.87 (review of PR #179).
const HOUSES_ON_VII_87: Array[Vector2i] = [Vector2i(6, 8), Vector2i(10, 8), Vector2i(10, 10)]
const DAMAGED_WHARF: Vector2i = Vector2i(28, 14)
# Cells of a real place of the sheets ([FACT]): their lot style says nothing about a use (review of PR #179).
const FACT_CELLS: Array[Vector2i] = [Vector2i(16, 14), Vector2i(24, 14), Vector2i(12, 12), Vector2i(14, 14)]
const NEUTRAL_STYLE: StringName = &"plain"
# The count of #152, which D-083 keeps: free cells in total and without the corner with no sheet (VII.77). Four cells of
# 25 m for each one of 50 m (D-086): 65 and 47 then.
const FREE_TOTAL: int = 260
const FREE_WITHOUT_CORNER: int = 188
const NO_SHEET_CORNER: Rect2i = Rect2i(0, 0, 12, 8)

var _catalog: DataCatalog
var _raw: Dictionary


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/riverside_strip.json"))


func _is_free_land(map: MapDef, cell: Vector2i) -> bool:
	return cell not in map.river_cells and cell not in map.dock_cells and cell not in map.road_cells \
		and cell not in map.existing_cells


# The cells a building of the map covers from its cell (D-086).
func _area(id: StringName, cell: Vector2i) -> Rect2i:
	return Rect2i(cell, _catalog.buildings[id].footprint)


# Mason's count of #152: an anchor with a use counts as free, like any other cell nothing blocks; all of its footprint.
func _free_cells(map: MapDef, outside: Rect2i = Rect2i()) -> int:
	var used: Array[Vector2i] = []
	for anchor: Vector2i in map.anchors:
		if map.anchors[anchor] != &"":
			used.append_array(EconomyContext.cells_of(_area(map.anchors[anchor], anchor)))
	var count: int = 0
	for y: int in range(map.height):
		for x: int in range(map.width):
			var cell: Vector2i = Vector2i(x, y)
			if outside.has_point(cell):
				continue
			if cell in used or _is_free_land(map, cell):
				count += 1
	return count


func _house_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for house: Vector2i in HOUSES:
		cells.append_array(EconomyContext.cells_of(_area(Simulation.DENSE_HOUSING, house)))
	return cells


func test_the_strip_lists_four_invented_period_houses_beside_a_street() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	assert_eq(map.period_houses, HOUSES)
	for house: Vector2i in HOUSES:
		var area: Rect2i = _area(Simulation.DENSE_HOUSING, house)
		assert_true(map.beside_road(area), "%s has a street on one side (D-079, D-086)" % house)
		for cell: Vector2i in EconomyContext.cells_of(area):
			assert_true(_is_free_land(map, cell), "%s stays free land until something places the house" % cell)
			assert_false(map.lot_styles.has(cell), "%s is a house, not a lot" % cell)
	assert_eq(_raw["period_houses"].size(), HOUSES.size())
	for entry: Dictionary in _raw["period_houses"]:
		assert_string_starts_with(str(entry["history"]), "[INVENTED]", str(entry["cell"]))
		assert_false(entry.has("building"), "Always dense housing (D-083): the field would be a second source")
		var cell: Vector2i = Vector2i(int(entry["cell"][0]), int(entry["cell"][1]))
		var on_vii_87: bool = cell in HOUSES_ON_VII_87
		assert_eq(str(entry["source"]).contains("sheet VII.87"), on_vii_87, "Sheet of %s" % cell)
		assert_eq(str(entry["source"]).contains("VII.77"), not on_vii_87, "Only (8,6) is in the corner of VII.77")


# Issue #180 (D-085): the four houses start with nobody, a value of the map's data.
func test_the_period_houses_start_empty() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	for entry: Dictionary in _raw["period_houses"]:
		assert_eq(entry.get("start_population"), 0.0, "start_population is written in the map (%s)" % str(entry["cell"]))
	for cell: Vector2i in HOUSES:
		assert_eq(map.period_house_population.get(cell), 0, str(cell))


func test_the_damaged_wharf_is_an_invented_river_cell() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	assert_eq(map.damaged_wharves, [DAMAGED_WHARF] as Array[Vector2i])
	var area: Rect2i = _area(RepairWharfCommand.WHARF, DAMAGED_WHARF)
	for cell: Vector2i in EconomyContext.cells_of(area):
		assert_true(cell in map.river_cells, "Water, like the cells of a wharf: %s" % cell)
	assert_true(map.beside_road(area), "A wharf works only beside a street")
	assert_false(map.anchors.has(DAMAGED_WHARF), "Nothing stands there yet")
	var entry: Dictionary = _raw["damaged_wharves"][0]
	# Issue #177 (Cristian, 2026-10-19): the repair cost lives once, in economy/repair.json, not in the map.
	assert_false(entry.has("repair_cost_ratio"), "Read through Params as repair.wharf_cost_ratio")
	assert_false(str(entry["history"]).contains("repair_cost_ratio"))
	assert_string_starts_with(str(entry["history"]), "[INVENTED]")
	# Cristian's rule: a damaged wharf never takes the name of a real one.
	assert_string_contains(str(entry["history"]), "fronts the real Swan/Sun Wharf frontage; not one of them")


func test_every_free_lot_has_one_style_and_nothing_else_has_one() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	var houses: Array[Vector2i] = _house_cells()
	for y: int in range(map.height):
		for x: int in range(map.width):
			var cell: Vector2i = Vector2i(x, y)
			assert_eq(map.lot_styles.has(cell), _is_free_land(map, cell) and cell not in houses, str(cell))
	assert_eq(map.lot_styles.size(), _raw["lot_styles"].values().reduce(
		func(total: int, cells: Array) -> int: return total + cells.size(), 0), "Each cell listed once")
	assert_string_contains("\n".join(_raw["history_notes"]), "[INVENTED] Lot styles")
	for cell: Vector2i in FACT_CELLS:
		assert_eq(map.lot_styles.get(cell), NEUTRAL_STYLE, "%s is a real place of the sheets" % cell)
	assert_false(&"ropewalk" in map.lot_styles.values(), "(4-11,4-5) is inside the London Docks wall (1805)")


func test_the_free_cell_count_is_the_same_as_in_152() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	assert_eq(_free_cells(map), FREE_TOTAL, "Total")
	assert_eq(_free_cells(map, NO_SHEET_CORNER), FREE_WITHOUT_CORNER, "Without the north-west corner")
