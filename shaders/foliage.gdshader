shader_type spatial;
// UV.x = 1 on foliage, 0 on trunk. COLOR = per-instance foliage color (MultiMesh colors).
uniform vec3 trunk_color : source_color = vec3(0.30, 0.22, 0.16);

void fragment() {
	ALBEDO = mix(trunk_color, COLOR.rgb, UV.x);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
