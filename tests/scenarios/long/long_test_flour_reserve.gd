extends GutTest

# Issue #116 over 20 seeds of the 70-minute artisans_beer_flour game: imported flour, 30 % of the wharf reserved for
# the barley and four wharves (3 + 1). Too slow for CI, so the file name does not start with test_: run it with
# tools/run_long_tests. The short suite plays the same game once with the seed of the file.
# Criterion of the issue (harness, subject to this validation): the artisans do not collapse in at least 17 of
# the 20 seeds, which is to say the city survives and ends stable.

const SEEDS: int = 20
const STABLE_SEEDS_REQUIRED: int = 17
# [harness] A seed only counts if the artisan housing ends at least this full: a few artisans left in empty
# houses is not a city that held them (Bailey's review of PR #119). Not to be lowered to make the test pass.
const MIN_ARTISAN_OCCUPANCY: float = 0.8


func test_the_artisans_do_not_collapse_with_imported_flour_and_thirty_percent_barley() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	var scenario: Dictionary = ScenarioRunner.load_file("res://tests/scenarios/long/artisans_beer_flour.json")
	assert_eq(runner.validate(scenario), [] as Array[String])
	var stable: int = 0
	var lowest_artisans: int = 1 << 30
	var lowest_occupancy: float = INF
	for seed_value: int in range(1, SEEDS + 1):
		var variant: Dictionary = scenario.duplicate(true)
		variant["seed"] = seed_value
		var result: ScenarioResult = runner.run(variant)
		assert_eq(result.unexpected_rejections(), [] as Array[Dictionary],
			"seed %d: a scripted command was refused; the script no longer fits data/" % seed_value)
		var final_row: Dictionary = result.final_row()
		var final_artisans: int = int(final_row["artisan_population"])
		var occupancy: float = _occupancy(final_artisans, int(final_row["artisan_housing_capacity"]))
		lowest_artisans = mini(lowest_artisans, final_artisans)
		lowest_occupancy = minf(lowest_occupancy, occupancy)
		if result.survived() and runner.is_stable(result) and occupancy >= MIN_ARTISAN_OCCUPANCY:
			stable += 1
	gut.p("artisans_beer_flour over %d seeds: %d stable, fewest artisans at the end %d, lowest occupancy %.2f"
		% [SEEDS, stable, lowest_artisans, lowest_occupancy])
	assert_gte(stable, STABLE_SEEDS_REQUIRED, "seeds where the city and its artisans hold")


# No artisan housing at the end means no artisans to keep: the seed does not count.
func _occupancy(population: int, capacity: int) -> float:
	if capacity <= 0:
		return 0.0
	return float(population) / float(capacity)
