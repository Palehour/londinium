extends GutTest

# Issue #87, task 2 (D-119, D-122): the harness plays tests/scenarios/incidents/district_services.json on the trial
# scenario of data/, the one with the incidents on. St George in the East gets four houses with a fire station, a health
# post and a police station beside them; Whitechapel gets four houses and no service. Over SEEDS games of 20 minutes
# the district with services has fewer incidents than the one without. Money and defeats are out of the way: only the
# incidents count.

const PATH: String = "res://tests/scenarios/incidents/district_services.json"
const SEEDS: int = 4
const SERVED: StringName = &"st_george_in_the_east"
const BARE: StringName = &"whitechapel"


func _runner() -> ScenarioRunner:
	var runner: ScenarioRunner = ScenarioRunner.create()
	if runner != null:
		runner.use_modifiers([Modifier.new(&"startup.money", &"set", 100000),
			Modifier.new(&"defeat.enabled", &"set", 0.0)] as Array[Modifier])
	return runner


func _incidents(result: ScenarioResult, district: StringName) -> int:
	var total: int = 0
	for entry: Dictionary in result.final_incidents["districts"][district].values():
		total += int(entry[IncidentSystem.RESOLVED]) + int(entry[IncidentSystem.UNRESOLVED])
	return total


func test_over_the_seeds_the_district_with_services_has_fewer_incidents() -> void:
	var runner: ScenarioRunner = _runner()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	var scenario: Dictionary = ScenarioRunner.load_file(PATH)
	assert_eq(runner.validate(scenario), [] as Array[String])
	var served: int = 0
	var bare: int = 0
	for seed_value: int in range(1, SEEDS + 1):
		scenario["seed"] = seed_value
		var result: ScenarioResult = runner.run(scenario)
		# The trial scenario has the incidents on, and the script builds everything it asks for.
		assert_true(result.final_incidents["enabled"])
		for command: Dictionary in result.commands:
			assert_true(command["accepted"], str(command))
		served += _incidents(result, SERVED)
		bare += _incidents(result, BARE)
		gut.p("seed %d: with services %d, without %d" % [seed_value, _incidents(result, SERVED), _incidents(result, BARE)])
		assert_lt(_incidents(result, SERVED), _incidents(result, BARE), "seed %d" % seed_value)
	assert_gt(bare, 0, "The district without services has incidents")
	assert_lt(served, bare)
