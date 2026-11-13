extends GutTest

# Issue #370 (D-192..D-195): mourning from cholera deaths, burial assignment to cemeteries, the St Mary Matfelon atrium
# anchor (4x4, not demolishable) and the player cemetery (4x4, 400 d, 1 d/min).

const WHITECHAPEL: StringName = &"whitechapel_full"
const STRIP: StringName = &"whitechapel_1850s"
const ATRIUM: StringName = &"st_mary_atrium"
const CEMETERY: StringName = &"cemetery"
const ATRIUM_CELL: Vector2i = Vector2i(24, 14)
const ATRIUM_SIDE: int = 4
const OLDFORD: StringName = &"oldford"
const WEST: StringName = &"west"
const EAST: StringName = &"east"
const SPLIT_X: int = 8
const SEED: int = 7
# Ticks the satisfaction needs, after the check that kills, to settle on the new target.
const SETTLE_TICKS: int = 3

var _catalog: DataCatalog


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog


func _mourning_params(extra: Array[Modifier] = []) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"mourning.enabled", &"set", 1))
	role.modifiers.append_array(extra)
	return SimTestParams.isolated_params(_catalog, role)


func _params() -> Params:
	return SimTestParams.isolated_params(_catalog)


func _context(map_id: StringName) -> EconomyContext:
	return EconomyContext.new(_catalog, _catalog.maps[map_id])


func _sim(state: EconomyState, params: Params, map_id: StringName) -> Simulation:
	return Simulation.new(params, state, SEED, _context(map_id))


func _at(id: StringName, cell: Vector2i, extra: Dictionary = {}) -> Dictionary:
	var building: Dictionary = {"definition_id": id, "cell": [cell.x, cell.y]}
	building.merge(extra)
	return building


# The first cell where a player cemetery fits on the full map (terrain, streets, standing buildings).
func _free_cell(context: EconomyContext) -> Vector2i:
	for y: int in range(context.map.height):
		for x: int in range(context.map.width):
			if context.placement_reason(CEMETERY, Vector2i(x, y), 0) == &"":
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _cemeteries(state: EconomyState) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for building: Dictionary in state.buildings:
		if building["definition_id"] == CEMETERY:
			found.append(building)
	return found


# -- data of D-193, D-194, D-195 --------------------------------------------------------------------------------------

func test_mourning_is_disabled_by_default() -> void:
	assert_false(bool(_params().get_value(&"mourning.enabled")))


func test_the_atrium_and_the_player_cemetery_have_the_decided_data() -> void:
	# The data as shipped: the isolated params of the sim tests zero the money sinks.
	var params: Params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	var atrium: BuildingDef = _catalog.buildings[ATRIUM]
	assert_eq(atrium.footprint, Vector2i(ATRIUM_SIDE, ATRIUM_SIDE))
	assert_false(atrium.buildable)
	assert_eq(params.get_value(&"building.st_mary_atrium.cost"), 0)
	assert_eq(params.get_value(&"building.st_mary_atrium.jobs"), 0)
	var cemetery: BuildingDef = _catalog.buildings[CEMETERY]
	assert_eq(cemetery.footprint, Vector2i(ATRIUM_SIDE, ATRIUM_SIDE))
	assert_true(cemetery.buildable)
	assert_eq(params.get_value(&"building.cemetery.cost"), 400)
	assert_eq(params.get_value(&"building.cemetery.upkeep_per_minute"), 1)
	assert_eq(params.get_value(&"building.cemetery.jobs"), 0)
	assert_eq(float(params.get_value(&"cemetery.preplaced.radius_m")), 300.0)
	assert_eq(float(params.get_value(&"cemetery.player.radius_m")), 300.0)
	assert_eq(float(params.get_value(&"satisfaction.mourning.buried_factor")), 0.0)


func test_the_placeholders_say_so_in_their_data_files() -> void:
	for file: String in ["satisfaction", "cemetery"]:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/economy/%s.json" % file))
		assert_string_contains(String(raw["documentation"]), "a ajustar por harness", file)
		assert_string_contains(String(raw["documentation"]), "D-066", file)


func test_every_scenario_before_this_one_states_mourning_off() -> void:
	for scenario: String in ["whitechapel_full", "victorian_demo", "border_import"]:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/%s.json" % scenario))
		assert_true(raw.has("mourning_enabled"), scenario)
		assert_false(raw["mourning_enabled"], scenario)
		assert_false(_catalog.scenarios[StringName(scenario)]["mourning_enabled"], scenario)


# -- the atrium (D-192, D-193, D-195) ---------------------------------------------------------------------------------

func test_st_mary_atrium_is_placed_in_whitechapel_full_even_with_mourning_off() -> void:
	var params: Params = _params()
	assert_false(bool(params.get_value(&"mourning.enabled")))
	var sim: Simulation = Simulation.create_new(params, EconomyState.new(), 1, _context(WHITECHAPEL))
	var found: bool = false
	for building: Dictionary in sim.snapshot()["economy"]["buildings"]:
		if building["definition_id"] == ATRIUM and building["cell"] == [ATRIUM_CELL.x, ATRIUM_CELL.y]:
			found = true
	assert_true(found)


func test_the_atrium_footprint_is_firm_free_land_beside_a_street() -> void:
	var map: MapDef = _catalog.maps[WHITECHAPEL]
	var area: Rect2i = Rect2i(ATRIUM_CELL, Vector2i(ATRIUM_SIDE, ATRIUM_SIDE))
	for cell: Vector2i in EconomyContext.cells_of(area):
		assert_true(cell in map.existing_cells, "%s is a standing cell" % cell)
		assert_false(cell in map.road_cells or cell in map.river_cells or cell in map.dock_cells
			or cell in map.stairs_cells, "%s is firm ground, no street" % cell)
	assert_true(map.beside_road(area))
	assert_eq(map.existing_cells.size(), ATRIUM_SIDE * ATRIUM_SIDE, "Only the atrium stands on this map")
	assert_eq(map.anchors[ATRIUM_CELL], ATRIUM)


func test_the_atrium_carries_its_historical_ref_and_a_player_cemetery_does_not() -> void:
	var map: MapDef = _catalog.maps[WHITECHAPEL]
	var ref: Dictionary = map.anchor_historical_refs[ATRIUM_CELL]
	assert_eq(ref["name"], "St Mary Matfelon")
	assert_eq(ref["year"], 1866)
	assert_eq(ref["license"], "[INVENTED] liberty: reabierto")
	assert_string_contains(ref["source_note"], "C-03")
	assert_string_contains(ref["source_note"], "1854")
	assert_eq(map.anchor_historical_refs.size(), 1, "Only preplaced buildings carry it")
	var params: Params = _mourning_params()
	var context: EconomyContext = _context(WHITECHAPEL)
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	state.money = 10000
	var cell: Vector2i = _free_cell(context)
	assert_ne(cell, Vector2i(-1, -1))
	var build: BuildCommand = BuildCommand.new(context, CEMETERY, cell)
	build.execute(state, params, RandomNumberGenerator.new())
	assert_true(build.accepted, str(build.reason))
	assert_false(state.buildings[0].has("historical_ref"), "A player building does not inherit the card")
	assert_false(context.map.anchor_historical_refs.has(cell))


func test_the_atrium_cannot_be_demolished_from_any_cell_by_the_anchor_rule() -> void:
	var params: Params = _params()
	var context: EconomyContext = _context(WHITECHAPEL)
	var sim: Simulation = Simulation.create_new(params, EconomyState.new(), 1, context)
	for cell: Vector2i in [ATRIUM_CELL, ATRIUM_CELL + Vector2i(3, 3), ATRIUM_CELL + Vector2i(1, 2)]:
		var command: DemolishCommand = DemolishCommand.new(cell)
		sim.apply_command(command)
		sim.tick()
		assert_false(command.accepted, str(cell))
		assert_eq(command.reason, &"historic_anchor", str(cell))
	var still: bool = sim.snapshot()["economy"]["buildings"].any(
		func(building: Dictionary) -> bool: return building["definition_id"] == ATRIUM)
	assert_true(still)


func test_an_atrium_with_burials_is_still_refused_by_the_anchor_rule_first() -> void:
	var context: EconomyContext = _context(WHITECHAPEL)
	var state: EconomyState = EconomyState.new()
	state.buildings.append(_at(ATRIUM, ATRIUM_CELL, {"buried": 12}))
	var command: DemolishCommand = DemolishCommand.new(ATRIUM_CELL)
	command.use_context(context)
	command.execute(state, _params(), RandomNumberGenerator.new())
	assert_false(command.accepted)
	assert_eq(command.reason, &"historic_anchor")
	assert_eq(state.buildings.size(), 1)


# -- the player cemetery (D-195) --------------------------------------------------------------------------------------

func test_player_cemetery_cannot_be_built_while_mourning_disabled() -> void:
	var context: EconomyContext = _context(WHITECHAPEL)
	var state: EconomyState = EconomyState.new()
	state.money = 10000
	var sim: Simulation = Simulation.new(_params(), state, SEED, context)
	var command: BuildCommand = BuildCommand.new(context, CEMETERY, _free_cell(context))
	sim.apply_command(command)
	sim.tick()
	assert_false(command.accepted)
	assert_eq(command.reason, &"mourning_disabled")
	assert_eq(sim.get_building_unavailable_reason(CEMETERY), &"mourning_disabled")


func test_player_cemetery_can_be_built_when_mourning_enabled_and_costs_400() -> void:
	var context: EconomyContext = _context(WHITECHAPEL)
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	state.money = 10000
	var sim: Simulation = Simulation.new(_mourning_params(), state, SEED, context)
	var command: BuildCommand = BuildCommand.new(context, CEMETERY, _free_cell(context))
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted, str(command.reason))
	assert_eq(sim.snapshot()["economy"]["buildings"][0]["paid"], 400)


func test_occupied_cemetery_cannot_be_demolished() -> void:
	var context: EconomyContext = _context(WHITECHAPEL)
	var cell: Vector2i = _free_cell(context)
	var state: EconomyState = EconomyState.new()
	state.buildings.append(_at(CEMETERY, cell, {"buried": 1}))
	var command: DemolishCommand = DemolishCommand.new(cell)
	command.use_context(context)
	command.execute(state, _mourning_params(), RandomNumberGenerator.new())
	assert_false(command.accepted)
	assert_eq(command.reason, &"cemetery_occupied")
	assert_eq(state.buildings.size(), 1)


func test_empty_cemetery_can_be_demolished() -> void:
	var context: EconomyContext = _context(WHITECHAPEL)
	var cell: Vector2i = _free_cell(context)
	var state: EconomyState = EconomyState.new()
	state.buildings.append(_at(CEMETERY, cell))
	var command: DemolishCommand = DemolishCommand.new(cell)
	command.use_context(context)
	command.execute(state, _mourning_params(), RandomNumberGenerator.new())
	assert_true(command.accepted, str(command.reason))
	assert_true(state.buildings.is_empty())


# -- burial assignment (D-195) ----------------------------------------------------------------------------------------

# A 16x16 map in one district, so its centroid is (7.5, 7.5) and mirrored cemeteries are exactly equidistant.
func _one_district() -> EconomyContext:
	var context: EconomyContext = _context(STRIP)
	for x: int in range(context.map.width):
		for y: int in range(context.map.height):
			context.map.district_by_cell[Vector2i(x, y)] = WEST
	context.map.district_names[WEST] = "West"
	context.map.district_water_sources[WEST] = &"neutral"
	return context


func _capacity(params: Params) -> int:
	return int(params.get_value(&"cemetery.player.capacity"))


func test_burial_goes_to_the_nearest_cemetery_with_room() -> void:
	var params: Params = _mourning_params()
	var context: EconomyContext = _one_district()
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	state.buildings.append(_at(CEMETERY, Vector2i(10, 8)))
	state.buildings.append(_at(CEMETERY, Vector2i(5, 5)))
	MourningSystem.assign_deaths(state, params, context, {WEST: 5} as Dictionary[StringName, int])
	var near: Dictionary = state.buildings[1]
	var far: Dictionary = state.buildings[0]
	assert_eq(int(near.get("buried", 0)), 5, "The nearer one takes them")
	assert_eq(int(far.get("buried", 0)), 0)
	assert_eq(state.mourning_buried[WEST], 5.0)
	assert_eq(state.mourning_unburied.get(WEST, 0.0), 0.0)


func test_a_tie_in_distance_goes_to_the_stable_order_of_the_cells() -> void:
	var params: Params = _mourning_params()
	var context: EconomyContext = _one_district()
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	# Centres (3, 5) and (12, 10): the same distance from (7.5, 7.5). Listed with the later one first.
	state.buildings.append(_at(CEMETERY, Vector2i(10, 8)))
	state.buildings.append(_at(CEMETERY, Vector2i(1, 3)))
	MourningSystem.assign_deaths(state, params, context, {WEST: 3} as Dictionary[StringName, int])
	assert_eq(int(state.buildings[1].get("buried", 0)), 3, "The one at the lowest cell wins the tie")
	assert_eq(int(state.buildings[0].get("buried", 0)), 0)


func test_a_partly_full_cemetery_hands_the_rest_to_the_next_and_each_death_is_buried_once() -> void:
	var params: Params = _mourning_params()
	var context: EconomyContext = _one_district()
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	state.buildings.append(_at(CEMETERY, Vector2i(5, 5), {"buried": _capacity(params) - 2}))
	state.buildings.append(_at(CEMETERY, Vector2i(10, 8)))
	MourningSystem.assign_deaths(state, params, context, {WEST: 5} as Dictionary[StringName, int])
	assert_eq(int(state.buildings[0]["buried"]), _capacity(params), "The nearest fills up")
	assert_eq(int(state.buildings[1]["buried"]), 3, "The rest of the five go to the next")
	assert_eq(int(state.buildings[0]["buried"]) - (_capacity(params) - 2) + int(state.buildings[1]["buried"]), 5,
		"One death, one cemetery")
	assert_eq(state.mourning_unburied.get(WEST, 0.0), 0.0)


func test_with_no_room_or_no_cemetery_the_deaths_stay_unburied() -> void:
	var params: Params = _mourning_params()
	var context: EconomyContext = _one_district()
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	MourningSystem.assign_deaths(state, params, context, {WEST: 4} as Dictionary[StringName, int])
	assert_eq(state.mourning_unburied[WEST], 4.0, "No cemetery")
	state.buildings.append(_at(CEMETERY, Vector2i(5, 5), {"buried": _capacity(params)}))
	MourningSystem.assign_deaths(state, params, context, {WEST: 3} as Dictionary[StringName, int])
	assert_eq(state.mourning_unburied[WEST], 7.0, "A full one")
	assert_eq(int(state.buildings[0]["buried"]), _capacity(params))


func test_a_cemetery_out_of_reach_of_the_district_does_not_bury() -> void:
	var params: Params = _mourning_params([Modifier.new(&"cemetery.player.radius_m", &"set", 25.0)])
	var context: EconomyContext = _one_district()
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	state.buildings.append(_at(CEMETERY, Vector2i(0, 0)))
	MourningSystem.assign_deaths(state, params, context, {WEST: 2} as Dictionary[StringName, int])
	assert_eq(state.mourning_unburied[WEST], 2.0)
	assert_false(state.buildings[0].has("buried"))


func test_the_atrium_buries_with_its_own_capacity_and_radius() -> void:
	var params: Params = _mourning_params()
	var context: EconomyContext = _context(WHITECHAPEL)
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	state.buildings.append(_at(ATRIUM, ATRIUM_CELL))
	MourningSystem.assign_deaths(state, params, context, {&"whitechapel": 6} as Dictionary[StringName, int])
	assert_eq(int(state.buildings[0]["buried"]), 6)
	state.buildings[0]["buried"] = int(params.get_value(&"cemetery.preplaced.capacity"))
	MourningSystem.assign_deaths(state, params, context, {&"whitechapel": 2} as Dictionary[StringName, int])
	assert_eq(state.mourning_unburied[&"whitechapel"], 2.0, "A full atrium leaves the rest unburied")


# -- luto in the satisfaction (D-194) ---------------------------------------------------------------------------------

func test_unburied_deaths_decay_over_time() -> void:
	var params: Params = _mourning_params()
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	state.mourning_unburied[&"whitechapel"] = 100.0
	MourningSystem.tick(state, params)
	assert_lt(state.mourning_unburied[&"whitechapel"], 100.0)
	assert_gt(state.mourning_unburied[&"whitechapel"], 0.0)


func test_mourning_adds_a_satisfaction_penalty() -> void:
	var params: Params = _mourning_params()
	var context: EconomyContext = _context(WHITECHAPEL)
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	state.population = 100
	state.buildings.append(_at(&"housing", Vector2i(20, 12)))
	state.mourning_unburied[&"whitechapel"] = 50.0
	SatisfactionSystem.new().update_target(state, params, context)
	var breakdown: Dictionary = ClassStates.satisfaction_breakdown_of(state, context.classes[&"worker"])
	assert_gt(breakdown["mourning"], 0.0)


func test_a_burial_with_room_erases_the_mourning_of_that_death() -> void:
	var params: Params = _mourning_params()
	var context: EconomyContext = _one_district()
	var state: EconomyState = EconomyState.new()
	state.mourning_enabled = true
	state.population = 100
	state.buildings.append(_at(&"housing", Vector2i(0, 0)))
	state.buildings.append(_at(CEMETERY, Vector2i(5, 5)))
	MourningSystem.assign_deaths(state, params, context, {WEST: 10} as Dictionary[StringName, int])
	assert_eq(MourningSystem.district_mourning(state, params, context)[WEST], 0.0, "buried_factor is 0")
	assert_eq(MourningSystem.class_penalty(state, params, context, context.classes[&"worker"]), 0.0)


func test_with_mourning_off_nothing_is_buried_nothing_weighs_and_the_breakdown_is_the_legacy_one() -> void:
	var params: Params = _params()
	var context: EconomyContext = _one_district()
	var state: EconomyState = EconomyState.new()
	state.population = 100
	state.buildings.append(_at(&"housing", Vector2i(0, 0)))
	state.buildings.append(_at(CEMETERY, Vector2i(5, 5)))
	MourningSystem.assign_deaths(state, params, context, {WEST: 10} as Dictionary[StringName, int])
	assert_true(state.mourning_buried.is_empty())
	assert_true(state.mourning_unburied.is_empty())
	assert_false(state.buildings[1].has("buried"))
	state.mourning_unburied[WEST] = 50.0
	assert_eq(MourningSystem.class_penalty(state, params, context, context.classes[&"worker"]), 0.0)
	SatisfactionSystem.new().update_target(state, params, context)
	var breakdown: Dictionary = ClassStates.satisfaction_breakdown_of(state, context.classes[&"worker"])
	assert_false(breakdown.has("mourning"), "Same breakdown as before the mourning existed")
	assert_false(state.to_dict().has("mourning_enabled"), "And the same save")


# The outbreak of the issue on the two-parish fixture: West drinks Old Ford, which is cut, so it dies; East lives.
func _outbreak_context() -> EconomyContext:
	var context: EconomyContext = _context(STRIP)
	for x: int in range(context.map.width):
		for y: int in range(context.map.height):
			context.map.district_by_cell[Vector2i(x, y)] = WEST if x < SPLIT_X else EAST
	context.map.district_names[WEST] = "West"
	context.map.district_names[EAST] = "East"
	context.map.district_water_sources[WEST] = &"old_ford"
	context.map.district_water_sources[EAST] = &"neutral"
	return context


# The worker's target after the outbreak, with the given mourning switch and cemeteries standing in West.
func _worker_target(mourning: bool, cemeteries: int) -> Dictionary:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"events.enabled", &"set", 1.0))
	role.modifiers.append(Modifier.new(&"defeat.enabled", &"set", 0.0))
	var params: Params = SimTestParams.isolated_params(_catalog, role)
	var context: EconomyContext = _outbreak_context()
	var state: EconomyState = EconomyState.new()
	state.money = 100000
	state.population = 80
	state.mourning_enabled = mourning
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(10, 0)]:
		state.buildings.append(_at(&"housing", cell))
	for cell: Vector2i in [Vector2i(0, 2), Vector2i(10, 2)]:
		state.buildings.append(_at(&"public_fountain", cell))
	for index: int in range(cemeteries):
		state.buildings.append(_at(CEMETERY, Vector2i(0, 4 + 4 * index)))
	var sim: Simulation = Simulation.new(params, state, SEED, context)
	sim.apply_command(MissionCommand.new(&"start", OLDFORD))
	sim.tick()
	var minutes: float = float(params.get_value(&"mission.oldford.duration_min"))
	for tick_index: int in range(SimTime.minutes_to_ticks(minutes) - 1 + SETTLE_TICKS):
		sim.tick()
	var economy: EconomyState = EconomyState.from_dict(sim.to_save()["economy"])
	var worker: ClassDef = context.classes[&"worker"]
	var breakdown: Dictionary = ClassStates.satisfaction_breakdown_of(economy, worker)
	return {"target": ClassStates.checkout(economy, worker).satisfaction_target, "breakdown": breakdown,
		"deaths": economy.mourning_unburied.get(WEST, 0.0) + economy.mourning_buried.get(WEST, 0.0)}


func test_an_outbreak_without_cover_raises_the_mourning_and_with_cover_it_does_not() -> void:
	var legacy: Dictionary = _worker_target(false, 0)
	var uncovered: Dictionary = _worker_target(true, 0)
	var covered: Dictionary = _worker_target(true, 1)
	assert_false(legacy["breakdown"].has("mourning"), "Off: no mourning term at all")
	assert_gt(uncovered["deaths"], 0.0, "The outbreak killed")
	assert_true(uncovered["breakdown"].has("mourning"))
	assert_gt(uncovered["breakdown"]["mourning"], 0.0)
	assert_lt(uncovered["target"], legacy["target"], "Without a cemetery the class moves toward its emigration threshold")
	assert_false(covered["breakdown"].has("mourning"), "A cemetery with room for all the deaths: no mourning")
	assert_almost_eq(covered["target"], legacy["target"], 0.001, "Same target as without the mourning")
	assert_gt(covered["target"], uncovered["target"])


func test_save_load_preserves_mourning_state() -> void:
	var params: Params = _mourning_params()
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


# -- texts of the reasons ---------------------------------------------------------------------------------------------

func test_the_new_reasons_have_a_text_in_both_languages() -> void:
	var rows: Dictionary[String, PackedStringArray] = {}
	for line: String in FileAccess.get_file_as_string("res://locale/ui.csv").split("\n"):
		var cells: PackedStringArray = line.split(",")
		if cells.size() >= 3:
			rows[cells[0]] = cells
	for reason: StringName in [&"mourning_disabled", &"cemetery_occupied"]:
		var key: String = "ui.reason.%s" % reason
		assert_true(rows.has(key), key)
		assert_false(String(rows[key][1]).is_empty(), "%s es" % key)
		assert_false(String(rows[key][2]).is_empty(), "%s en" % key)
		assert_ne(Strings.reason(reason), String(reason), "%s is wired in Strings" % key)
