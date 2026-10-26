extends GutTest

# Issue #52 over 20 seeds of the 70-minute artisans_beer game. Too slow for CI (it passed the 8 minutes of the
# test step), so the file name does not start with test_: run it with tools/run_long_tests. The short suite
# plays the same game once with the seed of the file (tests/slow/test_scenarios.gd).
# Criterion of Mason, approved by Cristian on 2026-10-13: the tax of the artisans pays the beer chain (without
# their housing) back with a median under 10 minutes, and in at least 17 of the 20 seeds in under 12 minutes.

const SEEDS: int = 20
const PAYBACK_MEDIAN_LIMIT: float = 10.0
const PAYBACK_SEED_LIMIT: float = 12.0
const PAYBACK_SEEDS_REQUIRED: int = 17
const MIN_BREAD_COVERAGE: float = 0.75
# Bread has to stay covered while the chain pays itself back: the minutes after it starts.
const COVERED_MINUTES: int = 10


func test_artisans_beer_pays_the_chain_back_across_twenty_seeds() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	var scenario: Dictionary = ScenarioRunner.load_file("res://tests/scenarios/long/artisans_beer.json")
	assert_eq(runner.validate(scenario), [] as Array[String])
	var paybacks: Array[float] = []
	var lowest: float = INF
	var within_limit: int = 0
	for seed_value: int in range(1, SEEDS + 1):
		var variant: Dictionary = scenario.duplicate(true)
		variant["seed"] = seed_value
		var result: ScenarioResult = runner.run(variant)
		assert_eq(result.unexpected_rejections(), [] as Array[Dictionary],
			"seed %d: a scripted command was refused; the script no longer fits data/" % seed_value)
		assert_true(result.survived(), "seed %d was lost" % seed_value)
		assert_gt(result.chain_start_tick, 0, "seed %d built the beer chain" % seed_value)
		assert_gt(int(result.final_row()["artisan_population"]), 0, "seed %d: artisans moved in" % seed_value)
		assert_gt(float(result.peak("beer_consumed_pm")), 0.0, "seed %d: the artisans drink beer" % seed_value)
		@warning_ignore("integer_division")
		var from_minute: int = result.chain_start_tick / ScenarioRunner.TICKS_PER_MINUTE
		var coverage: float = result.lowest("bread_coverage", from_minute, from_minute + COVERED_MINUTES)
		lowest = minf(lowest, coverage)
		assert_gte(coverage, MIN_BREAD_COVERAGE, "seed %d: bread coverage" % seed_value)
		var payback: float = result.payback_minutes(false)
		assert_gte(payback, 0.0, "seed %d: the tax of the artisans pays the chain back" % seed_value)
		assert_gt(result.payback_minutes(true), payback, "seed %d: the houses cost more" % seed_value)
		paybacks.append(payback)
		if payback >= 0.0 and payback < PAYBACK_SEED_LIMIT:
			within_limit += 1
	var median: float = _median(paybacks)
	paybacks.sort()
	gut.p("artisans_beer over %d seeds: lowest bread coverage %.2f, payback median %.2f min, best %.2f, worst %.2f, %d under %.0f min"
		% [SEEDS, lowest, median, paybacks[0], paybacks[SEEDS - 1], within_limit, PAYBACK_SEED_LIMIT])
	assert_lt(median, PAYBACK_MEDIAN_LIMIT, "median payback")
	assert_gte(within_limit, PAYBACK_SEEDS_REQUIRED, "seeds that pay back in under %.0f min" % PAYBACK_SEED_LIMIT)


func _median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	var middle: int = sorted.size() / 2
	return (sorted[middle - 1] + sorted[middle]) / 2.0
