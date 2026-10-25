class_name StatsClasses
extends RefCounted

# The classes view (issue #83, D-052): the city's satisfaction over a range of the chapter, stacked by class. Each
# layer is a class's satisfaction weighted by its share of the residents, so the top of the stack is the
# satisfaction of the average resident. It reads the satisfaction and population series the history already keeps
# (#82, D-066) and adds none; what each class's satisfaction is made of has no series yet.

const PERCENT: float = 100.0


# StatsTimeline.place() plus "lines", one per class in the data order: {"label", "values" (its layer),
# "satisfaction", "share" (of the residents, 0 to 1)}, oldest bucket first; and "total", the top of the stack.
static func build(simulation: Simulation, tier: StringName, span: int) -> Dictionary:
	var chart: Dictionary = StatsTimeline.place(simulation, tier, span)
	var labels: Array[String] = []
	var satisfaction: Array[PackedFloat32Array] = []
	var population: Array[PackedFloat32Array] = []
	for def: Dictionary in simulation.stats_series_defs():
		if def["metric"] != &"satisfaction":
			continue
		var member: StringName = def["dimensions"][&"class"]
		labels.append(Strings.label(Strings.CLASS_LABELS, member))
		satisfaction.append(StatsSummary.window(simulation.stats_series(def["id"], tier), "mean", span))
		population.append(_population(simulation, member, tier, span))
	var split: Dictionary = _split(satisfaction, population)
	var stacked: Array[PackedFloat32Array] = split["layers"]
	var lines: Array[Dictionary] = []
	for index: int in labels.size():
		lines.append({"label": labels[index], "values": stacked[index], "satisfaction": satisfaction[index],
			"share": split["shares"][index]})
	chart["lines"] = lines
	chart["total"] = _total(stacked)
	return chart


# Bucket by bucket, each class's satisfaction times its share of the residents.
static func layers(satisfaction: Array[PackedFloat32Array], population: Array[PackedFloat32Array]) -> Array[PackedFloat32Array]:
	return _split(satisfaction, population)["layers"]


# The city and each class at one bucket of the chart; empty when that bucket has no residents.
static func reading(chart: Dictionary, index: int) -> String:
	var total: PackedFloat32Array = chart["total"]
	if index < 0 or index >= total.size() or is_nan(total[index]):
		return ""
	var parts: PackedStringArray = [Strings.text(Strings.STATS_SCREEN_CLASSES_CITY) % total[index]]
	for line: Dictionary in chart["lines"]:
		parts.append(Strings.text(Strings.STATS_SCREEN_CLASSES_CLASS) % [line["label"], line["satisfaction"][index],
			line["share"][index] * PERCENT])
	return " · ".join(parts)


static func _population(simulation: Simulation, member: StringName, tier: StringName, span: int) -> PackedFloat32Array:
	for def: Dictionary in simulation.stats_series_defs():
		if def["metric"] == &"population" and def["dimensions"][&"class"] == member:
			return StatsSummary.window(simulation.stats_series(def["id"], tier), "mean", span)
	return PackedFloat32Array()


# {"layers", "shares"}, one PackedFloat32Array per class each. A bucket with no residents, or one a class has no
# data for (NaN), is NaN in every layer and share: there is no average resident to stack.
static func _split(satisfaction: Array[PackedFloat32Array], population: Array[PackedFloat32Array]) -> Dictionary:
	var stacked: Array[PackedFloat32Array] = []
	var shares: Array[PackedFloat32Array] = []
	var buckets: int = -1
	for index: int in satisfaction.size():
		stacked.append(PackedFloat32Array())
		shares.append(PackedFloat32Array())
		var size: int = mini(satisfaction[index].size(), population[index].size())
		buckets = size if buckets < 0 else mini(buckets, size)
	for bucket: int in maxi(0, buckets):
		var people: float = 0.0
		var known: bool = true
		for index: int in satisfaction.size():
			known = known and not is_nan(satisfaction[index][bucket]) and not is_nan(population[index][bucket])
			people += population[index][bucket]
		for index: int in satisfaction.size():
			var share: float = population[index][bucket] / people if known and people > 0.0 else NAN
			shares[index].append(share)
			stacked[index].append(satisfaction[index][bucket] * share)
	return {"layers": stacked, "shares": shares}


static func _total(stacked: Array[PackedFloat32Array]) -> PackedFloat32Array:
	var total: PackedFloat32Array = []
	for index: int in stacked.size():
		if index == 0:
			total = stacked[0].duplicate()
			continue
		for bucket: int in total.size():
			total[bucket] += stacked[index][bucket]
	return total
