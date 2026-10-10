class_name Params
extends RefCounted

var _base_values: Dictionary[StringName, Variant] = {}
var _money_keys: Array[StringName] = []
var _boolean_keys: Array[StringName] = []
var _modifiers: Array[Modifier] = []


func _init(catalog: DataCatalog, role: RoleDef) -> void:
	_base_values.assign(catalog.base_values)
	_money_keys.assign(catalog.money_keys)
	_boolean_keys.assign(catalog.boolean_keys)
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
	var threshold_key: StringName = &"population.growth.hunger_emigration_threshold"
	var recovery_key: StringName = &"population.growth.hunger_emigration_recovery"
	if key in [threshold_key, recovery_key]:
		var other: Variant = _get_modified_value(recovery_key if key == threshold_key else threshold_key, errors)
		if other == null:
			return null
		var threshold: float = float(value if key == threshold_key else other)
		var recovery: float = float(value if key == recovery_key else other)
		if recovery < threshold:
			errors.append("Params: population.growth.hunger_emigration_recovery must be >= population.growth.hunger_emigration_threshold after role modifiers")
			return null
	return value


func _get_modified_value(key: StringName, errors: Array[String]) -> Variant:
	if not _base_values.has(key):
		errors.append("Params: unknown key '%s'" % key)
		return null
	var value: Variant = _base_values[key]
	if key in _boolean_keys:
		return _modified_boolean(key, value, errors)
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


# Switches stay booleans: a role may only set them, with 0 (off) or 1 (on).
func _modified_boolean(key: StringName, value: Variant, errors: Array[String]) -> Variant:
	for modifier: Modifier in _modifiers:
		if modifier.key != key:
			continue
		if modifier.op != &"set" or modifier.value not in [0.0, 1.0]:
			errors.append("Params: boolean '%s' only accepts set 0 or 1" % key)
			return null
		value = modifier.value == 1.0
	return value
