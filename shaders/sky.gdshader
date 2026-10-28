shader_type sky;
uniform vec3 day_top : source_color = vec3(0.25, 0.5, 0.85);
uniform vec3 day_horizon : source_color = vec3(0.7, 0.82, 0.92);
uniform vec3 night_top : source_color = vec3(0.01, 0.015, 0.05);
uniform vec3 night_horizon : source_color = vec3(0.04, 0.06, 0.12);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.5, 0.25);
uniform vec3 ground_color : source_color = vec3(0.12, 0.13, 0.12);
uniform float daylight = 1.0;      // 0 night .. 1 day
uniform float sunset = 0.0;        // 0..1 golden hour amount
uniform float cloudiness = 0.2;    // 0..1
uniform float storm_dark = 0.0;    // 0..1
uniform float flash = 0.0;         // lightning
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);
	float hz = pow(1.0 - clamp(up, 0.0, 1.0), 2.5);
	vec3 top = mix(night_top, day_top, daylight);
	vec3 hor = mix(night_horizon, day_horizon, daylight);
	vec3 col = mix(top, hor, hz);
	// sunset glow near the sun direction and horizon
	float sd = clamp(dot(d, normalize(sun_dir)), 0.0, 1.0);
	col = mix(col, sunset_color, sunset * hz * (0.35 + 0.65 * pow(sd, 3.0)));
	// sun disk
	float disk = smoothstep(0.9993, 0.9997, sd);
	col += vec3(1.0, 0.92, 0.75) * disk * 6.0 * daylight * (1.0 - cloudiness * 0.9);
	col += vec3(1.0, 0.8, 0.5) * pow(sd, 60.0) * 0.6 * daylight * (1.0 - cloudiness * 0.7);
	// stars
	if (up > 0.0) {
		vec3 sp = floor(d * 260.0);
		float st = step(0.9975, hash(sp));
		float tw = 0.6 + 0.4 * sin(TIME * 3.0 + hash(sp + 3.0) * 20.0);
		col += vec3(st * tw) * (1.0 - daylight) * (1.0 - cloudiness) * smoothstep(0.0, 0.2, up);
	}
	// moon (opposite the sun)
	float md = clamp(dot(d, normalize(-sun_dir + vec3(0.2, 0.3, 0.0))), 0.0, 1.0);
	col += vec3(0.85, 0.88, 1.0) * smoothstep(0.9990, 0.9994, md) * (1.0 - daylight) * (1.0 - cloudiness);
	// clouds
	if (up > -0.05) {
		vec2 uv = d.xz / (d.y + 0.25);
		float c = fbm(vec3(uv * 1.4 + vec2(TIME * 0.01, TIME * 0.004), TIME * 0.005));
		float cov = smoothstep(0.62 - cloudiness * 0.45, 0.85 - cloudiness * 0.3, c);
		vec3 cday = mix(vec3(1.0), vec3(0.45, 0.47, 0.5), storm_dark);
		vec3 ccol = mix(vec3(0.06, 0.07, 0.1), cday, daylight);
		ccol = mix(ccol, sunset_color * 0.9 + 0.1, sunset * 0.6);
		col = mix(col, ccol, cov * smoothstep(-0.05, 0.15, up) * 0.95);
	}
	col *= 1.0 - storm_dark * 0.55;
	if (up < 0.0) {
		col = mix(col, ground_color * (0.2 + daylight * 0.8), smoothstep(0.0, -0.15, up));
	}
	col += vec3(0.8, 0.85, 1.0) * flash;
	COLOR = col;
}
