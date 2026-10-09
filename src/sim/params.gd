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
	var errors: Array[String] = []
	var value: Variant = _get_validated_value(key, errors)
	for message: String in errors:
		push_error(message)
	return value


func validation_errors() -> Array[String]:
	# Loading must reject invalid roles without emitting runtime script errors.
	var errors: Array[String] = []
	for key: StringName in _base_values:
		_get_validated_value(key, errors)
	return errors


func _get_validated_value(key: StringName, errors: Array[String]) -> Variant:
	var value: Variant = _get_modified_value(key, errors)
	if value == null:
		return null
	var defeat_key: StringName = &"defeat.depopulation.defeat_fraction"
	var warning_key: StringName = &"defeat.depopulation.warning_fraction"
	if key in [defeat_key, warning_key]:
		var other: Variant = _get_modified_value(warning_key if key == defeat_key else defeat_key, errors)
		if other == null:
			return null
		var defeat: float = float(value if key == defeat_key else other)
		var warning: float = float(value if key == warning_key else other)
		if defeat > warning:
			errors.append("Params: defeat.depopulation.defeat_fraction must be <= defeat.depopulation.warning_fraction after role modifiers")
			return null
	return value


func _get_modified_value(key: StringName, errors: Array[String]) -> Variant:
	if not _base_values.has(key):
		errors.append("Params: unknown key '%s'" % key)
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
				errors.append("Params: unknown operation '%s' for '%s'" % [modifier.op, key])
				return null
	if not is_finite(float(value)):
		errors.append("Params: nonfinite result for '%s'" % key)
		return null
	if not ParameterRanges.is_valid(key, float(value)):
		errors.append("Params: invalid range for '%s'" % key)
		return null
	# Rounding once preserves the specified order, including intermediate fractions.
	if key in _money_keys and typeof(value) == TYPE_FLOAT:
		if value >= 9223372036854775808.0 or value < -9223372036854775808.0:
			errors.append("Params: money result outside int64 for '%s'" % key)
			return null
		return roundi(value)
	return value
