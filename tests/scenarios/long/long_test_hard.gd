extends GutTest

# Issue #128 over 20 seeds: every script of tests/scenarios/hard/ plays on the Hard preset without a
# refused command (insufficient_money) or one that never ran, so the criterion "Hard without bankruptcy
# on its own" (D-065) is measured on all the seeds. Too slow for CI: run it with tools/run_long_tests.
# Criterion for Hard approved by Cristian in #128 (16/10): with the same commands, at least 17 of 20 seeds
# survive the whole game (150 min the long ones), and a seed that is lost shows a warning at least 10 min
# before the defeat.

const SEEDS: int = 20
const PRESET: StringName = &"hard"
const SURVIVING_SEEDS_REQUIRED: int = 17
const WARNING_LEAD_TICKS: int = 600

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


func test_at_least_17_seeds_survive_and_the_lost_ones_were_warned_10_min_before() -> void:
	assert_gt(_results.size(), 0)
	for id: String in _results:
		var survived: int = 0
		var lost: Array[String] = []
		for index: int in range(_results[id].size()):
			var result: ScenarioResult = _results[id][index]
			if result.survived():
				survived += 1
				continue
			var cause: StringName = StringName(String(result.final_row()["defeat_causes"]).get_slice(",", 0))
			# The first warning of any condition is the one the player sees first; the one of the condition that
			# ends the game is printed too.
			var first: int = _first_warning(result)
			lost.append("seed %d: %s at tick %d, first warning %d s before (its own condition %d s before)"
				% [index + 1, cause, result.defeat_tick, result.defeat_tick - first,
				result.defeat_tick - int(result.first_warning_tick.get(cause, result.defeat_tick))])
			assert_gte(result.defeat_tick - first, WARNING_LEAD_TICKS,
				"%s seed %d: warned at least 10 min before the defeat" % [id, index + 1])
		gut.p("%s: %d of %d seeds survive %s" % [id, survived, SEEDS, str(lost)])
		assert_gte(survived, SURVIVING_SEEDS_REQUIRED, "%s: seeds that survive" % id)


# First tick any defeat condition was in warning; the defeat tick itself when none was.
func _first_warning(result: ScenarioResult) -> int:
	var first: int = result.defeat_tick
	for tick: int in result.first_warning_tick.values():
		if tick >= 0:
			first = mini(first, tick)
	return first
