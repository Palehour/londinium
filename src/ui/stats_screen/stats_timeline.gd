class_name StatsTimeline
extends RefCounted

# The history view (issue #83, D-052): one metric over a range of the chapter, with a marker on each bucket where
# something the cause log keeps happened (#82, D-066). The log has the player's policies, the defeat warnings and
# the stages completed; decrees (#71), patrons (#81), outbreaks (#87) and large buildings log nothing yet.

# The metrics with series to draw: the summary's cards but fear and debt.
const METRICS: Array[StringName] = [&"population", &"balance", &"satisfaction", &"coverage"]
# The history records its first second as 1, where every subject logs its starting cause: that is no change.
const FIRST_SECOND: int = 1


# The card of the metric (StatsSummary.card) plus where its buckets sit in the chapter, "first_bucket" and
# "bucket_seconds", and its "markers": {"bucket" (index in the lines), "second", "text"}, oldest first.
static func build(simulation: Simulation, metric: StringName, tier: StringName, span: int) -> Dictionary:
	var chart: Dictionary = StatsSummary.card(simulation, metric, tier, span)
	chart["first_bucket"] = 0
	chart["bucket_seconds"] = 1
	chart["markers"] = [] as Array[Dictionary]
	var defs: Array[Dictionary] = simulation.stats_series_defs()
	if defs.is_empty():
		return chart
	var series: Dictionary = simulation.stats_series(defs[0]["id"], tier)
	var count: int = StatsSummary.window(series, "mean", span).size()
	var bucket_seconds: int = maxi(1, int(series.get("bucket_seconds", 1)))
	var first: int = int(series.get("first_bucket", 0)) + series.get("mean", PackedFloat32Array()).size() - count
	chart["first_bucket"] = first
	chart["bucket_seconds"] = bucket_seconds
	chart["markers"] = _markers(simulation, first, count, bucket_seconds)
	return chart


# What a marker says about an event, or nothing when the event is not one the chart marks: a policy the player
# changed, a defeat condition's warning or defeat, and a stage completed.
static func marker_text(event: Dictionary) -> String:
	var subject: StringName = StringName(event["subject"])
	var cause: StringName = StringName(event["cause"])
	match StringName(event["kind"]):
		&"policy":
			if int(event["second"]) <= FIRST_SECOND:
				return ""
			return Strings.text(Strings.STATS_SCREEN_MARKER_POLICY) % Strings.label(Strings.STATS_SCREEN_POLICIES, subject)
		&"defeat":
			if cause not in [&"warning", &"defeat"]:
				return ""
			var key: StringName = Strings.STATS_SCREEN_MARKER_WARNING if cause == &"warning" \
				else Strings.STATS_SCREEN_MARKER_DEFEAT
			return Strings.text(key) % Strings.label(Strings.CONDITION_LABELS, subject)
		&"victory":
			if cause == &"completed":
				return Strings.text(Strings.STATS_SCREEN_MARKER_STAGE)
	return ""


# Events of the closed buckets shown; one still in the open bucket waits for it to close, like its values.
static func _markers(simulation: Simulation, first: int, count: int, bucket_seconds: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: Dictionary in simulation.stats_events(first * bucket_seconds + 1):
		var text: String = marker_text(event)
		@warning_ignore("integer_division")
		var bucket: int = (int(event["second"]) - 1) / bucket_seconds - first
		if not text.is_empty() and bucket < count:
			found.append({"bucket": bucket, "second": int(event["second"]), "text": text})
	return found
