class_name MissionState
extends RefCounted

# A mission of this game (issue #63, D-090). It runs once: active, then completed, failed or abandoned for good.
var status: StringName = MissionSystem.ACTIVE
# Ticks left before its goal is checked, the current one included.
var remaining_ticks: int = 0


func to_dict() -> Dictionary:
	return {"status": status, "remaining_ticks": remaining_ticks}


static func from_dict(values: Dictionary) -> MissionState:
	var result: MissionState = MissionState.new()
	result.status = StringName(values.get("status", MissionSystem.ACTIVE))
	result.remaining_ticks = int(values.get("remaining_ticks", 0))
	return result
