class_name FactionDef
extends RefCounted

# One faction of the era (issue #84, D-139): its fixed engine and the translation key of its name by year. Its numbers
# (target_base, target_scale and each class's affinity) are Params keys under factions.<id>.*.

# Ratepayers: the target falls with the rates spending over the rates income (D-139, point 4).
const RATES_RATIO: StringName = &"rates_ratio"
# Reformers: the target rises with the mean share of the services of `coverage` that reach each house.
const SERVICE_COVERAGE: StringName = &"service_coverage"
# Vestrymen: the target rises with the mean satisfaction.
const STABILITY: StringName = &"stability"
const ENGINES: Array[StringName] = [RATES_RATIO, SERVICE_COVERAGE, STABILITY]

var id: StringName
var engine: StringName
# The service attributes SERVICE_COVERAGE averages, all weighing the same; empty for the other engines.
var coverage: Array[StringName] = []
# {from_year, key}, by ascending from_year: the name changes with the year (Toynbee Hall opened in 1884, D-139).
var names: Array[Dictionary] = []


func name_key(year: int) -> StringName:
	var key: StringName = &""
	for entry: Dictionary in names:
		if year >= int(entry["from_year"]):
			key = entry["key"]
	return key


# Built once by the loader: the systems read them every tick, and formatting keys there was most of the cost.
var target_base_key: StringName
var target_scale_key: StringName
# By class id, the Params key of that class's affinity to this faction.
var affinity_keys: Dictionary[StringName, StringName] = {}


func use_id(faction_id: StringName) -> void:
	id = faction_id
	target_base_key = StringName("factions.%s.target_base" % id)
	target_scale_key = StringName("factions.%s.target_scale" % id)


static func affinity_key(class_id: StringName, faction_id: StringName) -> StringName:
	return StringName("factions.affinity.%s.%s" % [class_id, faction_id])
