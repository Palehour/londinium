class_name StackedChart
extends Sparkline

# A stacked area chart (issue #83): each layer sits on the ones before it, on a scale from 0 to the highest top.
# Every layer is filled with its stroke's colour, see-through so the marks behind show, and its top edge keeps the
# stroke's dash: two layers differ even without their colour. A bucket without data (NaN) leaves a gap.

var _fill_alpha: float = 1.0


func show_layers(layers: Array[PackedFloat32Array], colors: Array[Color], dashes: PackedFloat32Array, width: float,
		fill_alpha: float) -> void:
	_fill_alpha = fill_alpha
	show_lines(_tops(layers), colors, dashes, width)


func _draw() -> void:
	_draw_marks()
	var high: float = 0.0
	for values: PackedFloat32Array in _lines:
		for value: float in values:
			if not is_nan(value):
				high = maxf(high, value)
	if high <= 0.0:
		return
	for index: int in _lines.size():
		var top: PackedFloat32Array = _lines[index]
		var step: float = size.x / float(maxi(1, top.size() - 1))
		var fill: Color = Color(_colors[index], _fill_alpha)
		var travelled: float = 0.0
		for bucket: int in range(1, top.size()):
			if is_nan(top[bucket - 1]) or is_nan(top[bucket]):
				continue
			var below: Array[float] = [_bottom(index, bucket - 1), _bottom(index, bucket)]
			var from: Vector2 = Vector2((bucket - 1) * step, _y(top[bucket - 1], high))
			var to: Vector2 = Vector2(bucket * step, _y(top[bucket], high))
			var under_to: Vector2 = Vector2(to.x, _y(below[1], high))
			var under_from: Vector2 = Vector2(from.x, _y(below[0], high))
			# Two triangles, not a polygon: an empty layer is a flat one, which a polygon cannot triangulate.
			draw_primitive(PackedVector2Array([from, to, under_to]), PackedColorArray([fill, fill, fill]), [])
			draw_primitive(PackedVector2Array([from, under_to, under_from]), PackedColorArray([fill, fill, fill]), [])
			travelled = _stroke(from, to, _colors[index], _dashes[index], travelled)


# Each layer's top: its value plus every layer below it, bucket by bucket.
static func _tops(layers: Array[PackedFloat32Array]) -> Array[PackedFloat32Array]:
	var tops: Array[PackedFloat32Array] = []
	for index: int in layers.size():
		var top: PackedFloat32Array = layers[index].duplicate()
		if index > 0:
			for bucket: int in mini(top.size(), tops[-1].size()):
				top[bucket] += tops[-1][bucket]
		tops.append(top)
	return tops


func _bottom(index: int, bucket: int) -> float:
	return _lines[index - 1][bucket] if index > 0 else 0.0


func _y(value: float, high: float) -> float:
	return size.y * (1.0 - value / high)
