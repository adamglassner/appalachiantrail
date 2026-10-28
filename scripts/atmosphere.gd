class_name Atmosphere
extends Node3D

signal lightning(strength: float)
## Sky, sun & moon, day/night cycle, fog, precipitation and lightning.
## Used by the overworld map, the event dioramas and the forage minigame.

var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ShaderMaterial
var rain: GPUParticles3D
var snow: GPUParticles3D
var follow: Node3D
var precip_offset := Vector3(0, 12, 0)

var hour := 9.0
var weather := "clear"
var fog_scale := 1.0
var flash := 0.0
var _flash_timer := 2.0
var shadows := true
var _cloud := 0.15
var _storm := 0.0
var _daylight := 1.0


func setup(area := 30.0, drop_scale := 1.0, fog_mult := 1.0) -> void:
	fog_scale = fog_mult
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.5
	env.fog_enabled = true
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = shadows
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_blur = 1.5
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.shadow_enabled = false
	moon.rotation_degrees = Vector3(-50, 140, 0)
	add_child(moon)

	rain = _make_precip(area, drop_scale, false)
	snow = _make_precip(area, drop_scale, true)
	add_child(rain)
	add_child(snow)
	apply()


func _make_precip(area: float, s: float, is_snow: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(area, 0.5, area)
	pm.direction = Vector3(0.12, -1, 0.05)
	pm.spread = 4.0 if not is_snow else 25.0
	if is_snow:
		pm.initial_velocity_min = 1.2 * s
		pm.initial_velocity_max = 2.0 * s
		pm.gravity = Vector3(0, -0.6 * s, 0)
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.6
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.15
	else:
		pm.initial_velocity_min = 18.0 * s
		pm.initial_velocity_max = 24.0 * s
		pm.gravity = Vector3(0, -12.0 * s, 0)
	p.process_material = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if is_snow:
		m.albedo_color = Color(1, 1, 1, 0.9)
		var sm := Props.sphere(0.05 * s, 6, 3)
		sm.material = m
		p.draw_pass_1 = sm
		p.amount = 2500
		p.lifetime = (precip_offset.y + 4.0) / (1.6 * s)
	else:
		m.albedo_color = Color(0.75, 0.82, 0.95, 0.35)
		var bm := Props.box(Vector3(0.012, 0.55, 0.012) * s)
		bm.material = m
		p.draw_pass_1 = bm
		p.amount = 4000
		p.lifetime = 1.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-area * 1.5, -40, -area * 1.5), Vector3(area * 3, 60, area * 3))
	p.emitting = false
	p.position = precip_offset
	return p


func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	apply()


func set_weather(w: String) -> void:
	weather = w
	apply()


func apply() -> void:
	if env == null:
		return
	match weather:
		"clear":
			_cloud = 0.12
			_storm = 0.0
		"hot":
			_cloud = 0.08
			_storm = 0.0
		"cloudy":
			_cloud = 0.72
			_storm = 0.15
		"fog":
			_cloud = 0.6
			_storm = 0.2
		"rain":
			_cloud = 0.88
			_storm = 0.45
		"storm":
			_cloud = 1.0
			_storm = 0.8
		"snow":
			_cloud = 0.9
			_storm = 0.3
	# sunrise ~6:30, sunset ~20:00 (hiking season)
	var a := (hour - 6.5) / 13.5 * PI
	var to_sun := Vector3(cos(a), sin(a) * 0.9, 0.35 + sin(a) * 0.25).normalized()
	var elev := sin(a)
	_daylight = smoothstep(-0.12, 0.28, elev)
	var sunset := clampf(1.0 - absf(elev - 0.06) / 0.3, 0.0, 1.0)
	sun.transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), Vector3.ZERO)
	var sun_col := Color(1.0, 0.96, 0.9).lerp(Color(1.0, 0.6, 0.35), sunset)
	sun.light_color = sun_col
	sun.light_energy = _daylight * 1.35 * (1.0 - _cloud * 0.62) + flash * 3.0
	sun.visible = _daylight > 0.01 or flash > 0.0
	moon.light_energy = (1.0 - _daylight) * 0.28 * (1.0 - _cloud * 0.5)
	moon.visible = _daylight < 0.99

	var night_amb := Color(0.12, 0.15, 0.26)
	var day_amb := Color(0.62, 0.67, 0.75).lerp(Color(0.55, 0.57, 0.62), _storm)
	env.ambient_light_color = night_amb.lerp(day_amb, _daylight).lerp(Color(1.0, 0.75, 0.6), sunset * 0.25)
	env.ambient_light_energy = 0.55 + _daylight * 0.35 + flash * 2.0

	var top := Color(0.25, 0.5, 0.88).lerp(Color(0.42, 0.47, 0.55), _cloud * 0.8)
	var hor := Color(0.72, 0.84, 0.94).lerp(Color(0.62, 0.65, 0.7), _cloud * 0.8)
	if weather == "hot":
		hor = Color(0.85, 0.85, 0.8)
	sky_mat.set_shader_parameter("day_top", top)
	sky_mat.set_shader_parameter("day_horizon", hor)
	sky_mat.set_shader_parameter("daylight", _daylight)
	sky_mat.set_shader_parameter("sunset", sunset * (1.0 - _cloud * 0.6))
	sky_mat.set_shader_parameter("cloudiness", _cloud)
	sky_mat.set_shader_parameter("storm_dark", _storm)
	sky_mat.set_shader_parameter("flash", flash)
	sky_mat.set_shader_parameter("sun_dir", to_sun)

	var fog_d := 0.004
	match weather:
		"fog":
			fog_d = 0.045
		"rain":
			fog_d = 0.011
		"storm":
			fog_d = 0.014
		"snow":
			fog_d = 0.018
		"cloudy":
			fog_d = 0.006
		"hot":
			fog_d = 0.008
	env.fog_density = fog_d * fog_scale
	var fog_col := hor.lerp(Color(0.05, 0.07, 0.12), 1.0 - _daylight).lerp(Color(0.95, 0.65, 0.45), sunset * 0.3)
	fog_col = fog_col.lerp(Color(0.3, 0.33, 0.37), _storm * 0.6 * _daylight)
	env.fog_light_color = fog_col
	sky_mat.set_shader_parameter("ground_color", hor.lerp(Color(0.2, 0.22, 0.2), 0.5))
	env.fog_light_energy = 0.6 + _daylight * 0.4

	rain.emitting = weather == "rain" or weather == "storm"
	rain.amount_ratio = 1.0 if weather == "storm" else 0.6
	snow.emitting = weather == "snow"


func daylight() -> float:
	return _daylight


func _process(delta: float) -> void:
	if follow != null and is_instance_valid(follow):
		var p := follow.global_position + precip_offset
		rain.global_position = p
		snow.global_position = p
	if weather == "storm":
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			flash = randf_range(0.6, 1.0)
			_flash_timer = randf_range(1.5, 6.0)
			lightning.emit(flash)
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 4.0)
		# a double-flicker looks more like lightning
		if flash < 0.35 and flash > 0.3 and randf() < 0.5:
			flash = 0.8
		apply()
