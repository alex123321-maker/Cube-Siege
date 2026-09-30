shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D artwork : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 body_color : source_color;
uniform vec4 edge_color : source_color;
uniform float age = 0.0;
uniform float start_delay = 0.0;
uniform float lifetime = 0.32;
uniform float sweep_time = 0.065;
uniform float intensity = 1.6;
uniform float opacity = 1.0;
uniform bool reveal = true;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

void fragment() {
	float t = max(0.0, age - start_delay);
	float phase = clamp(t / lifetime, 0.0, 1.0);
	// Sample the painted band, preserving the source image and its alpha.
	vec2 art_uv = vec2(UV.x, mix(0.28, 0.74, UV.y));
	vec4 ink = texture(artwork, art_uv);
	float luminance = dot(ink.rgb, vec3(0.299, 0.587, 0.114));
	float grain = noise(UV * vec2(35.0, 7.0) + vec2(phase * 1.4, 0.0));
	float erosion = smoothstep(0.28, 1.0, phase);
	float density = luminance * 0.76 + grain * 0.24;
	float dissolve = smoothstep(erosion - 0.08, erosion + 0.10, density);
	float head = mix(-0.10, 1.20, 1.0 - pow(1.0 - clamp(t / sweep_time, 0.0, 1.0), 3.0));
	float visible_band = reveal ? 1.0 - smoothstep(head - 0.12, head, UV.x) : 1.0;
	float attack = smoothstep(0.0, 0.014, t);
	float fade = 1.0 - smoothstep(0.45, 1.0, phase);
	float active = step(start_delay, age) * (1.0 - step(lifetime, t));
	vec3 color = mix(body_color.rgb, edge_color.rgb, smoothstep(0.60, 0.95, luminance));
	ALBEDO = color;
	EMISSION = color * intensity * pow(luminance, 1.4) * (1.0 - phase * 0.65);
	ALPHA = ink.a * smoothstep(0.008, 0.12, luminance) * dissolve * visible_band * attack * fade * active * opacity;
}
