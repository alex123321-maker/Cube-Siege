shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D artwork : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color;
uniform float age = 0.0;
uniform float lifetime = 0.14;
uniform float opacity = 1.0;
uniform float emission = 0.75;
uniform bool dust = false;
uniform bool dark_edge = false;

void fragment() {
	vec4 ink = texture(artwork, UV);
	float value = dot(ink.rgb, vec3(0.2126, 0.7152, 0.0722));
	float phase = clamp(age / lifetime, 0.0, 1.0);
	float border = smoothstep(0.0, 0.08, UV.x) * smoothstep(0.0, 0.08, UV.y)
		* smoothstep(0.0, 0.08, 1.0 - UV.x) * smoothstep(0.0, 0.08, 1.0 - UV.y);
	float erode = smoothstep(0.20, 1.0, phase);
	float alpha = ink.a * border * smoothstep(erode - 0.14, erode + 0.14, value);
	vec3 color = mix(tint.rgb * 0.5, vec3(1.0, 0.94, 0.76), smoothstep(0.25, 0.92, value));
	if (dust) {
		color = tint.rgb * mix(0.6, 1.15, value);
		alpha *= smoothstep(0.0, 0.09, phase) * pow(1.0 - phase, 1.5);
	} else {
		alpha *= 1.0 - phase * phase;
	}
	if (dark_edge) { color = tint.rgb; }
	ALBEDO = color;
	EMISSION = color * emission * value * pow(1.0 - phase, 2.0);
	ALPHA = alpha * opacity;
}
