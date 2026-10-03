shader_type spatial;
// VANTA's Dojo surface shader: a precision-instrument grid.
//
// The grid is derived from world position, so it is stable under camera motion
// (nothing crawls or shimmers), and it fades with distance and with viewing angle so
// it never competes with a target for attention. Everything here is procedural: no
// texture assets are shipped, which keeps the download small and the licensing story
// trivial.
//
// render_mode unshaded is deliberate. Surfaces in the training environment exist to
// communicate geometry, not to look expensive.

render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec3 base_color : source_color = vec3(0.055, 0.065, 0.078);
uniform vec3 grid_color : source_color = vec3(0.14, 0.16, 0.19);
uniform vec3 accent_color : source_color = vec3(1.0, 0.207, 0.271);
uniform float grid_size = 1.0;
uniform float line_width = 0.012;
uniform float major_every = 5.0;
uniform float fade_distance = 45.0;
uniform float accent_strength = 0.0;
uniform float vertical_fade = 0.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 coord, float cell, float width) {
	vec2 scaled = coord / cell;
	vec2 derivative = fwidth(scaled);
	vec2 grid = abs(fract(scaled - 0.5) - 0.5) / max(derivative, vec2(0.00001));
	float line = min(grid.x, grid.y);
	return 1.0 - min(line * width * 100.0, 1.0);
}

void fragment() {
	// Only the dominant plane of the surface gets a grid, so a wall does not show a
	// floor pattern on its side.
	vec3 normal_abs = abs(NORMAL);
	vec2 coord = normal_abs.y > 0.5 ? world_position.xz : (normal_abs.x > 0.5 ? world_position.zy : world_position.xy);

	vec3 colour = base_color;
	float minor = grid_line(coord, grid_size, line_width);
	float major = grid_line(coord, grid_size * major_every, line_width * 1.6);
	colour = mix(colour, grid_color, minor * 0.55);
	colour = mix(colour, grid_color * 1.35, major * 0.85);

	// Accent rules mark the lateral centre line and the 5 m distance markers, which
	// gives the player a distance reference without a HUD element.
	if (accent_strength > 0.0) {
		float centre = 1.0 - min(abs(coord.x) / max(fwidth(coord.x) * 2.0, 0.02), 1.0);
		colour = mix(colour, accent_color, centre * accent_strength * 0.6);
	}

	// Distance fade keeps the far wall quiet instead of a moire field.
	float distance_from_camera = length(world_position - CAMERA_POSITION_WORLD);
	float fade = 1.0 - clamp(distance_from_camera / fade_distance, 0.0, 1.0);
	float horizontal_fade = 1.0;
	if (vertical_fade > 0.0) {
		horizontal_fade = clamp(vertical_fade - abs(world_position.y), 0.0, 1.0);
	}

	ALBEDO = mix(base_color, colour, clamp(fade * 1.4, 0.0, 1.0) * horizontal_fade);
}
