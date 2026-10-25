class_name StatsSummary
extends RefCounted

# The six cards of the summary view (issue #83, D-052). Every card reads series the history already keeps (#82,
# D-066) in its medium level and adds none to the simulation. Fear has no series until #88 and debt none until the
# loans of #72, so those two cards come out without lines and the screen says there is no data. The history view
# draws the same metrics over other levels and spans (StatsTimeline).

const CARDS: Array[StringName] = [&"population", &"balance", &"satisfaction", &"coverage", &"fear", &"debt"]
const GOODS: Array[StringName] = [&"bread", &"beer"]
const SECONDS_PER_MINUTE: float = 60.0
const PERCENT: float = 100.0


# One {"id", "lines", "value"} per card, in CARDS order. A line is {"label", "values"}, oldest bucket first over the
# last span_seconds; "value" is the latest reading as text, empty while the card has no data.
static func build(simulation: Simulation, span_seconds: int) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for id: StringName in CARDS:
		cards.append(card(simulation, id, StatsHistory.TIER_MEDIUM, span_seconds))
	return cards


# One card over the last span_seconds of a level; a span of 0 or less takes every bucket the level keeps.
static func card(simulation: Simulation, id: StringName, tier: StringName, span: int) -> Dictionary:
	var result: Dictionary = {"id": id, "lines": [] as Array[Dictionary], "value": ""}
	var defs: Array[Dictionary] = simulation.stats_series_defs()
	if defs.is_empty():
		return result
	var lines: Array[Dictionary] = []
	match id:
		&"population":
			lines.append({"label": "", "values": _sum(simulation, defs, &"population", "mean", tier, span)})
		&"balance":
			lines.append({"label": "", "values": _balance(simulation, defs, tier, span)})
		&"satisfaction":
			lines = _classes(simulation, defs, tier, span)
		&"coverage":
			lines = _coverage(simulation, tier, span)
	result["lines"] = lines
	result["value"] = reading(id, lines, -1)
	return result


# The card's reading at one bucket of its lines, or at each line's newest bucket with data when index is negative.
# Empty when no line has data there.
static func reading(id: StringName, lines: Array[Dictionary], index: int) -> String:
	var values: PackedFloat32Array = []
	var any: bool = false
	for line: Dictionary in lines:
		var series: PackedFloat32Array = line["values"]
		var value: float = _latest(series) if index < 0 else (series[index] if index < series.size() else NAN)
		values.append(value)
		any = any or not is_nan(value)
	if not any:
		return ""
	match id:
		&"population":
			return str(roundi(values[0]))
		&"balance":
			return Strings.money(roundi(values[0]))
	var key: StringName = Strings.STATS_SCREEN_CLASS_VALUE if id == &"satisfaction" else Strings.GOOD_COVERAGE
	var parts: PackedStringArray = []
	for line: int in lines.size():
		parts.append(Strings.text(key) % [lines[line]["label"], values[line]])
	return " · ".join(parts)


static func _balance(simulation: Simulation, defs: Array[Dictionary], tier: StringName, span: int) -> PackedFloat32Array:
	var income: PackedFloat32Array = _sum(simulation, defs, &"income", "total", tier, span)
	var expense: PackedFloat32Array = _sum(simulation, defs, &"expense", "total", tier, span)
	# A bucket total is what came in during its seconds; scaled to a minute it reads like the live panel's balance.
	var bucket_seconds: int = maxi(1, int(simulation.stats_series(defs[0]["id"], tier).get("bucket_seconds", 1)))
	var per_minute: float = SECONDS_PER_MINUTE / float(bucket_seconds)
	var balance: PackedFloat32Array = []
	for index: int in mini(income.size(), expense.size()):
		balance.append((income[index] - expense[index]) * per_minute)
	return balance


static func _classes(simulation: Simulation, defs: Array[Dictionary], tier: StringName, span: int) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for def: Dictionary in defs:
		if def["metric"] != &"satisfaction":
			continue
		var label: String = Strings.label(Strings.CLASS_LABELS, def["dimensions"][&"class"])
		lines.append({"label": label, "values": window(simulation.stats_series(def["id"], tier), "mean", span)})
	return lines


static func _coverage(simulation: Simulation, tier: StringName, span: int) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for good: StringName in GOODS:
		var series: Dictionary = simulation.stats_series(StringName("coverage:%s" % good), tier)
		if series.is_empty():
			continue
		var values: PackedFloat32Array = window(series, "mean", span)
		for index: int in values.size():
			values[index] *= PERCENT
		lines.append({"label": Strings.label(Strings.GOOD_LABELS, good), "values": values})
	return lines


# Bucket by bucket sum of every series of a metric. A bucket a series has no data for (NaN) stays NaN.
static func _sum(simulation: Simulation, defs: Array[Dictionary], metric: StringName, field: String,
		tier: StringName, span: int) -> PackedFloat32Array:
	var total: PackedFloat32Array = []
	for def: Dictionary in defs:
		if def["metric"] != metric:
			continue
		var values: PackedFloat32Array = window(simulation.stats_series(def["id"], tier), field, span)
		if total.is_empty():
			total = values
			continue
		for index: int in mini(total.size(), values.size()):
			total[index] += values[index]
	return total


# The last span seconds of one field of a series; every bucket it keeps when span is 0 or less.
static func window(series: Dictionary, field: String, span: int) -> PackedFloat32Array:
	var values: PackedFloat32Array = series.get(field, PackedFloat32Array())
	if span <= 0:
		return values
	@warning_ignore("integer_division")
	var buckets: int = maxi(1, span / maxi(1, int(series.get("bucket_seconds", 1))))
	return values.slice(maxi(0, values.size() - buckets))


# The newest bucket with data; NaN when there is none.
static func _latest(values: PackedFloat32Array) -> float:
	for index: int in range(values.size() - 1, -1, -1):
		if not is_nan(values[index]):
			return values[index]
	return NAN
