shader_type spatial;
render_mode depth_draw_never, shadows_disabled, specular_disabled;

uniform vec3 burst_origin;
uniform float radius = 4.5;
uniform float age = 0.0;
uniform float lifetime = 1.45;
uniform float opacity = 0.58;
uniform vec4 ember_color : source_color = vec4(0.95, 0.26, 0.04, 1.0);
varying vec3 terrain_position;
varying vec3 terrain_normal;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	// Reuse actual receiver geometry, including slopes and separate step faces.
	terrain_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	terrain_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	VERTEX += NORMAL * 0.012;
}

void fragment() {
	vec3 offset = terrain_position - burst_origin;
	// The blast uses 3D distance, so a tall slope cannot acquire an infinite
	// cylindrical scorch footprint. Geometry is never stretched across a gap.
	float reach = length(offset) / radius;
	if (reach >= 1.0 || age >= lifetime) { discard; }
	float broad = noise2(terrain_position.xz * 1.1);
	float grain = noise2(terrain_position.xz * 7.0);
	float edge = 1.0 - smoothstep(0.92, 1.0, reach + broad * 0.025);
	float rim = smoothstep(0.58, 0.86, reach);
	float broken = smoothstep(0.28, 0.58, broad * 0.7 + grain * 0.3);
	// Residual heat dies before the footprint; the remaining mark is cool
	// soot, so a completed explosion does not keep advertising active fire.
	float heat = (1.0 - smoothstep(0.12, 0.58, age)) * broken * mix(0.14, 0.72, rim);
	float soot = mix(0.65, 1.0, broad) * mix(0.85, 1.0, rim);
	float reveal = smoothstep(0.05, 0.16, age);
	float fade = 1.0 - smoothstep(0.75, lifetime, age);
	float facing = mix(0.18, 1.0, smoothstep(0.0, 0.65, terrain_normal.y));
	ALBEDO = mix(vec3(0.065, 0.045, 0.035), ember_color.rgb * 0.55, heat);
	ROUGHNESS = 1.0;
	EMISSION = ember_color.rgb * heat * heat * 0.85;
	ALPHA = edge * reveal * fade * facing * opacity * max(soot, heat);
}
