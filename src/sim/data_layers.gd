class_name DataLayers
extends RefCounted

# Difficulty layers (D-044, D-065). Order: base → mods → preset → knobs → role. The preset is relative to the
# values below it and the knobs are absolute, so both are resolved here, once, into `set` modifiers that Params
# applies before the role's: the role stays last, through the single modifier function (D-014).

const NORMAL: StringName = &"normal"
# Factors in data are written with finite decimals (5/3 as 1.6666667), so a fractional result is snapped to
# this precision to land on the value that was approved (0.35 × 0.7142857 → 0.25). Whole keys are rounded.
const FRACTION_PRECISION: float = 0.000001

var modifiers: Array[Modifier] = []
var errors: Array[String] = []


func is_ok() -> bool:
	return errors.is_empty()


static func resolve(catalog: DataCatalog, preset_id: StringName,
		knob_values: Dictionary[StringName, Variant] = {}) -> DataLayers:
	var layers: DataLayers = DataLayers.new()
	if not catalog.difficulties.has(preset_id):
		layers.errors.append("difficulty: unknown preset '%s'" % preset_id)
		return layers
	for knob_id: StringName in knob_values:
		if not catalog.knobs.has(knob_id):
			layers.errors.append("difficulty: unknown knob '%s'" % knob_id)
	if not layers.errors.is_empty():
		return layers
	var values: Dictionary[StringName, Variant] = {}
	for modifier: Modifier in catalog.difficulties[preset_id].modifiers:
		var current: float = float(values.get(modifier.key, catalog.base_values[modifier.key]))
		values[modifier.key] = current * modifier.value if modifier.op == &"mul" else current + modifier.value
	# Catalog order, not the caller's, so the same knobs always resolve the same way.
	for knob: KnobDef in catalog.knobs.values():
		if knob_values.has(knob.id):
			layers._apply_knob(catalog, knob, knob_values[knob.id], values)
	if not layers.errors.is_empty():
		return layers
	for key: StringName in values:
		layers.modifiers.append(Modifier.new(key, &"set", _rounded(catalog, key, values[key])))
	var role: RoleDef = RoleDef.new()
	for message: String in Params.new(catalog, role, layers.modifiers).validation_errors():
		layers.errors.append("difficulty '%s': %s" % [preset_id, message])
	if not layers.errors.is_empty():
		layers.modifiers.clear()
	return layers


static func _knob_error(knob: KnobDef, value: Variant) -> String:
	if knob.kind == &"switch":
		return "" if typeof(value) == TYPE_BOOL else "knob '%s': expected true or false" % knob.id
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return "knob '%s': expected a number" % knob.id
	var number: float = float(value)
	var steps: float = (number - knob.minimum) / knob.step
	var in_range: bool = (number >= knob.minimum or is_equal_approx(number, knob.minimum)) \
		and (number <= knob.maximum or is_equal_approx(number, knob.maximum))
	if not in_range or not is_equal_approx(steps, roundf(steps)):
		return "knob '%s': %s is outside %s..%s step %s" % [knob.id, value, _number_text(knob.minimum),
			_number_text(knob.maximum), _number_text(knob.step)]
	return ""


# Whole bounds read as 60, not 60.0, in the error.
static func _number_text(value: float) -> String:
	return str(int(value)) if value == floorf(value) else str(value)


func _apply_knob(catalog: DataCatalog, knob: KnobDef, value: Variant, values: Dictionary[StringName, Variant]) -> void:
	var message: String = _knob_error(knob, value)
	if not message.is_empty():
		errors.append("difficulty: %s" % message)
		return
	match knob.kind:
		&"switch":
			for key: StringName in knob.keys:
				values[key] = 1.0 if value else 0.0
		&"value":
			for key: StringName in knob.keys:
				values[key] = float(value)
		&"price_volatility":
			for grain: StringName in knob.keys:
				_scale_grain(catalog, grain, float(value), values)


# Volatility scales how far a price may climb above its base and how far it may move at once; a grain always
# keeps a step of at least one penny, or its price could never move.
static func _scale_grain(catalog: DataCatalog, grain: StringName, factor: float,
		values: Dictionary[StringName, Variant]) -> void:
	var base_key: StringName = StringName("market.%s.base_price" % grain)
	var max_key: StringName = StringName("market.%s.max_price" % grain)
	var step_key: StringName = StringName("market.%s.max_step" % grain)
	var base: float = float(values.get(base_key, catalog.base_values[base_key]))
	var top: float = float(values.get(max_key, catalog.base_values[max_key]))
	var step: float = float(values.get(step_key, catalog.base_values[step_key]))
	values[max_key] = base + roundf((top - base) * factor)
	values[step_key] = maxf(1.0, roundf(step * factor))


static func _rounded(catalog: DataCatalog, key: StringName, value: Variant) -> float:
	if key in catalog.boolean_keys:
		return float(value)
	if key in catalog.integer_keys:
		return float(roundi(float(value)))
	return snappedf(float(value), FRACTION_PRECISION)
