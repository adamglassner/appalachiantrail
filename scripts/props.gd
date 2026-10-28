class_name Props
extends RefCounted
## Procedural low-poly props shared by the overworld map, the event dioramas and the forage minigame.

static var _mats := {}


static func mat(c: Color, rough := 0.85, emissive := 0.0, metal := 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f_%.2f" % [c.to_html(), rough, emissive, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	_mats[key] = m
	return m


static func mi(mesh: Mesh, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	m.position = pos
	m.rotation = rot
	m.scale = scl
	return m


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func sphere(r: float, seg := 12, rings := 6) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	return s


static func cyl(top: float, bottom: float, h: float, seg := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return c


static func prism(size: Vector3) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = size
	return p


# ------------------------------------------------------------------ colors

## Returns Vector2(greenup, autumn), each 0..1, for a day of year and how far north (0 = Georgia, 1 = Maine).
static func seasons(doy: float, north01: float) -> Vector2:
	var greenup := clampf((doy - (72.0 + north01 * 45.0)) / 40.0, 0.0, 1.0)
	var autumn := clampf((doy - (282.0 - north01 * 32.0)) / 22.0, 0.0, 1.0)
	return Vector2(greenup, autumn)


static func foliage_color(season: Vector2, rng: RandomNumberGenerator) -> Color:
	var bare := Color(0.46, 0.4, 0.33)
	var spring := Color(0.55, 0.72, 0.32)
	var summer := Color(0.22, 0.48, 0.2)
	var autumn: Array = [Color(0.82, 0.36, 0.12), Color(0.9, 0.6, 0.16), Color(0.7, 0.2, 0.12), Color(0.78, 0.5, 0.2), Color(0.3, 0.45, 0.2)]
	var c := bare.lerp(spring, clampf(season.x * 2.0, 0.0, 1.0))
	c = c.lerp(summer, clampf(season.x * 2.0 - 1.0, 0.0, 1.0))
	var a: Color = autumn[rng.randi() % autumn.size()]
	c = c.lerp(a, season.y)
	return c.darkened(rng.randf_range(-0.08, 0.15))


static func conifer_color(rng: RandomNumberGenerator) -> Color:
	return Color(0.13, 0.32, 0.2).darkened(rng.randf_range(-0.15, 0.2))


# ------------------------------------------------------------------ nature

static func conifer(h: float, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	n.add_child(mi(cyl(0.06 * h, 0.08 * h, 0.3 * h, 6), mat(Color(0.35, 0.24, 0.16)), Vector3(0, 0.15 * h, 0)))
	var col := conifer_color(rng)
	for i in 3:
		var t := float(i) / 3.0
		var r := (0.42 - t * 0.12) * h
		n.add_child(mi(cyl(0.0, r, 0.45 * h, 8), mat(col.lightened(t * 0.08)), Vector3(0, 0.38 * h + t * 0.3 * h, 0)))
	return n


static func deciduous(h: float, color: Color) -> Node3D:
	var n := Node3D.new()
	n.add_child(mi(cyl(0.05 * h, 0.08 * h, 0.5 * h, 6), mat(Color(0.38, 0.27, 0.18)), Vector3(0, 0.25 * h, 0)))
	n.add_child(mi(sphere(0.36 * h, 8, 5), mat(color), Vector3(0, 0.68 * h, 0), Vector3.ZERO, Vector3(1, 0.85, 1)))
	n.add_child(mi(sphere(0.24 * h, 8, 5), mat(color.lightened(0.06)), Vector3(0.18 * h, 0.85 * h, 0.05 * h)))
	return n


static func rock(size: float, rng: RandomNumberGenerator, col := Color(0.52, 0.5, 0.48)) -> MeshInstance3D:
	var r := mi(sphere(size, 7, 4), mat(col.darkened(rng.randf_range(0.0, 0.25)), 0.95),
		Vector3.ZERO, Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.4),
		Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.5, 0.85), rng.randf_range(0.8, 1.3)))
	return r


static func bush(size: float, color: Color, berries := Color(0, 0, 0, 0)) -> Node3D:
	var n := Node3D.new()
	n.add_child(mi(sphere(size, 8, 5), mat(color), Vector3(0, size * 0.6, 0), Vector3.ZERO, Vector3(1.2, 0.8, 1.1)))
	n.add_child(mi(sphere(size * 0.7, 8, 5), mat(color.lightened(0.08)), Vector3(size * 0.5, size * 0.75, size * 0.2)))
	if berries.a > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(size * 1000)
		for i in 9:
			var a := rng.randf() * TAU
			var y := rng.randf_range(0.4, 1.1) * size
			n.add_child(mi(sphere(size * 0.11, 6, 3), mat(berries, 0.4), Vector3(cos(a) * size * 1.05, y, sin(a) * size * 0.95)))
	return n


static func mushroom(toxic: bool, s := 1.0) -> Node3D:
	var n := Node3D.new()
	var cap_col := Color(0.85, 0.12, 0.1) if toxic else Color(0.95, 0.65, 0.18)
	n.add_child(mi(cyl(0.05 * s, 0.07 * s, 0.22 * s, 8), mat(Color(0.95, 0.92, 0.85)), Vector3(0, 0.11 * s, 0)))
	n.add_child(mi(sphere(0.16 * s, 10, 5), mat(cap_col, 0.5), Vector3(0, 0.24 * s, 0), Vector3.ZERO, Vector3(1, 0.5, 1)))
	if toxic:
		for i in 6:
			var a := i * TAU / 6.0
			n.add_child(mi(sphere(0.025 * s, 5, 3), mat(Color.WHITE), Vector3(cos(a) * 0.09 * s, 0.3 * s, sin(a) * 0.09 * s)))
	return n


static func ramps(s := 1.0) -> Node3D:
	var n := Node3D.new()
	for i in 4:
		var a := i * TAU / 4.0 + 0.3
		n.add_child(mi(box(Vector3(0.08, 0.02, 0.38) * s), mat(Color(0.3, 0.6, 0.25)), Vector3(cos(a) * 0.1, 0.12, sin(a) * 0.1) * s, Vector3(0.6, a, 0)))
	n.add_child(mi(cyl(0.02 * s, 0.03 * s, 0.12 * s, 6), mat(Color(0.75, 0.35, 0.45)), Vector3(0, 0.06 * s, 0)))
	return n


static func apple_tree(h: float) -> Node3D:
	var n := deciduous(h, Color(0.3, 0.5, 0.22))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 10:
		var a := rng.randf() * TAU
		n.add_child(mi(sphere(0.05 * h, 6, 3), mat(Color(0.8, 0.12, 0.1), 0.4), Vector3(cos(a) * 0.33 * h, 0.55 * h + rng.randf() * 0.3 * h, sin(a) * 0.33 * h)))
	return n


static func mountain(h: float, r: float, rng: RandomNumberGenerator, snow := false) -> Node3D:
	var n := Node3D.new()
	var col := Color(0.32, 0.42, 0.3).darkened(rng.randf_range(0, 0.2))
	n.add_child(mi(cyl(r * 0.08, r, h, 9), mat(col, 0.95), Vector3(0, h * 0.5, 0), Vector3(0, rng.randf() * TAU, 0)))
	if snow:
		n.add_child(mi(cyl(r * 0.08, r * 0.3, h * 0.3, 9), mat(Color(0.92, 0.94, 0.97), 0.7), Vector3(0, h * 0.86, 0)))
	return n


# ------------------------------------------------------------------ creatures

static func hiker(shirt: Color, pack: Color, hat := true) -> Node3D:
	var n := Node3D.new()
	n.name = "Hiker"
	var skin := Color(0.85, 0.66, 0.52)
	# legs
	n.add_child(mi(cyl(0.07, 0.08, 0.5, 6), mat(Color(0.25, 0.27, 0.3)), Vector3(-0.09, 0.25, 0)))
	n.add_child(mi(cyl(0.07, 0.08, 0.5, 6), mat(Color(0.25, 0.27, 0.3)), Vector3(0.09, 0.25, 0)))
	# torso
	n.add_child(mi(capsule(0.17, 0.62), mat(shirt), Vector3(0, 0.78, 0)))
	# head
	n.add_child(mi(sphere(0.13), mat(skin), Vector3(0, 1.22, 0)))
	if hat:
		n.add_child(mi(cyl(0.18, 0.18, 0.02, 12), mat(pack.darkened(0.2)), Vector3(0, 1.3, 0)))
		n.add_child(mi(cyl(0.1, 0.12, 0.1, 12), mat(pack.darkened(0.2)), Vector3(0, 1.35, 0)))
	# backpack
	n.add_child(mi(box(Vector3(0.32, 0.5, 0.2)), mat(pack), Vector3(0, 0.88, 0.2)))
	n.add_child(mi(capsule(0.08, 0.34), mat(Color(0.3, 0.55, 0.3)), Vector3(0, 1.18, 0.22), Vector3(0, 0, PI / 2)))
	# trekking poles
	n.add_child(mi(cyl(0.012, 0.012, 1.1, 4), mat(Color(0.6, 0.6, 0.65), 0.4, 0, 0.6), Vector3(-0.25, 0.5, -0.15), Vector3(0.25, 0, 0.1)))
	n.add_child(mi(cyl(0.012, 0.012, 1.1, 4), mat(Color(0.6, 0.6, 0.65), 0.4, 0, 0.6), Vector3(0.25, 0.5, -0.15), Vector3(-0.15, 0, -0.1)))
	return n


static func bear(s := 1.0) -> Node3D:
	var n := Node3D.new()
	n.name = "Bear"
	var fur := mat(Color(0.08, 0.07, 0.07), 0.95)
	n.add_child(mi(capsule(0.45 * s, 1.5 * s), fur, Vector3(0, 0.75 * s, 0), Vector3(PI / 2, 0, 0)))
	n.add_child(mi(sphere(0.32 * s), fur, Vector3(0, 0.95 * s, -0.85 * s)))
	n.add_child(mi(cyl(0.1 * s, 0.15 * s, 0.25 * s, 8), mat(Color(0.45, 0.33, 0.22)), Vector3(0, 0.88 * s, -1.12 * s), Vector3(PI / 2, 0, 0)))
	n.add_child(mi(sphere(0.05 * s), mat(Color(0.02, 0.02, 0.02), 0.3), Vector3(0, 0.9 * s, -1.25 * s)))
	n.add_child(mi(sphere(0.1 * s), fur, Vector3(-0.2 * s, 1.22 * s, -0.8 * s)))
	n.add_child(mi(sphere(0.1 * s), fur, Vector3(0.2 * s, 1.22 * s, -0.8 * s)))
	for p in [Vector3(-0.25, 0, -0.45), Vector3(0.25, 0, -0.45), Vector3(-0.25, 0, 0.45), Vector3(0.25, 0, 0.45)]:
		n.add_child(mi(cyl(0.12 * s, 0.13 * s, 0.6 * s, 8), fur, Vector3(p.x * s, 0.3 * s, p.z * s)))
	return n


static func pony(col: Color) -> Node3D:
	var n := Node3D.new()
	var m := mat(col, 0.9)
	n.add_child(mi(capsule(0.3, 1.2), m, Vector3(0, 0.85, 0), Vector3(PI / 2, 0, 0)))
	n.add_child(mi(capsule(0.13, 0.6), m, Vector3(0, 1.2, -0.5), Vector3(-0.7, 0, 0)))
	n.add_child(mi(box(Vector3(0.2, 0.22, 0.42)), m, Vector3(0, 1.38, -0.75), Vector3(0.4, 0, 0)))
	n.add_child(mi(box(Vector3(0.06, 0.25, 0.5)), mat(col.darkened(0.5)), Vector3(0, 1.4, -0.42), Vector3(-0.7, 0, 0)))
	for p in [Vector3(-0.15, 0, -0.35), Vector3(0.15, 0, -0.35), Vector3(-0.15, 0, 0.35), Vector3(0.15, 0, 0.35)]:
		n.add_child(mi(cyl(0.06, 0.07, 0.6, 6), m, Vector3(p.x, 0.3, p.z)))
	return n


static func snake() -> Node3D:
	var n := Node3D.new()
	for i in 16:
		var t := float(i) / 15.0
		var c := Color(0.45, 0.36, 0.2) if i % 3 != 0 else Color(0.18, 0.13, 0.08)
		n.add_child(mi(sphere(0.06 * (1.0 - t * 0.5), 8, 4), mat(c, 0.5), Vector3(sin(t * 9.0) * 0.25, 0.05, t * 1.6 - 0.8)))
	n.add_child(mi(sphere(0.08, 8, 4), mat(Color(0.4, 0.3, 0.18), 0.5), Vector3(0, 0.12, -0.85), Vector3.ZERO, Vector3(1, 0.6, 1.4)))
	return n


# ------------------------------------------------------------------ structures

static func house(wall: Color, roof: Color, size := Vector3(1.6, 1.1, 1.3)) -> Node3D:
	var n := Node3D.new()
	n.add_child(mi(box(size), mat(wall), Vector3(0, size.y / 2, 0)))
	var r := mi(prism(Vector3(size.x * 1.15, size.y * 0.7, size.z * 1.1)), mat(roof), Vector3(0, size.y + size.y * 0.35, 0))
	n.add_child(r)
	n.add_child(mi(box(Vector3(0.3, 0.55, 0.04)), mat(Color(0.35, 0.22, 0.14)), Vector3(0, 0.28, size.z / 2 + 0.01)))
	var win := mat(Color(1.0, 0.82, 0.45), 0.4, 1.6)
	n.add_child(mi(box(Vector3(0.28, 0.25, 0.04)), win, Vector3(-size.x * 0.3, size.y * 0.6, size.z / 2 + 0.01)))
	n.add_child(mi(box(Vector3(0.28, 0.25, 0.04)), win, Vector3(size.x * 0.3, size.y * 0.6, size.z / 2 + 0.01)))
	return n


static func shelter() -> Node3D:
	var n := Node3D.new()
	var wood := mat(Color(0.5, 0.36, 0.22))
	n.add_child(mi(box(Vector3(2.6, 1.2, 0.15)), wood, Vector3(0, 0.6, -0.9)))
	n.add_child(mi(box(Vector3(0.15, 1.2, 1.9)), wood, Vector3(-1.25, 0.6, 0)))
	n.add_child(mi(box(Vector3(0.15, 1.2, 1.9)), wood, Vector3(1.25, 0.6, 0)))
	n.add_child(mi(box(Vector3(2.5, 0.1, 1.8)), mat(Color(0.6, 0.45, 0.3)), Vector3(0, 0.35, 0)))
	n.add_child(mi(box(Vector3(3.0, 0.1, 2.5)), mat(Color(0.3, 0.3, 0.32)), Vector3(0, 1.45, 0.1), Vector3(-0.32, 0, 0)))
	return n


static func tent(col: Color) -> Node3D:
	var n := Node3D.new()
	n.add_child(mi(prism(Vector3(1.4, 0.9, 2.0)), mat(col, 0.7), Vector3(0, 0.45, 0)))
	return n


static func campfire() -> Node3D:
	var n := Node3D.new()
	var wood := mat(Color(0.3, 0.2, 0.12))
	for i in 4:
		var a := i * TAU / 4.0
		n.add_child(mi(cyl(0.05, 0.05, 0.6, 6), wood, Vector3(cos(a) * 0.12, 0.08, sin(a) * 0.12), Vector3(PI / 2 - 0.3, a, 0)))
	for i in 7:
		var a := i * TAU / 7.0
		n.add_child(mi(sphere(0.09, 6, 3), mat(Color(0.45, 0.45, 0.45)), Vector3(cos(a) * 0.35, 0.05, sin(a) * 0.35)))
	var flame := mi(cyl(0.0, 0.16, 0.45, 8), mat(Color(1.0, 0.55, 0.15), 0.5, 4.0), Vector3(0, 0.3, 0))
	flame.name = "Flame"
	n.add_child(flame)
	n.add_child(mi(cyl(0.0, 0.09, 0.3, 8), mat(Color(1.0, 0.85, 0.3), 0.5, 5.0), Vector3(0, 0.27, 0)))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 2.5
	l.omni_range = 6.0
	l.position = Vector3(0, 0.6, 0)
	l.name = "FireLight"
	n.add_child(l)
	return n


static func sign_post(col := Color(0.42, 0.3, 0.18)) -> Node3D:
	var n := Node3D.new()
	n.add_child(mi(box(Vector3(0.1, 1.4, 0.1)), mat(col), Vector3(0, 0.7, 0)))
	n.add_child(mi(box(Vector3(0.9, 0.4, 0.06)), mat(col.lightened(0.15)), Vector3(0, 1.2, 0.05)))
	return n


static func blaze_tree() -> Node3D:
	var n := Node3D.new()
	n.add_child(mi(cyl(0.2, 0.26, 3.5, 8), mat(Color(0.38, 0.28, 0.2)), Vector3(0, 1.75, 0)))
	n.add_child(mi(box(Vector3(0.12, 0.25, 0.02)), mat(Color(0.98, 0.98, 0.95), 0.6, 0.3), Vector3(0, 1.6, 0.235)))
	return n


static func water_material() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/water.gdshader")
	return sm
