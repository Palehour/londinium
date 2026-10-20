extends GutTest

# Issue #67 (D-034, D-070): production still goes to the global store, but a house gets a good only within the
# service radius, in street steps, of a building that hands it out. A house's coverage is the global coverage
# times its access (1 or 0); satisfaction and hunger add the houses up by their capacity.

const WIDTH: int = 24

var _catalog: DataCatalog
var _context: EconomyContext
var _initial: EconomyState
var _radius: int


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = RoadTestMap.street(_catalog, WIDTH)
	# In street steps: the radius is in metres since issue #186 (D-086), a step is one street piece.
	_radius = int(_params().get_value(&"building.bakery.service_radius_m")) / RoadSystem.metres(_params(), _context, 1)
	_initial = EconomyState.new()
	_initial.money = 100000
	_initial.population = 10
	_initial.stocks.assign({&"wheat": 0, &"flour": 0, &"bread": 1000})


func _params(role: RoleDef = null) -> Params:
	return Params.new(_catalog, role if role != null else _catalog.roles[&"neutral_administrator"])


# A bakery at the first street cell and houses at the given steps from it.
func _sim(house_steps: Array[int], role: RoleDef = null) -> Simulation:
	var sim: Simulation = Simulation.new(_params(role), _initial, 7, _context)
	sim.apply_command(BuildCommand.new(_context, &"bakery", RoadTestMap.land(1)))
	for steps: int in house_steps:
		sim.apply_command(BuildCommand.new(_context, &"housing", RoadTestMap.land(steps)))
	sim.tick()
	return sim


func _served(sim: Simulation, steps: int) -> bool:
	return RoadTestMap.entry(sim.snapshot(), "houses", RoadTestMap.land(steps))["served"][&"bread"]


func _bread_term(sim: Simulation) -> float:
	return float(sim.snapshot()["economy"]["satisfaction_breakdown"]["bread"])


func test_house_within_radius_is_served() -> void:
	var sim: Simulation = _sim([_radius] as Array[int])
	assert_true(_served(sim, _radius))


func test_house_one_step_beyond_radius_is_not() -> void:
	var sim: Simulation = _sim([_radius + 1] as Array[int])
	assert_false(_served(sim, _radius + 1))
	assert_eq(_bread_term(sim), 0.0, "an unserved house gets no bread, whatever the store holds")


func test_radius_zero_is_global() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"building.bakery.service_radius_m", &"set", 0))
	var sim: Simulation = _sim([WIDTH] as Array[int], role)
	assert_true(_served(sim, WIDTH))


# People move into the served houses first: an unserved house costs nothing while the served ones hold everybody.
func test_people_fill_the_served_houses_first() -> void:
	var both: Simulation = _sim([2, 3] as Array[int])
	var one: Simulation = _sim([2, _radius + 1] as Array[int])
	assert_gt(_bread_term(both), 0.0)
	assert_eq(_bread_term(one), _bread_term(both))


# D-081: a class with two houses, one served and one beyond the radius. People fill the served one first, and the
# access is the served capacity over the people with a house. The housing bonus is off so each house holds its base.
func test_access_is_the_served_capacity_over_the_people_with_a_house() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"needs.housing_bonus_per_category", &"set", 0))
	var capacity: int = int(_params(role).get_value(&"building.housing.capacity"))
	# More people than the served house holds and fewer than both: option B would give 1/2 here, D-081 does not.
	_initial.population = capacity + 5
	var both: Simulation = _sim([2, 3] as Array[int], role)
	var one: Simulation = _sim([2, _radius + 1] as Array[int], role)
	assert_gt(_bread_term(both), 0.0)
	assert_almost_eq(_bread_term(one), _bread_term(both) * float(capacity) / _initial.population, 1e-9)


func test_unserved_share_lowers_hunger_coverage() -> void:
	var served: Simulation = _sim([2] as Array[int])
	var unserved: Simulation = _sim([_radius + 1] as Array[int])
	assert_gt(float(served.snapshot()["defeat"]["hunger"]["coverage"]), 0.0)
	assert_eq(float(unserved.snapshot()["defeat"]["hunger"]["coverage"]), 0.0)


func test_house_without_street_adds_no_capacity() -> void:
	var roads: Array[Vector2i] = [Vector2i(0, 1)]
	var context: EconomyContext = RoadTestMap.blocks(_catalog, Vector2i(6, 5), roads)
	var one: Simulation = Simulation.new(_params(), _initial, 7, context)
	one.apply_command(BuildCommand.new(context, &"housing", RoadTestMap.cell(Vector2i(0, 0))))
	one.tick()
	var two: Simulation = Simulation.new(_params(), _initial, 7, context)
	two.apply_command(BuildCommand.new(context, &"housing", RoadTestMap.cell(Vector2i(0, 0))))
	two.apply_command(BuildCommand.new(context, &"housing", RoadTestMap.cell(Vector2i(4, 2))))
	two.tick()
	assert_eq(two.snapshot()["economy"]["buildings"].size(), 2)
	assert_eq(two.snapshot()["economy"]["housing_capacity"], one.snapshot()["economy"]["housing_capacity"])
	assert_false(RoadTestMap.entry(two.snapshot(), "houses", RoadTestMap.cell(Vector2i(4, 2)))["connected"])
