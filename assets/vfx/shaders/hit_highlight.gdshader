shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.87, 0.60, 1.0);

void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * strength * 0.45;
	ALPHA = strength * (0.22 + rim * 0.24);
}
