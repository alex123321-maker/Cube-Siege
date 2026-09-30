shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D artwork : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 base_color : source_color;
uniform vec4 hot_color : source_color;
uniform float age = 0.0;
uniform float delay = 0.0;
uniform float lifetime = 1.0;
uniform float opacity = 1.0;
uniform float intensity = 1.0;
uniform float turn = 0.0;
uniform bool fire = false;

void vertex() {
	// Camera-facing painted lobes still depth-test against the real scene.
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	facing[0] *= length(MODEL_MATRIX[0].xyz);
	facing[1] *= length(MODEL_MATRIX[1].xyz);
	facing[2] *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
}

void fragment() {
	float t = clamp((age - delay) / lifetime, 0.0, 1.0);
	float c = cos(turn), s = sin(turn);
	vec2 uv = mat2(vec2(c, -s), vec2(s, c)) * (UV - 0.5) + 0.5;
	vec4 ink = texture(artwork, uv);
	float border = smoothstep(0.0, 0.045, min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y)));
	float value = dot(ink.rgb, vec3(0.2126, 0.7152, 0.0722));
	float gate = step(delay, age);
	float erosion = smoothstep(0.28, 1.0, t);
	float dissolve = smoothstep(erosion - 0.16, erosion + 0.16, value);
	vec3 color;
	float envelope;
	if (fire) {
		color = mix(base_color.rgb, hot_color.rgb, smoothstep(0.12 + t * 0.6, 0.78, value));
		envelope = 1.0 - smoothstep(0.1, 1.0, t);
		EMISSION = color * intensity * value * envelope;
	} else {
		color = base_color.rgb * mix(0.35, 1.45, value);
		envelope = smoothstep(0.0, 0.09, t) * (1.0 - smoothstep(0.2, 1.0, t));
	}
	ALBEDO = color;
	ALPHA = ink.a * border * dissolve * envelope * opacity * gate;
}
