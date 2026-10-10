class_name Modifier
extends RefCounted

var key: StringName
var op: StringName
var value: float


func _init(p_key: StringName, p_op: StringName, p_value: float) -> void:
	key = p_key
	op = p_op
	value = p_value
