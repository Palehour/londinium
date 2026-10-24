class_name StatsSummary
extends RefCounted

# The six cards of the summary view (issue #83, D-052). Every card reads series the history already keeps (#82,
# D-066) in its medium level and adds none to the simulation. Fear has no series until #88 and debt none until the
# loans of #72, so those two cards come out without lines and the screen says there is no data.

const CARDS: Array[StringName] = [&"population", &"balance", &"satisfaction", &"coverage", &"fear", &"debt"]
const GOODS: Array[StringName] = [&"bread", &"beer"]
const SECONDS_PER_MINUTE: float = 60.0
const PERCENT: float = 100.0


# One {"id", "lines", "value"} per card, in CARDS order. A line is {"label", "values"}, oldest bucket first over the
# last span_seconds; "value" is the latest reading as text, empty while the card has no data.
static func build(simulation: Simulation, span_seconds: int) -> Array[Dictionary]:
	var defs: Array[Dictionary] = simulation.stats_series_defs()
	var cards: Array[Dictionary] = []
	for id: StringName in CARDS:
		cards.append({"id": id, "lines": [] as Array[Dictionary], "value": ""})
	if defs.is_empty():
		return cards
	var population: PackedFloat32Array = _sum(simulation, defs, &"population", "mean", span_seconds)
	_fill(cards[0], [{"label": "", "values": population}], str(roundi(_latest(population))))
	_fill_balance(cards[1], simulation, defs, span_seconds)
	_fill_classes(cards[2], simulation, defs, span_seconds)
	_fill_coverage(cards[3], simulation, defs, span_seconds)
	return cards


static func _fill_balance(card: Dictionary, simulation: Simulation, defs: Array[Dictionary], span: int) -> void:
	var income: PackedFloat32Array = _sum(simulation, defs, &"income", "total", span)
	var expense: PackedFloat32Array = _sum(simulation, defs, &"expense", "total", span)
	# A bucket total is what came in during its seconds; scaled to a minute it reads like the live panel's balance.
	var per_minute: float = SECONDS_PER_MINUTE / float(_bucket_seconds(simulation, defs))
	var balance: PackedFloat32Array = []
	for index: int in mini(income.size(), expense.size()):
		balance.append((income[index] - expense[index]) * per_minute)
	_fill(card, [{"label": "", "values": balance}], Strings.money(roundi(_latest(balance))))


static func _fill_classes(card: Dictionary, simulation: Simulation, defs: Array[Dictionary], span: int) -> void:
	var lines: Array[Dictionary] = []
	var parts: PackedStringArray = []
	for def: Dictionary in defs:
		if def["metric"] != &"satisfaction":
			continue
		var label: String = Strings.label(Strings.CLASS_LABELS, def["dimensions"][&"class"])
		var values: PackedFloat32Array = _window(simulation.stats_series(def["id"], StatsHistory.TIER_MEDIUM), "mean", span)
		lines.append({"label": label, "values": values})
		parts.append(Strings.text(Strings.STATS_SCREEN_CLASS_VALUE) % [label, _latest(values)])
	_fill(card, lines, " · ".join(parts))


static func _fill_coverage(card: Dictionary, simulation: Simulation, defs: Array[Dictionary], span: int) -> void:
	var lines: Array[Dictionary] = []
	var parts: PackedStringArray = []
	for good: StringName in GOODS:
		var series: Dictionary = simulation.stats_series(StringName("coverage:%s" % good), StatsHistory.TIER_MEDIUM)
		if series.is_empty():
			continue
		var values: PackedFloat32Array = _window(series, "mean", span)
		for index: int in values.size():
			values[index] *= PERCENT
		var label: String = Strings.label(Strings.GOOD_LABELS, good)
		lines.append({"label": label, "values": values})
		parts.append(Strings.text(Strings.GOOD_COVERAGE) % [label, _latest(values)])
	_fill(card, lines, " · ".join(parts))


# A card whose lines have no closed bucket yet keeps them (the chart waits) but shows no reading.
static func _fill(card: Dictionary, lines: Array[Dictionary], value: String) -> void:
	card["lines"] = lines
	for line: Dictionary in lines:
		if not is_nan(_latest(line["values"])):
			card["value"] = value
			return


# Bucket by bucket sum of every series of a metric. A bucket a series has no data for (NaN) stays NaN.
static func _sum(simulation: Simulation, defs: Array[Dictionary], metric: StringName, field: String,
		span: int) -> PackedFloat32Array:
	var total: PackedFloat32Array = []
	for def: Dictionary in defs:
		if def["metric"] != metric:
			continue
		var values: PackedFloat32Array = _window(simulation.stats_series(def["id"], StatsHistory.TIER_MEDIUM), field, span)
		if total.is_empty():
			total = values
			continue
		for index: int in mini(total.size(), values.size()):
			total[index] += values[index]
	return total


# The last span seconds of one field of a medium-level series.
static func _window(series: Dictionary, field: String, span: int) -> PackedFloat32Array:
	var values: PackedFloat32Array = series.get(field, PackedFloat32Array())
	@warning_ignore("integer_division")
	var buckets: int = maxi(1, span / maxi(1, int(series.get("bucket_seconds", 1))))
	return values.slice(maxi(0, values.size() - buckets))


static func _bucket_seconds(simulation: Simulation, defs: Array[Dictionary]) -> int:
	return maxi(1, int(simulation.stats_series(defs[0]["id"], StatsHistory.TIER_MEDIUM).get("bucket_seconds", 1)))


# The newest bucket with data; NaN when there is none.
static func _latest(values: PackedFloat32Array) -> float:
	for index: int in range(values.size() - 1, -1, -1):
		if not is_nan(values[index]):
			return values[index]
	return NAN
