class_name DefeatIcon
extends Control

# One icon per defeat condition, told apart by outline and inner mark, not by color (issue #350). Drawn in code:
# no image files.

const SHAPE_SQUARE: StringName = &"square"
const SHAPE_TRIANGLE: StringName = &"triangle"
const SHAPE_CIRCLE: StringName = &"circle"
const SHAPE_DIAMOND: StringName = &"diamond"
const SHAPES: Dictionary[StringName, StringName] = {
	&"bankruptcy": SHAPE_SQUARE, &"loan_bankruptcy": SHAPE_DIAMOND,
	&"hunger": SHAPE_TRIANGLE, &"depopulation": SHAPE_CIRCLE,
}
const SIZE: float = 40.0
const LINE_WIDTH: float = 3.0
const MARK_WIDTH: float = 3.0
const CIRCLE_POINTS: int = 32
const INSET: float = 4.0
# Where the inner marks sit, in icon pixels.
const BAR_TOP: float = 12.0
const BAR_BOTTOM_GAP: float = 10.0
const DOT_GAP: float = 5.0
const DOT_RADIUS: float = 1.8
const BAR_SIDE: float = 8.0

var shape: StringName = SHAPE_DIAMOND
var ink: Color = Color.BLACK
var paper: Color = Color.WHITE


static func shape_for(condition: StringName) -> StringName:
	return SHAPES.get(condition, SHAPE_DIAMOND)


func setup(condition: StringName, ink_color: Color, paper_color: Color) -> void:
	shape = shape_for(condition)
	ink = ink_color
	paper = paper_color
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var low: float = INSET
	var high: float = SIZE - INSET
	var middle: float = SIZE / 2.0
	match shape:
		SHAPE_SQUARE:
			draw_rect(Rect2(low, low, high - low, high - low), paper)
			draw_rect(Rect2(low, low, high - low, high - low), ink, false, LINE_WIDTH)
			# A cracked ledger: a diagonal split.
			draw_line(Vector2(low, high), Vector2(high, low), ink, MARK_WIDTH)
		SHAPE_TRIANGLE:
			var triangle: PackedVector2Array = PackedVector2Array([Vector2(middle, low), Vector2(high, high), Vector2(low, high)])
			draw_colored_polygon(triangle, paper)
			draw_polyline(PackedVector2Array([triangle[0], triangle[1], triangle[2], triangle[0]]), ink, LINE_WIDTH)
			# An exclamation bar and dot.
			draw_line(Vector2(middle, low + BAR_TOP), Vector2(middle, high - BAR_BOTTOM_GAP), ink, MARK_WIDTH)
			draw_circle(Vector2(middle, high - DOT_GAP), DOT_RADIUS, ink)
		SHAPE_CIRCLE:
			draw_circle(Vector2(middle, middle), middle - INSET, paper)
			draw_arc(Vector2(middle, middle), middle - INSET, 0.0, TAU, CIRCLE_POINTS, ink, LINE_WIDTH)
			# An empty ring: nobody left inside.
			draw_arc(Vector2(middle, middle), middle / 2.0, 0.0, TAU, CIRCLE_POINTS, ink, MARK_WIDTH)
		_:
			var diamond: PackedVector2Array = PackedVector2Array([Vector2(middle, low), Vector2(high, middle), Vector2(middle, high), Vector2(low, middle)])
			draw_colored_polygon(diamond, paper)
			draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), ink, LINE_WIDTH)
			draw_line(Vector2(low + BAR_SIDE, middle), Vector2(high - BAR_SIDE, middle), ink, MARK_WIDTH)
