class_name ScenarioResult
extends RefCounted

# One CSV row per game minute (0 = before the first tick), plus a last row at the final tick when
# the game does not end on a whole minute. Order here is the CSV order.
const CSV_COLUMNS: Array[String] = [
	"scenario", "minute", "tick", "population", "money", "bread_coverage", "satisfaction",
	"bread_coverage_instant", "satisfaction_target", "tax_rate", "bread_stock",
	"bread_produced_pm", "bread_consumed_pm", "bread_demand_pm", "taxes_pm", "wages_pm",
	"upkeep_pm", "wheat_spent_pm", "operating_balance_pm", "construction_pm", "wheat_price",
	"employed", "unemployed", "housing_capacity", "n_wharf", "n_mill", "n_bakery", "n_housing",
	"bankruptcy", "hunger", "depopulation", "defeat_causes", "wheat_stock",
	"imports_spent_pm", "tea_spent_pm", "tea_stock", "tea_coverage", "flour_stock",
	"barley_spent_pm", "barley_stock",
	"n_malthouse", "n_brewery", "malt_stock", "beer_stock",
	"artisan_population", "artisan_satisfaction", "artisan_housing_capacity", "n_artisan_housing",
	"beer_coverage", "beer_consumed_pm", "artisan_taxes_pm",
]
# Float columns are printed with two decimals; everything else is printed as it is.
const FLOAT_COLUMNS: Array[String] = [
	"bread_coverage", "satisfaction", "bread_coverage_instant", "satisfaction_target", "tax_rate",
	"bread_produced_pm", "bread_consumed_pm", "bread_demand_pm", "taxes_pm", "wages_pm",
	"upkeep_pm", "wheat_spent_pm", "operating_balance_pm", "construction_pm", "imports_spent_pm",
	"tea_spent_pm", "tea_coverage", "barley_spent_pm",
	"artisan_satisfaction", "beer_coverage", "beer_consumed_pm", "artisan_taxes_pm",
]

var id: String = ""
var rows: Array[Dictionary] = []
# The economy dictionary of the last snapshot (EconomyState.to_dict()), for questions about the
# final state that the per-minute rows do not answer, such as DefeatSystem.is_city_stable().
var final_economy: Dictionary = {}
# The streets and the diagnostics at the end (issue #67): which houses each good reaches, the transport legs and why
# a building stops.
var final_distance: Dictionary = {}
var final_diagnostics: Dictionary = {}
# The incidents of each district at the end (issue #87, D-119): its pressure and its incidents by attribute.
var final_incidents: Dictionary = {}
# First tick (1-based count of ticks run) with a defeat cause, or -1 if the city survived.
var defeat_tick: int = -1
var defeat_causes: Array[StringName] = []
# One entry per scripted command: {tick, cmd, accepted, reason, expect_reject}.
var commands: Array[Dictionary] = []
# Highest timer ever reached by each defeat condition, in seconds.
var max_timer: Dictionary[StringName, int] = {}
# Tick count at which each condition first showed a warning (or defeat); absent if never.
var first_warning_tick: Dictionary[StringName, int] = {}
# "building:reason" pairs the panel's bread diagnostics showed at any tick, e.g. "mill:missing_building".
var bread_cause_pairs: Dictionary[String, bool] = {}
# Ticks (1-based count of ticks run) at which a staffed building of each type ran out of input while it still
# had capacity to use, e.g. &"mill" for a mill waiting for wheat (ProductionSystem counts it in _convert).
var waiting_input_ticks: Dictionary[StringName, Array] = {}
# Issue #52: what the head tax of the artisans pays back. The clock starts when the first building of the
# beer chain (malthouse, brewery) or of the artisans is up; it ends when the tax collected from the artisans
# reaches what that chain has cost since: "with housing" counts the artisan housing too, "without" leaves it
# out (the houses are what the beer is for). -1 until it happens.
var chain_start_tick: int = -1
var payback_tick_with_housing: int = -1
var payback_tick_without_housing: int = -1
# First tick that ended with artisans in the city (issue #55: the beer crisis starts relative to it); -1: never.
var first_artisan_tick: int = -1
# Bytes the chapter statistics take in a save at the end of the game, compressed (issue #82); not a CSV column.
var stats_history_bytes: int = -1
# The whole end-of-game snapshot plus that history, compressed alike: an upper bound of a save until #57.
var save_bytes: int = -1
# Events in the cause log at the end, and how many of them are intermittent (D-066); not CSV columns.
var stats_cause_events: int = -1
var stats_intermittent_events: int = -1
# The cause log itself, only when the runner keeps it (ScenarioRunner.keep_cause_events): what the "why?" of #73
# will read, so a probe can check that it names the cause of a defeat (issue #128).
var cause_events: Array[Dictionary] = []


func row(minute: int) -> Dictionary:
	return rows[minute]


func final_row() -> Dictionary:
	return rows[rows.size() - 1]


# Average of one column over minutes [from_minute, to_minute], both included.
func mean(column: String, from_minute: int, to_minute: int) -> float:
	var total: float = 0.0
	var count: int = 0
	for minute: int in range(from_minute, mini(to_minute, rows.size() - 1) + 1):
		total += float(rows[minute][column])
		count += 1
	return total / float(count) if count > 0 else 0.0


# Lowest value of one column over minutes [from_minute, to_minute], both included.
func lowest(column: String, from_minute: int, to_minute: int) -> float:
	var found: float = INF
	for minute: int in range(from_minute, mini(to_minute, rows.size() - 1) + 1):
		found = minf(found, float(rows[minute][column]))
	return found


func peak(column: String) -> float:
	var highest: float = -INF
	for values: Dictionary in rows:
		highest = maxf(highest, float(values[column]))
	return highest


# Tick (0-based, as in `executed_tick`) at which the second wharf was actually bought, or -1. The
# purchase is the financing event: with wait_for_money it happens between two per-minute rows.
func second_chain_purchase_tick() -> int:
	var wharves: int = 0
	for entry: Dictionary in commands:
		if entry["cmd"] == "build" and entry["building"] == "wharf" and entry["accepted"]:
			wharves += 1
			if wharves == 2:
				return int(entry["executed_tick"])
	return -1


# Minutes from the start of the beer chain to the payback; -1 when there was none.
func payback_minutes(with_housing: bool) -> float:
	var tick: int = payback_tick_with_housing if with_housing else payback_tick_without_housing
	if tick < 0 or chain_start_tick < 0:
		return -1.0
	return float(tick - chain_start_tick) / 60.0


# First minute in [from_minute, to_minute] whose column reaches `value`; -1 when none does.
func first_minute_at_least(column: String, value: float, from_minute: int, to_minute: int) -> int:
	for minute: int in range(from_minute, mini(to_minute, rows.size() - 1) + 1):
		if float(rows[minute][column]) >= value:
			return minute
	return -1


# Per-minute rows whose column is below `value` (minute 0 included).
func minutes_below(column: String, value: float) -> int:
	var count: int = 0
	for values: Dictionary in rows:
		if float(values[column]) < value:
			count += 1
	return count


# The metrics a scenario's "measure" asks for (issue #55), in a fixed order. Windows were checked by
# ScenarioRunner.validate(). A game lost early keeps its last row, so the windows read the frozen state.
func measured(measure: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	if measure.has("tax_window"):
		var window: Array = measure["tax_window"]
		found["taxes_pm_window"] = mean("taxes_pm", int(window[0]), int(window[1]))
	if measure.has("beer_cut"):
		found.merge(_beer_cut_metrics(measure["beer_cut"]))
	if measure.get("hourly", false):
		found.merge(_hourly_metrics())
	return found


# The beer is cut by the first accepted demolish and comes back with the first accepted build after it; both
# follow the game (the cut waits for the first artisans), so their minutes come from the commands. Reported:
# artisans before the cut, the fewest until the window ends, and how many minutes after the beer is back they
# reach `recovered_share` of the population before (-1: not within the window). A game whose cut never ran, or
# that had no artisans before it, has nothing to recover and never counts as recovered.
func _beer_cut_metrics(cut: Dictionary) -> Dictionary:
	var found: Dictionary = {
		"first_artisans_minute": float(first_artisan_tick) / 60.0 if first_artisan_tick >= 0 else -1.0,
		"beer_cut_minute": -1.0, "beer_cut_minutes": -1.0,
		"artisans_before_cut": 0.0, "artisans_lowest_after_cut": 0.0, "artisans_lost_in_cut": 0.0,
		"artisans_recovery_minutes": -1, "artisans_recovered": 0,
	}
	var cut_tick: int = _executed_tick("demolish", 0)
	var back_tick: int = _executed_tick("build", cut_tick + 1) if cut_tick >= 0 else -1
	if back_tick < 0:
		return found
	@warning_ignore("integer_division")
	var from_minute: int = cut_tick / 60
	@warning_ignore("integer_division")
	var back_minute: int = (back_tick + 59) / 60
	var window_end: int = back_minute + int(cut["recovery_minutes"])
	var before: float = float(row(from_minute)["artisan_population"])
	var fewest: float = lowest("artisan_population", from_minute, window_end)
	var recovered_at: int = -1
	if before > 0.0:
		recovered_at = first_minute_at_least("artisan_population", before * float(cut["recovered_share"]),
			back_minute, window_end)
	found["beer_cut_minute"] = float(cut_tick) / 60.0
	found["beer_cut_minutes"] = float(back_tick - cut_tick) / 60.0
	found["artisans_before_cut"] = before
	found["artisans_lowest_after_cut"] = fewest
	found["artisans_lost_in_cut"] = before - fewest
	found["artisans_recovery_minutes"] = recovered_at - back_minute if recovered_at >= 0 else -1
	found["artisans_recovered"] = 1 if recovered_at >= 0 else 0
	return found


# Executed tick of the first accepted command `cmd` that ran at `from_tick` or later; -1 when none did.
func _executed_tick(cmd: String, from_tick: int) -> int:
	for entry: Dictionary in commands:
		if entry["cmd"] == cmd and entry["accepted"] and int(entry["executed_tick"]) >= from_tick:
			return int(entry["executed_tick"])
	return -1


# Drift over long games: from the end of the first hour (the city is still being built) to the end. Money per
# hour, the lowest bread and beer coverage of those hours and the minutes in debt over the whole game.
func _hourly_metrics() -> Dictionary:
	var settled: int = ScenarioRunner.MINUTES_PER_HOUR
	var last: int = rows.size() - 1
	var hours: float = float(last - settled) / float(ScenarioRunner.MINUTES_PER_HOUR)
	return {
		"money_drift_per_hour": (float(final_row()["money"]) - float(row(settled)["money"])) / hours,
		"bread_coverage_lowest_after_hour1": lowest("bread_coverage", settled, last),
		"beer_coverage_lowest_after_hour1": lowest("beer_coverage", settled, last),
		"minutes_in_debt": minutes_below("money", 0.0),
	}


# One value per hour after the first: the lowest of `column` over minutes (start, start + 60], for long-test logs.
func lowest_per_hour(column: String) -> Array[float]:
	var found: Array[float] = []
	var start: int = ScenarioRunner.MINUTES_PER_HOUR
	while start < rows.size() - 1:
		found.append(lowest(column, start + 1, start + ScenarioRunner.MINUTES_PER_HOUR))
		start += ScenarioRunner.MINUTES_PER_HOUR
	return found


func survived() -> bool:
	return defeat_tick < 0


func unexpected_rejections() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in commands:
		# An accepted command only counts as expected when the script did not expect a refusal.
		var expected: StringName = entry["expect_reject"]
		var matches: bool = entry["reason"] == expected if not entry["accepted"] else expected == &""
		if not matches:
			found.append(entry)
	return found


static func csv_header() -> String:
	return ",".join(CSV_COLUMNS)


func csv_lines() -> Array[String]:
	var lines: Array[String] = []
	for values: Dictionary in rows:
		var cells: PackedStringArray = PackedStringArray()
		for column: String in CSV_COLUMNS:
			var value: Variant = values[column]
			cells.append("%.2f" % float(value) if column in FLOAT_COLUMNS else str(value))
		lines.append(",".join(cells))
	return lines
