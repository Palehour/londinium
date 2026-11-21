class_name NarratorText
extends RefCounted

# The words of a notice (issue #73, D-137): its rule's key, filled with the labels of its subject and cause. The
# placeholders of each kind are fixed here because the subject of each kind is a different thing (a building, a
# good, a class, a policy); which events speak, and with which key, stays in data/ui/narrator.json.

const NO_CELL: Vector2i = Vector2i(-1, -1)
const SUBJECT_AT: String = "@"
const CELL_SEPARATOR: String = ","
const TYPE_NONE: StringName = &"none"
const TYPE_BUILDING: StringName = &"building"
const TYPE_TILE: StringName = &"tile"


# `building_labels`: the map's names of the buildings, by id.
static func text(notice: Dictionary, building_labels: Dictionary) -> String:
	if notice["kind"] == Narrator.DIGEST_KIND:
		var parts: Array[String] = []
		for item: Dictionary in notice["items"]:
			parts.append(Strings.text(Strings.NARRATOR_DIGEST_ITEM) % [int(item["count"]), text(item["notice"], building_labels)])
		return Strings.text(Narrator.DIGEST_KEY) % " · ".join(parts)
	var phrase: String = Strings.text(notice["key"])
	var values: Array = _values(notice, building_labels)
	if not values.is_empty():
		phrase = phrase % values
	if int(notice["merged"]) > 1:
		phrase = Strings.text(Strings.NARRATOR_MERGED) % [phrase, int(notice["merged"])]
	return phrase


# The cell a notice's map target holds, NO_CELL when it has none.
static func cell_of(notice: Dictionary) -> Vector2i:
	return notice["map_target"].get("cell", NO_CELL)


# The place a notice points at: {"type": "building", "id", "cell"} for a subject that carries a cell, else
# {"type": "none"}. A district is not a subject of any kind the log keeps yet, so it falls to none.
static func map_target(subject: StringName, target_from: StringName) -> Dictionary:
	if target_from != NarratorConfig.TARGET_SUBJECT_CELL:
		return {"type": TYPE_NONE}
	var cell: Vector2i = _cell_of_subject(subject)
	if cell == NO_CELL:
		return {"type": TYPE_NONE}
	return {"type": TYPE_BUILDING, "id": StringName(String(subject).get_slice(SUBJECT_AT, 0)), "cell": cell}


# What the target is now: a building that was demolished falls back to its tile, and nothing is left when the tile is
# out of the map. `has_building` and `in_map` answer for a cell.
static func resolve_target(target: Dictionary, has_building: Callable, in_map: Callable) -> Dictionary:
	if target.get("type", TYPE_NONE) == TYPE_NONE:
		return target
	var cell: Vector2i = target["cell"]
	if has_building.call(cell):
		return target
	if in_map.call(cell):
		return {"type": TYPE_TILE, "cell": cell}
	return {"type": TYPE_NONE}


# {"series", "second"} for the chart of #83, or {} when the rule names no series.
static func graph_link(subject: StringName, series: String, second: int) -> Dictionary:
	if series.is_empty():
		return {}
	return {"series": StringName(fill(series, subject)), "second": second}


# `{subject}` is the event's subject; `{building}` its building id (the subject without its cell).
static func fill(template: String, subject: StringName) -> String:
	return template.replace("{subject}", String(subject)).replace("{building}", String(subject).get_slice(SUBJECT_AT, 0))


static func _cell_of_subject(subject: StringName) -> Vector2i:
	if not String(subject).contains(SUBJECT_AT):
		return NO_CELL
	var parts: PackedStringArray = String(subject).get_slice(SUBJECT_AT, 1).split(CELL_SEPARATOR)
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return NO_CELL
	return Vector2i(int(parts[0]), int(parts[1]))


static func _values(notice: Dictionary, building_labels: Dictionary) -> Array:
	var subject: StringName = notice["subject"]
	match notice["kind"]:
		&"defeat":
			return [Strings.label(Strings.CONDITION_LABELS, subject)]
		&"emigration":
			return [Strings.label(Strings.CLASS_LABELS, subject)]
		&"building":
			var id: StringName = StringName(String(subject).get_slice(SUBJECT_AT, 0))
			var name: String = building_labels.get(id, String(id))
			if notice["cause"] == CauseLog.INTERMITTENT:
				return [name, int(notice["count"])]
			return [name, Strings.reason(notice["cause"])]
		&"import":
			return [Strings.label(Strings.GOOD_LABELS, subject), Strings.reason(notice["cause"])]
		&"policy":
			return [Strings.label(Strings.STATS_SCREEN_POLICIES, subject), String(notice["cause"])]
	return []
