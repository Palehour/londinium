extends GutTest

# Issue #170: an NLS sheet comes as a scanned image (IIIF), so its pixels are tied to British National Grid metres
# with control points (OHM street corners) and a least-squares similarity: one scale, one rotation and a shift, the
# way a scan of a sheet keeps its shape. Bailey asks for the error of every point, in metres.

const SCALE: float = 1.9
const ROTATION_DEGREES: float = 1.5
const ORIGIN: PackedFloat64Array = [534700.0, 180200.0]
const SHIFT: Vector2 = Vector2(600.0, 300.0)
const TOLERANCE: float = 0.001


# Sheet pixel of a grid point under the known transform: x right, y down, so northing grows upwards.
func _pixel(en: PackedFloat64Array) -> PackedFloat64Array:
	var offset: Vector2 = Vector2(en[0] - ORIGIN[0], -(en[1] - ORIGIN[1])).rotated(deg_to_rad(ROTATION_DEGREES))
	var pixel: Vector2 = offset * SCALE + SHIFT
	return PackedFloat64Array([pixel.x, pixel.y])


func _points() -> Array[PackedFloat64Array]:
	var points: Array[PackedFloat64Array] = []
	for en: Array in [[534650.0, 180150.0], [534800.0, 180160.0], [534720.0, 180260.0], [534900.0, 180300.0],
			[534600.0, 180320.0], [534950.0, 180120.0]]:
		points.append(PackedFloat64Array(en))
	return points


func _pixels(points: Array[PackedFloat64Array]) -> Array[PackedFloat64Array]:
	var pixels: Array[PackedFloat64Array] = []
	for en: PackedFloat64Array in points:
		pixels.append(_pixel(en))
	return pixels


func test_the_fit_recovers_scale_rotation_and_shift() -> void:
	var points: Array[PackedFloat64Array] = _points()
	var fit: SheetGeoreference = SheetGeoreference.fit(_pixels(points), points)
	assert_not_null(fit)
	if fit == null:
		return
	assert_almost_eq(fit.scale, SCALE, TOLERANCE)
	assert_almost_eq(fit.rotation_degrees, ROTATION_DEGREES, TOLERANCE)
	var en: PackedFloat64Array = PackedFloat64Array([534555.5, 180044.4])
	var pixel: PackedFloat64Array = fit.to_pixel(en)
	assert_almost_eq(pixel[0], _pixel(en)[0], TOLERANCE)
	assert_almost_eq(pixel[1], _pixel(en)[1], TOLERANCE)
	var back: PackedFloat64Array = fit.to_bng(pixel)
	assert_almost_eq(back[0], en[0], TOLERANCE)
	assert_almost_eq(back[1], en[1], TOLERANCE)
	for index: int in range(points.size()):
		assert_almost_eq(fit.residual_metres(_pixels(points)[index], points[index]), 0.0, TOLERANCE)


func test_a_misplaced_point_shows_its_error_in_metres() -> void:
	var points: Array[PackedFloat64Array] = _points()
	var pixels: Array[PackedFloat64Array] = _pixels(points)
	# 30 px off at 1.9 px/m: among six points the fit spreads little of it, so that point keeps most of the error.
	pixels[3] = PackedFloat64Array([pixels[3][0] + 30.0, pixels[3][1]])
	var fit: SheetGeoreference = SheetGeoreference.fit(pixels, points)
	var errors: Array[float] = []
	for index: int in range(points.size()):
		errors.append(fit.residual_metres(pixels[index], points[index]))
	assert_eq(errors.find(errors.max()), 3)
	assert_between(errors[3], 0.5 * 30.0 / SCALE, 30.0 / SCALE)


func test_two_points_are_the_least_and_they_must_differ() -> void:
	var points: Array[PackedFloat64Array] = _points()
	assert_null(SheetGeoreference.fit(_pixels(points).slice(0, 1), points.slice(0, 1)))
	var same: Array[PackedFloat64Array] = [points[0], points[0]]
	assert_null(SheetGeoreference.fit(_pixels(same), same))
	assert_not_null(SheetGeoreference.fit(_pixels(points).slice(0, 2), points.slice(0, 2)))
