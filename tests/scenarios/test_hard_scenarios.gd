extends GutTest

# Issue #128: the scripts of tests/scenarios/hard/ are the Normal ones rewritten for the 800 d of Hard,
# so that balance_report --preset hard plays every run. Here each one plays once, with the seed of its
# file; the 20 seeds are in long/long_test_hard.gd (tools/run_long_tests). A refusal after a change in
# data/ or in the preset means "recalibrate the script", not that the simulator broke.

const PRESET: StringName = &"hard"


func test_every_hard_script_runs_clean_on_its_seed() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	assert_eq(runner.use_difficulty(PRESET), [] as Array[String])
	var paths: Array[String] = ScenarioRunner.preset_scenario_paths(PRESET)
	assert_gt(paths.size(), 0)
	for path: String in paths:
		var result: ScenarioResult = runner.run(ScenarioRunner.load_file(path))
		assert_eq(result.unexpected_rejections(), [] as Array[Dictionary],
			"%s: a scripted command was refused or never ran on Hard" % result.id)
