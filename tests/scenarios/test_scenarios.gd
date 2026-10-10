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
# treasury: the second chain is paid for with the first one's profit, which with these taxes takes
# until minute 8-12. If this test fails after a change in data/, that is expected: recalibrate the
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


func test_big_tight_second_chain_is_paid_from_profit_between_minutes_8_and_12() -> void:
	var result: ScenarioResult = _result("big_tight")
	var runner: ScenarioRunner = ScenarioRunner.create()
	var chain_cost: int = 0
	for building: String in ["wharf", "mill", "bakery"]:
		chain_cost += int(runner.param(StringName("building.%s.cost" % building)))
	var funded_minute: int = -1
	for minute: int in range(1, result.rows.size()):
		if int(result.row(minute)["money"]) >= chain_cost:
			funded_minute = minute
			break
	assert_between(funded_minute, 8, 12, "the first chain pays for the second one in the issue's window")
	assert_gte(int(result.row(12)["money"]), chain_cost, "affordable when the script builds it (tick 720)")
	assert_lt(int(result.final_row()["money"]), int(result.row(12)["money"]), "and it was spent on it")


# H1/H2 of PR #40: at the tax rate the issue asks for (0.6) the second chain is paid for before
# minute 8 and the city stays under 1.5x the small one. No script timing fixes that; only a change
# in data/ does. This pins what happens today so the gap stays visible in the suite. If it fails
# after a change in data/, check with Mason whether criteria 1 and 3 of #39 are now met.
func test_big_tight_r06_shows_the_gap_with_the_issue_39_criteria() -> void:
	var result: ScenarioResult = _result("big_tight_r06")
	var small: ScenarioResult = _result("small_rich")
	assert_true(result.survived())
	var final: Dictionary = result.final_row()
	assert_eq([final["n_wharf"], final["n_mill"], final["n_bakery"], final["n_housing"]], [2, 2, 2, 2])
	assert_eq(result.row(1)["tax_rate"], 0.6)
	var runner: ScenarioRunner = ScenarioRunner.create()
	var chain_cost: int = 0
	for building: String in ["wharf", "mill", "bakery"]:
		chain_cost += int(runner.param(StringName("building.%s.cost" % building)))
	var funded_minute: int = -1
	for minute: int in range(1, result.rows.size()):
		if int(result.row(minute)["money"]) >= chain_cost:
			funded_minute = minute
			break
	assert_between(funded_minute, 1, 7, "criterion 1 asks for minutes 8-12; not met at r=0.6")
	assert_lt(float(final["population"]), 1.5 * float(small.final_row()["population"]),
		"criterion 3 asks for 1.5x; not met at r=0.6 with this order of building")
	assert_gte(float(final["bread_coverage"]), 0.95)


func test_two_equilibria_differ() -> void:
	var small: ScenarioResult = _result("small_rich")
	var big: ScenarioResult = _result("big_tight")
	assert_gte(float(big.final_row()["population"]), 1.5 * float(small.final_row()["population"]))
	assert_gte(int(small.final_row()["money"]), int(big.final_row()["money"]) + 100)
	assert_gte(float(small.final_row()["bread_coverage"]), 0.95)
	assert_gte(float(big.final_row()["bread_coverage"]), 0.95)
	assert_gt(small.mean("operating_balance_pm", LAST_MINUTES_FROM, MINUTES), 0.0)
	assert_gt(big.mean("operating_balance_pm", LAST_MINUTES_FROM, MINUTES), 0.0)


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
# ~29 people; hunger emigration (4-8 a minute) empties a smaller city first. Expected behaviour.
func test_hunger_riot_defeat() -> void:
	var result: ScenarioResult = _result("defeat_hunger")
	_assert_lost_only_by(result, &"hunger", 496, 15)
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
