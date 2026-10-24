class_name Sparkline
extends Control

# A small line chart (issue #83): every line on one shared scale, each with its own stroke. Buckets without data
# (NaN) leave a gap instead of a made-up value. The dashes run along the whole line, not segment by segment, so a
# dashed line still reads as dashed when its buckets are only a few pixels apart.

var _lines: Array[PackedFloat32Array] = []
var _colors: Array[Color] = []
var _dashes: PackedFloat32Array = []
var _width: float = 1.0


func show_lines(lines: Array[PackedFloat32Array], colors: Array[Color], dashes: PackedFloat32Array, width: float) -> void:
	_lines = lines
	_colors = colors
	_dashes = dashes
	_width = width
	queue_redraw()


func _draw() -> void:
	var low: float = INF
	var high: float = -INF
	for values: PackedFloat32Array in _lines:
		for value: float in values:
			if not is_nan(value):
				low = minf(low, value)
				high = maxf(high, value)
	if low > high:
		return
	# A flat line sits in the middle rather than on an edge.
	var span: float = high - low if high > low else 1.0
	var base: float = low if high > low else low - 0.5
	for index: int in _lines.size():
		var values: PackedFloat32Array = _lines[index]
		var step: float = size.x / float(maxi(1, values.size() - 1))
		var travelled: float = 0.0
		for bucket: int in range(1, values.size()):
			if is_nan(values[bucket - 1]) or is_nan(values[bucket]):
				continue
			var from: Vector2 = Vector2((bucket - 1) * step, size.y * (1.0 - (values[bucket - 1] - base) / span))
			var to: Vector2 = Vector2(bucket * step, size.y * (1.0 - (values[bucket] - base) / span))
			travelled = _stroke(from, to, _colors[index], _dashes[index], travelled)


# Draws one segment of a line whose dash pattern has already run `travelled` pixels; returns the new total.
func _stroke(from: Vector2, to: Vector2, color: Color, dash: float, travelled: float) -> float:
	var length: float = from.distance_to(to)
	if dash <= 0.0:
		draw_line(from, to, color, _width, true)
		return travelled + length
	var done: float = 0.0
	while done < length:
		var phase: float = fmod(travelled + done, 2.0 * dash)
		var piece: float = minf(length - done, (dash if phase < dash else 2.0 * dash) - phase)
		if phase < dash:
			draw_line(from.lerp(to, done / length), from.lerp(to, (done + piece) / length), color, _width, true)
		done += piece
	return travelled + length
