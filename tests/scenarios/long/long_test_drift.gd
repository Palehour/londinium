extends GutTest

# Long drift games of issue #55, approved by Cristian on 2026-10-13: the artisans_beer city played for 4 hours
# (20 seeds) and 8 hours (5 seeds), to catch drifts, money inflation and debt that 15- or 70-minute games hide.
# They only require the city to survive with every scripted command accepted; the measures are printed for Mason
# and Cristian (approved "subject to validation", so there is no threshold yet). Run with tools/run_long_tests.

const GAMES: Dictionary[String, int] = {"drift_4h": 20, "drift_8h": 5}
const LONG_DIR: String = "res://tests/scenarios/long"


func test_drift_games_survive_and_report_their_drift() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	for id: String in GAMES:
		var scenario: Dictionary = ScenarioRunner.load_file(LONG_DIR.path_join("%s.json" % id))
		assert_eq(runner.validate(scenario), [] as Array[String], id)
		for seed_value: int in range(1, GAMES[id] + 1):
			var variant: Dictionary = scenario.duplicate(true)
			variant["seed"] = seed_value
			var result: ScenarioResult = runner.run(variant)
			assert_eq(result.unexpected_rejections(), [] as Array[Dictionary],
				"%s seed %d: a scripted command was refused; the script no longer fits data/" % [id, seed_value])
			assert_true(result.survived(), "%s seed %d was lost" % [id, seed_value])
			var found: Dictionary = result.measured(scenario["measure"])
			gut.p("%s seed %d: money %+.0f per hour, lowest bread %.2f and beer %.2f after hour 1, %d min in debt; lowest bread by hour %s, beer %s"
				% [id, seed_value, found["money_drift_per_hour"], found["bread_coverage_lowest_after_hour1"],
				found["beer_coverage_lowest_after_hour1"], int(found["minutes_in_debt"]),
				str(result.lowest_per_hour("bread_coverage")), str(result.lowest_per_hour("beer_coverage"))])
