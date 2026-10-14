extends GutTest

# Long drift games of issue #55, approved by Cristian on 2026-10-13: the artisans_beer city played for 4 hours
# (20 seeds) and 8 hours (5 seeds), to catch drifts, money inflation and debt that 15- or 70-minute games hide.
# They require the city to survive with every scripted command accepted, and the measures are printed for Mason
# and Cristian. Issue #118 reports the median money drift of the 4-hour game against its target and re-measures
# stage 3 of #56. Run with tools/run_long_tests.

const GAMES: Dictionary[String, int] = {"drift_4h": 20, "drift_8h": 5}
const LONG_DIR: String = "res://tests/scenarios/long"
# Issue #118 target: on the 4-hour game, the median money drift of the 20 seeds between hours 1 and 4. Cristian
# deferred it to #90 (monuments) on 2026-10-14 (D-063), so it is reported, not asserted.
const CRITERION_GAME: String = "drift_4h"
const DRIFT_FROM: float = 1500.0
const DRIFT_TO: float = 4000.0
# Stage 3 of #56 (approved by Cristian on 2026-10-13): collected tax >= 250 per minute, sustained 10 minutes
# (the mean of the window, as in the defeats). It was expected between hours 1 and 1.5; only reported here.
const STAGE3_TAX_PER_MINUTE: float = 250.0
const STAGE3_WINDOW_MINUTES: int = 10

static var _drifts: Dictionary[String, Array] = {}
static var _stage3_minutes: Array[int] = []


func before_all() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	for id: String in GAMES:
		var scenario: Dictionary = ScenarioRunner.load_file(LONG_DIR.path_join("%s.json" % id))
		assert_eq(runner.validate(scenario), [] as Array[String], id)
		_drifts[id] = []
		for seed_value: int in range(1, GAMES[id] + 1):
			var variant: Dictionary = scenario.duplicate(true)
			variant["seed"] = seed_value
			var result: ScenarioResult = runner.run(variant)
			assert_eq(result.unexpected_rejections(), [] as Array[Dictionary],
				"%s seed %d: a scripted command was refused; the script no longer fits data/" % [id, seed_value])
			assert_true(result.survived(), "%s seed %d was lost" % [id, seed_value])
			var found: Dictionary = result.measured(scenario["measure"])
			_drifts[id].append(float(found["money_drift_per_hour"]))
			var stage3: int = _first_sustained_minute(result, STAGE3_TAX_PER_MINUTE, STAGE3_WINDOW_MINUTES)
			if id == CRITERION_GAME:
				_stage3_minutes.append(stage3)
			gut.p("%s seed %d: money %+.0f per hour, lowest bread %.2f and beer %.2f after hour 1, %d min in debt; stage 3 of #56 at minute %d; lowest bread by hour %s, beer %s"
				% [id, seed_value, found["money_drift_per_hour"], found["bread_coverage_lowest_after_hour1"],
				found["beer_coverage_lowest_after_hour1"], int(found["minutes_in_debt"]), stage3,
				str(result.lowest_per_hour("bread_coverage")), str(result.lowest_per_hour("beer_coverage"))])


# The minute that closes the first window of `window` minutes whose mean collected tax reaches `per_minute`;
# -1 if no window does.
static func _first_sustained_minute(result: ScenarioResult, per_minute: float, window: int) -> int:
	for minute: int in range(window, result.rows.size()):
		if result.mean("taxes_pm", minute - window + 1, minute) >= per_minute:
			return minute
	return -1


static func _median(values: Array) -> float:
	var sorted: Array = values.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	var middle: int = sorted.size() / 2
	if sorted.size() % 2 == 1:
		return float(sorted[middle])
	return (float(sorted[middle - 1]) + float(sorted[middle])) / 2.0


func test_drift_games_survive_and_report_their_drift() -> void:
	for id: String in GAMES:
		assert_eq(_drifts.get(id, []).size(), GAMES[id], "%s played every seed" % id)


func test_money_drift_of_the_four_hour_game_is_reported_against_its_target() -> void:
	var drifts: Array = _drifts.get(CRITERION_GAME, [])
	assert_eq(drifts.size(), GAMES[CRITERION_GAME])
	if drifts.is_empty():
		return
	var median: float = _median(drifts)
	var verdict: String = "inside" if median >= DRIFT_FROM and median <= DRIFT_TO else "outside"
	gut.p("%s over %d seeds: median money drift %+.0f per hour (lowest %+.0f, highest %+.0f), %s the target %.0f to %.0f deferred to #90"
		% [CRITERION_GAME, drifts.size(), median, drifts.min(), drifts.max(), verdict, DRIFT_FROM, DRIFT_TO])


func test_stage_three_of_56_is_reported() -> void:
	assert_eq(_stage3_minutes.size(), GAMES[CRITERION_GAME])
	var reached: Array = _stage3_minutes.filter(func(minute: int) -> bool: return minute >= 0)
	var median: float = _median(reached) if not reached.is_empty() else -1.0
	gut.p("stage 3 of #56 (tax >= %.0f per minute over %d min) on %s: reached in %d of %d seeds, median minute %.1f, earliest %s, latest %s"
		% [STAGE3_TAX_PER_MINUTE, STAGE3_WINDOW_MINUTES, CRITERION_GAME, reached.size(), _stage3_minutes.size(),
		median, str(reached.min()), str(reached.max())])
