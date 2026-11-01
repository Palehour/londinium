extends GutTest

# Issue #296 (D-157): a quarter turn rotates the footprint and, when there is one, the terrain mask, together.
# The wharf does not rotate and keeps the mask of D-155. rotation is 0 to 3, clockwise, and a save keeps it.
# A save from before the field loads as 0. Sizes come from data (D-156); this file does not invent one.

const MAP: StringName = &"whitechapel_1850s"
const SHORE: Vector2i = Vector2i(4, 13)
const FIRM: Vector2i = Vector2i(4, 4)
const MASK_ORIGIN: Vector2i = Vector2i(4, 11)

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


func _run(command: SimulationCommand) -> Simulation:
	var sim: Simulation = Simulation.new(SimTestParams.isolated_params(_catalog), _initial, 7, _context)
	sim.apply_command(command)
	sim.tick()
	return sim


func test_rotating_swaps_the_footprint_and_the_mask_together() -> void:
	var malthouse: BuildingDef = _context.buildings[&"malthouse"]
	malthouse.footprint = Vector2i(2, 1)
	malthouse.terrain_mask = [&"firm", &"riverbank"] as Array[StringName]
	# East of the origin is firm until labelled; south of it is the riverbank row.
	_context.map.terrain[MASK_ORIGIN + Vector2i.RIGHT] = &"riverbank"
	var flat: BuildCommand = BuildCommand.new(_context, &"malthouse", MASK_ORIGIN, 0)
	var turned: BuildCommand = BuildCommand.new(_context, &"malthouse", MASK_ORIGIN, 1)
	var wrong_side: BuildCommand = BuildCommand.new(_context, &"malthouse", MASK_ORIGIN + Vector2i.RIGHT, 1)
	assert_eq(_run(flat).snapshot()["economy"]["buildings"].size(), 1, flat.reason)
	var placed_sim: Simulation = _run(turned)
	assert_eq(placed_sim.snapshot()["economy"]["buildings"].size(), 1, turned.reason)
	assert_eq(_run(wrong_side).snapshot()["economy"]["buildings"].size(), 0)
	assert_eq(wrong_side.reason, &"requires_firm")
	var placed: Dictionary = placed_sim.snapshot()["economy"]["buildings"][0]
	assert_eq(int(placed["rotation"]), 1)
	assert_eq(_context.area_of(placed).size, Vector2i(1, 2))


func test_the_wharf_does_not_rotate() -> void:
	var turned: BuildCommand = BuildCommand.new(_context, &"wharf", SHORE, 1)
	var sim: Simulation = _run(turned)
	assert_false(turned.accepted)
	assert_eq(turned.reason, &"cannot_rotate")
	assert_eq(sim.snapshot()["economy"]["buildings"], [])
	assert_eq(_catalog.buildings[&"wharf"].terrain_mask, [&"riverbank", &"riverbank", &"river", &"river"] as Array[StringName])
	var standing: BuildCommand = BuildCommand.new(_context, &"wharf", SHORE, 0)
	assert_true(_run(standing).snapshot()["economy"]["buildings"].size() == 1, standing.reason)
	assert_false(_catalog.buildings[&"wharf"].rotates)


func test_one_cell_of_the_rotated_footprint_is_enough_to_refuse() -> void:
	_context.map.terrain[FIRM + Vector2i.DOWN] = &"marsh"
	var turned: BuildCommand = BuildCommand.new(_context, &"malthouse", FIRM, 1)
	var flat: BuildCommand = BuildCommand.new(_context, &"malthouse", FIRM, 0)
	assert_false(_run(turned).snapshot()["economy"]["buildings"].size() == 1)
	assert_eq(turned.reason, &"marsh")
	var sim: Simulation = _run(flat)
	assert_eq(sim.snapshot()["economy"]["buildings"].size(), 1, flat.reason)
	assert_eq(_context.area_of(sim.snapshot()["economy"]["buildings"][0]).size, Vector2i(2, 1))


func test_a_save_keeps_the_rotation_and_an_old_building_loads_unrotated() -> void:
	var sim: Simulation = _run(BuildCommand.new(_context, &"malthouse", FIRM, 1))
	var placed: Dictionary = sim.snapshot()["economy"]["buildings"][0]
	assert_eq(int(placed["rotation"]), 1)
	var restored: EconomyState = EconomyState.from_dict(sim.to_save()["economy"])
	assert_eq(int(restored.buildings[0]["rotation"]), 1)
	assert_eq(_context.area_of(restored.buildings[0]).size, Vector2i(1, 2))
	var without: Dictionary = sim.to_save()["economy"]
	without["buildings"][0].erase("rotation")
	var old: EconomyState = EconomyState.from_dict(without)
	assert_false(old.buildings[0].has("rotation"))
	assert_eq(_context.area_of(old.buildings[0]).size, Vector2i(2, 1))


func test_a_version_2_save_gains_rotation_without_moving_cells() -> void:
	var saved: Dictionary = {"version": SaveFile.BEFORE_ROTATION_VERSION, "simulation": {"economy": {
		"buildings": [{"definition_id": "malthouse", "cell": [4, 6]}],
		"player_roads": [{"cell": [1, 2]}],
	}}}
	var upgraded: Dictionary = SaveFile.upgraded(saved, 25)
	assert_eq(upgraded["version"], SaveFile.VERSION)
	assert_eq(upgraded["simulation"]["economy"]["buildings"][0]["cell"], [4, 6])
	assert_eq(upgraded["simulation"]["economy"]["buildings"][0]["rotation"], 0)
	assert_eq(upgraded["simulation"]["economy"]["player_roads"][0]["cell"], [1, 2])
	saved["version"] = SaveFile.CELLS_OF_50_M_VERSION
	var scaled: Dictionary = SaveFile.upgraded(saved, 25)
	assert_eq(scaled["simulation"]["economy"]["buildings"][0]["cell"], [8, 12])
	assert_eq(scaled["simulation"]["economy"]["buildings"][0]["rotation"], 0)


func test_rotation_outside_0_to_3_is_refused() -> void:
	var command: BuildCommand = BuildCommand.new(_context, &"malthouse", FIRM, 4)
	assert_false(_run(command).snapshot()["economy"]["buildings"].size() == 1)
	assert_eq(command.reason, &"cannot_rotate")
