class_name KnobDef
extends RefCounted

# A loose difficulty knob (D-065). Its value is absolute and overrides the preset.
# kind "switch": a boolean for every key. "value": the number for every key. "price_volatility": the keys are
# grains, and the value scales their max_step and the room between base and max price.
var id: StringName
var kind: StringName
var keys: Array[StringName] = []
var minimum: float = 0.0
var maximum: float = 0.0
var step: float = 0.0
