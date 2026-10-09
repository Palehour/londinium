class_name Params
extends RefCounted

var _base_values: Dictionary[StringName, Variant] = {}
var _money_keys: Array[StringName] = []
var _modifiers: Array[Modifier] = []


func _init(catalog: DataCatalog, role: RoleDef) -> void:
	_base_values.assign(catalog.base_values)
	_money_keys.assign(catalog.money_keys)
	for modifier: Modifier in role.modifiers:
		_modifiers.append(Modifier.new(modifier.key, modifier.op, modifier.value))


func get_value(key: StringName) -> Variant:
	var value: Variant = _get_modified_value(key)
	if value == null:
		return null
	var defeat_key: StringName = &"defeat.depopulation.defeat_fraction"
	var warning_key: StringName = &"defeat.depopulation.warning_fraction"
	if key in [defeat_key, warning_key]:
		var other: Variant = _get_modified_value(warning_key if key == defeat_key else defeat_key)
		if other == null:
			return null
		var defeat: float = float(value if key == defeat_key else other)
		var warning: float = float(value if key == warning_key else other)
		if defeat > warning:
			push_error("Params: defeat.depopulation.defeat_fraction must be <= defeat.depopulation.warning_fraction after role modifiers")
			return null
	return value


func _get_modified_value(key: StringName) -> Variant:
	if not _base_values.has(key):
		push_error("Params: unknown key '%s'" % key)
		return null
	var value: Variant = _base_values[key]
	for modifier: Modifier in _modifiers:
		if modifier.key != key:
			continue
		match modifier.op:
			&"add": value = float(value) + modifier.value
			&"mul": value = float(value) * modifier.value
			&"set": value = modifier.value
			_:
				push_error("Params: unknown operation '%s' for '%s'" % [modifier.op, key])
				return null
	if not is_finite(float(value)):
		push_error("Params: nonfinite result for '%s'" % key)
		return null
	if not ParameterRanges.is_valid(key, float(value)):
		push_error("Params: invalid range for '%s'" % key)
		return null
	# Rounding once preserves the specified order, including intermediate fractions.
	if key in _money_keys and typeof(value) == TYPE_FLOAT:
		if value >= 9223372036854775808.0 or value < -9223372036854775808.0:
			push_error("Params: money result outside int64 for '%s'" % key)
			return null
		return roundi(value)
	return value
