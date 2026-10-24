// The subtle ink pass of the 3D greybox (issue #65, D-028): thin contours where depth or facing changes, hatching only
// in deep shadows, and paper grain. A screen quad drawn after the opaque city; the marks and the selection draw after
// it and the labels are 2D, so it never covers game information. Every number comes from data/ui/city.json ("ink").
shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, filter_nearest;
uniform vec3 ink_color : source_color;
uniform float line_px;
uniform float depth_threshold;
uniform float normal_threshold;
uniform float line_strength;
uniform float hatch_luminance;
uniform float hatch_spacing_px;
uniform float hatch_strength;
uniform float grain_strength;
uniform float grain_scale_px;
// The cell grid, inked on the ground only (below ground_top_m), as fine as grid_width_px at any distance.
uniform float grid_cell_m;
uniform float grid_width_px;
uniform float grid_strength;
uniform float ground_top_m;

// The quad covers the screen whatever the camera: its two-metre square is put straight in clip space.
void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inv_projection) {
	vec3 ndc = vec3(uv * 2.0 - 1.0, texture(depth_texture, uv).r);
	vec4 view = inv_projection * vec4(ndc, 1.0);
	return -view.z / view.w;
}

vec3 view_normal(vec2 uv) {
	return texture(normal_texture, uv).xyz * 2.0 - 1.0;
}

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 step_uv = line_px / VIEWPORT_SIZE;
	vec2 offsets[4] = {vec2(step_uv.x, 0.0), vec2(-step_uv.x, 0.0), vec2(0.0, step_uv.y), vec2(0.0, -step_uv.y)};
	float depth = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec3 normal = view_normal(SCREEN_UV);
	float around[4];
	float turn = 0.0;
	for (int i = 0; i < 4; i++) {
		around[i] = view_depth(SCREEN_UV + offsets[i], INV_PROJECTION_MATRIX);
		turn = max(turn, 1.0 - dot(normal, view_normal(SCREEN_UV + offsets[i])));
	}
	// The second difference: a plane seen at a grazing angle changes depth steadily and draws no line, a silhouette does.
	float bend = max(abs(around[0] + around[1] - 2.0 * depth), abs(around[2] + around[3] - 2.0 * depth)) / max(depth, 0.001);
	float line = max(step(depth_threshold, bend), step(normal_threshold, turn)) * line_strength;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_texture, SCREEN_UV).r, 1.0);
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz / view.w, 1.0)).xyz;
	vec2 to_line = abs(fract(world.xz / grid_cell_m + 0.5) - 0.5) * grid_cell_m;
	vec2 pixel = fwidth(world.xz) * grid_width_px;
	float grid = max(1.0 - smoothstep(0.0, pixel.x, to_line.x), 1.0 - smoothstep(0.0, pixel.y, to_line.y));
	line = max(line, grid * grid_strength * step(world.y, ground_top_m));
	// The background has no depth (reversed z: 0 is infinitely far): no contour or grid on it, only the grain.
	line *= step(0.000001, texture(depth_texture, SCREEN_UV).r);
	vec3 color = texture(screen_texture, SCREEN_UV).rgb;
	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	float shadow = clamp(1.0 - luminance / hatch_luminance, 0.0, 1.0);
	float stroke = step(0.5, fract((FRAGCOORD.x + FRAGCOORD.y) / hatch_spacing_px));
	float hatch = (1.0 - stroke) * shadow * hatch_strength;
	vec3 inked = mix(color, ink_color, max(line, hatch));
	float grain = hash(floor(FRAGCOORD.xy / grain_scale_px)) - 0.5;
	ALBEDO = inked * (1.0 + grain * 2.0 * grain_strength);
}
