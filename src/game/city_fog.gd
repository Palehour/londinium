class_name CityFog
extends RefCounted

# The fog of the 3D greybox (issue #65, D-028): it opens as the camera comes close and closes as it pulls back. High
# quality is volumetric fog (Forward+ only); low quality is a plain depth fog that starts at the point the camera looks
# at. Game information is never hidden by it (Cristian, 2026-10-11): the point in view keeps at least
# MIN_FOCUS_VISIBILITY, and the marks, the selection and the labels are drawn outside the fog.

const HIGH: StringName = &"high"
const LOW: StringName = &"low"
const QUALITIES: Array[StringName] = [HIGH, LOW]
# The least share of the light of the point in view that the fog lets through, at any zoom. A rule, not a look: the
# data cannot go under it.
const MIN_FOCUS_VISIBILITY: float = 0.5


# 0 at the nearest zoom, 1 at the farthest, on a log scale so each wheel step moves it the same.
static func zoom_share(camera: CityCamera) -> float:
	return clampf(log(camera.distance / camera.min_distance) / log(camera.max_distance / camera.min_distance), 0.0, 1.0)


# The share of light from the point in view that reaches the camera with the high quality fog.
static func focus_visibility(settings: Dictionary[String, float], camera: CityCamera) -> float:
	return lerpf(settings["focus_visibility_near"], settings["focus_visibility_far"], zoom_share(camera))


# Extinction per metre so that the point in view, `distance` metres away, keeps its visibility: exp(-d * distance).
static func volumetric_density(settings: Dictionary[String, float], camera: CityCamera) -> float:
	return -log(focus_visibility(settings, camera)) / camera.distance


# The strongest the low quality fog gets, far behind the point in view.
static func depth_opacity(settings: Dictionary[String, float], camera: CityCamera) -> float:
	return lerpf(settings["depth_opacity_near"], settings["depth_opacity_far"], zoom_share(camera))


static func apply(environment: Environment, settings: Dictionary[String, float], color: Color, camera: CityCamera,
		quality: StringName) -> void:
	var high: bool = quality == HIGH
	environment.volumetric_fog_enabled = high
	environment.fog_enabled = not high
	if high:
		environment.volumetric_fog_density = volumetric_density(settings, camera)
		environment.volumetric_fog_albedo = color
		# The fog gives off its own colour, so the far city fades into a pale veil and not into a dark one.
		environment.volumetric_fog_emission = color
		environment.volumetric_fog_emission_energy = settings["volumetric_glow"]
		# The background is already the colour of the far city; fog over it only darkens the edge of the map.
		environment.volumetric_fog_sky_affect = 0.0
		environment.volumetric_fog_length = camera.distance * settings["volumetric_length_ratio"]
		return
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = color
	environment.fog_density = depth_opacity(settings, camera)
	environment.fog_depth_begin = camera.distance
	environment.fog_depth_end = camera.distance * settings["depth_end_ratio"]
