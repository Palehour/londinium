class_name NeedOverlay
extends RefCounted

# The need layers of the map (issue #73, D-038): for one good, which houses get it and which do not. It only reads
# the snapshot (`distance.houses`, written by RoadSystem); whether a house is served is the simulation's answer.

const NONE: StringName = &""


# Every good some class needs, in the order of the classes and their needs, each once: the layers the map offers.
static func goods(context: EconomyContext) -> Array[StringName]:
	var found: Array[StringName] = []
	if context == null:
		return found
	for definition: ClassDef in context.classes.values():
		for need: NeedDef in definition.needs:
			if need.good not in found:
				found.append(need.good)
	return found


# The houses whose class needs the good, each {cell, definition_id, served}. A house cut off from the streets is
# not served: the simulation already says so in its served list.
static func houses(snapshot: Dictionary, good: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if good == NONE:
		return found
	for house: Dictionary in snapshot.get("distance", {}).get("houses", []):
		var served: Dictionary = house["served"]
		if not served.has(good):
			continue
		found.append({"cell": house["cell"].duplicate(), "definition_id": house["definition_id"],
			"served": bool(served[good])})
	return found


# The layer after this one, back to none after the last.
static func next(goods_list: Array[StringName], current: StringName) -> StringName:
	var cycle: Array[StringName] = [NONE]
	cycle.append_array(goods_list)
	return cycle[(maxi(cycle.find(current), 0) + 1) % cycle.size()]
