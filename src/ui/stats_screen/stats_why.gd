class_name StatsWhy
extends RefCounted

# The "why?" of a chart bucket (issue #319, D-052, D-168): what the bucket's value was against the one before, and the
# causes the cause log (#82, D-066) holds for the seconds that bucket covers, newest first and with no filter
# (D-137). It reads what the history already keeps and adds no series; the simulation is never touched.

const NO_CELL: Vector2i = Vector2i(-1, -1)
const SUBJECT_CELL_MARK: String = "@"


# For one bucket of a chart, `index` among the chart's lines (as ChartTab.cursor_index() gives it). `parts` are the
# values to break down, each {"label", "values" (oldest bucket first), "unit"}. Returns:
# "available": whether the bucket has a value to explain; "lines": one text per part with a value;
# "events": the log's events inside the bucket, newest first; "cell": where "see on the map" goes, NO_CELL if none;
# "pruned": the log has dropped its oldest events.
static func compose(simulation: Simulation, chart: Dictionary, index: int, parts: Array[Dictionary]) -> Dictionary:
	var found: Dictionary = {"available": false, "lines": [] as Array[String], "events": [] as Array[Dictionary],
		"cell": NO_CELL, "pruned": simulation.stats_cause_first_serial() > 0}
	if index < 0 or chart.is_empty():
		return found
	var lines: Array[String] = []
	for part: Dictionary in parts:
		var text: String = _part_line(part, index)
		if not text.is_empty():
			lines.append(text)
	found["lines"] = lines
	found["available"] = not lines.is_empty()
	var events: Array[Dictionary] = _events_in_bucket(simulation, chart, index)
	found["events"] = events
	found["cell"] = _first_cell(events)
	return found


# The cell a building event's subject names ("bakery@3,4" is 3,4), or NO_CELL for any other subject.
static func cell_of(event: Dictionary) -> Vector2i:
	if StringName(event["kind"]) != &"building":
		return NO_CELL
	var text: String = String(event["subject"])
	var mark: int = text.rfind(SUBJECT_CELL_MARK)
	if mark < 0:
		return NO_CELL
	var pair: PackedStringArray = text.substr(mark + 1).split(",")
	if pair.size() != 2 or not pair[0].is_valid_int() or not pair[1].is_valid_int():
		return NO_CELL
	return Vector2i(int(pair[0]), int(pair[1]))


# A bucket covers the seconds (first + index) * bucket_seconds + 1 to (first + index + 1) * bucket_seconds, the same
# rule history_markers() uses.
static func _events_in_bucket(simulation: Simulation, chart: Dictionary, index: int) -> Array[Dictionary]:
	var seconds: int = maxi(1, int(chart["bucket_seconds"]))
	var start: int = (int(chart["first_bucket"]) + index) * seconds + 1
	var found: Array[Dictionary] = []
	for event: Dictionary in simulation.stats_events(start):
		if int(event["second"]) < start + seconds:
			found.push_front(event)
	return found


static func _first_cell(events: Array[Dictionary]) -> Vector2i:
	for event: Dictionary in events:
		var cell: Vector2i = cell_of(event)
		if cell != NO_CELL:
			return cell
	return NO_CELL


# "" when the part has no value in the bucket: an empty bucket holds NaN, and nothing is invented for it.
static func _part_line(part: Dictionary, index: int) -> String:
	var values: PackedFloat32Array = part["values"]
	if index >= values.size() or is_nan(values[index]):
		return ""
	var unit: StringName = part["unit"]
	var now: String = StatsTimeline.format_value(values[index], unit)
	if index == 0 or is_nan(values[index - 1]):
		return Strings.text(Strings.STATS_SCREEN_WHY_FIRST) % [part["label"], now]
	var change: float = values[index] - values[index - 1]
	var sign: String = "+" if change > 0.0 else ""
	return Strings.text(Strings.STATS_SCREEN_WHY_PART) % [part["label"],
		StatsTimeline.format_value(values[index - 1], unit), now, sign + StatsTimeline.format_value(change, unit)]
