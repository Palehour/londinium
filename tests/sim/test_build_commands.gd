extends GutTest

var _catalog: DataCatalog
var _params: Params
var _context: EconomyContext
var _initial: EconomyState


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	_initial = EconomyState.new()
	_initial.money = 10000
	_initial.stocks.assign({&"wheat": 0, &"flour": 0, &"bread": 0})


func _sim() -> Simulation:
	return Simulation.new(_params, _initial, 123, _context)


func _reject(id: StringName, cell: Vector2i, expected_reason: StringName) -> void:
	var sim: Simulation = _sim()
	var before: Dictionary = sim.snapshot()["economy"]
	var command: BuildCommand = BuildCommand.new(_context, id, cell)
	sim.apply_command(command)
	sim.tick()
	assert_false(command.accepted)
	assert_eq(command.reason, expected_reason)
	assert_eq(sim.snapshot()["economy"], before, "Rejected commands have no economic effects")


func test_build_is_deferred_and_charges_cost_once() -> void:
	var sim: Simulation = _sim()
	var command: BuildCommand = BuildCommand.new(_context, &"bakery", Vector2i(2, 3))
	var before: Dictionary = sim.snapshot()
	sim.apply_command(command)
	assert_eq(command.reason, &"pending")
	assert_eq(sim.snapshot(), before)
	sim.tick()
	assert_true(command.accepted)
	assert_eq(command.reason, &"")
	var after: Dictionary = sim.snapshot()["economy"]
	assert_eq(after["money"], _initial.money - int(_params.get_value(&"building.bakery.cost")))
	assert_eq(after["buildings"].size(), 1)
	assert_eq(after["buildings"][0]["definition_id"], &"bakery")
	assert_eq(after["buildings"][0]["cell"], [2, 3])
	sim.tick()
	assert_eq(sim.snapshot()["economy"]["money"], after["money"])


func test_whitechapel_rejects_field_on_every_non_cultivable_cell_with_reason() -> void:
	assert_true(_context.map.cultivable_cells.is_empty())
	for x: int in range(_context.map.width):
		for y: int in range(_context.map.height):
			_reject(&"wheat_field", Vector2i(x, y), &"not_cultivable")


func test_synthetic_cultivable_map_allows_field_and_charges_params_cost() -> void:
	_context.map.cultivable_cells.append(Vector2i(1, 1))
	var sim: Simulation = _sim()
	var command: BuildCommand = BuildCommand.new(_context, &"wheat_field", Vector2i(1, 1))
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted)
	assert_eq(sim.snapshot()["economy"]["buildings"].size(), 1)
	assert_eq(sim.snapshot()["economy"]["money"],
		_initial.money - int(_params.get_value(&"building.wheat_field.cost")))
	assert_true(_catalog.maps[&"whitechapel_1850s"].cultivable_cells.is_empty())


func test_wharf_requires_river_and_land_buildings_cannot_use_river() -> void:
	_reject(&"wharf", Vector2i(1, 1), &"requires_river")
	_reject(&"mill", Vector2i(0, 7), &"requires_land")
	var sim: Simulation = _sim()
	var command: BuildCommand = BuildCommand.new(_context, &"wharf", Vector2i(0, 7))
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted)


func test_unknown_building_out_of_bounds_and_insufficient_funds_are_rejected() -> void:
	_reject(&"tea_importer", Vector2i(1, 1), &"unknown_building")
	for cell: Vector2i in [Vector2i(-1, 1), Vector2i(1, -1), Vector2i(8, 1), Vector2i(1, 8)]:
		_reject(&"bakery", cell, &"outside_map")
	_initial.money = int(_params.get_value(&"building.bakery.cost")) - 1
	_reject(&"bakery", Vector2i(1, 1), &"insufficient_money")


func test_two_builds_on_same_cell_are_processed_fifo_and_second_is_rejected() -> void:
	var sim: Simulation = _sim()
	var first: BuildCommand = BuildCommand.new(_context, &"bakery", Vector2i(1, 1))
	var second: BuildCommand = BuildCommand.new(_context, &"mill", Vector2i(1, 1))
	sim.apply_command(first)
	sim.apply_command(second)
	sim.tick()
	assert_true(first.accepted)
	assert_false(second.accepted)
	assert_eq(second.reason, &"occupied_cell")
	assert_eq(sim.snapshot()["economy"]["buildings"].size(), 1)
	assert_eq(sim.snapshot()["economy"]["money"],
		_initial.money - int(_params.get_value(&"building.bakery.cost")))


func test_demolish_is_deferred_preserves_global_stock_and_has_no_refund() -> void:
	_initial.buildings.append({"definition_id": &"bakery", "cell": [1, 1],
		"reserved_input": 0.5, "output_fraction": 0.75})
	_initial.stocks[&"flour"] = 4
	_initial.stocks[&"bread"] = 2
	var sim: Simulation = _sim()
	var command: DemolishCommand = DemolishCommand.new(Vector2i(1, 1))
	var before: Dictionary = sim.snapshot()
	sim.apply_command(command)
	assert_eq(sim.snapshot(), before)
	sim.tick()
	assert_true(command.accepted)
	assert_eq(command.reason, &"")
	var state: Dictionary = sim.snapshot()["economy"]
	assert_true(state["buildings"].is_empty())
	assert_eq(state["stocks"], _initial.stocks)
	assert_eq(state["money"], _initial.money)


func test_demolish_empty_cell_rejects_without_mutation() -> void:
	var sim: Simulation = _sim()
	var before: Dictionary = sim.snapshot()["economy"]
	var command: DemolishCommand = DemolishCommand.new(Vector2i(1, 1))
	sim.apply_command(command)
	sim.tick()
	assert_false(command.accepted)
	assert_eq(command.reason, &"no_building")
	assert_eq(sim.snapshot()["economy"], before)


func test_demolition_frees_cell_for_rebuild_without_reusing_fractions() -> void:
	_initial.buildings.append({"definition_id": &"bakery", "cell": [1, 1],
		"reserved_input": 0.5, "output_fraction": 0.75})
	var sim: Simulation = _sim()
	var demolish: DemolishCommand = DemolishCommand.new(Vector2i(1, 1))
	var rebuild: BuildCommand = BuildCommand.new(_context, &"bakery", Vector2i(1, 1))
	sim.apply_command(demolish)
	sim.apply_command(rebuild)
	sim.tick()
	assert_true(demolish.accepted)
	assert_true(rebuild.accepted)
	var building: Dictionary = sim.snapshot()["economy"]["buildings"][0]
	assert_eq(building["reserved_input"], 0.0)
	assert_eq(building["output_fraction"], 0.0)


func test_commands_precede_workers_and_production_and_demolition_reassigns_workers() -> void:
	_initial.population = 3
	_initial.stocks[&"wheat"] = 2
	_initial.buildings.append({"definition_id": &"mill", "cell": [1, 1]})
	var sim: Simulation = _sim()
	var build: BuildCommand = BuildCommand.new(_context, &"bakery", Vector2i(2, 1))
	sim.apply_command(build)
	sim.tick()
	var state: Dictionary = sim.snapshot()["economy"]
	assert_eq(state["buildings"][0]["workers"], 0)
	assert_eq(state["buildings"][1]["workers"], 3)
	assert_eq(state["stocks"][&"wheat"], 2)
	sim.apply_command(DemolishCommand.new(Vector2i(2, 1)))
	sim.tick()
	state = sim.snapshot()["economy"]
	assert_eq(state["buildings"][0]["workers"], 3)
	assert_eq(state["stocks"][&"wheat"], 1)


func test_build_cost_applies_all_modifiers_and_rounds_only_at_end() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"building.bakery.cost", &"set", 1),
		Modifier.new(&"building.bakery.cost", &"mul", 0.5),
		Modifier.new(&"building.bakery.cost", &"mul", 3)])
	_params = Params.new(_catalog, role)
	_initial.money = 2
	var sim: Simulation = _sim()
	var command: BuildCommand = BuildCommand.new(_context, &"bakery", Vector2i(1, 1))
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted)
	assert_eq(sim.snapshot()["economy"]["money"], 0)


func test_context_and_queued_build_copy_structural_data() -> void:
	var sim: Simulation = _sim()
	var command: BuildCommand = BuildCommand.new(_context, &"wharf", Vector2i(0, 7))
	_context.map.river_cells.clear()
	_context.buildings[&"wharf"].tags.clear()
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted)
	assert_false(_catalog.maps[&"whitechapel_1850s"].river_cells.is_empty())
