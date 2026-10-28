shader_type spatial;
render_mode cull_disabled;
uniform float progress = 0.0;   // 0..1 fraction of trail completed
uniform vec3 done_color : source_color = vec3(1.0, 0.70, 0.22);
uniform vec3 todo_color : source_color = vec3(0.95, 0.93, 0.85);

void fragment() {
	float done = step(UV.x, progress);
	float edge = 1.0 - pow(abs(UV.y - 0.5) * 2.0, 4.0);
	vec3 c = mix(todo_color, done_color, done);
	ALBEDO = c * (0.65 + 0.35 * edge);
	EMISSION = c * (done * 0.9 + (1.0 - done) * 0.12);
	ROUGHNESS = 0.7;
}
