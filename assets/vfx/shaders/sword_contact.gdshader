shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D artwork : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 contact_color : source_color = vec4(1.0, 0.7, 0.29, 1.0);
uniform float age = 0.0;
uniform float lifetime = 0.16;
uniform float intensity = 1.6;

void fragment() {
	vec4 ink = texture(artwork, UV);
	float value = dot(ink.rgb, vec3(0.2126, 0.7152, 0.0722));
	float phase = clamp(age / lifetime, 0.0, 1.0);
	float erosion = smoothstep(0.15, 1.0, phase);
	float dissolve = smoothstep(erosion - 0.12, erosion + 0.12, value);
	vec3 color = mix(contact_color.rgb, vec3(1.0, 0.96, 0.79), smoothstep(0.65, 0.98, value));
	ALBEDO = color;
	EMISSION = color * intensity * value * (1.0 - phase);
	ALPHA = ink.a * smoothstep(0.02, 0.18, value) * dissolve * (1.0 - phase * phase);
}
