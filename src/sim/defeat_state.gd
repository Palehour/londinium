class_name DefeatState
extends RefCounted

var status: StringName = &"ok"
var elapsed_seconds: int = 0
var cause: StringName = &""


func to_dict() -> Dictionary:
	return {"status": status, "elapsed_seconds": elapsed_seconds, "cause": cause}


static func from_dict(values: Dictionary) -> DefeatState:
	var result: DefeatState = DefeatState.new()
	result.status = StringName(values.get("status", "ok"))
	result.elapsed_seconds = int(values.get("elapsed_seconds", 0))
	result.cause = StringName(values.get("cause", ""))
	return result
