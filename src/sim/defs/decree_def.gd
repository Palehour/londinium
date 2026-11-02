class_name DecreeDef
extends RefCounted

# One decree of the era (issue #71, D-124). Its upkeep is the Params key decree.<id>.upkeep_per_min.

var id: StringName
var for_factions: Array[StringName] = []
var against_factions: Array[StringName] = []
var name_key: StringName = &""
var upkeep_key: StringName = &""


static func upkeep_key_for(decree_id: StringName) -> StringName:
	return StringName("decree.%s.upkeep_per_min" % decree_id)


func use_id(decree_id: StringName) -> void:
	id = decree_id
	upkeep_key = upkeep_key_for(decree_id)
