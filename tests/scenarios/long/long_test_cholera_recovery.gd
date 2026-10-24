extends GutTest

# Issue #202 (D-090) over 20 seeds: in tests/scenarios/events/cholera_recovery.json the Old Ford mission starts by
# itself and fails with no water (a quarter dies with prep 0). Ten minutes after the close the city has at least 80 %
# of the people it had before the deaths in at least 17 of 20 seeds, and it is never a defeat. Too slow for CI: run
# it with tools/run_long_tests; the short suite plays the seed of the file (test_cholera_scenario.gd).

const PATH: String = "res://tests/scenarios/events/cholera_recovery.json"
const SEEDS: int = 20
const RECOVERED_SEEDS_REQUIRED: int = 17
const RECOVERED_SHARE: float = 0.8

static var _results: Array[ScenarioResult] = []
static var _close: int = 0


func before_all() -> void:
	var runner: ScenarioRunner = CholeraScenario.runner()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	_close = CholeraScenario.close_minute(runner)
	var scenario: Dictionary = ScenarioRunner.load_file(PATH)
	for seed_value: int in range(1, SEEDS + 1):
		var variant: Dictionary = scenario.duplicate(true)
		variant["seed"] = seed_value
		_results.append(runner.run(variant))


func test_at_least_17_of_20_seeds_recover_80_percent_in_10_minutes() -> void:
	assert_eq(_results.size(), SEEDS)
	var recovered: int = 0
	var shares: Array[String] = []
	for index: int in range(_results.size()):
		var share: float = CholeraScenario.recovered_share(_results[index], _close)
		shares.append("%d: %.2f" % [index + 1, share])
		recovered += 1 if share >= RECOVERED_SHARE else 0
	gut.p("Recovered share by seed: %s" % ", ".join(shares))
	assert_gte(recovered, RECOVERED_SEEDS_REQUIRED, ", ".join(shares))


func test_no_seed_is_defeated() -> void:
	for index: int in range(_results.size()):
		assert_eq(_results[index].defeat_causes, [] as Array[StringName], "seed %d" % (index + 1))
		assert_eq(CholeraScenario.status(_results[index]), &"failed", "seed %d" % (index + 1))
