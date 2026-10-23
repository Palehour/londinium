class_name MissionDef
extends RefCounted

# Structure of a mission (issue #63, D-090); its numbers are Params keys `mission.<id>.*`.
var id: StringName
var goal_metric: StringName
# A boolean Params key: while it is true and the mission is active, the depopulation timer stands still. Empty: none.
var defeat_pause: StringName = &""
# Per outcome (completed, failed, abandoned), its effects in order: {"type": StringName, "key": StringName}.
var effects: Dictionary[StringName, Array] = {}
