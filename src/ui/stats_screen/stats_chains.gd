class_name StatsChains
extends RefCounted

# The chains view (issue #315, D-173). One chain from data/ui/stats.json, each link a building and the good it
# moves. The five columns read the series of D-066 over the same windows as the other tabs: flows add the bucket
# totals, stock keeps the last one. A series the registry does not have is missing (NaN, drawn as "—"), never a
# made-up zero. A link with no building of its type says there is no data instead of those numbers.
# The highlight is the first bread_causes entry with an id, and only on the chain whose data says so. Beer has
# none. The colour and the width live in stats.json; this class only says which link.

const COLUMN_IN: StringName = &"in"
const COLUMN_PRODUCED: StringName = &"produced"
const COLUMN_CONSUMED: StringName = &"consumed"
const COLUMN_SPOILED: StringName = &"spoiled"
const COLUMN_STOCK: StringName = &"stock"
const DIAGNOSTIC_BREAD: StringName = &"bread"


# One chain: {"id", "links": [{building, good, present, highlighted, values}]}. values maps each column to a float,
# NaN where the series does not exist or the window has no number.
static func build(simulation: Simulation, order: Array[Dictionary], chain_index: int, span: int,
		tier: StringName) -> Dictionary:
	if chain_index < 0 or chain_index >= order.size():
		return {"id": &"", "links": [] as Array[Dictionary]}
	var chain: Dictionary = order[chain_index]
	var snapshot: Dictionary = simulation.snapshot()
	var marked: StringName = &""
	if StringName(chain.get("diagnostic", &"")) == DIAGNOSTIC_BREAD:
		marked = first_marked_id(snapshot["diagnostics"]["bread_causes"])
	var buildings: Array = snapshot["economy"]["buildings"]
	var source: Array = chain["links"]
	var links: Array[Dictionary] = []
	for index: int in source.size():
		var link: Dictionary = source[index]
		var building: StringName = link["building"]
		links.append({
			"building": building,
			"good": link["good"],
			"present": _present(buildings, building),
			"highlighted": _highlighted(building, index, source, marked),
			"values": _values(simulation, link["good"], tier, span),
		})
	return {"id": chain["id"], "links": links}


# The first cause that names a building. An empty id (insufficient capacity) is skipped. "" when none do.
static func first_marked_id(causes: Array) -> StringName:
	for cause: Variant in causes:
		if cause is not Dictionary:
			continue
		var id: String = str(cause.get("definition_id", ""))
		if not id.is_empty():
			return StringName(id)
	return &""


# The line the link shows. Absent buildings say there is no data; the columns are not invented as zeros.
static func reading(link: Dictionary, columns: Array[StringName]) -> String:
	var name: String = Strings.building_label(String(link["building"]))
	if name.is_empty():
		name = String(link["building"])
	if not link["present"]:
		return Strings.text(Strings.STATS_SCREEN_CHAINS_ABSENT) % [name, Strings.text(Strings.STATS_SCREEN_NO_DATA)]
	var parts: PackedStringArray = []
	var values: Dictionary = link["values"]
	for column: StringName in columns:
		var label: String = Strings.label(Strings.STATS_SCREEN_CHAIN_COLUMNS, column)
		parts.append(Strings.text(Strings.STATS_SCREEN_CHAINS_VALUE) % [label, format_amount(float(values[column]))])
	return "%s · %s" % [name, " · ".join(parts)]


static func format_amount(value: float) -> String:
	if is_nan(value):
		return Strings.text(Strings.STATS_SCREEN_NO_READING)
	if is_equal_approx(value, round(value)):
		return str(roundi(value))
	return "%.1f" % value


# Only the first link of this chain whose building is the marked id. Another chain is never marked.
static func _highlighted(building: StringName, index: int, links: Array, marked: StringName) -> bool:
	if marked == &"" or building != marked:
		return false
	for earlier: int in index:
		if links[earlier]["building"] == marked:
			return false
	return true


static func _present(buildings: Array, building: StringName) -> bool:
	for placed: Variant in buildings:
		if placed is Dictionary and StringName(placed.get("definition_id", "")) == building:
			return true
	return false


static func _values(simulation: Simulation, good: StringName, tier: StringName, span: int) -> Dictionary[StringName, float]:
	var bought: float = _flow(simulation, &"bought", good, tier, span)
	var produced: float = _flow(simulation, &"produced", good, tier, span)
	var incoming: float = NAN
	# A missing side is left out of the sum. Both missing stays missing, so a gap is not drawn as 0.
	if not is_nan(bought) or not is_nan(produced):
		incoming = (0.0 if is_nan(bought) else bought) + (0.0 if is_nan(produced) else produced)
	return {
		COLUMN_IN: incoming,
		COLUMN_PRODUCED: produced,
		COLUMN_CONSUMED: _flow(simulation, &"consumed", good, tier, span),
		COLUMN_SPOILED: _flow(simulation, &"spoiled", good, tier, span),
		COLUMN_STOCK: _stock(simulation, good, tier, span),
	}


static func _flow(simulation: Simulation, metric: StringName, good: StringName, tier: StringName, span: int) -> float:
	return _reduce(simulation.stats_series(_series_id(metric, good), tier), span, false)


static func _stock(simulation: Simulation, good: StringName, tier: StringName, span: int) -> float:
	return _reduce(simulation.stats_series(_series_id(&"stock", good), tier), span, true)


static func _series_id(metric: StringName, good: StringName) -> StringName:
	return SeriesDef.create(metric, &"units", SeriesDef.AGGREGATION_SUM, {&"good": good}, _unused).id


static func _unused(_state: Variant) -> float:
	return 0.0


static func _reduce(series: Dictionary, span: int, last: bool) -> float:
	if series.is_empty():
		return NAN
	var values: PackedFloat32Array = StatsSummary.window(series, "total", span)
	if last:
		for index: int in range(values.size() - 1, -1, -1):
			if not is_nan(values[index]):
				return values[index]
		return NAN
	var total: float = 0.0
	var found: bool = false
	for value: float in values:
		if is_nan(value):
			continue
		total += value
		found = true
	return total if found else NAN
