extends GutTest

# Issue #202 (D-090), the short check: the seed of tests/scenarios/events/cholera_recovery.json, where the Old Ford
# mission starts by itself and fails with no water. Ten minutes after the close the city has 80 % of its people back
# and it is no defeat. The 20 seeds of the criterion run in tests/scenarios/long/long_test_cholera_recovery.gd.

const PATH: String = "res://tests/scenarios/events/cholera_recovery.json"
const RECOVERED_SHARE: float = 0.8


func test_the_seed_of_the_file_recovers_without_defeat() -> void:
	var runner: ScenarioRunner = CholeraScenario.runner()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	var result: ScenarioResult = runner.run(ScenarioRunner.load_file(PATH))
	assert_eq(result.defeat_causes, [] as Array[StringName])
	assert_eq(CholeraScenario.status(result), &"failed")
	assert_gt(int(result.final_economy["missions"][CholeraScenario.MISSION]["deaths"]), 0)
	assert_gte(CholeraScenario.recovered_share(result, CholeraScenario.close_minute(runner)), RECOVERED_SHARE)
