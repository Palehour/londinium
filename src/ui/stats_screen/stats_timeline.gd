class_name StatsTimeline
extends RefCounted

# The history view (issue #316, D-168): one series of the D-066 registry over a range, with a marker only for an
# event kind the simulation has already emitted and that data/ui/stats.json lists. place() and marker_text() stay
# for the classes view and the cause-log wording; the history chart does not use them.

# The history records its first second as 1, where every subject logs its starting cause: that is no change.
const FIRST_SECOND: int = 1
# Kinds a real chapter logs today, and that Historia must not draw: they are not the marker candidates of D-168.
const HIDDEN_KINDS: Array[StringName] = [&"crisis", &"decree", &"patron", &"large_construction", &"policy", &"defeat"]


# Where a range's buckets sit in the chapter, "first_bucket" and "bucket_seconds", and its "markers"; every series
# of a level shares its buckets, so any one tells.
static func place(simulation: Simulation, tier: StringName, span: int) -> Dictionary:
	var placed: Dictionary = {"first_bucket": 0, "bucket_seconds": 1, "markers": [] as Array[Dictionary]}
	var defs: Array[Dictionary] = simulation.stats_series_defs()
	if defs.is_empty():
		return placed
	var series: Dictionary = simulation.stats_series(defs[0]["id"], tier)
	var count: int = StatsSummary.window(series, "mean", span).size()
	var bucket_seconds: int = maxi(1, int(series.get("bucket_seconds", 1)))
	var first: int = int(series.get("first_bucket", 0)) + series.get("mean", PackedFloat32Array()).size() - count
	placed["first_bucket"] = first
	placed["bucket_seconds"] = bucket_seconds
	placed["markers"] = _markers(simulation, first, count, bucket_seconds)
	return placed


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


# One series over the last span seconds of a level. The line is the registry field (mean when the series averages,
# otherwise total): no per-minute scale and no percent. Fear and debt have no series, so the chart has no line.
# Markers come from history_markers(), not from place().
static func chart(simulation: Simulation, series_id: StringName, tier: StringName, span: int,
		candidates: Array) -> Dictionary:
	var def: Dictionary = _definition(simulation, series_id)
	var drawn: Dictionary = {"id": series_id, "label": series_label(series_id, def), "unit": def.get("unit", &""),
		"lines": [] as Array[Dictionary], "first_bucket": 0, "bucket_seconds": 1, "markers": [] as Array[Dictionary]}
	if def.is_empty():
		return drawn
	var series: Dictionary = simulation.stats_series(series_id, tier)
	if series.is_empty():
		return drawn
	var field: String = "mean" if def["aggregation"] == &"mean" else "total"
	var values: PackedFloat32Array = StatsSummary.window(series, field, span)
	var bucket_seconds: int = maxi(1, int(series.get("bucket_seconds", 1)))
	var full: PackedFloat32Array = series.get(field, PackedFloat32Array())
	var first: int = int(series.get("first_bucket", 0)) + full.size() - values.size()
	drawn["first_bucket"] = first
	drawn["bucket_seconds"] = bucket_seconds
	drawn["lines"] = [{"label": drawn["label"], "values": values}] as Array[Dictionary]
	var events: Array[Dictionary] = simulation.stats_events()
	drawn["markers"] = history_markers(events, first, values.size(), bucket_seconds, candidates, _kinds(events))
	return drawn


# The name of a series from translation keys only. A missing member is left out rather than shown as its id.
static func series_label(series_id: StringName, def: Dictionary) -> String:
	if series_id == &"fear":
		return Strings.text(Strings.STATS_SCREEN_CARDS[&"fear"])
	if series_id == &"debt":
		return Strings.text(Strings.STATS_SCREEN_CARDS[&"debt"])
	if def.is_empty():
		return Strings.text(Strings.STATS_SCREEN_NO_DATA)
	var parts: PackedStringArray = PackedStringArray([Strings.text(def["label_key"])])
	for dimension: StringName in def["dimensions"]:
		var member: String = _member_label(dimension, def["dimensions"][dimension])
		if not member.is_empty():
			parts.append(member)
	return " · ".join(parts)


# The bucket value as the player reads it. Pence go through Strings.money; the rest use a translation format.
# A ratio stays a ratio: it is not turned into a percent.
static func format_value(value: float, unit: StringName) -> String:
	if is_nan(value):
		return ""
	if unit == &"pence":
		return Strings.money(roundi(value))
	var key: StringName = Strings.STATS_SCREEN_HISTORY_VALUE_RATIO if unit == &"ratio" \
		else Strings.STATS_SCREEN_HISTORY_VALUE
	return Strings.text(key) % value


# Markers of the closed buckets, grouped by bucket. A kind is drawn only when it is a candidate and the simulation
# has already emitted it. Several in one bucket become one mark whose text is the count key.
static func history_markers(events: Array, first: int, count: int, bucket_seconds: int, candidates: Array,
		registered: Array) -> Array[Dictionary]:
	var known: Dictionary = _known(registered)
	var allowed: Dictionary = {}
	for candidate: Variant in candidates:
		if candidate is not Dictionary:
			continue
		var kind: StringName = StringName(candidate.get("kind", &""))
		if kind != &"" and known.has(kind):
			allowed[kind] = candidate
	var groups: Dictionary = {}
	var order: Array[int] = []
	var seconds: int = maxi(1, bucket_seconds)
	for event: Variant in events:
		if event is not Dictionary:
			continue
		var kind: StringName = StringName(event.get("kind", &""))
		if not allowed.has(kind):
			continue
		@warning_ignore("integer_division")
		var bucket: int = (int(event.get("second", 0)) - 1) / seconds - first
		if bucket < 0 or bucket >= count:
			continue
		if not groups.has(bucket):
			groups[bucket] = [] as Array[Dictionary]
			order.append(bucket)
		var candidate: Dictionary = allowed[kind]
		groups[bucket].append({"kind": kind, "icon": String(candidate.get("icon", "")),
			"name": Strings.text(StringName(candidate.get("label_key", &"")))})
	var found: Array[Dictionary] = []
	for bucket: int in order:
		var items: Array = groups[bucket]
		var lines: PackedStringArray = PackedStringArray()
		var kinds: Array[StringName] = []
		for item: Dictionary in items:
			lines.append(Strings.text(Strings.STATS_SCREEN_MARKER_LINE) % [item["icon"], item["name"]])
			kinds.append(item["kind"])
		var text: String = lines[0] if lines.size() == 1 \
			else Strings.text(Strings.STATS_SCREEN_MARKER_STACK) % [" · ".join(lines), lines.size()]
		found.append({"bucket": bucket, "count": lines.size(), "text": text, "kinds": kinds,
			"icon": items[0]["icon"]})
	return found


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


static func _definition(simulation: Simulation, series_id: StringName) -> Dictionary:
	for def: Dictionary in simulation.stats_series_defs():
		if def["id"] == series_id:
			return def
	return {}


static func _kinds(events: Array[Dictionary]) -> Array[StringName]:
	var found: Array[StringName] = []
	for event: Dictionary in events:
		var kind: StringName = event["kind"]
		if kind not in found:
			found.append(kind)
	return found


static func _known(registered: Array) -> Dictionary:
	var found: Dictionary = {}
	for kind: Variant in registered:
		found[StringName(kind)] = true
	return found


# Never the raw id: a member without a key is omitted, so a new dimension cannot leak its identifier.
static func _member_label(dimension: StringName, member: StringName) -> String:
	var key: StringName = &""
	match dimension:
		&"class":
			key = Strings.CLASS_LABELS.get(member, &"")
		&"good":
			key = Strings.GOOD_LABELS.get(member, &"")
		&"building":
			return Strings.building_label(String(member))
		&"category":
			key = Strings.CATEGORY_LABELS.get(member, &"")
		&"condition":
			key = Strings.CONDITION_LABELS.get(member, &"")
		&"source":
			key = Strings.STATS_SOURCE_LABELS.get(member, &"")
		&"cause":
			key = Strings.STATS_CAUSE_LABELS.get(member, &"")
		&"stage":
			key = Strings.STATS_STAGE_LABELS.get(member, &"")
	if key == &"":
		return ""
	return Strings.text(key)
