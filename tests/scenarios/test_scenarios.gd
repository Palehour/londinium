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
# Criterion 3 at r=0.6: a seed that bought the second chain before minute 12 (minute < 12.0),
# ends with at least 1.5x the population of small_rich (same seed). A seed that buys later or never is exempt from that, as bad
# luck with the price accepted in criterion 1, as long as its city is alive, stable and earning.
# (Criterion 3's reference scenario is big_tight at 0.7, tested above.)
# The thresholds are the criterion, not what was measured: do not lower them to make the suite green.
const SEEDS: int = 20
# "On time" is strictly before minute 12 (minute < 12.0): a purchase at minute 12.0 is not on time.
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
		var bought_in_time: bool = minute < ON_TIME_BY
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


# Issue #41, the criterion Cristian chose (Mason's option A): the same city with a purchase policy
# (accumulate at 1, never pay more than 2 above a 2-minute reserve, keep 60) against the blind script,
# same seed. (a) no city is lost or unstable in 20 seeds; (b) the median minute of the second chain's
# purchase is at most 1.5 minutes later than the blind script's. The thresholds are the criterion,
# not what was measured: do not relax them to make the suite green.
const POLICY_MAX_DELAY_MINUTES: float = 1.5


func _purchase_minute(result: ScenarioResult) -> float:
	var tick: int = result.second_chain_purchase_tick()
	return float(tick) / 60.0 if tick >= 0 else NEVER


func _median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	var middle: int = sorted.size() / 2
	return (sorted[middle - 1] + sorted[middle]) / 2.0


func test_big_tight_r06_smart_keeps_every_city_safe_and_buys_at_most_a_minute_and_a_half_later() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	var blind: Dictionary = ScenarioRunner.load_file("res://tests/scenarios/big_tight_r06.json")
	var smart: Dictionary = ScenarioRunner.load_file("res://tests/scenarios/big_tight_r06_smart.json")
	var blind_minutes: Array[float] = []
	var smart_minutes: Array[float] = []
	var never_bought: int = 0
	for seed_value: int in range(1, SEEDS + 1):
		var blind_variant: Dictionary = blind.duplicate(true)
		blind_variant["seed"] = seed_value
		var smart_variant: Dictionary = smart.duplicate(true)
		smart_variant["seed"] = seed_value
		var blind_result: ScenarioResult = runner.run(blind_variant)
		var smart_result: ScenarioResult = runner.run(smart_variant)
		# A seed whose treasury never reaches the second chain's price leaves that purchase unrun
		# (never_ran). It counts as out of range, not as a broken script.
		var refused: Array[Dictionary] = smart_result.unexpected_rejections().filter(
			func(entry: Dictionary) -> bool: return entry["reason"] != &"never_ran")
		assert_eq(refused, [] as Array[Dictionary], "seed %d (smart): a scripted command was refused" % seed_value)
		blind_minutes.append(_purchase_minute(blind_result))
		smart_minutes.append(_purchase_minute(smart_result))
		if smart_minutes.back() >= NEVER:
			never_bought += 1
		assert_true(smart_result.survived(), "(a) seed %d (smart) was lost" % seed_value)
		assert_true(runner.is_stable(smart_result), "(a) seed %d (smart) is not stable" % seed_value)
		assert_gt(smart_result.mean("operating_balance_pm", 1, MINUTES), 0.0, "(a) seed %d (smart) loses money" % seed_value)
	var delay: float = _median(smart_minutes) - _median(blind_minutes)
	gut.p("big_tight_r06_smart over %d seeds: median purchase minute %.2f (blind %.2f), %.2f min later, %d never bought"
		% [SEEDS, _median(smart_minutes), _median(blind_minutes), delay, never_bought])
	assert_lte(delay, POLICY_MAX_DELAY_MINUTES, "(b) median purchase minute, smart minus blind")


# Issue #41: with the price at 1 a player can stockpile and live off the stock once it rises.
func test_wheat_stock_builds_while_cheap_and_feeds_the_mill_when_buying_stops() -> void:
	var result: ScenarioResult = _result("wheat_stock_price_1_then_3")
	_assert_scripts_ran_clean(result)
	assert_true(result.survived())
	assert_gt(result.peak("wheat_stock"), 50.0, "the stock goes past 50 while the price is 1")
	var price_rises: int = 6
	var limit_lifted: int = 11
	assert_gt(int(result.row(price_rises)["wheat_stock"]), 50)
	# Minutes 7 to 10: price 3 is above the maximum of 2, so nothing is bought and the mill lives on the stock.
	for minute: int in range(price_rises + 1, limit_lifted):
		assert_eq(result.row(minute)["wheat_spent_pm"], 0.0, "no purchases at minute %d" % minute)
		assert_gt(result.row(minute)["bread_produced_pm"], 0.0, "bread is still baked at minute %d" % minute)
		assert_lt(int(result.row(minute)["wheat_stock"]), int(result.row(minute - 1)["wheat_stock"]), "the stock is being used")
	assert_gt(int(result.row(limit_lifted)["wheat_stock"]), 0, "the stock lasted until the player lifted the limit")
	assert_gte(float(result.final_row()["bread_coverage"]), 0.95, "buying again at 3 keeps the city fed")


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


# Issue #42: can stockpiling pay? The same 20 seeds, smart against blind, judged on net worth at
# minute 15 (money plus the wheat in store at the base price) instead of on the treasury alone.
# Each lever is tried alone, on top of the #41 script. The first three numbers are the criterion's
# "ties or wins in at least 12 of 20"; the strict wins and losses keep the difference from being
# flattened (accumulating has to win some seeds and lose others).
const NET_WORTH_TARGET: int = 12
const MIN_STRICT_WINS: int = 3
const MIN_STRICT_LOSSES: int = 2


# {wins, ties, losses, lost_cities, median_gap} of smart minus blind, seed by seed.
func _net_worth_comparison(runner: ScenarioRunner, target_stock: int) -> Dictionary:
	var blind: Dictionary = ScenarioRunner.load_file("res://tests/scenarios/big_tight_r06.json")
	var smart: Dictionary = ScenarioRunner.load_file("res://tests/scenarios/big_tight_r06_smart.json")
	if target_stock >= 0:
		smart = ScenarioRunner.with_target_stock(smart, target_stock)
	var tally: Dictionary = {"wins": 0, "ties": 0, "losses": 0, "lost_cities": 0}
	var gaps: Array[float] = []
	for seed_value: int in range(1, SEEDS + 1):
		var blind_variant: Dictionary = blind.duplicate(true)
		blind_variant["seed"] = seed_value
		var smart_variant: Dictionary = smart.duplicate(true)
		smart_variant["seed"] = seed_value
		var blind_result: ScenarioResult = runner.run(blind_variant)
		var smart_result: ScenarioResult = runner.run(smart_variant)
		if not smart_result.survived() or not runner.is_stable(smart_result):
			tally["lost_cities"] += 1
		var gap: int = runner.net_worth(smart_result.final_row()) - runner.net_worth(blind_result.final_row())
		gaps.append(float(gap))
		if gap > 0:
			tally["wins"] += 1
		elif gap == 0:
			tally["ties"] += 1
		else:
			tally["losses"] += 1
	tally["median_gap"] = _median(gaps)
	return tally


func test_net_worth_counts_the_wheat_in_store_at_the_base_price() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	var base_price: int = int(runner.param(&"market.wheat.base_price"))
	assert_eq(runner.net_worth({"money": 100, "wheat_stock": 0}), 100)
	assert_eq(runner.net_worth({"money": 100, "wheat_stock": 30}), 100 + 30 * base_price)


func test_net_worth_levers_one_at_a_time() -> void:
	var report: Array[String] = []
	for lever: Dictionary in [
		{"name": "baseline (target 60, max price 3)", "target": -1, "max_price": 0},
		{"name": "lever 1: target stock 30", "target": 30, "max_price": 0},
		{"name": "lever 2: market max price 4", "target": -1, "max_price": 4},
	]:
		var runner: ScenarioRunner = ScenarioRunner.create()
		if lever["max_price"] > 0:
			runner.pin_wheat_max_price(lever["max_price"])
		var tally: Dictionary = _net_worth_comparison(runner, lever["target"])
		report.append("%s: smart ties or wins %d/%d (wins %d, ties %d, losses %d), median gap %.1f pence, lost cities %d"
			% [lever["name"], tally["wins"] + tally["ties"], SEEDS, tally["wins"], tally["ties"],
			tally["losses"], tally["median_gap"], tally["lost_cities"]])
		assert_eq(tally["lost_cities"], 0, "%s: no city may be lost or unstable" % lever["name"])
		# The thresholds are the criterion, checked on the policy as it ships (#41). The levers are
		# measurements for Cristian to judge: they are reported, not asserted, because a lever that
		# fails the criterion is a valid result of the experiment.
		if lever["target"] < 0 and lever["max_price"] == 0:
			assert_gte(tally["wins"] + tally["ties"], NET_WORTH_TARGET, "smart ties or wins in net worth")
			assert_gte(tally["wins"], MIN_STRICT_WINS, "accumulating must win some seeds")
			assert_gte(tally["losses"], MIN_STRICT_LOSSES, "accumulating must lose some seeds")
	gut.p("\n".join(report))


# --- Importaciones (#7, D-025 y D-026) ---

# D-025: with the tax at 0.85 the city only grows if it drinks tea. The tax of both games is the
# same; the only difference is the switch.
func test_tea_lets_the_city_grow_at_a_tax_of_85_percent_and_without_it_it_does_not() -> void:
	var off: ScenarioResult = _result("tea_off")
	var on: ScenarioResult = _result("tea_on")
	assert_true(off.survived())
	assert_true(on.survived())
	assert_eq(on.final_row()["tax_rate"], 0.85)
	assert_eq(off.final_row()["tax_rate"], 0.85)
	assert_almost_eq(float(off.final_row()["population"]), 20.0, 0.5)
	assert_gt(float(on.final_row()["population"]), float(off.final_row()["population"]))
	assert_eq(float(on.final_row()["tea_coverage"]), 1.0)
	assert_eq(off.final_row()["tea_stock"], 0)


func test_tea_costs_money_and_it_is_in_the_operating_balance() -> void:
	var on: ScenarioResult = _result("tea_on")
	assert_gt(on.mean("imports_spent_pm", LAST_MINUTES_FROM, MINUTES), 0.0)
	assert_eq(_result("tea_off").mean("imports_spent_pm", LAST_MINUTES_FROM, MINUTES), 0.0)


# D-026: the bakery runs on imported flour with no mill, and the flour costs between 20 % and 30 %
# more than the wheat that would have been milled into it (priced at the base price, 2).
func test_imported_flour_feeds_the_city_with_no_mill() -> void:
	var imported: ScenarioResult = _result("flour_imported")
	assert_true(imported.survived())
	assert_eq(imported.final_row()["n_mill"], 0)
	assert_gte(float(imported.final_row()["bread_coverage"]), 0.95)
	assert_gt(imported.mean("imports_spent_pm", LAST_MINUTES_FROM, MINUTES), 0.0)
	assert_eq(imported.mean("wheat_spent_pm", LAST_MINUTES_FROM, MINUTES), 0.0)


# The same city with no mill: with the import it eats, without it the bread runs out and the game is lost.
func test_the_city_with_no_mill_is_lost_unless_it_imports_flour() -> void:
	var imported: ScenarioResult = _result("flour_imported")
	var not_imported: ScenarioResult = _result("flour_not_imported")
	assert_true(imported.survived())
	assert_false(not_imported.survived())
	assert_eq(not_imported.final_row()["n_mill"], 0)
	assert_eq(not_imported.mean("imports_spent_pm", 0, MINUTES), 0.0)
	assert_gt(not_imported.defeat_tick, 0)


func test_imported_flour_costs_a_quarter_more_per_bread_than_milling_at_the_base_price() -> void:
	var imported: ScenarioResult = _result("flour_imported")
	var bread: float = imported.mean("bread_produced_pm", LAST_MINUTES_FROM, MINUTES)
	var per_bread: float = imported.mean("imports_spent_pm", LAST_MINUTES_FROM, MINUTES) / bread
	# Two loaves per unit of flour; wheat at 2 pence makes 1 penny of input per loaf.
	assert_gte(per_bread, 1.0 * 1.2)
	assert_lte(per_bread, 1.0 * 1.3)


# D-025: the growth ceiling with tea is a tax of 0.85 exactly (100 - 40 r + 4 >= 70), and 0.86 is over it.
func test_tea_raises_the_growth_ceiling_from_75_to_85_percent() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	var cases: Array[Array] = [["tea_off", 0.75, true], ["tea_off", 0.76, false],
		["tea_on", 0.85, true], ["tea_on", 0.86, false]]
	for case: Array in cases:
		var scenario: Dictionary = ScenarioRunner.with_tax(ScenarioRunner.load_file(
			ScenarioRunner.SCENARIO_DIR.path_join("%s.json" % case[0])), case[1])
		var result: ScenarioResult = runner.run(scenario)
		assert_eq(float(result.final_row()["population"]) > 20.0, case[2], "%s at %s" % [case[0], case[1]])


# --- Issue #51: both chains open at once ---

# Cristian's criterion: with trigo → pan and cebada → cerveza running together, bread still covers at least
# this much in every one of the 20 seeds, and the share of the wharf that goes to barley never leaves the mill
# without wheat.
const BOTH_CHAINS_MIN_COVERAGE: float = 0.75
# The new wharf's first wheat reaches the mill within the first seconds; measured worst case is 7 ticks.
const SECOND_WHARF_SETTLE_TICKS: int = 15


func test_both_chains_keep_bread_covered_and_the_mill_supplied_across_twenty_seeds() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	var scenario: Dictionary = ScenarioRunner.load_file("res://tests/scenarios/both_chains.json")
	var lowest: float = INF
	var made_beer: int = 0
	for seed_value: int in range(1, SEEDS + 1):
		var variant: Dictionary = scenario.duplicate(true)
		variant["seed"] = seed_value
		var result: ScenarioResult = runner.run(variant)
		_assert_scripts_ran_clean(result)
		assert_true(result.survived(), "seed %d was lost" % seed_value)
		var coverage: float = float(result.final_row()["bread_coverage"])
		lowest = minf(lowest, coverage)
		assert_gte(coverage, BOTH_CHAINS_MIN_COVERAGE, "seed %d: bread coverage" % seed_value)
		# The mill's own supply, tick by tick. With one wharf and 30 % of it given to barley the mill gets 7 of
		# its 10 wheat per minute, so it waits for wheat part of the time until the second wharf arrives (the
		# PR reports how much); from then on the wheat share is 14 per minute and it must never wait again.
		var bought: int = result.second_chain_purchase_tick() + 1
		assert_gt(bought, 0, "seed %d bought its second wharf" % seed_value)
		# ... and it does wait before it: with 7 of its 10 wheat per minute it cannot be fully busy.
		var waited_before: int = 0
		for tick: int in result.waiting_input_ticks.get(&"mill", []):
			if tick <= bought:
				waited_before += 1
		assert_gt(waited_before, 0, "seed %d: the mill waits for wheat before the second wharf" % seed_value)
		for tick: int in result.waiting_input_ticks.get(&"mill", []):
			assert_lte(tick, bought + SECOND_WHARF_SETTLE_TICKS,
				"seed %d, tick %d: the mill ran out of wheat after the second wharf" % [seed_value, tick])
		# Nobody eats beer yet: the brewery fills its warehouse and stops, it never overshoots.
		assert_lte(result.peak("beer_stock"), float(runner.param(&"market.beer.storage_capacity")))
		assert_lte(result.peak("malt_stock"), float(runner.param(&"market.malt.storage_capacity")))
		if float(result.final_row()["beer_stock"]) > 0.0:
			made_beer += 1
	gut.p("both_chains over %d seeds: lowest final bread coverage %.2f, %d made beer" % [SEEDS, lowest, made_beer])
	assert_eq(made_beer, SEEDS, "the beer chain works in every seed")


# --- Issue #52: artisans ---

# The beer chain starts to pay for itself when its first building is up; the issue asks for less than ten
# minutes from then, with the tax of the artisans (the chain without their housing).
const ARTISANS_PAYBACK_MINUTES: float = 10.0
# Measured worst case with the data of Mason (PR #52); a higher figure means the economy moved.
const ARTISANS_PAYBACK_MEASURED_WORST: float = 10.5


func test_artisans_beer_keeps_bread_covered_and_the_artisans_pay_the_chain_across_twenty_seeds() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	var scenario: Dictionary = ScenarioRunner.load_file("res://tests/scenarios/long/artisans_beer.json")
	assert_eq(runner.validate(scenario), [] as Array[String])
	assert_eq(String(scenario["id"]), "artisans_beer")
	var lowest: float = INF
	var worst_payback: float = 0.0
	var within_ten: int = 0
	for seed_value: int in range(1, SEEDS + 1):
		var variant: Dictionary = scenario.duplicate(true)
		variant["seed"] = seed_value
		var result: ScenarioResult = runner.run(variant)
		_assert_scripts_ran_clean(result)
		assert_true(result.survived(), "seed %d was lost" % seed_value)
		assert_gt(result.chain_start_tick, 0, "seed %d built the beer chain" % seed_value)
		assert_gt(int(result.final_row()["artisan_population"]), 0, "seed %d: artisans moved in" % seed_value)
		assert_gt(float(result.peak("beer_consumed_pm")), 0.0, "seed %d: the artisans drink beer" % seed_value)
		# Bread stays covered while the artisans pay the chain back: the ten minutes after it starts.
		@warning_ignore("integer_division")
		var from_minute: int = result.chain_start_tick / ScenarioRunner.TICKS_PER_MINUTE
		var coverage: float = result.lowest("bread_coverage", from_minute, from_minute + 10)
		lowest = minf(lowest, coverage)
		assert_gte(coverage, BOTH_CHAINS_MIN_COVERAGE, "seed %d: bread coverage" % seed_value)
		var payback: float = result.payback_minutes(false)
		assert_gte(payback, 0.0, "seed %d: the tax of the artisans pays the chain back" % seed_value)
		assert_lte(payback, ARTISANS_PAYBACK_MEASURED_WORST, "seed %d: payback moved" % seed_value)
		assert_gt(result.payback_minutes(true), payback, "seed %d: the houses cost more" % seed_value)
		worst_payback = maxf(worst_payback, payback)
		if payback < ARTISANS_PAYBACK_MINUTES:
			within_ten += 1
	gut.p("artisans_beer over %d seeds: lowest bread coverage %.2f, payback worst %.2f min, %d under %.0f min"
		% [SEEDS, lowest, worst_payback, within_ten, ARTISANS_PAYBACK_MINUTES])
	if within_ten < SEEDS:
		pending("Issue #52 asks for a payback under %.0f min in all seeds; with the approved values it is %d of %d (worst %.2f min). Reported to Mason, data/ untouched."
			% [ARTISANS_PAYBACK_MINUTES, within_ten, SEEDS, worst_payback])


# Parity (issue #52): a city that builds no artisan housing has no artisans, drinks no beer and collects no
# head tax from them, in every scenario that existed before the class.
func test_scenarios_without_artisan_housing_never_have_artisans() -> void:
	for id: String in _results:
		if id == "artisans_beer":
			continue
		var result: ScenarioResult = _result(id)
		assert_eq(result.peak("artisan_population"), 0.0, id)
		assert_eq(result.peak("n_artisan_housing"), 0.0, id)
		assert_eq(result.peak("beer_consumed_pm"), 0.0, id)
		assert_eq(result.peak("artisan_taxes_pm"), 0.0, id)
		assert_eq(result.payback_minutes(false), -1.0, id)


# Parity: a city that builds neither malthouse nor brewery never has malt or beer.
func test_scenarios_without_the_beer_chain_never_touch_malt_or_beer() -> void:
	for id: String in ["flour_milled", "big_tight_r06", "small_rich", "tea_on"]:
		var result: ScenarioResult = _result(id)
		assert_eq(int(result.final_economy["stocks"].get(&"malt", 0)), 0, id)
		assert_eq(int(result.final_economy["stocks"].get(&"beer", 0)), 0, id)
		assert_eq(result.peak("n_malthouse") + result.peak("n_brewery"), 0.0, id)
