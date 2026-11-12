extends GutTest

# Issue #370 (D-193/D-194/D-195): mourning from cholera deaths, burial assignment to cemeteries,
# the St Mary Matfelon atrium anchor and the player cemetery.

const WHITECHAPEL: StringName = &"whitechapel_full"
const ATRIUM_CELL: Vector2i = Vector2i(24, 14)

var _catalog: DataCatalog


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog


func _mourning_params(catalog: DataCatalog) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"mourning.enabled", &"set", 1))
	return SimTestParams.isolated_params(catalog, role)


func _params(catalog: DataCatalog) -> Params:
	return SimTestParams.isolated_params(catalog)


func _context(map_id: StringName) -> EconomyContext:
	return EconomyContext.new(_catalog, _catalog.maps[map_id])


func _sim(state: EconomyState, params: Params, map_id: StringName) -> Simulation:
	return Simulation.new(params, state, 7, _context(map_id))


func test_mourning_is_disabled_by_default() -> void:
	assert_false(bool(_params(_catalog).get_value(&"mourning.enabled")))


func test_st_mary_atrium_is_placed_in_whitechapel_full() -> void:
	var params: Params = _params(_catalog)
	var sim: Simulation = Simulation.create_new(params, EconomyState.new(), 1, _context(WHITECHAPEL))
	var found: bool = false
	for building: Dictionary in sim.snapshot()["economy"]["buildings"]:
		if building["definition_id"] == &"st_mary_atrium" and building["cell"] == [ATRIUM_CELL.x, ATRIUM_CELL.y]:
			found = true
			break
	assert_true(found)


func test_player_cemetery_cannot_be_built_while_mourning_disabled() -> void:
	var params: Params = _params(_catalog)
	var state: EconomyState = EconomyState.new()
	state.money = 10000
	var sim: Simulation = _sim(state, params, WHITECHAPEL)
	var command: BuildCommand = BuildCommand.new(_context(WHITECHAPEL), &"cemetery", Vector2i(2, 2))
	sim.apply_command(command)
	sim.tick()
	assert_false(command.accepted)
	assert_eq(command.reason, &"mourning_disabled")


func test_player_cemetery_can_be_built_when_mourning_enabled() -> void:
	var params: Params = _mourning_params(_catalog)
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	state.money = 10000
	var sim: Simulation = _sim(state, params, WHITECHAPEL)
	var command: BuildCommand = BuildCommand.new(_context(WHITECHAPEL), &"cemetery", Vector2i(2, 2))
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted, str(command.reason))


func test_occupied_cemetery_cannot_be_demolished() -> void:
	var params: Params = _mourning_params(_catalog)
	var state: EconomyState = EconomyState.new()
	state.money = 10000
	state.buildings.append({"definition_id": &"cemetery", "cell": [2, 2], "buried": 1})
	var sim: Simulation = _sim(state, params, WHITECHAPEL)
	var command: DemolishCommand = DemolishCommand.new(Vector2i(2, 2))
	sim.apply_command(command)
	sim.tick()
	assert_false(command.accepted)
	assert_eq(command.reason, &"cemetery_occupied")


func test_empty_cemetery_can_be_demolished() -> void:
	var params: Params = _mourning_params(_catalog)
	var state: EconomyState = EconomyState.new()
	state.money = 10000
	state.buildings.append({"definition_id": &"cemetery", "cell": [2, 2]})
	var sim: Simulation = _sim(state, params, WHITECHAPEL)
	var command: DemolishCommand = DemolishCommand.new(Vector2i(2, 2))
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted, str(command.reason))


func test_burial_prefers_the_nearest_cemetery_with_capacity() -> void:
	var params: Params = _mourning_params(_catalog)
	var context: EconomyContext = _context(WHITECHAPEL)
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	state.population = 100
	# Two houses in Whitechapel district.
	state.buildings.append({"definition_id": &"housing", "cell": [20, 12]})
	state.buildings.append({"definition_id": &"housing", "cell": [22, 12]})
	# A player cemetery close to the houses; no preplaced atrium in this direct state.
	state.buildings.append({"definition_id": &"cemetery", "cell": [20, 10]})

	MourningSystem.assign_deaths(state, params, context, {&"whitechapel": 5})
	assert_eq(int(state.mourning_buried.get(&"whitechapel", 0)), 5)
	assert_eq(int(state.mourning_unburied.get(&"whitechapel", 0)), 0)

	# Fill the player cemetery by hand and check overflow goes unburied.
	for building: Dictionary in state.buildings:
		if building["definition_id"] == &"cemetery":
			building["buried"] = int(params.get_value(&"cemetery.player.capacity"))
	MourningSystem.assign_deaths(state, params, context, {&"whitechapel": 3})
	assert_eq(int(state.mourning_unburied.get(&"whitechapel", 0)), 3)


func test_unburied_deaths_decay_over_time() -> void:
	var params: Params = _mourning_params(_catalog)
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	state.mourning_unburied[&"whitechapel"] = 100.0
	var before: float = state.mourning_unburied[&"whitechapel"]
	MourningSystem.tick(state, params)
	var after: float = state.mourning_unburied[&"whitechapel"]
	assert_lt(after, before)
	assert_gt(after, 0.0)


func test_mourning_adds_a_satisfaction_penalty() -> void:
	var params: Params = _mourning_params(_catalog)
	var context: EconomyContext = _context(WHITECHAPEL)
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	state.population = 100
	state.buildings.append({"definition_id": &"housing", "cell": [20, 12]})
	state.mourning_unburied[&"whitechapel"] = 50.0

	var worker: ClassDef = context.classes[&"worker"]
	SatisfactionSystem.new().update_target(state, params, context)
	var breakdown: Dictionary = ClassStates.satisfaction_breakdown_of(state, worker)
	assert_true(breakdown.has("mourning"))
	assert_gt(breakdown["mourning"], 0.0)


func test_save_load_preserves_mourning_state() -> void:
	var params: Params = _mourning_params(_catalog)
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	state.mourning_unburied[&"whitechapel"] = 12.0
	state.mourning_buried[&"whitechapel"] = 8.0
	var sim: Simulation = _sim(state, params, WHITECHAPEL)
	var saved: Dictionary = bytes_to_var(var_to_bytes(sim.to_save()))
	var loaded: Simulation = Simulation.from_save(params, _context(WHITECHAPEL), [], saved)
	var economy: Dictionary = loaded.snapshot()["economy"]
	assert_true(economy.get("mourning_enabled", false))
	assert_eq(economy["mourning_unburied"]["whitechapel"], 12.0)
	assert_eq(economy["mourning_buried"]["whitechapel"], 8.0)
