shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D artwork : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 body_color : source_color;
uniform vec4 edge_color : source_color;
uniform float intensity = 1.6;
uniform float opacity = 0.9;

void fragment() {
	// Keep the painting's bright cutting edge at the sword tip.
	vec4 ink = texture(artwork, vec2(mix(0.16, 0.90, UV.x), mix(0.28, 0.74, UV.y)));
	float value = dot(ink.rgb, vec3(0.299, 0.587, 0.114));
	float freshness = COLOR.a;
	float dissolve = smoothstep((1.0 - freshness) * 0.85 - 0.1, (1.0 - freshness) * 0.85 + 0.1, value);
	float cutting_edge = 1.0 - smoothstep(0.0, 0.045, UV.y);
	vec3 color = mix(body_color.rgb, edge_color.rgb, smoothstep(0.5, 0.92, value));
	color = mix(color, edge_color.rgb, cutting_edge);
	ALBEDO = color;
	EMISSION = color * max(value, cutting_edge) * intensity * freshness;
	ALPHA = max(ink.a * smoothstep(0.01, 0.15, value) * dissolve, cutting_edge * 0.75) * freshness * opacity;
}
