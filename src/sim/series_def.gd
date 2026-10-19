class_name SeriesDef
extends RefCounted

# One statistics series (issue #82, D-066): a metric, optionally narrowed to one member of each of its dimensions
# (a class, a good, a building type...). How a bucket sums it up depends on the aggregation: flows add up, levels
# are averaged or keep their last value.

const AGGREGATION_SUM: StringName = &"sum"
const AGGREGATION_MEAN: StringName = &"mean"
const AGGREGATION_LAST: StringName = &"last"
const AGGREGATIONS: Array[StringName] = [AGGREGATION_SUM, AGGREGATION_MEAN, AGGREGATION_LAST]
# District is declared before districts exist (#60) so saves made now never need migrating.
const DIMENSIONS: Array[StringName] = [&"class", &"good", &"building", &"category", &"source", &"cause", &"stage",
	&"condition", &"district"]
const UNITS: Array[StringName] = [&"pence", &"units", &"people", &"ratio", &"score", &"seconds", &"minutes"]

var id: StringName
var metric: StringName
var label_key: StringName
var unit: StringName
var aggregation: StringName
# Dimension -> member, in declaration order; empty for a global series.
var dimensions: Dictionary[StringName, StringName] = {}
# Reads the value of one tick from the state; it never writes to it.
var sampler: Callable


static func create(metric_id: StringName, unit_id: StringName, aggregation_id: StringName,
		members: Dictionary[StringName, StringName], read: Callable) -> SeriesDef:
	var result: SeriesDef = SeriesDef.new()
	result.metric = metric_id
	result.label_key = StringName("ui.stats.%s" % metric_id)
	result.unit = unit_id
	result.aggregation = aggregation_id
	result.dimensions = members.duplicate()
	result.sampler = read
	var parts: PackedStringArray = [String(metric_id)]
	for dimension: StringName in members:
		parts.append(String(members[dimension]))
	result.id = StringName(":".join(parts))
	return result


# What a view needs to label and scale the series, without the sampler.
func describe() -> Dictionary:
	return {"id": id, "metric": metric, "label_key": label_key, "unit": unit, "aggregation": aggregation,
		"dimensions": dimensions.duplicate()}
