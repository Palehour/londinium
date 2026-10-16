extends GutTest

# Issue #128 over 20 seeds: every script of tests/scenarios/hard/ plays on the Hard preset without a
# refused command (insufficient_money) or one that never ran, so the criterion "Hard without bankruptcy
# on its own" (D-065) is measured on all the seeds. Too slow for CI: run it with tools/run_long_tests.
# The defeats are printed, not asserted: they are the measurement the issue asks for, and if there is a
# bankruptcy the Hard numbers are decided again with Cristian, not here.

const SEEDS: int = 20
const PRESET: StringName = &"hard"

static var _results: Dictionary[String, Array] = {}


func before_all() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	assert_eq(runner.use_difficulty(PRESET), [] as Array[String])
	for path: String in ScenarioRunner.preset_scenario_paths(PRESET):
		var scenario: Dictionary = ScenarioRunner.load_file(path)
		var results: Array[ScenarioResult] = []
		for seed_value: int in range(1, SEEDS + 1):
			var variant: Dictionary = scenario.duplicate(true)
			variant["seed"] = seed_value
			results.append(runner.run(variant))
		_results[String(scenario["id"])] = results


func test_every_hard_script_runs_clean_on_20_seeds() -> void:
	assert_gt(_results.size(), 0)
	for id: String in _results:
		assert_eq(_results[id].size(), SEEDS, id)
		for index: int in range(_results[id].size()):
			var result: ScenarioResult = _results[id][index]
			assert_eq(result.unexpected_rejections(), [] as Array[Dictionary],
				"%s seed %d: a scripted command was refused or never ran" % [id, index + 1])


func test_report_the_defeats_on_hard() -> void:
	for id: String in _results:
		var lost: Array[String] = []
		for index: int in range(_results[id].size()):
			var result: ScenarioResult = _results[id][index]
			if not result.survived():
				lost.append("seed %d: %s at tick %d" % [index + 1, result.final_row()["defeat_causes"], result.defeat_tick])
		gut.p("%s: %d of %d seeds lost %s" % [id, lost.size(), SEEDS, str(lost)])
	pass_test("measurement only: the defeats are listed above")
