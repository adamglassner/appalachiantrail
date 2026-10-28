shader_type spatial;
uniform vec3 deep_color : source_color = vec3(0.05, 0.22, 0.35);
uniform vec3 shallow_color : source_color = vec3(0.18, 0.48, 0.55);
uniform float wave_scale = 1.0;
uniform float speed = 1.0;

float h2(vec2 p) {
	return sin(p.x * 1.7 + TIME * 1.3 * speed) * 0.5 + sin(p.y * 2.3 - TIME * 1.1 * speed) * 0.5
		+ sin((p.x + p.y) * 3.1 + TIME * 2.0 * speed) * 0.25;
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wp.xz * wave_scale;
	float e = 0.05;
	float dx = h2(p + vec2(e, 0.0)) - h2(p - vec2(e, 0.0));
	float dz = h2(p + vec2(0.0, e)) - h2(p - vec2(0.0, e));
	vec3 n = normalize(vec3(-dx * 0.6, 1.0, -dz * 0.6));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep_color, shallow_color, 0.35 + 0.3 * h2(p * 0.5));
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	EMISSION = vec3(0.6, 0.75, 0.85) * fres * 0.15;
}
