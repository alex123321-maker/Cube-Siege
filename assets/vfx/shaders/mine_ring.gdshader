shader_type spatial;
// The box bounds a world-space volume. Scene depth clips rays against terrain
// and enemies; back faces also support a camera inside the bounds.
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, shadows_disabled;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D artwork : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color;
uniform vec4 hot_color : source_color;
uniform vec3 burst_origin;
uniform float radius = 4.5;
uniform float half_height = 0.765;
uniform float age = 0.0;
uniform float opacity = 0.76;
uniform float edge_lifetime = 0.28;
uniform float hold_time = 0.09;
uniform float lifetime = 0.42;
varying vec3 world_vertex;

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(cell), hash3(cell + vec3(1, 0, 0)), f.x),
		mix(hash3(cell + vec3(0, 1, 0)), hash3(cell + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(cell + vec3(0, 0, 1)), hash3(cell + vec3(1, 0, 1)), f.x),
		mix(hash3(cell + vec3(0, 1, 1)), hash3(cell + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 ray = normalize(world_vertex - CAMERA_POSITION_WORLD);
	vec3 camera = CAMERA_POSITION_WORLD - burst_origin;
	vec3 bounds = vec3(radius, half_height, radius);
	vec3 inverse_ray = 1.0 / (sign(ray) * max(abs(ray), vec3(0.00001)) + vec3(0.000001));
	vec3 a = (-bounds - camera) * inverse_ray;
	vec3 b = (bounds - camera) * inverse_ray;
	vec3 near_hit = min(a, b);
	vec3 far_hit = max(a, b);
	float enter = max(0.0, max(near_hit.x, max(near_hit.y, near_hit.z)));
	float leave = min(far_hit.x, min(far_hit.y, far_hit.z));
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 scene = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_distance = length(scene.xyz / scene.w - CAMERA_POSITION_WORLD);
	leave = min(leave, scene_distance);
	if (leave <= enter || age >= lifetime) { discard; }

	// One blast fills its maximum footprint on the damage frame. Outer heat
	// dissipates in place; there is no travelling ring or implosion.
	float envelope = 1.0 - smoothstep(hold_time, lifetime, age);
	float step_length = (leave - enter) / 24.0;
	vec4 accumulated = vec4(0.0);
	for (int i = 0; i < 24; i++) {
		vec3 p = camera + ray * (enter + (float(i) + 0.5) * step_length);
		vec3 q = p / radius;
		float r = length(q.xz);
		float outer = 1.0 - smoothstep(0.96, 1.0, r);
		float local_lifetime = mix(lifetime, edge_lifetime, smoothstep(0.45, 0.95, r));
		float cooling = 1.0 - smoothstep(hold_time, local_lifetime, age);
		vec3 flow = q * 11.0 + vec3(0.0, -age * 1.5, 0.0);
		flow += vec3(sin(flow.y * 0.6 + flow.z * 0.35), sin(flow.x * 0.65),
			cos(flow.z * 0.55 + flow.y * 0.3)) * 0.55;
		float fine = noise3(flow * 2.1 + 7.0);
		float folds = noise3(flow) * 0.68 + fine * 0.32;
		float vertical = 1.0 - smoothstep(0.55, 0.95, abs(p.y / half_height));
		// Painted brushwork modulates heat gently; the 3D field owns volume
		// shape. Two oblique projections avoid extruding one image into columns.
		vec2 art_uv = q.xz * 1.25 + 0.5;
		art_uv += vec2(sin(q.z * 6.0 + q.y * 2.0), cos(q.x * 5.0 - q.y * 3.0)) * 0.07;
		// Filter sub-voxel brush grain: hard texture cutouts undersample along
		// a 24-step ray and turn into vertical bands at grazing angles.
		art_uv += vec2(q.y * 0.7, -q.y * 0.5);
		vec4 painting = textureLod(artwork, art_uv, 2.0);
		vec4 cross_painting = textureLod(artwork, vec2(q.x + q.z * 0.35,
			q.y * 3.0 + q.z * 0.5) * 1.25 + vec2(0.36, 0.65), 2.0);
		float ink = mix(painting.r * painting.a, cross_painting.r * cross_painting.a, 0.5);
		float density = smoothstep(0.40, 0.53, folds - abs(p.y / half_height) * 0.10) * outer * vertical;
		density *= mix(0.40, 1.0, smoothstep(0.21, 0.38, fine));
		// Darker pockets separate hot lobes. Painted variation lightly breaks
		// up the hot ridges while the 3D folds retain the blast's volume.
		float painted_folds = folds + (ink - 0.35) * 0.06;
		vec3 color = mix(tint.rgb * 0.32, tint.rgb, smoothstep(0.40, 0.53, painted_folds));
		color = mix(color, hot_color.rgb, smoothstep(0.60, 0.72, painted_folds));
		float alpha = 1.0 - exp(-density * opacity * cooling * step_length * 3.5 / (radius / 4.5));
		accumulated.rgb += (1.0 - accumulated.a) * color * alpha;
		accumulated.a += (1.0 - accumulated.a) * alpha;
		if (accumulated.a > 0.97) { break; }
	}
	ALBEDO = accumulated.rgb / max(accumulated.a, 0.001);
	EMISSION = ALBEDO * 0.35 * envelope;
	ALPHA = accumulated.a;
}
