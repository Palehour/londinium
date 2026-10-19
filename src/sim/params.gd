class_name Params
extends RefCounted

const WHEAT_POLICY_KEYS: Array[StringName] = [&"policy.wheat.default_accumulate_price",
	&"policy.wheat.default_max_price", &"policy.wheat.default_target_stock",
	&"market.wheat.storage_capacity", &"market.wheat.min_price", &"market.wheat.max_price",
	&"policy.wheat.default_reserve_minutes"]

var _base_values: Dictionary[StringName, Variant] = {}
var _money_keys: Array[StringName] = []
var _boolean_keys: Array[StringName] = []
var _modifiers: Array[Modifier] = []
# Values that already passed validation. Base values and modifiers never change after _init, so a key that
# validated once always gives the same value; the systems ask for the same keys many times a tick (once per
# class since issue #52), and validating every time was the slowest part of a tick. Failed reads are not
# kept, so every one of them still reports its errors.
var _validated: Dictionary[StringName, Variant] = {}


# `layers` are the difficulty's `set` modifiers (DataLayers). They go first so the role still applies last (D-065).
func _init(catalog: DataCatalog, role: RoleDef, layers: Array[Modifier] = []) -> void:
	_base_values.assign(catalog.base_values)
	_money_keys.assign(catalog.money_keys)
	_boolean_keys.assign(catalog.boolean_keys)
	for modifier: Modifier in layers + role.modifiers:
		_modifiers.append(Modifier.new(modifier.key, modifier.op, modifier.value))


func get_value(key: StringName) -> Variant:
	if _validated.has(key):
		return _validated[key]
	var errors: Array[String] = []
	var value: Variant = _get_validated_value(key, errors)
	for message: String in errors:
		push_error(message)
	if errors.is_empty():
		_validated[key] = value
	return value


# True when the data defines the key, so callers can ask about an optional parameter without an error.
func has_value(key: StringName) -> bool:
	return _base_values.has(key)


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
	var partner: StringName = _class_hunger_partner(key)
	if partner != &"":
		var other_hunger: Variant = _get_modified_value(partner, errors)
		if other_hunger == null:
			return null
		var is_threshold: bool = String(key).ends_with("hunger_emigration_threshold")
		var class_threshold: float = float(value if is_threshold else other_hunger)
		var class_recovery: float = float(other_hunger if is_threshold else value)
		if class_recovery < class_threshold:
			errors.append("Params: %s must be >= %s after role modifiers" % [
				key if not is_threshold else partner, partner if not is_threshold else key])
			return null
	if key in WHEAT_POLICY_KEYS:
		var message: String = _wheat_policy_error(errors)
		if not message.is_empty():
			errors.append("Params: %s after role modifiers" % message)
			return null
	return value


# The other key of the hunger hysteresis pair of a class (class.<id>.growth.*), or &"" for any other key.
func _class_hunger_partner(key: StringName) -> StringName:
	var text: String = String(key)
	if not text.begins_with("class."):
		return &""
	if text.ends_with(".growth.hunger_emigration_threshold"):
		return StringName(text.trim_suffix("threshold") + "recovery")
	if text.ends_with(".growth.hunger_emigration_recovery"):
		return StringName(text.trim_suffix("recovery") + "threshold")
	return &""


func _wheat_policy_error(errors: Array[String]) -> String:
	var values: Array[int] = []
	for key: StringName in WHEAT_POLICY_KEYS:
		var other: Variant = _get_modified_value(key, errors)
		if other == null:
			return "wheat policy parameters are unavailable"
		values.append(int(other))
	return wheat_policy_error(values)


# Values in WHEAT_POLICY_KEYS order.
static func wheat_policy_error(values: Array[int]) -> String:
	return WheatPolicy.validation_error(values[0], values[1], values[2], values[6], values[3], values[4], values[5])


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
