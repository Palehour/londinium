class_name DistrictLessons
extends RefCounted

# The lessons of the history view (issue #87, D-120): for each district of the map, the lessons it has by attribute
# and, once the cholera has come, the severity and deaths it had there. Read from the incidents snapshot only; empty
# with the incidents off (D-122), so the view of a game without them is the one of before.


# One line for the title and one per district, in the snapshot's order. `names` are the map's district names; a map
# without districts has the whole city as its one district.
static func lines(incidents: Dictionary, names: Dictionary[StringName, String]) -> Array[String]:
	var result: Array[String] = []
	if not incidents.get("enabled", false):
		return result
	result.append(Strings.text(Strings.STATS_SCREEN_LESSONS))
	for district: StringName in incidents["districts"]:
		var entry: Dictionary = incidents["districts"][district]
		var counts: Array[String] = []
		for attribute: StringName in ServiceSystem.ATTRIBUTES:
			counts.append(Strings.text(Strings.SERVICE_VALUE) % [Strings.text(Strings.SERVICE_ATTRIBUTES[attribute]),
				int(entry[attribute]["lessons"])])
		var crisis: String = Strings.text(Strings.STATS_SCREEN_LESSONS_NO_CRISIS)
		if entry.has("crisis"):
			crisis = Strings.text(Strings.STATS_SCREEN_LESSONS_CRISIS) % [roundi(float(entry["crisis"]["severity"]) * 100.0),
				int(entry["crisis"]["deaths"])]
		var name: String = names.get(district, "")
		result.append(Strings.text(Strings.STATS_SCREEN_LESSONS_ROW) % [
			name if not name.is_empty() else Strings.text(Strings.SERVICE_WHOLE_CITY), " · ".join(counts), crisis])
	return result
