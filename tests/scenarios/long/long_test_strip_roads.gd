extends GutTest

# Issue #67, criterion of D-080 (decided by Cristian on 2026-10-17): on the 16x12 strip with streets, the long game
# survives 150 minutes in at least 17 of 20 seeds. If it does not, the radii or k of D-070 change in data/, not the
# rule. Too slow for CI: run it with tools/run_long_tests.
# Issue #180 (D-085): the four 1870 houses of D-083 now stand in every game. They held 14 of 20 seeds while
# immigrants filled them without bread; counting only the served houses brings the criterion back, and switching
# population.growth.served_capacity_only off must lose it again, so the rule is what fixes it.

const SEEDS: int = 20
const SURVIVING_SEEDS_REQUIRED: int = 17
const SCENARIO: String = "res://tests/scenarios/strip/long/strip_roads_150.json"
const SERVED_ONLY: StringName = &"population.growth.served_capacity_only"

static var _survived: Array[int] = []
static var _lost: Array[String] = []
static var _survived_without_rule: Array[int] = []
static var _lost_without_rule: Array[String] = []


func before_all() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	var scenario: Dictionary = ScenarioRunner.load_file(SCENARIO)
	assert_eq(runner.validate(scenario), [] as Array[String])
	_play(runner, scenario, _survived, _lost)
	runner.use_modifiers([Modifier.new(SERVED_ONLY, &"set", 0)] as Array[Modifier])
	_play(runner, scenario, _survived_without_rule, _lost_without_rule)


func _play(runner: ScenarioRunner, scenario: Dictionary, survived: Array[int], lost: Array[String]) -> void:
	for seed_value: int in range(1, SEEDS + 1):
		var variant: Dictionary = scenario.duplicate(true)
		variant["seed"] = seed_value
		var result: ScenarioResult = runner.run(variant)
		assert_eq(result.unexpected_rejections(), [] as Array[Dictionary],
			"seed %d: a scripted command was refused; the script no longer fits data/" % seed_value)
		if result.survived():
			survived.append(seed_value)
		else:
			lost.append("seed %d: %s at tick %d" % [seed_value, str(result.defeat_causes), result.defeat_tick])


func test_at_least_17_of_20_seeds_survive_150_minutes_with_streets() -> void:
	gut.p("strip_roads_150: %d of %d seeds survive 150 minutes. Lost: %s" % [_survived.size(), SEEDS,
		", ".join(_lost) if not _lost.is_empty() else "none"])
	assert_gte(_survived.size(), SURVIVING_SEEDS_REQUIRED)


func test_without_the_served_houses_rule_the_criterion_is_lost() -> void:
	gut.p("strip_roads_150 without D-085: %d of %d seeds survive 150 minutes. Lost: %s" % [
		_survived_without_rule.size(), SEEDS,
		", ".join(_lost_without_rule) if not _lost_without_rule.is_empty() else "none"])
	assert_lt(_survived_without_rule.size(), SURVIVING_SEEDS_REQUIRED)
