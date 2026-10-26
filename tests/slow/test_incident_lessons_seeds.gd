extends GutTest

# Issue #87, task 3 (D-120), criterion 7 over 20 seeds: tests/scenarios/incidents/lessons_early_late.json on the trial
# scenario, with the historic events on and the cholera at the last minute its range allows, so the incidents have
# time to teach. Both districts have the same health when it comes, half their houses within a post's radius; St George
# had its post from the start and Whitechapel got its own five minutes before. St George, with the lessons of the
# outbreaks its post resolved, has fewer cholera deaths in at least 17 of 20 seeds. It takes about two minutes, so
# it lives in tests/slow/ and CI runs it in the slow job (#87, D-132).

const PATH: String = "res://tests/scenarios/incidents/lessons_early_late.json"
const SEEDS: int = 20
const EARLY_SEEDS_REQUIRED: int = 17
const EARLY: StringName = &"st_george_in_the_east"
const LATE: StringName = &"whitechapel"
const CHOLERA_MIN: float = 60.0

static var _results: Array[ScenarioResult] = []


func before_all() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	runner.use_modifiers([Modifier.new(&"startup.money", &"set", 100000), Modifier.new(&"defeat.enabled", &"set", 0.0),
		Modifier.new(&"events.enabled", &"set", 1.0),
		Modifier.new(&"events.cholera.trigger_min", &"set", CHOLERA_MIN)] as Array[Modifier])
	var scenario: Dictionary = ScenarioRunner.load_file(PATH)
	assert_eq(runner.validate(scenario), [] as Array[String])
	for seed_value: int in range(1, SEEDS + 1):
		var variant: Dictionary = scenario.duplicate(true)
		variant["seed"] = seed_value
		_results.append(runner.run(variant))


func _crisis(result: ScenarioResult, district: StringName) -> Dictionary:
	return result.final_incidents["districts"][district].get("crisis", {})


func test_every_seed_builds_everything_and_the_cholera_comes() -> void:
	assert_eq(_results.size(), SEEDS)
	for index: int in range(_results.size()):
		var result: ScenarioResult = _results[index]
		for command: Dictionary in result.commands:
			assert_true(command["accepted"], "seed %d: %s" % [index + 1, command])
		assert_eq(StringName(result.final_economy["missions"]["oldford"]["status"]), MissionSystem.FAILED,
			"seed %d" % (index + 1))
		for district: StringName in [EARLY, LATE]:
			assert_false(_crisis(result, district).is_empty(), "seed %d %s" % [index + 1, district])


func test_the_district_served_early_has_fewer_deaths_in_at_least_17_of_20_seeds() -> void:
	var fewer: int = 0
	var lines: Array[String] = []
	for index: int in range(_results.size()):
		var result: ScenarioResult = _results[index]
		var early: Dictionary = _crisis(result, EARLY)
		var late: Dictionary = _crisis(result, LATE)
		var districts: Dictionary = result.final_incidents["districts"]
		lines.append("%d: early %d lessons, severity %.3f, %d deaths; late %d lessons, severity %.3f, %d deaths" % [
			index + 1, districts[EARLY][ServiceSystem.HEALTH]["lessons"], early.get("severity", -1.0),
			early.get("deaths", -1), districts[LATE][ServiceSystem.HEALTH]["lessons"], late.get("severity", -1.0),
			late.get("deaths", -1)])
		fewer += 1 if int(early.get("deaths", 0)) < int(late.get("deaths", 0)) else 0
	gut.p("\n".join(lines))
	assert_gte(fewer, EARLY_SEEDS_REQUIRED, "\n".join(lines))
