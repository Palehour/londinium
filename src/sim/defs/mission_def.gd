class_name MissionDef
extends RefCounted

# Structure of a mission (issue #63, D-090); its numbers are Params keys `mission.<id>.*`.
var id: StringName
var goal_metric: StringName
# The Params key of the goal's threshold: `mission.<id>.goal.at_least` or a shared key like mission.min_water_d.
var goal_key: StringName
# The event that starts it (issue #202): with the events on, duration_min before the minute in closes_at_key.
# Empty: only MissionCommand starts it.
var trigger_id: StringName = &""
var closes_at_key: StringName = &""
# Chronicler's fields (year, location, tag, sources, liberties): text for the card, never a rule.
var card: Dictionary = {}
# A boolean Params key: while it is true and the mission is active, the depopulation timer stands still. Empty: none.
var defeat_pause: StringName = &""
# Per outcome (started, completed, failed, abandoned), its effects in order: {"type": StringName, "key": StringName},
# without the key when the effect has no number.
var effects: Dictionary[StringName, Array] = {}
