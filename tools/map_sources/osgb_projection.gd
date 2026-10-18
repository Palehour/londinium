class_name OsgbProjection
extends RefCounted

# WGS84 latitude/longitude (OpenHistoricalMap, Web Mercator tiles) to British National Grid metres (EPSG:27700) and
# back, for the sources of the historic maps (issue #152). Formulas and constants are the Ordnance Survey's ("A guide
# to coordinate systems in Great Britain"): a 7-parameter Helmert shift between WGS84 and OSGB36, good to about 5 m
# (a tenth of a cell), and the Transverse Mercator projection of the National Grid on the Airy 1830 ellipsoid.
# Latitude and longitude travel as [lat, lon] in degrees and grid points as [easting, northing] in metres, both in
# PackedFloat64Array: Vector2 is single precision and would round a northing to the decimetre.

const AIRY_A: float = 6377563.396
const AIRY_B: float = 6356256.909
const WGS84_A: float = 6378137.0
const WGS84_B: float = 6356752.3142
# National Grid: scale on the central meridian, true origin (49°N, 2°W) and false origin in metres.
const F0: float = 0.9996012717
const LAT0: float = 49.0
const LON0: float = -2.0
const E0: float = 400000.0
const N0: float = -100000.0
# WGS84 to OSGB36: translation in metres, scale in ppm and rotations in arc seconds.
const HELMERT_T: Array[float] = [-446.448, 125.157, -542.06]
const HELMERT_S: float = 20.4894
const HELMERT_R: Array[float] = [-0.1502, -0.247, -0.8421]
# Stops the inverse projection once the meridional arc is within 0.01 mm.
const ARC_TOLERANCE: float = 0.00001
const LATITUDE_ITERATIONS: int = 10
const TILE_PIXELS: float = 256.0


static func wgs84_to_bng(lat_lon: PackedFloat64Array) -> PackedFloat64Array:
	return osgb36_to_bng(_helmert(lat_lon, WGS84_A, WGS84_B, AIRY_A, AIRY_B, 1.0))


static func bng_to_wgs84(en: PackedFloat64Array) -> PackedFloat64Array:
	return _helmert(bng_to_osgb36(en), AIRY_A, AIRY_B, WGS84_A, WGS84_B, -1.0)


static func osgb36_to_bng(lat_lon: PackedFloat64Array) -> PackedFloat64Array:
	var lat: float = deg_to_rad(lat_lon[0])
	var e2: float = _eccentricity_squared(AIRY_A, AIRY_B)
	var s: float = sin(lat)
	var c: float = cos(lat)
	var t2: float = tan(lat) * tan(lat)
	var nu: float = AIRY_A * F0 / sqrt(1.0 - e2 * s * s)
	var rho: float = AIRY_A * F0 * (1.0 - e2) / pow(1.0 - e2 * s * s, 1.5)
	var eta2: float = nu / rho - 1.0
	var i: float = _meridional_arc(lat) + N0
	var ii: float = nu / 2.0 * s * c
	var iii: float = nu / 24.0 * s * pow(c, 3) * (5.0 - t2 + 9.0 * eta2)
	var iiia: float = nu / 720.0 * s * pow(c, 5) * (61.0 - 58.0 * t2 + t2 * t2)
	var iv: float = nu * c
	var v: float = nu / 6.0 * pow(c, 3) * (nu / rho - t2)
	var vi: float = nu / 120.0 * pow(c, 5) * (5.0 - 18.0 * t2 + t2 * t2 + 14.0 * eta2 - 58.0 * t2 * eta2)
	var d: float = deg_to_rad(lat_lon[1] - LON0)
	return PackedFloat64Array([E0 + iv * d + v * pow(d, 3) + vi * pow(d, 5),
		i + ii * d * d + iii * pow(d, 4) + iiia * pow(d, 6)])


static func bng_to_osgb36(en: PackedFloat64Array) -> PackedFloat64Array:
	var e2: float = _eccentricity_squared(AIRY_A, AIRY_B)
	var lat: float = deg_to_rad(LAT0) + (en[1] - N0) / (AIRY_A * F0)
	while absf(en[1] - N0 - _meridional_arc(lat)) >= ARC_TOLERANCE:
		lat += (en[1] - N0 - _meridional_arc(lat)) / (AIRY_A * F0)
	var s: float = sin(lat)
	var t: float = tan(lat)
	var t2: float = t * t
	var sec: float = 1.0 / cos(lat)
	var nu: float = AIRY_A * F0 / sqrt(1.0 - e2 * s * s)
	var rho: float = AIRY_A * F0 * (1.0 - e2) / pow(1.0 - e2 * s * s, 1.5)
	var eta2: float = nu / rho - 1.0
	var vii: float = t / (2.0 * rho * nu)
	var viii: float = t / (24.0 * rho * pow(nu, 3)) * (5.0 + 3.0 * t2 + eta2 - 9.0 * t2 * eta2)
	var ix: float = t / (720.0 * rho * pow(nu, 5)) * (61.0 + 90.0 * t2 + 45.0 * t2 * t2)
	var x: float = sec / nu
	var xi: float = sec / (6.0 * pow(nu, 3)) * (nu / rho + 2.0 * t2)
	var xii: float = sec / (120.0 * pow(nu, 5)) * (5.0 + 28.0 * t2 + 24.0 * t2 * t2)
	var xiia: float = sec / (5040.0 * pow(nu, 7)) * (61.0 + 662.0 * t2 + 1320.0 * t2 * t2 + 720.0 * pow(t2, 3))
	var de: float = en[0] - E0
	return PackedFloat64Array([rad_to_deg(lat - vii * de * de + viii * pow(de, 4) - ix * pow(de, 6)),
		LON0 + rad_to_deg(x * de - xi * pow(de, 3) + xii * pow(de, 5) - xiia * pow(de, 7))])


# Global pixel of a Web Mercator tile pyramid (256 px tiles): tile x = floor(pixel[0] / 256).
static func wgs84_to_tile_pixel(lat_lon: PackedFloat64Array, zoom: int) -> PackedFloat64Array:
	var size: float = TILE_PIXELS * pow(2.0, zoom)
	var lat: float = deg_to_rad(lat_lon[0])
	return PackedFloat64Array([(lat_lon[1] + 180.0) / 360.0 * size,
		(1.0 - log(tan(lat) + 1.0 / cos(lat)) / PI) / 2.0 * size])


static func tile_pixel_to_wgs84(pixel: PackedFloat64Array, zoom: int) -> PackedFloat64Array:
	var size: float = TILE_PIXELS * pow(2.0, zoom)
	var lat: float = atan(sinh(PI * (1.0 - 2.0 * pixel[1] / size)))
	return PackedFloat64Array([rad_to_deg(lat), pixel[0] / size * 360.0 - 180.0])


static func _eccentricity_squared(a: float, b: float) -> float:
	return 1.0 - b * b / (a * a)


static func _meridional_arc(lat: float) -> float:
	var n: float = (AIRY_A - AIRY_B) / (AIRY_A + AIRY_B)
	var lat0: float = deg_to_rad(LAT0)
	var dl: float = lat - lat0
	var sl: float = lat + lat0
	return AIRY_B * F0 * ((1.0 + n + 1.25 * n * n + 1.25 * pow(n, 3)) * dl
		- (3.0 * n + 3.0 * n * n + 21.0 / 8.0 * pow(n, 3)) * sin(dl) * cos(sl)
		+ (15.0 / 8.0 * n * n + 15.0 / 8.0 * pow(n, 3)) * sin(2.0 * dl) * cos(2.0 * sl)
		- 35.0 / 24.0 * pow(n, 3) * sin(3.0 * dl) * cos(3.0 * sl))


# Latitude/longitude on one ellipsoid to the other through cartesian coordinates. `direction` 1 applies the
# WGS84 to OSGB36 parameters and -1 their inverse (the OS's own way back, exact to a few millimetres).
static func _helmert(lat_lon: PackedFloat64Array, from_a: float, from_b: float, to_a: float, to_b: float,
		direction: float) -> PackedFloat64Array:
	var lat: float = deg_to_rad(lat_lon[0])
	var lon: float = deg_to_rad(lat_lon[1])
	var from_e2: float = _eccentricity_squared(from_a, from_b)
	var nu: float = from_a / sqrt(1.0 - from_e2 * sin(lat) * sin(lat))
	var px: float = nu * cos(lat) * cos(lon)
	var py: float = nu * cos(lat) * sin(lon)
	var pz: float = (1.0 - from_e2) * nu * sin(lat)
	var s: float = 1.0 + HELMERT_S * direction / 1000000.0
	var rx: float = deg_to_rad(HELMERT_R[0] / 3600.0) * direction
	var ry: float = deg_to_rad(HELMERT_R[1] / 3600.0) * direction
	var rz: float = deg_to_rad(HELMERT_R[2] / 3600.0) * direction
	var qx: float = HELMERT_T[0] * direction + s * px - rz * py + ry * pz
	var qy: float = HELMERT_T[1] * direction + rz * px + s * py - rx * pz
	var qz: float = HELMERT_T[2] * direction - ry * px + rx * py + s * pz
	var to_e2: float = _eccentricity_squared(to_a, to_b)
	var horizontal: float = sqrt(qx * qx + qy * qy)
	var to_lat: float = atan2(qz, horizontal * (1.0 - to_e2))
	for _step: int in range(LATITUDE_ITERATIONS):
		var to_nu: float = to_a / sqrt(1.0 - to_e2 * sin(to_lat) * sin(to_lat))
		to_lat = atan2(qz + to_e2 * to_nu * sin(to_lat), horizontal)
	return PackedFloat64Array([rad_to_deg(to_lat), rad_to_deg(atan2(qy, qx))])
