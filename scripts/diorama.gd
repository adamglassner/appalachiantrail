class_name Diorama
extends SubViewportContainer
## A small floating-island 3D diorama rendered in its own world, used for event scenes.

var vp: SubViewport
var root: Node3D
var stage: Node3D
var atmos: Atmosphere
var cam: Camera3D
var _t := 0.0
var _yaw := 0.6
var orbit_speed := 0.12
var cam_dist := 14.0
var cam_height := 6.0
var focus := Vector3(0, 0.8, 0)
var rng := RandomNumberGenerator.new()
var _anim: Array = []   # [node, kind, base]
var season := Vector2(1, 0)


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.size = Vector2i(640, 400)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	root = Node3D.new()
	vp.add_child(root)
	atmos = Atmosphere.new()
	root.add_child(atmos)
	atmos.precip_offset = Vector3(0, 9, 0)
	atmos.setup(9.0, 0.55, 0.7)
	atmos.sun.directional_shadow_max_distance = 30.0
	cam = Camera3D.new()
	cam.fov = 42.0
	root.add_child(cam)
	cam.current = true
	stage = Node3D.new()
	root.add_child(stage)
	atmos.follow = stage


## opts: hour, weather, doy, north (0..1), party (int), kind-specific extras
func show_scene(kind: String, opts := {}) -> void:
	UiTheme.clear(stage)
	_anim.clear()
	rng.seed = hash(kind) + int(opts.get("seed", 0))
	var hour: float = opts.get("hour", 13.0)
	var weather: String = opts.get("weather", "clear")
	var doy: int = opts.get("doy", 150)
	var north: float = opts.get("north", 0.3)
	var party: int = clampi(int(opts.get("party", 2)), 1, 5)
	season = Props.seasons(doy, north)
	if kind in ["camp", "bear_camp"]:
		hour = 21.0
	if kind == "storm" and weather != "snow":
		weather = "storm"
	if kind == "river" and weather == "storm":
		weather = "rain"
	atmos.set_hour(hour)
	atmos.set_weather(weather)
	orbit_speed = 0.12
	cam_dist = 14.0
	cam_height = 6.0
	focus = Vector3(0, 0.5, 0)
	var ground := _ground_color(kind, doy)
	_island(ground, kind)
	match kind:
		"river":
			_river_scene(party)
		"bear":
			_bear_scene(party)
		"town":
			_town_scene(party)
		"storm":
			_storm_scene(party)
		"injury":
			_injury_scene(party)
		"magic":
			_magic_scene(party)
		"vista":
			_vista_scene(party)
		"camp":
			_camp_scene(party)
		"summit":
			_summit_scene(party, opts.get("finish", false))
		"ponies":
			_ponies_scene(party)
		"rocks":
			_rocks_scene(party)
		"snake":
			_snake_scene(party)
		_:
			_forest_scene(party)
	if weather == "snow" or (doy < 85 and north > 0.2) or doy > 300:
		_snow_patches()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_yaw += delta * orbit_speed
	cam.position = focus + Vector3(sin(_yaw) * cam_dist, cam_height, cos(_yaw) * cam_dist)
	cam.look_at(focus, Vector3.UP)
	for a in _anim:
		var n: Node3D = a[0]
		if not is_instance_valid(n):
			continue
		match a[1]:
			"bob":
				n.position.y = a[2].y + absf(sin(_t * 4.0 + a[2].x)) * 0.06
			"sway":
				n.rotation.y = a[2].y + sin(_t * 0.8) * 0.4
			"flame":
				n.scale = Vector3(1, 1.0 + sin(_t * 18.0) * 0.18, 1)
			"water":
				pass
			"pony":
				n.rotation.x = sin(_t * 1.5 + a[2].x) * 0.05
			"snake":
				n.rotation.y = a[2].y + sin(_t * 2.0) * 0.15


# ------------------------------------------------------------------ building blocks

func _ground_color(kind: String, doy: int) -> Color:
	if kind in ["summit", "rocks", "storm"]:
		return Color(0.36, 0.4, 0.3)
	if kind == "ponies":
		return Color(0.48, 0.58, 0.3)
	var spring := Color(0.4, 0.55, 0.25)
	var summer := Color(0.3, 0.47, 0.2)
	var fall := Color(0.55, 0.42, 0.22)
	var c := Color(0.45, 0.4, 0.3).lerp(spring, clampf(season.x * 2.0, 0, 1)).lerp(summer, clampf(season.x * 2.0 - 1.0, 0, 1))
	return c.lerp(fall, season.y * 0.7) * 0.85


func _island(top: Color, kind: String) -> void:
	var r := 6.0
	stage.add_child(Props.mi(Props.cyl(r, r * 0.92, 0.5, 40), Props.mat(top, 0.95), Vector3(0, -0.25, 0)))
	stage.add_child(Props.mi(Props.cyl(r * 0.92, r * 0.55, 1.6, 40), Props.mat(Color(0.36, 0.27, 0.2), 0.95), Vector3(0, -1.3, 0)))
	stage.add_child(Props.mi(Props.cyl(r * 0.55, 0.3, 1.6, 20), Props.mat(Color(0.3, 0.23, 0.18), 0.95), Vector3(0, -2.9, 0)))
	# grass tufts / pebbles
	for i in 40:
		var a := rng.randf() * TAU
		var d := rng.randf_range(1.0, r - 0.3)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if kind in ["summit", "rocks", "storm"]:
			var rk := Props.rock(rng.randf_range(0.08, 0.25), rng)
			rk.position = p
			stage.add_child(rk)
		else:
			stage.add_child(Props.mi(Props.cyl(0.0, 0.08, 0.25, 4), Props.mat(top.lightened(0.12)), p + Vector3(0, 0.12, 0)))


func _trail_strip(length := 11.0, angle := 0.0, w := 0.9) -> void:
	var s := Props.mi(Props.box(Vector3(w, 0.04, length)), Props.mat(Color(0.5, 0.4, 0.28), 1.0), Vector3(0, 0.01, 0), Vector3(0, angle, 0))
	stage.add_child(s)


func _trees(count: int, min_r := 2.0, max_r := 5.7, conifer_frac := 0.4, avoid_x := 0.0) -> void:
	# keep the middle of the island clear so the action stays visible
	min_r = maxf(min_r, 3.3)
	for i in int(count * 0.65):
		var a := rng.randf() * TAU
		var d := rng.randf_range(min_r, max_r)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if avoid_x > 0.0 and absf(p.x) < avoid_x:
			continue
		var h := rng.randf_range(1.3, 2.5)
		var t: Node3D
		if rng.randf() < conifer_frac:
			t = Props.conifer(h * 1.2, rng)
		else:
			t = Props.deciduous(h, Props.foliage_color(season, rng))
		t.position = p
		t.rotation.y = rng.randf() * TAU
		stage.add_child(t)


func _hikers(n: int, origin: Vector3, facing: float, spread := 0.7, bob := false) -> Array:
	var out: Array = []
	for i in n:
		var h := Props.hiker(WorldMap.SHIRTS[i % WorldMap.SHIRTS.size()], WorldMap.PACKS[i % WorldMap.PACKS.size()])
		var off := Vector3((i - (n - 1) / 2.0) * spread, 0, (i % 2) * 0.5)
		h.position = origin + off.rotated(Vector3.UP, facing)
		h.rotation.y = facing
		stage.add_child(h)
		if bob:
			_anim.append([h, "bob", Vector3(i, h.position.y, 0)])
		out.append(h)
	return out


func _snow_patches() -> void:
	for i in 14:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.5, 5.6)
		stage.add_child(Props.mi(Props.cyl(rng.randf_range(0.3, 0.8), rng.randf_range(0.4, 0.9), 0.04, 12), Props.mat(Color(0.95, 0.96, 1.0), 0.6), Vector3(cos(a) * d, 0.02, sin(a) * d)))


# ------------------------------------------------------------------ scenes

func _river_scene(party: int) -> void:
	var water := Props.mi(Props.box(Vector3(12.2, 0.12, 2.6)), Props.water_material(), Vector3(0, -0.02, 0))
	stage.add_child(water)
	for i in 6:
		var rk := Props.rock(rng.randf_range(0.18, 0.32), rng)
		rk.position = Vector3(rng.randf_range(-1.0, 1.0), 0.03, -1.0 + i * 0.4)
		stage.add_child(rk)
	for i in 4:
		var rk2 := Props.rock(rng.randf_range(0.3, 0.6), rng)
		rk2.position = Vector3(rng.randf_range(-5, 5), 0.05, 1.4 * (1 if i % 2 == 0 else -1))
		stage.add_child(rk2)
	_trail_strip(3.5, 0.0)
	var tr := Props.mi(Props.box(Vector3(0.9, 0.04, 3.0)), Props.mat(Color(0.5, 0.4, 0.28), 1.0), Vector3(0, 0.01, -3.6))
	stage.add_child(tr)
	_hikers(party, Vector3(0, 0, 2.4), PI, 0.6)
	_trees(22, 2.2, 5.7, 0.5, 1.2)
	focus = Vector3(0, 0.5, 0)


func _bear_scene(party: int) -> void:
	_trail_strip(11.0, 0.0)
	var b := Props.bear(0.8)
	b.position = Vector3(0, 0, -2.0)
	b.rotation.y = PI
	stage.add_child(b)
	_anim.append([b, "sway", Vector3(0, PI, 0)])
	_hikers(party, Vector3(0, 0, 1.8), 0.0, 0.6)
	_trees(30, 1.4, 5.7, 0.35, 1.0)
	for i in 5:
		var bs := Props.bush(rng.randf_range(0.3, 0.55), Color(0.2, 0.42, 0.22))
		bs.position = Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
		if absf(bs.position.x) > 1.0:
			stage.add_child(bs)
	focus = Vector3(0, 0.6, 0)


func _town_scene(party: int) -> void:
	stage.add_child(Props.mi(Props.box(Vector3(12, 0.04, 1.6)), Props.mat(Color(0.25, 0.25, 0.27), 0.9), Vector3(0, 0.01, 0.6)))
	for i in 12:
		stage.add_child(Props.mi(Props.box(Vector3(0.4, 0.045, 0.06)), Props.mat(Color(0.95, 0.85, 0.4), 0.6), Vector3(-5.0 + i * 0.9, 0.02, 0.6)))
	var walls := [Color(0.92, 0.9, 0.85), Color(0.72, 0.3, 0.25), Color(0.85, 0.78, 0.6), Color(0.55, 0.68, 0.78), Color(0.5, 0.6, 0.45)]
	for i in 4:
		var h := Props.house(walls[i % walls.size()], Color(0.28, 0.24, 0.24), Vector3(1.8, rng.randf_range(1.2, 1.8), 1.5))
		h.position = Vector3(-3.6 + i * 2.4, 0, -1.4)
		stage.add_child(h)
	var sg := Props.sign_post()
	sg.position = Vector3(3.5, 0, 2.0)
	stage.add_child(sg)
	# a pickup truck
	var car := Node3D.new()
	car.add_child(Props.mi(Props.box(Vector3(1.6, 0.4, 0.75)), Props.mat(Color(0.2, 0.35, 0.6), 0.35, 0, 0.3), Vector3(0, 0.38, 0)))
	car.add_child(Props.mi(Props.box(Vector3(0.7, 0.35, 0.7)), Props.mat(Color(0.2, 0.35, 0.6), 0.35, 0, 0.3), Vector3(-0.3, 0.75, 0)))
	for wx in [-0.5, 0.5]:
		for wz in [-0.38, 0.38]:
			car.add_child(Props.mi(Props.cyl(0.17, 0.17, 0.12, 12), Props.mat(Color(0.08, 0.08, 0.08)), Vector3(wx, 0.17, wz), Vector3(PI / 2, 0, 0)))
	car.position = Vector3(-1.5, 0, 0.7)
	stage.add_child(car)
	_hikers(party, Vector3(1.6, 0, 2.2), 0.4, 0.6)
	_trees(10, 4.2, 5.7, 0.4)
	focus = Vector3(0, 0.8, 0)


func _storm_scene(party: int) -> void:
	for i in 10:
		var rk := Props.rock(rng.randf_range(0.4, 1.0), rng)
		rk.position = Vector3(rng.randf_range(-4.5, 4.5), 0.1, rng.randf_range(-4.5, 4.5))
		if rk.position.length() > 1.5:
			stage.add_child(rk)
	# cairns
	for c in 3:
		var base := Vector3(-3.0 + c * 3.0, 0, -2.5 + c * 1.5)
		for j in 4:
			stage.add_child(Props.mi(Props.sphere(0.25 - j * 0.04, 7, 4), Props.mat(Color(0.5, 0.5, 0.48)), base + Vector3(0, 0.15 + j * 0.3, 0), Vector3.ZERO, Vector3(1.2, 0.7, 1.0)))
	_hikers(party, Vector3(0, 0, 0.5), 0.6, 0.55)
	for i in 4:
		var t := Props.conifer(rng.randf_range(0.8, 1.3), rng)
		t.position = Vector3(rng.randf_range(-5, 5), 0, 4.5)
		stage.add_child(t)
	cam_height = 3.0


func _injury_scene(party: int) -> void:
	_trail_strip(11.0, 0.3)
	var hs := _hikers(max(party, 2), Vector3(0, 0, 0), 0.3, 0.9)
	var hurt: Node3D = hs[0]
	hurt.rotation = Vector3(-0.0, 0.3, 1.25)
	hurt.position += Vector3(0, 0.25, 0)
	var kit := Node3D.new()
	kit.add_child(Props.mi(Props.box(Vector3(0.45, 0.25, 0.32)), Props.mat(Color(0.85, 0.15, 0.15), 0.5), Vector3(0, 0.12, 0)))
	kit.add_child(Props.mi(Props.box(Vector3(0.22, 0.02, 0.06)), Props.mat(Color.WHITE), Vector3(0, 0.26, 0)))
	kit.add_child(Props.mi(Props.box(Vector3(0.06, 0.02, 0.22)), Props.mat(Color.WHITE), Vector3(0, 0.26, 0)))
	kit.position = Vector3(0.8, 0, 0.8)
	stage.add_child(kit)
	_trees(26, 1.6, 5.7, 0.4, 1.1)
	var rt := Props.mi(Props.cyl(0.08, 0.1, 1.6, 6), Props.mat(Color(0.4, 0.3, 0.2)), Vector3(-0.2, 0.05, -1.2), Vector3(PI / 2, 0.4, 0))
	stage.add_child(rt)


func _magic_scene(party: int) -> void:
	_trail_strip(11.0, 0.0)
	# table, cooler and goodies
	var tbl := Node3D.new()
	tbl.add_child(Props.mi(Props.box(Vector3(1.8, 0.06, 0.8)), Props.mat(Color(0.92, 0.92, 0.9)), Vector3(0, 0.75, 0)))
	for lx in [-0.8, 0.8]:
		for lz in [-0.35, 0.35]:
			tbl.add_child(Props.mi(Props.cyl(0.02, 0.02, 0.75, 4), Props.mat(Color(0.5, 0.5, 0.5), 0.4, 0, 0.5), Vector3(lx, 0.375, lz)))
	var cols := [Color(0.85, 0.15, 0.15), Color(0.2, 0.5, 0.9), Color(0.95, 0.75, 0.15), Color(0.3, 0.75, 0.3)]
	for i in 8:
		tbl.add_child(Props.mi(Props.cyl(0.05, 0.05, 0.16, 8), Props.mat(cols[i % 4], 0.3, 0.0, 0.6), Vector3(-0.7 + i * 0.18, 0.86, rng.randf_range(-0.2, 0.2))))
	tbl.add_child(Props.mi(Props.box(Vector3(0.5, 0.1, 0.35)), Props.mat(Color(0.95, 0.75, 0.4)), Vector3(0.4, 0.83, 0.1)))
	tbl.position = Vector3(1.6, 0, -0.5)
	tbl.rotation.y = -0.3
	stage.add_child(tbl)
	var cooler := Node3D.new()
	cooler.add_child(Props.mi(Props.box(Vector3(0.8, 0.45, 0.5)), Props.mat(Color(0.2, 0.45, 0.85), 0.4), Vector3(0, 0.225, 0)))
	cooler.add_child(Props.mi(Props.box(Vector3(0.84, 0.1, 0.54)), Props.mat(Color(0.95, 0.95, 0.95), 0.4), Vector3(0, 0.5, 0)))
	cooler.position = Vector3(1.5, 0, 0.7)
	stage.add_child(cooler)
	var sg := Props.sign_post(Color(0.75, 0.55, 0.3))
	sg.position = Vector3(-1.3, 0, -1.0)
	stage.add_child(sg)
	var lbl := Label3D.new()
	lbl.text = "TRAIL\nMAGIC!"
	lbl.font_size = 64
	lbl.pixel_size = 0.004
	lbl.position = Vector3(-1.3, 1.2, -0.94)
	lbl.modulate = Color(0.15, 0.08, 0.02)
	lbl.outline_size = 0
	lbl.font = UiTheme.bold_font()
	stage.add_child(lbl)
	_hikers(party, Vector3(0, 0, 1.4), 0.5, 0.6, true)
	_trees(22, 3.0, 5.7, 0.35)


func _vista_scene(party: int) -> void:
	# a rocky ledge jutting toward distant ridges
	var ledge := Props.mi(Props.box(Vector3(3.0, 0.5, 2.4)), Props.mat(Color(0.5, 0.48, 0.44), 0.95), Vector3(0, 0.15, -3.4), Vector3(0.05, 0.2, 0))
	stage.add_child(ledge)
	_hikers(party, Vector3(0, 0.4, -3.6), PI, 0.55)
	for i in 9:
		var m := Props.mountain(rng.randf_range(3.0, 7.0), rng.randf_range(3.0, 6.0), rng)
		var a := -PI / 2 + (i - 4) * 0.28 + rng.randf_range(-0.1, 0.1)
		m.position = Vector3(cos(a) * rng.randf_range(24, 34), -6.0, sin(a) * rng.randf_range(24, 34))
		root_add(m)
	_trees(20, 1.0, 5.7, 0.4)
	focus = Vector3(0, 0.6, -2.5)
	orbit_speed = 0.05
	_yaw = 0.2


func root_add(n: Node3D) -> void:
	stage.add_child(n)


func _camp_scene(party: int) -> void:
	var sh := Props.shelter()
	sh.position = Vector3(0, 0, -2.2)
	stage.add_child(sh)
	var fire := Props.campfire()
	fire.position = Vector3(0, 0, 0.6)
	stage.add_child(fire)
	_anim.append([fire.get_node("Flame"), "flame", Vector3.ZERO])
	var tn := Props.tent(Color(0.95, 0.55, 0.15))
	tn.position = Vector3(2.8, 0, 0.8)
	tn.rotation.y = 0.6
	stage.add_child(tn)
	var hs := _hikers(party, Vector3(0, 0, 1.6), PI, 0.7)
	for i in hs.size():
		var h: Node3D = hs[i]
		var a := PI * 0.3 + i * 0.7
		h.position = fire.position + Vector3(cos(a) * 1.2, 0, sin(a) * 1.2)
		var d := fire.position - h.position
		h.rotation.y = atan2(-d.x, -d.z)
	# a log bench
	stage.add_child(Props.mi(Props.cyl(0.15, 0.15, 1.6, 8), Props.mat(Color(0.4, 0.28, 0.18)), Vector3(-1.2, 0.15, 1.2), Vector3(0, 0.5, PI / 2)))
	_trees(24, 3.2, 5.7, 0.5)


func _summit_scene(party: int, finish: bool) -> void:
	# rocky summit cone
	stage.add_child(Props.mi(Props.cyl(0.8, 3.5, 1.4, 12), Props.mat(Color(0.48, 0.47, 0.44), 0.95), Vector3(0, 0.45, -0.5)))
	for i in 12:
		var rk := Props.rock(rng.randf_range(0.25, 0.6), rng)
		rk.position = Vector3(rng.randf_range(-4.5, 4.5), 0.1, rng.randf_range(-4.5, 4.5))
		if rk.position.length() > 3.3:
			stage.add_child(rk)
	if finish:
		# the famous A-frame summit sign
		var sgn := Node3D.new()
		var brown := Props.mat(Color(0.35, 0.22, 0.12))
		sgn.add_child(Props.mi(Props.box(Vector3(0.12, 1.8, 0.12)), brown, Vector3(-0.9, 0.9, 0), Vector3(0, 0, 0.12)))
		sgn.add_child(Props.mi(Props.box(Vector3(0.12, 1.8, 0.12)), brown, Vector3(0.9, 0.9, 0), Vector3(0, 0, -0.12)))
		sgn.add_child(Props.mi(Props.box(Vector3(2.2, 1.0, 0.1)), brown, Vector3(0, 1.3, 0)))
		var l := Label3D.new()
		l.text = "KATAHDIN\nBaxter Peak  5267 ft\nNorthern Terminus of the\nAppalachian Trail"
		l.font_size = 40
		l.pixel_size = 0.0045
		l.modulate = Color(0.98, 0.95, 0.85)
		l.outline_size = 0
		l.position = Vector3(0, 1.3, 0.06)
		l.font = UiTheme.bold_font()
		sgn.add_child(l)
		sgn.position = Vector3(0, 1.15, -0.6)
		stage.add_child(sgn)
		_hikers(party, Vector3(0, 1.15, 0.5), 0.0, 0.6, true)
	else:
		var tw := Props.mi(Props.cyl(0.6, 0.7, 1.2, 10), Props.mat(Color(0.6, 0.6, 0.58)), Vector3(0, 1.75, -0.8))
		stage.add_child(tw)
		_hikers(party, Vector3(0, 1.15, 0.6), 0.0, 0.6)
	for i in 6:
		var m := Props.mountain(rng.randf_range(2.0, 5.0), rng.randf_range(3.0, 6.0), rng, season.x < 0.3)
		var a := rng.randf() * TAU
		m.position = Vector3(cos(a) * 20, -4.0, sin(a) * 20)
		stage.add_child(m)
	focus = Vector3(0, 1.4, 0)
	cam_height = 4.5
	cam_dist = 10.5


func _ponies_scene(party: int) -> void:
	var cols := [Color(0.45, 0.3, 0.18), Color(0.85, 0.82, 0.75), Color(0.25, 0.18, 0.12)]
	for i in 3:
		var p := Props.pony(cols[i])
		p.position = Vector3(-2.0 + i * 1.8, 0, -1.0 + (i % 2) * 1.4)
		p.rotation.y = rng.randf() * TAU
		stage.add_child(p)
		_anim.append([p, "pony", Vector3(i, 0, 0)])
	for i in 10:
		var rk := Props.rock(rng.randf_range(0.3, 0.7), rng)
		rk.position = Vector3(rng.randf_range(-5, 5), 0.05, rng.randf_range(-5, 5))
		stage.add_child(rk)
	_hikers(party, Vector3(0.5, 0, 2.4), PI + 0.3, 0.6)
	for i in 6:
		var b := Props.bush(rng.randf_range(0.3, 0.5), Color(0.25, 0.4, 0.2))
		var a := rng.randf() * TAU
		b.position = Vector3(cos(a) * 4.5, 0, sin(a) * 4.5)
		stage.add_child(b)


func _rocks_scene(party: int) -> void:
	for i in 34:
		var rk := Props.rock(rng.randf_range(0.4, 1.3), rng)
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 5.3)
		rk.position = Vector3(cos(a) * d, rng.randf_range(0.0, 0.5), sin(a) * d)
		stage.add_child(rk)
	var hs := _hikers(party, Vector3(0, 0.9, 0.5), 0.3, 0.8)
	for h in hs:
		h.rotation.x = -0.25
	_trees(6, 4.8, 5.7, 0.8)


func _snake_scene(party: int) -> void:
	_trail_strip(11.0, 0.0)
	var s := Props.snake()
	s.position = Vector3(0, 0, -0.6)
	s.rotation.y = PI / 2
	s.scale = Vector3.ONE * 1.3
	stage.add_child(s)
	_anim.append([s, "snake", Vector3(0, PI / 2, 0)])
	for i in 6:
		var rk := Props.rock(rng.randf_range(0.2, 0.5), rng)
		rk.position = Vector3(rng.randf_range(-1.5, 1.5), 0.05, rng.randf_range(-1.5, 0.5))
		if absf(rk.position.x) > 0.6:
			stage.add_child(rk)
	_hikers(party, Vector3(0, 0, 2.2), 0.0, 0.6)
	_trees(24, 1.6, 5.7, 0.3, 1.0)
	focus = Vector3(0, 0.3, 0)
	cam_dist = 9.0
	cam_height = 3.5


func _forest_scene(party: int) -> void:
	_trail_strip(11.0, 0.2)
	var bt := Props.blaze_tree()
	bt.position = Vector3(0.9, 0, -1.0)
	bt.rotation.y = -0.4
	stage.add_child(bt)
	_hikers(party, Vector3(0, 0, 1.3), 0.2, 0.6)
	_trees(40, 1.2, 5.7, 0.5, 0.9)
