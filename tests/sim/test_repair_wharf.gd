extends GutTest

# Issue #177 (D-083): repairing the damaged wharf of the strip turns its cell into a wharf and costs
# repair.wharf_cost_ratio of a new wharf, rounded down to whole pence. Only a damaged wharf cell with nothing on it can be
# repaired, and only with the money. A new wharf may still be built there instead (Cristian, 2026-10-19).

const STRIP: StringName = &"riverside_strip"
const DAMAGED_WHARF: Vector2i = Vector2i(14, 7)
const PLAIN_RIVER: Vector2i = Vector2i(13, 7)
const LAND: Vector2i = Vector2i(13, 6)
const RATIO_KEY: StringName = &"repair.wharf_cost_ratio"

var _catalog: DataCatalog
var _strip: EconomyContext


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_strip = EconomyContext.new(_catalog, _catalog.maps[STRIP])


func _sim(money: int, modifiers: Array[Modifier] = []) -> Simulation:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	var state: EconomyState = EconomyState.new()
	state.money = money
	return Simulation.new(SimTestParams.isolated_params(_catalog, role), state, 7, _strip)


func _params(modifiers: Array[Modifier] = []) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	return SimTestParams.isolated_params(_catalog, role)


func _run(sim: Simulation, command: SimulationCommand) -> SimulationCommand:
	sim.apply_command(command)
	sim.tick()
	return command


func _building_at(sim: Simulation, cell: Vector2i) -> Dictionary:
	for building: Dictionary in sim.snapshot()["economy"]["buildings"]:
		if building["cell"] == [cell.x, cell.y]:
			return building
	return {}


func _money(sim: Simulation) -> int:
	return sim.snapshot()["economy"]["money"]


func test_the_strip_has_its_damaged_wharf_and_the_ratio_comes_from_data() -> void:
	assert_true(DAMAGED_WHARF in _strip.map.damaged_wharves)
	assert_eq(_params().get_value(RATIO_KEY), 0.5, "D-083: repairing costs half a new wharf")


func test_repairing_a_damaged_wharf_makes_it_a_wharf_for_half_a_new_one() -> void:
	var new_wharf: int = int(_params().get_value(&"building.wharf.cost"))
	var sim: Simulation = _sim(10000)
	var command: SimulationCommand = _run(sim, RepairWharfCommand.new(DAMAGED_WHARF))
	assert_true(command.accepted, str(command.reason))
	assert_eq(_building_at(sim, DAMAGED_WHARF).get("definition_id"), &"wharf")
	assert_eq(10000 - _money(sim), floori(new_wharf * 0.5), "Half of %d" % new_wharf)
	assert_eq(_building_at(sim, DAMAGED_WHARF).get("paid"), floori(new_wharf * 0.5), "Demolition refunds on what was paid")


func test_the_repair_cost_is_rounded_down_to_whole_pence() -> void:
	# 241 × 0.5 = 120.5: rounding to the nearest would charge 121.
	var sim: Simulation = _sim(10000, [Modifier.new(&"building.wharf.cost", &"set", 241)])
	assert_true(_run(sim, RepairWharfCommand.new(DAMAGED_WHARF)).accepted)
	assert_eq(10000 - _money(sim), 120)


func test_the_repair_cost_follows_the_ratio_of_params() -> void:
	var new_wharf: int = int(_params().get_value(&"building.wharf.cost"))
	var sim: Simulation = _sim(10000, [Modifier.new(RATIO_KEY, &"set", 0.25)])
	assert_true(_run(sim, RepairWharfCommand.new(DAMAGED_WHARF)).accepted)
	assert_eq(10000 - _money(sim), floori(new_wharf * 0.25))


func test_a_wharf_is_not_repaired_without_the_money() -> void:
	var repair: int = floori(int(_params().get_value(&"building.wharf.cost")) * 0.5)
	var sim: Simulation = _sim(repair - 1)
	var command: SimulationCommand = _run(sim, RepairWharfCommand.new(DAMAGED_WHARF))
	assert_false(command.accepted)
	assert_eq(command.reason, &"insufficient_money")
	assert_eq(_money(sim), repair - 1)
	assert_true(_building_at(sim, DAMAGED_WHARF).is_empty())
	var exact: Simulation = _sim(repair)
	assert_true(_run(exact, RepairWharfCommand.new(DAMAGED_WHARF)).accepted, "Exactly the price is enough")
	assert_eq(_money(exact), 0)


func test_only_a_damaged_wharf_cell_can_be_repaired() -> void:
	for cell: Vector2i in [PLAIN_RIVER, LAND, Vector2i(-1, 7), Vector2i(16, 7)]:
		var sim: Simulation = _sim(10000)
		var command: SimulationCommand = _run(sim, RepairWharfCommand.new(cell))
		assert_false(command.accepted, str(cell))
		assert_eq(command.reason, &"not_damaged_wharf", str(cell))
		assert_eq(_money(sim), 10000, str(cell))


func test_a_damaged_wharf_with_a_new_wharf_on_it_is_not_repaired() -> void:
	var sim: Simulation = _sim(10000)
	assert_true(_run(sim, BuildCommand.new(_strip, &"wharf", DAMAGED_WHARF)).accepted, "Building anew is still allowed")
	var money: int = _money(sim)
	var command: SimulationCommand = _run(sim, RepairWharfCommand.new(DAMAGED_WHARF))
	assert_false(command.accepted)
	assert_eq(command.reason, &"occupied_cell")
	assert_eq(_money(sim), money)


func test_a_repaired_wharf_is_not_repaired_twice_until_it_is_demolished() -> void:
	var sim: Simulation = _sim(10000)
	assert_true(_run(sim, RepairWharfCommand.new(DAMAGED_WHARF)).accepted)
	assert_eq(_run(sim, RepairWharfCommand.new(DAMAGED_WHARF)).reason, &"occupied_cell")
	assert_true(_run(sim, DemolishCommand.new(DAMAGED_WHARF)).accepted, "Not an anchor: it is demolished as usual")
	assert_true(_run(sim, RepairWharfCommand.new(DAMAGED_WHARF)).accepted, "The ruin is still there")
