class_name SheetGeoreference
extends RefCounted

# Ties the pixels of a scanned NLS sheet (IIIF) to British National Grid metres (issue #170): a least-squares
# similarity, one scale, one rotation and a shift, which is how a scan of a flat sheet keeps its shape. An affine fit
# would also bend the sheet to absorb the errors of the control points, and those errors are what Bailey asks to see.
# Pixels grow to the right and down; easting and northing travel as [easting, northing], like OsgbProjection.

# Below this many pixels per metre the points sit on top of each other and give no fit.
const MIN_SCALE: float = 0.000001

var scale: float
var rotation_degrees: float
# pixel = rotation·scale·(easting - origin, origin - northing) + shift, kept as its four numbers.
var _a: float
var _b: float
var _shift: Vector2
var _origin: PackedFloat64Array


# The fit of `pixels` to `points` (the same length), or null with fewer than two distinct points.
static func fit(pixels: Array[PackedFloat64Array], points: Array[PackedFloat64Array]) -> SheetGeoreference:
	if pixels.size() < 2 or pixels.size() != points.size():
		return null
	var result: SheetGeoreference = SheetGeoreference.new()
	result._origin = points[0]
	# Normal equations of x = a·u - b·v + tx, y = b·u + a·v + ty, with u east and v south of the first point.
	var sums: Dictionary[String, float] = {"uu": 0.0, "u": 0.0, "v": 0.0, "x": 0.0, "y": 0.0, "ux": 0.0, "uy": 0.0}
	for index: int in range(points.size()):
		var u: float = points[index][0] - result._origin[0]
		var v: float = result._origin[1] - points[index][1]
		sums["uu"] += u * u + v * v
		sums["u"] += u
		sums["v"] += v
		sums["x"] += pixels[index][0]
		sums["y"] += pixels[index][1]
		sums["ux"] += u * pixels[index][0] + v * pixels[index][1]
		sums["uy"] += u * pixels[index][1] - v * pixels[index][0]
	var count: float = points.size()
	var spread: float = sums["uu"] - (sums["u"] * sums["u"] + sums["v"] * sums["v"]) / count
	if spread <= 0.0:
		return null
	result._a = (sums["ux"] - (sums["u"] * sums["x"] + sums["v"] * sums["y"]) / count) / spread
	result._b = (sums["uy"] - (sums["u"] * sums["y"] - sums["v"] * sums["x"]) / count) / spread
	result._shift = Vector2(sums["x"] - result._a * sums["u"] + result._b * sums["v"],
		sums["y"] - result._b * sums["u"] - result._a * sums["v"]) / count
	result.scale = sqrt(result._a * result._a + result._b * result._b)
	if result.scale < MIN_SCALE:
		return null
	result.rotation_degrees = rad_to_deg(atan2(result._b, result._a))
	return result


func to_pixel(en: PackedFloat64Array) -> PackedFloat64Array:
	var u: float = en[0] - _origin[0]
	var v: float = _origin[1] - en[1]
	return PackedFloat64Array([_a * u - _b * v + _shift.x, _b * u + _a * v + _shift.y])


func to_bng(pixel: PackedFloat64Array) -> PackedFloat64Array:
	var x: float = pixel[0] - _shift.x
	var y: float = pixel[1] - _shift.y
	var squared: float = scale * scale
	return PackedFloat64Array([_origin[0] + (_a * x + _b * y) / squared, _origin[1] - (_a * y - _b * x) / squared])


# How far, in metres on the ground, the fit puts `pixel` from the point it was given for.
func residual_metres(pixel: PackedFloat64Array, en: PackedFloat64Array) -> float:
	var fitted: PackedFloat64Array = to_pixel(en)
	return Vector2(fitted[0] - pixel[0], fitted[1] - pixel[1]).length() / scale
