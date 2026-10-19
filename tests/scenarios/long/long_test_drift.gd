extends GutTest

# Long drift games of issue #55, approved by Cristian on 2026-10-13: the artisans_beer city played for 4 hours
# (20 seeds) and 8 hours (5 seeds), to catch drifts, money inflation and debt that 15- or 70-minute games hide.
# They require the city to survive with every scripted command accepted, and the measures are printed for Mason
# and Cristian. Issue #118 reports the median money drift of the 4-hour game against its target, re-measures
# stage 3 of #56 and requires the bread criterion of the 4-hour game. Run with tools/run_long_tests.

const GAMES: Dictionary[String, int] = {"drift_4h": 20, "drift_8h": 5}
const LONG_DIR: String = "res://tests/scenarios/long"
# Issue #118 target: on the 4-hour game, the median money drift of the 20 seeds between hours 1 and 4. Cristian
# deferred it to #90 (monuments) on 2026-10-14 (D-063), so it is reported, not asserted.
const CRITERION_GAME: String = "drift_4h"
const DRIFT_FROM: float = 1500.0
const DRIFT_TO: float = 4000.0
# Stage 3 of #56, Cristian's 2026-10-15 decision: each complete minute must collect the minimum,
# for consecutive minutes; a low minute resets the streak. Only observe it: long games have no victory.
# Bread criterion of the 4-hour game after hour 1, decided by Cristian in #118 on 2026-10-14 (Mason's proposal, D-063):
# no defeat in any seed, lowest bread coverage >= 0.5 in every seed and >= 0.6 in at least 17 of the 20.
const BREAD_FLOOR: float = 0.5
const BREAD_TARGET: float = 0.6
const BREAD_TARGET_SEEDS: int = 17
# Issue #82, Cristian on 2026-10-13: an 8-hour game must not save more than 5 MB of statistics, compressed.
# On 2026-10-15 he asked the same of the whole save, and that the cause log of the 8-hour game (long game B) stay
# under its cap: if it reaches it, raise stats.causes.min_duration_seconds first, not the cap.
const STATS_GAME: String = "drift_8h"
const STATS_MAX_BYTES: int = 5 * 1024 * 1024

static var _drifts: Dictionary[String, Array] = {}
static var _stage3_minutes: Array[int] = []
static var _lowest_bread: Array[float] = []
static var _defeats: int = 0
static var _stats_bytes: Array[int] = []
static var _save_bytes: Array[int] = []
static var _cause_events: Array[int] = []
static var _cause_cap: int = 0

var _stage3_tax: float
var _stage3_required: int


func before_all() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	_stage3_tax = float(runner.param(&"victory.victorian_demo.revenue.threshold"))
	_stage3_required = int(runner.param(&"victory.victorian_demo.revenue.required_minutes"))
	_cause_cap = int(runner.param(&"stats.causes.max_events"))
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
			var stage3: int = _first_sustained_minute(result, _stage3_tax, _stage3_required)
			if id == CRITERION_GAME:
				_stage3_minutes.append(stage3)
				_lowest_bread.append(float(found["bread_coverage_lowest_after_hour1"]))
				_defeats += 0 if result.survived() else 1
			if id == STATS_GAME:
				_stats_bytes.append(result.stats_history_bytes)
				_save_bytes.append(result.save_bytes)
				_cause_events.append(result.stats_cause_events)
				gut.p("%s seed %d: statistics history %d bytes and whole save %d bytes compressed; %d cause events of %d (%d intermittent)"
					% [id, seed_value, result.stats_history_bytes, result.save_bytes, result.stats_cause_events,
					_cause_cap, result.stats_intermittent_events])
			gut.p("%s seed %d: money %+.0f per hour, lowest bread %.2f and beer %.2f after hour 1, %d min in debt; stage 3 of #56 at minute %d; lowest bread by hour %s, beer %s"
				% [id, seed_value, found["money_drift_per_hour"], found["bread_coverage_lowest_after_hour1"],
				found["beer_coverage_lowest_after_hour1"], int(found["minutes_in_debt"]), stage3,
				str(result.lowest_per_hour("bread_coverage")), str(result.lowest_per_hour("beer_coverage"))])


# Rows at minute m contain the actual taxes paid in that complete minute (the 60-tick Stats window).
static func _first_sustained_minute(result: ScenarioResult, per_minute: float, required: int) -> int:
	var streak: int = 0
	for minute: int in range(1, result.rows.size()):
		streak = streak + 1 if float(result.row(minute)["taxes_pm"]) >= per_minute else 0
		if streak >= required:
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


func test_eight_hour_statistics_save_under_5_mb() -> void:
	assert_eq(_stats_bytes.size(), GAMES[STATS_GAME])
	for size: int in _stats_bytes:
		assert_between(size, 1, STATS_MAX_BYTES)
	assert_eq(_save_bytes.size(), GAMES[STATS_GAME])
	for size: int in _save_bytes:
		assert_between(size, 1, STATS_MAX_BYTES, "whole save")


func test_eight_hour_cause_log_stays_under_its_cap() -> void:
	assert_eq(_cause_events.size(), GAMES[STATS_GAME])
	for events: int in _cause_events:
		assert_between(events, 1, _cause_cap - 1, "raise stats.causes.min_duration_seconds, not the cap")


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
	gut.p("stage 3 of #56 (tax >= %.0f per minute in each of %d consecutive min) on %s: reached in %d of %d seeds, median minute %.1f, earliest %s, latest %s"
		% [_stage3_tax, _stage3_required, CRITERION_GAME, reached.size(), _stage3_minutes.size(),
		median, str(reached.min()), str(reached.max())])


func test_stage_three_of_56_reaches_minutes_sixty_to_ninety_in_all_twenty_seeds() -> void:
	assert_eq(_stage3_minutes.size(), 20)
	for index: int in range(_stage3_minutes.size()):
		assert_between(_stage3_minutes[index], 60, 90, "seed %d" % (index + 1))


func test_bread_after_hour_one_of_the_four_hour_game_meets_its_criterion() -> void:
	assert_eq(_lowest_bread.size(), GAMES[CRITERION_GAME])
	var below_floor: Array[int] = []
	var below_target: Array[int] = []
	for index: int in range(_lowest_bread.size()):
		if _lowest_bread[index] < BREAD_FLOOR:
			below_floor.append(index + 1)
		if _lowest_bread[index] < BREAD_TARGET:
			below_target.append(index + 1)
	var at_target: int = _lowest_bread.size() - below_target.size()
	gut.p("%s bread after hour 1: %d defeats, below %.1f in seeds %s, at or above %.1f in %d of %d (below in seeds %s)"
		% [CRITERION_GAME, _defeats, BREAD_FLOOR, str(below_floor), BREAD_TARGET, at_target, _lowest_bread.size(),
		str(below_target)])
	assert_eq(_defeats, 0, "seeds lost")
	assert_eq(below_floor, [] as Array[int], "seeds whose lowest bread after hour 1 is under %.1f" % BREAD_FLOOR)
	assert_gte(at_target, BREAD_TARGET_SEEDS, "seeds whose lowest bread after hour 1 reaches %.1f" % BREAD_TARGET)
