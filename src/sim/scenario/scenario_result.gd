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
