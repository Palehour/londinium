class_name StatsCompare
extends RefCounted

# The compare view's table (issue #318, D-168): the readings of two moments of the chapter, A and B, and what changed
# between them. It reads the summary's cards (StatsSummary), so it adds no series to the simulation and invents no
# number: a bucket with no data stays "—" and has no difference. Moments, not districts: the history keeps the city's
# series only, so there is nothing to split by district yet (D-168).

# The summary cards that have data. Fear has no series yet (#323), so it is not a row.
const CARDS: Array[StringName] = [&"population", &"balance", &"satisfaction", &"coverage", &"debt"]
const MONEY_CARDS: Array[StringName] = [&"balance", &"debt"]


# One {"card", "label", "a", "b", "diff"} per line of every compared card, in CARDS order. `cards` come from
# StatsSummary.build() over one window; a and b are bucket indexes of it (-1 when that marker is not set or is
# outside the window). A value is NaN when it is unknown, and diff is NaN unless both are known.
static func rows(cards: Array[Dictionary], index_a: int, index_b: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for card: Dictionary in cards:
		if card["id"] not in CARDS:
			continue
		for line: Dictionary in card["lines"]:
			var value_a: float = _at(line["values"], index_a)
			var value_b: float = _at(line["values"], index_b)
			found.append({"card": card["id"], "label": _label(card["id"], line["label"], card["lines"].size()),
				"a": value_a, "b": value_b, "diff": value_b - value_a})
	return found


# A bucket's value as the player reads it; "—" when there is none.
static func format(card: StringName, value: float) -> String:
	if is_nan(value):
		return Strings.text(Strings.STATS_SCREEN_NO_READING)
	if card == &"population":
		return str(roundi(value))
	if card in MONEY_CARDS:
		return Strings.money(roundi(value))
	return Strings.text(Strings.STATS_SCREEN_HISTORY_VALUE) % value


# B minus A, with its sign written; "—" when either moment has no value.
static func format_diff(card: StringName, diff: float) -> String:
	if is_nan(diff):
		return Strings.text(Strings.STATS_SCREEN_NO_READING)
	var text: String = format(card, absf(diff))
	if diff > 0.0:
		return Strings.text(Strings.STATS_SCREEN_COMPARE_UP) % text
	if diff < 0.0:
		return Strings.text(Strings.STATS_SCREEN_COMPARE_DOWN) % text
	return text


# The index in a chart of the bucket that holds `second` (the one a sample closes), or -1 when the chart does not show
# it. `chart` has "first_bucket", "bucket_seconds" and "lines", as ChartTab's.
static func bucket_of(chart: Dictionary, second: int, count: int) -> int:
	if second < 1 or count <= 0:
		return -1
	@warning_ignore("integer_division")
	var index: int = (second - 1) / int(chart["bucket_seconds"]) - int(chart["first_bucket"])
	return index if index >= 0 and index < count else -1


static func _at(values: PackedFloat32Array, index: int) -> float:
	return values[index] if index >= 0 and index < values.size() else NAN


static func _label(card: StringName, line_label: String, lines: int) -> String:
	var title: String = Strings.text(Strings.STATS_SCREEN_CARDS[card])
	if lines < 2 or line_label.is_empty():
		return title
	return Strings.text(Strings.STATS_SCREEN_COMPARE_ROW) % [title, line_label]
