class_name CityInk
extends RefCounted

# The subtle ink pass of the 3D greybox (issue #65, D-028): fine contours, hatching only in deep shadows and paper
# grain, over the city and under the game information. The full engraving stays for the UI, the Archive and the cards.

const SHADER: Shader = preload("res://src/game/city_view/ink.gdshader")
const KEYS: Array[String] = ["line_px", "depth_threshold", "normal_threshold", "line_strength", "hatch_luminance",
	"hatch_spacing_px", "hatch_strength", "grain_strength", "grain_scale_px", "grid_width_px", "grid_strength", "ground_top_m"]
# Subtle on purpose and never over the game (Cristian, 2026-10-11): the grain moves a pixel by at most this share of its
# light, and hatching only reaches pixels darker than MAX_HATCH_LUMINANCE. Rules, not looks: the data cannot go past them.
const MAX_GRAIN: float = 0.1
const MAX_HATCH_LUMINANCE: float = 0.3
# The quad draws after the opaque city; whatever must stay readable draws after it (CityView's marks and selection).
const RENDER_PRIORITY: int = 0
const ABOVE_INK: int = RENDER_PRIORITY + 1


static func material(settings: Dictionary[String, float], color: Color, cell_size_m: float) -> ShaderMaterial:
	var ink: ShaderMaterial = ShaderMaterial.new()
	ink.shader = SHADER
	ink.render_priority = RENDER_PRIORITY
	ink.set_shader_parameter("ink_color", color)
	ink.set_shader_parameter("grid_cell_m", cell_size_m)
	for key: String in KEYS:
		ink.set_shader_parameter(key, settings[key])
	return ink


# A two-metre quad the shader puts straight in clip space; the huge cull margin keeps it from being culled.
static func quad(settings: Dictionary[String, float], color: Color, cell_size_m: float) -> MeshInstance3D:
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	mesh.material = material(settings, color, cell_size_m)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "Ink"
	instance.mesh = mesh
	instance.extra_cull_margin = 16384.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
