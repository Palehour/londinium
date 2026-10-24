class_name MissionState
extends RefCounted

# A mission of this game (issue #63, D-090). It runs once: active, then completed, failed or abandoned for good.
var status: StringName = MissionSystem.ACTIVE
# Ticks left before its goal is checked, the current one included.
var remaining_ticks: int = 0
# After a cholera failure (issue #202, D-090): the people it killed, then the ticks the houses stay empty and, once
# those are over, the ticks of faster immigration.
var deaths: int = 0
var vacancy_ticks: int = 0
var recovery_ticks: int = 0


func to_dict() -> Dictionary:
	return {"status": status, "remaining_ticks": remaining_ticks, "deaths": deaths, "vacancy_ticks": vacancy_ticks,
		"recovery_ticks": recovery_ticks}


static func from_dict(values: Dictionary) -> MissionState:
	var result: MissionState = MissionState.new()
	result.status = StringName(values.get("status", MissionSystem.ACTIVE))
	result.remaining_ticks = int(values.get("remaining_ticks", 0))
	result.deaths = int(values.get("deaths", 0))
	result.vacancy_ticks = int(values.get("vacancy_ticks", 0))
	result.recovery_ticks = int(values.get("recovery_ticks", 0))
	return result
