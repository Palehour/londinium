extends GutTest

# Issue #152: the sources of the riverside strip come in WGS84 (OpenHistoricalMap) and Web Mercator tiles (NLS);
# the map importer reads British National Grid metres (EPSG:27700).

# Worked example of the Ordnance Survey's "A guide to coordinate systems in Great Britain" (annex C): a point on
# the Airy 1830 ellipsoid (OSGB36) and its National Grid easting and northing.
const OS_EXAMPLE_LAT_LON: PackedFloat64Array = [52.0 + 39.0 / 60.0 + 27.2531 / 3600.0,
	1.0 + 43.0 / 60.0 + 4.5177 / 3600.0]
const OS_EXAMPLE_EN: PackedFloat64Array = [651409.903, 313177.270]
const MILLIMETRE: float = 0.001
# One centimetre of latitude or longitude in London, in degrees.
const CENTIMETRE_IN_DEGREES: float = 0.0000002


func test_the_os_worked_example_projects_to_its_grid_reference() -> void:
	var en: PackedFloat64Array = OsgbProjection.osgb36_to_bng(OS_EXAMPLE_LAT_LON)
	assert_almost_eq(en[0], OS_EXAMPLE_EN[0], MILLIMETRE)
	assert_almost_eq(en[1], OS_EXAMPLE_EN[1], MILLIMETRE)


func test_the_os_worked_example_grid_reference_goes_back_to_its_latitude_and_longitude() -> void:
	var lat_lon: PackedFloat64Array = OsgbProjection.bng_to_osgb36(OS_EXAMPLE_EN)
	assert_almost_eq(lat_lon[0], OS_EXAMPLE_LAT_LON[0], CENTIMETRE_IN_DEGREES)
	assert_almost_eq(lat_lon[1], OS_EXAMPLE_LAT_LON[1], CENTIMETRE_IN_DEGREES)


# The datum shift (Helmert, about 5 m of accuracy per the OS) must undo itself, or a point would drift when the
# comparison image maps the grid back onto the NLS tiles.
func test_wgs84_and_the_grid_go_back_and_forth() -> void:
	for en: PackedFloat64Array in [PackedFloat64Array([534200, 180400]), PackedFloat64Array([535000, 179800]),
			PackedFloat64Array([533600, 180550])]:
		var back: PackedFloat64Array = OsgbProjection.wgs84_to_bng(OsgbProjection.bng_to_wgs84(en))
		assert_almost_eq(back[0], en[0], 0.01, str(en))
		assert_almost_eq(back[1], en[1], 0.01, str(en))


# OSGB36 sits over 100 m from WGS84 in London: skipping the datum shift would put every street two cells off.
func test_the_datum_shift_is_applied() -> void:
	var lat_lon: PackedFloat64Array = PackedFloat64Array([51.5045, -0.0620])
	var shifted: PackedFloat64Array = OsgbProjection.wgs84_to_bng(lat_lon)
	var unshifted: PackedFloat64Array = OsgbProjection.osgb36_to_bng(lat_lon)
	assert_between(Vector2(shifted[0] - unshifted[0], shifted[1] - unshifted[1]).length(), 100.0, 150.0)


func test_web_mercator_pixels_follow_the_tile_scheme() -> void:
	var centre: PackedFloat64Array = OsgbProjection.wgs84_to_tile_pixel(PackedFloat64Array([0.0, 0.0]), 1)
	assert_almost_eq(centre[0], 256.0, MILLIMETRE)
	assert_almost_eq(centre[1], 256.0, MILLIMETRE)
	var lat_lon: PackedFloat64Array = PackedFloat64Array([51.5045, -0.0620])
	var pixel: PackedFloat64Array = OsgbProjection.wgs84_to_tile_pixel(lat_lon, 19)
	var back: PackedFloat64Array = OsgbProjection.tile_pixel_to_wgs84(pixel, 19)
	assert_almost_eq(back[0], lat_lon[0], CENTIMETRE_IN_DEGREES)
	assert_almost_eq(back[1], lat_lon[1], CENTIMETRE_IN_DEGREES)
