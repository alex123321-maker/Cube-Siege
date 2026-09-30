shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 steel_color : source_color;
uniform vec4 edge_color : source_color;
uniform vec4 gold_color : source_color;
uniform sampler2D artwork : source_color, filter_linear_mipmap, repeat_disable;
uniform bool traveling_head = false;
uniform float age = 0.0;
uniform float delay = 0.0;
uniform float lifetime = 0.50;
uniform float sweep_time = 0.075;
uniform float intensity = 2.2;
uniform float opacity = 1.0;
uniform int layer = 0; // sculpted blade, gold filament, pressure wake, ground cut, glint

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float t = max(age - delay, 0.0);
	float phase = clamp(t / lifetime, 0.0, 1.0);
	float head = 1.14 * (1.0 - pow(1.0 - clamp(t / sweep_time, 0.0, 1.0), 2.0));
	float reveal = 1.0 - smoothstep(head - 0.08, head, UV.x);
	float taper = pow(max(sin(UV.x * 3.14159265), 0.0), 0.35);
	float grain = hash(floor(UV * vec2(100.0, 18.0)));
	float erosion = smoothstep(0.26, 1.0, phase);
	float density = 0.27 + 0.38 * grain + 0.35 * (1.0 - UV.y);
	float dissolve = smoothstep(erosion - 0.08, erosion + 0.08, density);
	float envelope = smoothstep(0.0, 0.012, t) * (1.0 - smoothstep(0.28, 1.0, phase));
	float alpha = taper * reveal * dissolve * envelope;
	float rim = 1.0 - smoothstep(0.025, 0.13, UV.y);
	float bevel = 1.0 - smoothstep(0.13, 0.30, UV.y);
	float streak = pow(0.5 + 0.5 * sin(UV.y * 91.0 + UV.x * 13.0), 12.0);
	vec3 color = mix(steel_color.rgb, edge_color.rgb * 0.72, bevel);
	color = mix(color, vec3(1.0, 0.98, 0.88), rim);
	float glow = rim * 1.4 + bevel * 0.24 + streak * 0.10;
	if (layer == 0) {
		float ink_u = UV.x;
		float travel_mask = 1.0;
		if (traveling_head) {
			float moving_head = 1.90 * (1.0 - pow(1.0 - clamp(t / 0.23, 0.0, 1.0), 2.0));
			ink_u = (UV.x - moving_head + 0.88) / 0.88;
			travel_mask = step(0.0, ink_u) * (1.0 - step(1.0, ink_u));
			reveal = 1.0;
		}
		vec4 ink = texture(artwork, vec2(mix(0.025, 0.973, clamp(ink_u, 0.0, 1.0)), mix(0.25, 0.735, UV.y)));
		float value = dot(ink.rgb, vec3(0.299, 0.587, 0.114));
		float arrival = sweep_time * (1.0 - sqrt(max(0.0, 1.0 - UV.x / 1.14)));
		float tail_age = max(t - arrival, 0.0);
		float local_fade = 1.0 - smoothstep(0.055, 0.24, tail_age);
		float cutout = smoothstep(erosion * 0.40 - 0.13, erosion * 0.40 + 0.04, value);
		alpha = ink.a * reveal * envelope * local_fade * cutout * travel_mask;
		color = mix(steel_color.rgb * 0.60, ink.rgb, smoothstep(0.08, 0.65, value));
		glow = pow(value, 3.0) * 0.85;
	} else if (layer == 1) {
		color = mix(gold_color.rgb, vec3(1.0, 0.94, 0.70), rim);
		alpha *= (1.0 - smoothstep(0.2, 1.0, UV.y)) * (0.5 + grain * 0.5);
		alpha *= 1.0 - smoothstep(0.11, 0.24, t);
		glow = 0.45;
	} else if (layer == 2) {
		vec4 ink = texture(artwork, vec2(mix(0.025, 0.973, UV.x), mix(0.25, 0.735, UV.y)));
		color = steel_color.rgb;
		alpha *= ink.a * (0.1 + 0.4 * streak) * (1.0 - smoothstep(0.08, 0.30, t));
		glow = 0.08;
	} else if (layer == 3) {
		color = mix(vec3(0.04, 0.11, 0.14), gold_color.rgb, pow(1.0 - phase, 8.0));
		alpha = envelope * dissolve * taper * pow(sin(UV.y * 3.14159265), 0.7) * 0.55;
		glow = pow(1.0 - phase, 10.0) * 0.5;
	} else {
		vec2 p = (UV - 0.5) * 2.0;
		float radial = length(p);
		float rays = exp(-abs(p.x) * 24.0) * exp(-abs(p.y) * 2.5)
			+ exp(-abs(p.y) * 32.0) * exp(-abs(p.x) * 2.5);
		alpha = (exp(-radial * 12.0) + rays) * (1.0 - phase) * envelope;
		if (layer == 5) {
			alpha = (exp(-radial * 12.0) + rays * 0.65) * pow(phase, 2.0);
		}
		color = vec3(1.0, 0.95, 0.78);
		glow = 2.0;
	}
	ALBEDO = color;
	EMISSION = color * glow * intensity * (1.0 - phase * 0.65);
	ALPHA = clamp(alpha * opacity, 0.0, 1.0) * step(delay, age) * (1.0 - step(lifetime, t));
}
