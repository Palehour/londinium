class_name DefeatCriticalRows
extends RefCounted

# Which defeat conditions the critical banner lists, and in which order (issue #350). The simulation decides the
# level and the seconds left (snapshot["defeat_state"]); this only reads them, it applies no rule.

const LEVEL_CRITICAL: StringName = &"critical"
# The three conditions of D-013, in the order the panel lists them, so a tie keeps a fixed order.
const TIE_ORDER: Array[StringName] = [&"bankruptcy", &"hunger", &"depopulation"]


# Rows {condition, seconds_left, cause} of every condition at the critical level, fewest seconds first.
# `cause` is the text and icon to use: the state's own "cause" when it carries one (bankruptcy under a receiver says
# loan_bankruptcy, D-128), else the condition. The condition stays bankruptcy for the order, the sound and the
# warning line. A snapshot without "defeat_state" (older saves, tests that build snapshots by hand) has no rows.
static func rows(snapshot: Dictionary) -> Array[Dictionary]:
	var states: Variant = snapshot.get("defeat_state", {})
	var found: Array[Dictionary] = []
	if states is not Dictionary:
		return found
	for condition: Variant in (states as Dictionary).keys():
		var state: Variant = states[condition]
		if state is not Dictionary or state.get("level", &"") != LEVEL_CRITICAL:
			continue
		found.append({"condition": StringName(condition), "seconds_left": int(state.get("seconds_left", 0)),
			"cause": StringName(state.get("cause", condition))})
	# sort_custom is not stable, so the tie is broken by an explicit rank.
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["seconds_left"] != b["seconds_left"]:
			return a["seconds_left"] < b["seconds_left"]
		var rank_a: int = _rank(a["condition"])
		var rank_b: int = _rank(b["condition"])
		if rank_a != rank_b:
			return rank_a < rank_b
		return String(a["condition"]) < String(b["condition"]))
	return found


static func conditions(found: Array[Dictionary]) -> Array[StringName]:
	var names: Array[StringName] = []
	for row: Dictionary in found:
		names.append(row["condition"])
	return names


static func _rank(condition: StringName) -> int:
	var index: int = TIE_ORDER.find(condition)
	return index if index >= 0 else TIE_ORDER.size()
