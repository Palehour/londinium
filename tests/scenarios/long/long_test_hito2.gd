extends GutTest

# Issue #55 over 20 seeds: the balance scenarios of milestone 2 (bread against beer, the beer crisis and the
# grain sweep). Too slow for CI, like long_test_artisans_beer.gd: run it with tools/run_long_tests. The short
# suite plays each scenario once with the seed of its file (tests/slow/test_scenarios.gd).
# Criteria approved by Cristian on 2026-10-13 (comment "Números aprobados por Cristian" in #55):
# (a) the mean tax collected per minute from minute 50 to 70, median of 20 seeds, differs by at least 30 %
#     between the stable splits of 0 % and 30 % barley;
# (b) beer cut for 5 minutes: no defeat, and in 17 of 20 seeds the artisans are back to 80 % of their number
#     before the cut within 10 minutes of the beer coming back. Decided by Cristian in PR #117: the cut starts a
#     fixed time after the first artisans arrive; a seed where they never arrive cuts nothing, is reported apart
#     and does not count as recovered.

const SEEDS: int = 20
const LONG_DIR: String = "res://tests/scenarios/long"
const SCENARIOS: Array[String] = ["bread_vs_beer_0", "bread_vs_beer_30", "beer_crisis", "grain_split"]
const MIN_TAX_DIFFERENCE: float = 0.30
const RECOVERED_SEEDS_REQUIRED: int = 17

static var _results: Dictionary[String, Array] = {}
static var _stable: Dictionary[String, Array] = {}


func before_all() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	for id: String in SCENARIOS:
		var scenario: Dictionary = ScenarioRunner.load_file(LONG_DIR.path_join("%s.json" % id))
		assert_eq(runner.validate(scenario), [] as Array[String], id)
		var results: Array[ScenarioResult] = []
		var stable: Array[bool] = []
		for seed_value: int in range(1, SEEDS + 1):
			var variant: Dictionary = scenario.duplicate(true)
			variant["seed"] = seed_value
			var result: ScenarioResult = runner.run(variant)
			results.append(result)
			stable.append(result.survived() and runner.is_stable(result))
		_results[id] = results
		_stable[id] = stable


func _measured(id: String, metric: String) -> Array[float]:
	var scenario: Dictionary = ScenarioRunner.load_file(LONG_DIR.path_join("%s.json" % id))
	var found: Array[float] = []
	for result: ScenarioResult in _results[id]:
		found.append(float(result.measured(scenario["measure"])[metric]))
	return found


func test_every_scenario_plays_twenty_seeds_without_refusals_or_defeats() -> void:
	for id: String in SCENARIOS:
		assert_eq(_results[id].size(), SEEDS, id)
		for index: int in range(_results[id].size()):
			var result: ScenarioResult = _results[id][index]
			# With no artisans the crisis commands wait forever (never_ran): reported in the crisis test, not here.
			if id == "beer_crisis" and result.first_artisan_tick < 0:
				continue
			assert_eq(result.unexpected_rejections(), [] as Array[Dictionary],
				"%s seed %d: a scripted command was refused; the script no longer fits data/" % [id, index + 1])
			assert_true(result.survived(), "%s seed %d was lost" % [id, index + 1])


func test_grain_splits_differ_by_thirty_percent_in_collected_tax() -> void:
	var low: float = _median(_measured("bread_vs_beer_0", "taxes_pm_window"))
	var high: float = _median(_measured("bread_vs_beer_30", "taxes_pm_window"))
	var difference: float = (high - low) / low if low > 0.0 else -1.0
	var stable_low: int = _stable["bread_vs_beer_0"].count(true)
	var stable_high: int = _stable["bread_vs_beer_30"].count(true)
	gut.p("tax per minute, minutes 50-70, median of %d seeds: 0 %% barley %.2f (stable in %d), 30 %% barley %.2f (stable in %d), difference %.1f %%"
		% [SEEDS, low, stable_low, high, stable_high, difference * 100.0])
	# "Stable" is the simulation's own rule (DefeatSystem.is_city_stable) on the final state, as in balance_report.
	# It is reported, not required: the approved criterion has no number of stable seeds.
	assert_gte(difference, MIN_TAX_DIFFERENCE, "(high - low) / low")


func test_beer_crisis_demotes_artisans_and_they_come_back_before_losing() -> void:
	var scenario: Dictionary = ScenarioRunner.load_file(LONG_DIR.path_join("beer_crisis.json"))
	var recovered: int = 0
	var without_artisans: Array[int] = []
	for index: int in range(SEEDS):
		var result: ScenarioResult = _results["beer_crisis"][index]
		if result.first_artisan_tick < 0:
			without_artisans.append(index + 1)
			continue
		var found: Dictionary = result.measured(scenario["measure"])
		gut.p("beer_crisis seed %d: first artisans at min %.1f, cut at min %.1f for %.1f min, %d artisans before, %d lost, back to 80 %% after %d min (-1: not within 10)"
			% [index + 1, found["first_artisans_minute"], found["beer_cut_minute"], found["beer_cut_minutes"],
			int(found["artisans_before_cut"]), int(found["artisans_lost_in_cut"]), int(found["artisans_recovery_minutes"])])
		assert_gt(float(found["artisans_before_cut"]), 0.0, "seed %d: artisans before the cut" % (index + 1))
		assert_gt(float(found["artisans_lost_in_cut"]), 0.0, "seed %d: the cut demotes artisans" % (index + 1))
		recovered += int(found["artisans_recovered"])
	gut.p("beer_crisis: %d of %d seeds recover 80 %% within 10 min; seeds with no artisans (no cut, not recovered): %s"
		% [recovered, SEEDS, str(without_artisans)])
	assert_gte(recovered, RECOVERED_SEEDS_REQUIRED, "seeds that recover")


func _median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	var middle: int = sorted.size() / 2
	return (sorted[middle - 1] + sorted[middle]) / 2.0
