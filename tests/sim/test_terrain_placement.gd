extends GutTest

# Issue #88, task 3: building by terrain, cell by cell of the footprint (D-149, D-151, D-152). The wharf's north row
# stands on the riverbank and its south row on the river; the mill and the malthouse go on firm ground or riverbank;
# the brewery, the houses and the services only on firm ground; nothing on a marsh until it is drained (D-136).
# On whitechapel_1850s the river is rows 14 and 15 and the riverbank rows 12 and 13; everything above is firm ground.

const MAP: StringName = &"whitechapel_1850s"
const WHARF: StringName = &"wharf"
const BOTH_TERRAINS: Array[StringName] = [&"mill", &"malthouse"]
# The north-west corner of a 2x2 block: on the riverbank row and the river below it, or wholly on firm ground.
const ON_THE_SHORE: Vector2i = Vector2i(4, 13)
const FIRM_BLOCK: Vector2i = Vector2i(4, 4)
# A block the tests relabel as riverbank or marsh.
const LABELLED_BLOCK: Vector2i = Vector2i(8, 8)

var _catalog: DataCatalog
var _context: EconomyContext
var _initial: EconomyState


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[MAP])
	_initial = EconomyState.new()
	_initial.money = 100000
	_initial.stocks.assign({&"wheat": 0, &"flour": 0, &"bread": 0})


func _label(origin: Vector2i, terrain: StringName) -> void:
	for cell: Vector2i in EconomyContext.cells_of(Rect2i(origin, _catalog.buildings[WHARF].footprint)):
		if terrain == &"firm":
			_context.map.terrain.erase(cell)
		else:
			_context.map.terrain[cell] = terrain


func _build(id: StringName, cell: Vector2i) -> BuildCommand:
	var sim: Simulation = Simulation.new(SimTestParams.isolated_params(_catalog), _initial, 7, _context)
	var command: BuildCommand = BuildCommand.new(_context, id, cell)
	sim.apply_command(command)
	sim.tick()
	if command.accepted:
		assert_eq(sim.snapshot()["economy"]["buildings"].size(), 1, id)
	else:
		assert_eq(sim.snapshot()["economy"]["money"], _initial.money, "%s: a refused build spends nothing" % id)
	return command


func _assert_built(id: StringName, cell: Vector2i) -> void:
	var command: BuildCommand = _build(id, cell)
	assert_true(command.accepted, "%s at %s: %s" % [id, cell, command.reason])


func _assert_refused(id: StringName, cell: Vector2i, reason: StringName) -> void:
	var command: BuildCommand = _build(id, cell)
	assert_false(command.accepted, "%s at %s" % [id, cell])
	assert_eq(command.reason, reason, "%s at %s" % [id, cell])


# The buildings the player places on firm ground only: everything but the wharf, the mill, the malthouse and the
# wheat field, which also needs a cultivable cell.
func _firm_only() -> Array[StringName]:
	var found: Array[StringName] = []
	for definition: BuildingDef in _catalog.buildings.values():
		if definition.buildable and "cultivable" not in definition.tags \
				and definition.allowed_terrain == ([&"firm"] as Array[StringName]):
			found.append(definition.id)
	return found


func test_the_wharf_stands_on_the_riverbank_and_the_river() -> void:
	_assert_built(WHARF, ON_THE_SHORE)


func test_the_wharf_is_refused_on_firm_ground() -> void:
	_assert_refused(WHARF, FIRM_BLOCK, &"requires_riverbank")


func test_the_wharf_needs_the_riverbank_cell_by_cell() -> void:
	# Firm ground beside the water is not yet riverbank (D-148): the north row must be labelled.
	_label(ON_THE_SHORE, &"firm")
	_assert_refused(WHARF, ON_THE_SHORE, &"requires_riverbank")


func test_the_wharf_is_refused_wholly_on_the_river() -> void:
	# Its north row asks for land: the old wharf of four river cells is no longer a wharf.
	_assert_refused(WHARF, ON_THE_SHORE + Vector2i.DOWN, &"requires_land")


func test_the_wharf_is_refused_wholly_on_the_riverbank() -> void:
	_label(LABELLED_BLOCK, &"riverbank")
	_assert_refused(WHARF, LABELLED_BLOCK, &"requires_river")


func test_mill_and_malthouse_go_on_firm_ground_or_riverbank() -> void:
	for id: StringName in BOTH_TERRAINS:
		_assert_built(id, FIRM_BLOCK)
	_label(LABELLED_BLOCK, &"riverbank")
	for id: StringName in BOTH_TERRAINS:
		_assert_built(id, LABELLED_BLOCK)


func test_brewery_houses_and_services_go_only_on_firm_ground() -> void:
	var firm_only: Array[StringName] = _firm_only()
	for id: StringName in [&"brewery", &"housing", &"artisan_housing", &"health_post", &"fire_station",
			&"police_station"]:
		assert_has(firm_only, id)
	_label(LABELLED_BLOCK, &"riverbank")
	# Water buildings wait for the events to be built at all, so the map's answer is checked for every one.
	for id: StringName in firm_only:
		assert_eq(_context.placement_reason(id, FIRM_BLOCK), &"", id)
		assert_eq(_context.placement_reason(id, LABELLED_BLOCK), &"requires_firm", id)
	for id: StringName in [&"brewery", &"housing", &"police_station"]:
		_assert_built(id, FIRM_BLOCK)
		_assert_refused(id, LABELLED_BLOCK, &"requires_firm")


func test_one_riverbank_cell_of_the_footprint_is_enough_to_refuse_a_house() -> void:
	# Rows 11 and 12: only the south row is riverbank.
	_assert_refused(&"housing", ON_THE_SHORE + Vector2i.UP * 2, &"requires_firm")
	_assert_built(&"mill", ON_THE_SHORE + Vector2i.UP * 2)


func test_nothing_is_built_on_a_marsh() -> void:
	_label(LABELLED_BLOCK, &"marsh")
	for id: StringName in [&"mill", &"brewery", &"housing", WHARF]:
		_assert_refused(id, LABELLED_BLOCK, &"marsh")


func test_the_map_offers_the_wharf_only_where_the_shore_fits() -> void:
	assert_eq(_context.building_unavailable_reason(WHARF), &"")
	# Riverbank only away from the water: no north row of riverbank stands on the river.
	for x: int in range(_context.map.width):
		_context.map.terrain.erase(Vector2i(x, 13))
	assert_eq(_context.building_unavailable_reason(WHARF), &"requires_river")
