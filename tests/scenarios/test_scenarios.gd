extends GutTest

# The 15-minute scripted games behind the GDD's "Criterios de éxito del hito". Each scenario's
# command list lives next to this file as JSON. Numbers below were measured with the data/ in
# force when the scenarios were written (docs: PR de #10); a failure after a data/ change means
# "recalibrate the scenario or tell Mason", not that the simulator broke.

const LAST_MINUTES_FROM: int = 13
const MINUTES: int = 15

static var _results: Dictionary[String, ScenarioResult] = {}
# Timings come from data/ (defeat.json), so retuning them does not leave stale copies here.
static var _grace_ticks: int = 0
static var _hunger_seconds: int = 0
static var _depopulation_seconds: int = 0


func before_all() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	_grace_ticks = int(runner.param(&"defeat.grace_seconds"))
	_hunger_seconds = int(runner.param(&"defeat.hunger.duration_seconds"))
	_depopulation_seconds = int(runner.param(&"defeat.depopulation.duration_seconds"))
	for path: String in ScenarioRunner.scenario_paths():
		var scenario: Dictionary = ScenarioRunner.load_file(path)
		_results[String(scenario["id"])] = runner.run(scenario)


func _result(id: String) -> ScenarioResult:
	assert_true(_results.has(id), "scenario %s exists" % id)
	return _results[id]


func _assert_scripts_ran_clean(result: ScenarioResult) -> void:
	assert_eq(result.unexpected_rejections(), [] as Array[Dictionary],
		"%s: a scripted command was refused; the script no longer fits data/" % result.id)


func test_every_scenario_runs_its_script_without_refusals() -> void:
	assert_gte(_results.size(), 6)
	for id: String in _results:
		_assert_scripts_ran_clean(_results[id])


# --- Criterio 2: dos equilibrios distintos ---

func test_small_rich_survives_comfortable_and_cash_positive() -> void:
	var result: ScenarioResult = _result("small_rich")
	assert_true(result.survived())
	assert_almost_eq(float(result.final_row()["population"]), 20.0, 2.0)
	assert_gte(float(result.final_row()["bread_coverage"]), 0.95)
	assert_gte(int(result.final_row()["money"]), 800)
	assert_gte(result.mean("operating_balance_pm", LAST_MINUTES_FROM, MINUTES), 0.0)


# F1/F2/F7 (#39): big_tight is now two chains and two housing blocks. What is tight is the
# treasury: the second chain is paid for with the first one's profit and built at tick 720. The
# release window of the issue (minutes 8-12) is checked on big_tight_r06. If this test fails after a change in data/, that is expected: recalibrate the
# scenario (or tell Mason). It is not a bug.
func test_big_tight_funds_its_second_chain_and_ends_larger() -> void:
	var result: ScenarioResult = _result("big_tight")
	assert_true(result.survived())
	var final: Dictionary = result.final_row()
	assert_between(int(final["population"]), 33, 38)
	assert_gte(float(final["bread_coverage"]), 0.95)
	assert_eq([final["n_wharf"], final["n_mill"], final["n_bakery"], final["n_housing"]], [2, 2, 2, 2])
	assert_gt(int(final["money"]), 0)
	assert_gt(result.mean("operating_balance_pm", LAST_MINUTES_FROM, MINUTES), 0.0)


# First minute with a treasury that pays for `cost`, counted from minute 1; -1 if it never does.
func _first_minute_with_money(result: ScenarioResult, cost: int) -> int:
	for minute: int in range(1, result.rows.size()):
		if int(result.row(minute)["money"]) >= cost:
			return minute
	return -1


func test_big_tight_second_chain_is_affordable_when_the_script_builds_it() -> void:
	var result: ScenarioResult = _result("big_tight")
	var chain_cost: int = _chain_cost()
	# Loose on purpose: the exact minute moves with the wheat price; the script builds at minute 12.
	var funded: int = _first_minute_with_money(result, chain_cost)
	assert_between(funded, 1, 11, "the first chain pays for the second one before minute 12")
	assert_gte(int(result.row(12)["money"]), chain_cost, "affordable when the script builds it (tick 720)")
	assert_lt(int(result.final_row()["money"]), int(result.row(12)["money"]), "and it was spent on it")


func _chain_cost() -> int:
	var runner: ScenarioRunner = ScenarioRunner.create()
	var total: int = 0
	for building: String in ["wharf", "mill", "bakery"]:
		total += int(runner.param(StringName("building.%s.cost" % building)))
	return total


# Issue #39 at the tax rate it asks for (0.6): the second chain and the second housing block are
# bought together as soon as the treasury reaches their price (wait_for_money), so the purchase
# happens when the money is there whatever the wheat price did. This is the fixed seed; the
# 20-seed behaviour is in the next test. If this fails after a change in data/, that is expected:
# recalibrate the scenario (or tell Mason).
func test_big_tight_r06_buys_chain_and_housing_together_and_ends_far_larger() -> void:
	var result: ScenarioResult = _result("big_tight_r06")
	var small: ScenarioResult = _result("small_rich")
	assert_true(result.survived())
	var final: Dictionary = result.final_row()
	assert_eq([final["n_wharf"], final["n_mill"], final["n_bakery"], final["n_housing"]], [2, 2, 2, 2])
	assert_eq(result.row(1)["tax_rate"], 0.6)
	var bought: Array[int] = []
	for entry: Dictionary in result.commands:
		if entry["tick"] == 60:
			bought.append(entry["executed_tick"])
	assert_eq(bought.size(), 4, "wharf, mill, bakery and housing")
	assert_eq(bought.count(bought[0]), 4, "all in the same tick")
	assert_eq(result.second_chain_purchase_tick(), bought[0])
	assert_gte(float(final["population"]), 1.5 * float(small.final_row()["population"]))
	assert_gte(float(final["bread_coverage"]), 0.95)


# Issue #39 criterion 1 (Cristian's wording): with r=0.6 and a varying wheat price, over 20 seeds of
# big_tight_r06, (a) the median minute at which the second chain is bought is between 8 and 12 and
# (b) at least 18 of 20 seeds buy it between minutes 6 and 15. A seed that does not buy before the
# end counts as outside the range, as long as its city stays stable and keeps a positive balance.
# Criterion 3 at r=0.6: a seed that bought the second chain by minute 12 ends with at least 1.5x the
# population of small_rich (same seed). A seed that buys later or never is exempt from that, as bad
# luck with the price accepted in criterion 1, as long as its city is alive, stable and earning.
# (Criterion 3's reference scenario is big_tight at 0.7, tested above.)
# The thresholds are the criterion, not what was measured: do not lower them to make the suite green.
const SEEDS: int = 20
const ON_TIME_BY: float = 12.0
const GAP: float = 1.5
const MEDIAN_FROM: float = 8.0
const MEDIAN_TO: float = 12.0
const RANGE_FROM: float = 6.0
const RANGE_TO: float = 15.0
const RANGE_TARGET: int = 18
# Never bought: sorts after every real minute, so it can only push the median up.
const NEVER: float = 1000000.0


func test_big_tight_r06_financing_across_twenty_seeds() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	var scenario: Dictionary = ScenarioRunner.load_file("res://tests/scenarios/big_tight_r06.json")
	var small_scenario: Dictionary = ScenarioRunner.load_file("res://tests/scenarios/small_rich.json")
	var minutes: Array[float] = []
	var in_range: int = 0
	var on_time: int = 0
	for seed_value: int in range(1, SEEDS + 1):
		var variant: Dictionary = scenario.duplicate(true)
		variant["seed"] = seed_value
		var result: ScenarioResult = runner.run(variant)
		var tick: int = result.second_chain_purchase_tick()
		var minute: float = float(tick) / 60.0 if tick >= 0 else NEVER
		minutes.append(minute)
		var in_window: bool = minute >= RANGE_FROM and minute <= RANGE_TO
		var bought_in_time: bool = minute <= ON_TIME_BY
		if in_window:
			in_range += 1
		if bought_in_time:
			on_time += 1
			var small_variant: Dictionary = small_scenario.duplicate(true)
			small_variant["seed"] = seed_value
			var small: ScenarioResult = runner.run(small_variant)
			assert_gte(float(result.final_row()["population"]), GAP * float(small.final_row()["population"]),
				"seed %d bought at minute %.2f, so it should end at %.1fx the small city" % [seed_value, minute, GAP])
		# Outside the range, or too late for the population gap, the city must still be fine.
		if not in_window or not bought_in_time:
			assert_true(result.survived(), "seed %d is outside the range or late, but was lost" % seed_value)
			assert_true(runner.is_stable(result), "seed %d is outside the range or late, and not stable" % seed_value)
			assert_gt(result.mean("operating_balance_pm", 1, MINUTES), 0.0,
				"seed %d is outside the range or late, and loses money" % seed_value)
	minutes.sort()
	@warning_ignore("integer_division")
	var middle: int = SEEDS / 2
	var median: float = (minutes[middle - 1] + minutes[middle]) / 2.0
	gut.p("big_tight_r06 over %d seeds: median purchase minute %.2f, %d of %d bought between minutes %d and %d, %d by minute %d"
		% [SEEDS, median, in_range, SEEDS, int(RANGE_FROM), int(RANGE_TO), on_time, int(ON_TIME_BY)])
	assert_between(median, MEDIAN_FROM, MEDIAN_TO, "(a) median minute of the second chain's purchase")
	assert_gte(in_range, RANGE_TARGET, "(b) seeds that buy it between minutes 6 and 15")


func test_two_equilibria_differ() -> void:
	var small: ScenarioResult = _result("small_rich")
	var big: ScenarioResult = _result("big_tight")
	assert_gte(float(big.final_row()["population"]), 1.5 * float(small.final_row()["population"]))
	assert_gte(int(small.final_row()["money"]), int(big.final_row()["money"]) + 100)
	assert_gte(float(small.final_row()["bread_coverage"]), 0.95)
	assert_gte(float(big.final_row()["bread_coverage"]), 0.95)
	var small_balance: float = small.mean("operating_balance_pm", LAST_MINUTES_FROM, MINUTES)
	var big_balance: float = big.mean("operating_balance_pm", LAST_MINUTES_FROM, MINUTES)
	assert_gt(small_balance, 0.0)
	assert_gt(big_balance, 0.0)
	# Relational, not absolute: two staffed chains earn more per minute than one.
	assert_gt(big_balance, small_balance, "the big city earns more per minute than the small one")


# --- Criterio 4: se puede perder por cada condición, con aviso en el panel ---

func _assert_lost_only_by(result: ScenarioResult, cause: StringName, expected_tick: int, tolerance: int) -> void:
	_assert_scripts_ran_clean(result)
	assert_false(result.survived(), "%s should be lost" % result.id)
	assert_eq(result.defeat_causes.size(), 1, "%s: only one cause, got %s" % [result.id, str(result.defeat_causes)])
	if not result.defeat_causes.is_empty():
		assert_eq(result.defeat_causes[0], cause)
	assert_almost_eq(float(result.defeat_tick), float(expected_tick), float(tolerance))
	# Nothing can be lost before the grace period ends plus the condition's own timer.
	assert_gt(result.defeat_tick, _grace_ticks)
	assert_true(result.first_warning_tick.has(cause), "the panel warned about %s" % cause)
	if result.first_warning_tick.has(cause):
		assert_lt(result.first_warning_tick[cause], result.defeat_tick, "warning comes before the defeat")
	assert_eq(result.final_row()["defeat_causes"], String(cause))


func test_depopulation_defeat() -> void:
	_assert_lost_only_by(_result("defeat_depopulation"), &"depopulation", 480, 10)
	assert_eq(_result("defeat_depopulation").final_row()["population"], 0)


# F3: the famine only reaches its timer because it starts right before the grace ends with
# ~34 people; hunger emigration (4-8 a minute) empties a smaller city first. Expected behaviour.
func test_hunger_riot_defeat() -> void:
	var result: ScenarioResult = _result("defeat_hunger")
	_assert_lost_only_by(result, &"hunger", 480, 10)
	assert_eq(result.max_timer[&"hunger"], _hunger_seconds)
	assert_lt(result.max_timer[&"depopulation"], _depopulation_seconds, "depopulation must not get there first")


# F5: with the treasury empty the wharf stops buying wheat, and the panel names it.
func test_bankruptcy_defeat() -> void:
	var result: ScenarioResult = _result("defeat_bankruptcy")
	_assert_lost_only_by(result, &"bankruptcy", 480, 15)
	assert_lt(int(result.final_row()["money"]), 0)
	assert_true(result.bread_cause_pairs.has("wharf:no_money_for_wheat"))


# --- Criterio 3: una crisis provocada y corregida antes de perder ---

func test_crisis_is_caused_explained_and_recovered() -> void:
	var result: ScenarioResult = _result("crisis_recovery")
	_assert_scripts_ran_clean(result)
	assert_true(result.survived())
	assert_true(result.first_warning_tick.has(&"hunger"), "the hunger warning showed up")
	assert_gt(result.max_timer[&"hunger"], 0)
	assert_lt(result.max_timer[&"hunger"], _hunger_seconds, "corrected before the riot")
	assert_true(result.bread_cause_pairs.has("mill:missing_building"), "the panel names the missing mill")
	assert_eq(result.final_row()["hunger"], &"ok")
	assert_gte(float(result.final_row()["bread_coverage"]), 0.9)
	var before_crisis: int = result.row(4)["population"]
	assert_gte(float(result.final_row()["population"]), 0.8 * float(before_crisis))
