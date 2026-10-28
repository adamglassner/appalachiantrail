shader_type spatial;
// Vertex COLOR: r = normalized height (0..1), g = patch noise, b = beach factor, a = mountain belt (1 = forested range)
uniform float doy = 90.0;          // day of year
uniform float snow_level = 1.2;    // normalized height above which snow sits (>1 = none)
uniform float wetness = 0.0;

varying float v_h;
varying float v_patch;
varying float v_sand;
varying float v_belt;
varying float v_north;
varying vec3 v_wnormal;
varying vec2 v_xz;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_h = COLOR.r;
	v_patch = COLOR.g;
	v_sand = COLOR.b;
	v_belt = COLOR.a;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_xz = wp.xz;
	v_north = clamp((-wp.z + 55.0) / 110.0, 0.0, 1.0);
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float greenup = clamp((doy - (72.0 + v_north * 45.0)) / 40.0, 0.0, 1.0);
	float autumn = clamp((doy - (282.0 - v_north * 32.0)) / 22.0, 0.0, 1.0);
	float slope = 1.0 - clamp(v_wnormal.y, 0.0, 1.0);

	// --- forest canopy (mountains)
	vec3 bare = vec3(0.42, 0.39, 0.31);
	vec3 spring = vec3(0.47, 0.62, 0.28);
	vec3 summer = vec3(0.19, 0.38, 0.16);
	vec3 fall_a = vec3(0.80, 0.34, 0.10);
	vec3 fall_b = vec3(0.90, 0.62, 0.16);
	vec3 fall_c = vec3(0.62, 0.17, 0.10);
	vec3 canopy = mix(bare, spring, smoothstep(0.0, 0.5, greenup));
	canopy = mix(canopy, summer, smoothstep(0.5, 1.0, greenup));
	vec3 fall = mix(fall_a, fall_b, smoothstep(0.35, 0.65, v_patch));
	fall = mix(fall, fall_c, smoothstep(0.55, 0.8, fract(v_patch * 3.1)) * 0.5);
	fall = mix(fall, summer, 0.18);
	canopy = mix(canopy, fall, autumn);
	canopy *= 0.82 + v_patch * 0.34;
	vec3 conifer = vec3(0.10, 0.22, 0.15) * (0.9 + v_patch * 0.2);
	float conif = smoothstep(0.55, 0.75, v_h + v_north * 0.25 + (v_patch - 0.5) * 0.3);
	vec3 forest = mix(canopy, conifer, conif);

	// --- farmland patchwork (valleys)
	vec2 cell = floor(v_xz * 2.2 + vec2(v_patch * 0.8));
	float f = hash12(cell);
	vec3 field1 = mix(vec3(0.42, 0.52, 0.27), vec3(0.55, 0.5, 0.3), autumn);
	vec3 field2 = mix(vec3(0.52, 0.56, 0.3), vec3(0.62, 0.55, 0.34), autumn);
	vec3 field3 = vec3(0.34, 0.46, 0.23);
	vec3 fields = f < 0.33 ? field1 : (f < 0.66 ? field2 : field3);
	fields = mix(vec3(0.48, 0.42, 0.33), fields, smoothstep(0.0, 0.6, greenup));
	float woods = smoothstep(0.25, 0.75, v_belt + (v_patch - 0.5) * 0.5);
	vec3 col = mix(fields, forest, woods);

	// --- alpine rock above treeline (only the highest summits)
	vec3 rock = vec3(0.50, 0.48, 0.45) * (0.85 + v_patch * 0.3);
	col = mix(col, rock, smoothstep(0.86, 0.95, v_h + v_north * 0.12 - (1.0 - v_north) * 0.15));
	col = mix(col, rock * 0.8, smoothstep(0.45, 0.75, slope) * 0.6);
	// beaches
	col = mix(col, vec3(0.80, 0.74, 0.58), v_sand);
	// snow
	float snow = smoothstep(snow_level, snow_level + 0.05, v_h + v_north * 0.12 + (v_patch - 0.5) * 0.06);
	snow *= 1.0 - smoothstep(0.6, 0.8, slope);
	col = mix(col, vec3(0.93, 0.95, 0.98), snow);
	// valleys a touch darker for depth
	col *= 0.8 + 0.3 * smoothstep(0.0, 0.6, v_h);
	ALBEDO = col * (1.0 - wetness * 0.25);
	ROUGHNESS = mix(0.95, 0.6, wetness) - snow * 0.25;
	SPECULAR = 0.2 + wetness * 0.3;
}
