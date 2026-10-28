class_name WorldMap
extends Node3D
## The overworld: procedural Appalachian terrain built from the real trail coordinates,
## with forests, towns, landmark pins, the trail ribbon and the party marker.

const K := 9.0            # map units per degree of latitude
const LON0 := -76.5
const LAT0 := 40.25
const COS_LAT := 0.766
const HALF := 128.0       # terrain half-extent
const STEP := 0.9         # terrain grid spacing
const HEIGHT := 4.2       # vertical scale

# rough US east coastline (lat, lon), land is to the west/north
const COAST := [
	[33.4, -79.0], [34.2, -77.8], [34.7, -76.6], [35.2, -75.6], [35.9, -75.6], [36.9, -75.95],
	[37.6, -75.6], [38.4, -75.05], [38.9, -74.9], [39.5, -74.3], [40.45, -74.0], [40.6, -73.5],
	[40.9, -72.4], [41.15, -72.0], [41.4, -71.4], [41.55, -70.6], [41.75, -69.95], [42.05, -70.15],
	[42.4, -70.95], [42.85, -70.75], [43.35, -70.45], [43.65, -70.2], [43.95, -69.6], [44.25, -68.9],
	[44.45, -68.1], [44.75, -67.2], [45.2, -66.7], [46.5, -66.3],
]

var trail_pts := PackedVector3Array()   # dense trail polyline (y filled after terrain)
var trail_miles := PackedFloat32Array()
var heights := PackedFloat32Array()
var max_height := 1.0
var grid_n := 0
var dist_field := PackedFloat32Array()
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()

var terrain_mat: ShaderMaterial
var trail_mat: ShaderMaterial
var tree_mm: MultiMesh
var tree_info: Array = []   # [north01, is_conifer, rng_seed]
var atmos: Atmosphere
var party_node: Node3D
var party_hikers: Array = []
var party_ring: MeshInstance3D
var party_pin: Node3D
var trail_near: MeshInstance3D
var trail_far: MeshInstance3D
var camera: Camera3D
var landmark_nodes: Array = []
var campfire: Node3D

# camera rig
var cam_target := Vector3.ZERO
var cam_yaw := 0.35
var cam_pitch := 0.75
var cam_dist := 8.0
var overview := false
var _goal_dist := 8.0
var _dragging := false
var input_enabled := true
var orbit_auto := false

var party_miles := 0.0
var walking := false
var _walk_t := 0.0
var _last_doy := -1


func build(seed_v := 2198) -> void:
	noise.seed = seed_v
	noise.frequency = 0.035
	noise.fractal_octaves = 5
	noise2.seed = seed_v + 7
	noise2.frequency = 0.16
	noise2.fractal_octaves = 4
	_prepare_lookup()
	_build_trail_2d()
	_build_terrain()
	_finish_trail()
	_build_water()
	_build_forest()
	_build_landmarks()
	_build_party()
	atmos = Atmosphere.new()
	add_child(atmos)
	atmos.setup(26.0, 1.0, 1.0)
	atmos.follow = party_node
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.far = 600.0
	add_child(camera)
	camera.current = true
	set_party_miles(0.0)
	cam_target = party_node.position
	_update_camera(1.0)


# ------------------------------------------------------------------ projection

static func project(lat: float, lon: float) -> Vector2:
	return Vector2((lon - LON0) * K * COS_LAT, -(lat - LAT0) * K)


func _build_trail_2d() -> void:
	var lms: Array = TrailData.LANDMARKS
	var ctrl: Array = []
	for lm in lms:
		ctrl.append(project(lm["lat"], lm["lon"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(ctrl.size() - 1):
		var p0: Vector2 = ctrl[max(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[min(i + 2, ctrl.size() - 1)]
		var m1: float = lms[i]["mile"]
		var m2: float = lms[i + 1]["mile"]
		var seg_len := p1.distance_to(p2)
		var steps := maxi(4, int(seg_len / 0.18))
		var perp := (p2 - p1).orthogonal().normalized()
		var wf := rng.randf_range(2.0, 4.0)
		var wa := minf(0.35, seg_len * 0.06)
		for s in steps:
			var t := float(s) / steps
			var p := _catmull(p0, p1, p2, p3, t)
			p += perp * sin(t * PI * wf) * wa * sin(t * PI)
			trail_pts.append(Vector3(p.x, 0, p.y))
			trail_miles.append(lerpf(m1, m2, t))
	var last: Vector2 = ctrl[ctrl.size() - 1]
	trail_pts.append(Vector3(last.x, 0, last.y))
	trail_miles.append(lms[lms.size() - 1]["mile"])


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# ------------------------------------------------------------------ terrain

var _coast_pts := PackedVector2Array()
var _peaks: Array = []
var _coast_grid := PackedFloat32Array()
const COAST_STEP := 2.5
var _coast_n := 0


func _coast_exact(p: Vector2) -> float:
	# positive = inland
	var best := 1e9
	var sgn := 1.0
	for i in range(_coast_pts.size() - 1):
		var a := _coast_pts[i]
		var b := _coast_pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_to(q)
		if d < best:
			best = d
			# coast runs SW->NE; land is to the left of travel direction (west/north)
			var cr := ab.x * (p - a).y - ab.y * (p - a).x
			sgn = -1.0 if cr > 0.0 else 1.0
	return best * sgn


func _prepare_lookup() -> void:
	for c in COAST:
		_coast_pts.append(project(c[0], c[1]))
	var peaks := [[35.56, -83.5, 0.6, 2.5], [36.1, -82.13, 0.5, 2.0], [44.27, -71.3, 1.8, 3.5],
		[44.16, -71.64, 1.2, 2.5], [45.9, -68.92, 2.2, 2.2], [44.02, -71.83, 1.0, 2.0], [36.63, -81.52, 0.8, 2.5],
		[35.33, -83.59, 0.5, 2.0], [42.64, -73.17, 0.5, 1.6]]
	for pk in peaks:
		_peaks.append([project(pk[0], pk[1]), float(pk[2]), float(pk[3])])
	_coast_n = int(HALF * 2.0 / COAST_STEP) + 2
	_coast_grid.resize(_coast_n * _coast_n)
	for zz in _coast_n:
		for xx in _coast_n:
			var p := Vector2(xx * COAST_STEP - HALF, zz * COAST_STEP - HALF)
			_coast_grid[zz * _coast_n + xx] = 40.0 if p.x < -60.0 else _coast_exact(p)


func _coast_signed(p: Vector2) -> float:
	var fx := (p.x + HALF) / COAST_STEP
	var fz := (p.y + HALF) / COAST_STEP
	var x0 := clampi(int(floor(fx)), 0, _coast_n - 2)
	var z0 := clampi(int(floor(fz)), 0, _coast_n - 2)
	var tx := fx - x0
	var tz := fz - z0
	var a := lerpf(_coast_grid[z0 * _coast_n + x0], _coast_grid[z0 * _coast_n + x0 + 1], tx)
	var b := lerpf(_coast_grid[(z0 + 1) * _coast_n + x0], _coast_grid[(z0 + 1) * _coast_n + x0 + 1], tx)
	return lerpf(a, b, tz)


func _peak_bonus(p: Vector2) -> float:
	var b := 0.0
	for pk in _peaks:
		var d := p.distance_to(pk[0])
		var r: float = pk[2]
		if d < r * 3.0:
			b += pk[1] * exp(-(d / r) * (d / r))
	return b


func _build_terrain() -> void:
	grid_n = int(HALF * 2.0 / STEP) + 1
	var n := grid_n
	dist_field.resize(n * n)
	dist_field.fill(1e6)
	# stamp trail distance (squared) into the grid
	var r := 17.0
	var rc := int(ceil(r / STEP))
	var i := 0
	while i < trail_pts.size():
		var tp := trail_pts[i]
		var gx := int(round((tp.x + HALF) / STEP))
		var gz := int(round((tp.z + HALF) / STEP))
		for zz in range(maxi(0, gz - rc), mini(n, gz + rc + 1)):
			var wz := zz * STEP - HALF
			var dz2 := (wz - tp.z) * (wz - tp.z)
			for xx in range(maxi(0, gx - rc), mini(n, gx + rc + 1)):
				var wx := xx * STEP - HALF
				var d2 := (wx - tp.x) * (wx - tp.x) + dz2
				var idx := zz * n + xx
				if d2 < dist_field[idx]:
					dist_field[idx] = d2
		i += 3
	heights.resize(n * n)
	var sand := PackedFloat32Array()
	sand.resize(n * n)
	var patch := PackedFloat32Array()
	patch.resize(n * n)
	var belts := PackedFloat32Array()
	belts.resize(n * n)
	var hmax := 0.0
	for zz in n:
		for xx in n:
			var idx := zz * n + xx
			var wx := xx * STEP - HALF
			var wz := zz * STEP - HALF
			var p := Vector2(wx, wz)
			var d := sqrt(dist_field[idx])
			var belt := smoothstep(15.0, 2.5, d)
			var crest := exp(-(d / 2.0) * (d / 2.0))
			var nv := noise.get_noise_2d(wx, wz) * 0.5 + 0.5
			var rg := 1.0 - absf(noise2.get_noise_2d(wx, wz))
			rg = rg * rg * rg
			var h := 0.12 + nv * 0.3
			h += belt * (0.35 + nv * 0.55 + rg * 1.05)
			h += crest * 0.35
			h += _peak_bonus(p)
			var cs := _coast_signed(p)
			var land := smoothstep(-0.5, 3.0, cs)
			h = lerpf(-0.6, h, land)
			sand[idx] = clampf(1.0 - absf(cs - 0.5) / 0.8, 0.0, 1.0) * (1.0 - belt)
			belts[idx] = belt
			h *= HEIGHT * 0.5
			heights[idx] = h
			hmax = maxf(hmax, h)
			patch[idx] = noise2.get_noise_2d(wx * 2.7 + 50.0, wz * 2.7) * 0.5 + 0.5
	max_height = hmax

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	for zz in n:
		for xx in n:
			var idx := zz * n + xx
			var h := heights[idx]
			verts[idx] = Vector3(xx * STEP - HALF, h, zz * STEP - HALF)
			var hl := heights[zz * n + maxi(xx - 1, 0)]
			var hr := heights[zz * n + mini(xx + 1, n - 1)]
			var hd := heights[maxi(zz - 1, 0) * n + xx]
			var hu := heights[mini(zz + 1, n - 1) * n + xx]
			normals[idx] = Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()
			colors[idx] = Color(clampf(h / hmax, 0.0, 1.0), patch[idx], sand[idx], belts[idx])
	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for zz in n - 1:
		for xx in n - 1:
			var a := zz * n + xx
			var b := a + 1
			var c := a + n
			var d2 := c + 1
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = c
			indices[k + 3] = b
			indices[k + 4] = d2
			indices[k + 5] = c
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	var t := MeshInstance3D.new()
	t.name = "Terrain"
	t.mesh = mesh
	t.material_override = terrain_mat
	add_child(t)


func height_at(x: float, z: float) -> float:
	var fx := (x + HALF) / STEP
	var fz := (z + HALF) / STEP
	var x0 := clampi(int(floor(fx)), 0, grid_n - 2)
	var z0 := clampi(int(floor(fz)), 0, grid_n - 2)
	var tx := clampf(fx - x0, 0.0, 1.0)
	var tz := clampf(fz - z0, 0.0, 1.0)
	var h00 := heights[z0 * grid_n + x0]
	var h10 := heights[z0 * grid_n + x0 + 1]
	var h01 := heights[(z0 + 1) * grid_n + x0]
	var h11 := heights[(z0 + 1) * grid_n + x0 + 1]
	# match the triangle split used by the mesh
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


func trail_dist_at(x: float, z: float) -> float:
	var gx := clampi(int(round((x + HALF) / STEP)), 0, grid_n - 1)
	var gz := clampi(int(round((z + HALF) / STEP)), 0, grid_n - 1)
	return sqrt(dist_field[gz * grid_n + gx])


# ------------------------------------------------------------------ trail ribbon

func _finish_trail() -> void:
	for i in trail_pts.size():
		var p := trail_pts[i]
		trail_pts[i] = Vector3(p.x, height_at(p.x, p.z) + 0.07, p.z)
	trail_mat = ShaderMaterial.new()
	trail_mat.shader = load("res://shaders/trail.gdshader")
	var near := MeshInstance3D.new()
	near.name = "Trail"
	near.mesh = _ribbon_mesh(0.11, 0.0, 1)
	near.material_override = trail_mat
	near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(near)
	trail_near = near
	# a bold version of the line for the zoomed-out overview
	var far := MeshInstance3D.new()
	far.name = "TrailFar"
	far.mesh = _ribbon_mesh(1.1, 0.35, 4)
	far.material_override = trail_mat
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.visible = false
	add_child(far)
	trail_far = far


func _ribbon_mesh(w: float, lift: float, stride: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var total: float = TrailData.TOTAL_MILES
	var idxs: Array = []
	var i := 0
	while i < trail_pts.size():
		idxs.append(i)
		i += stride
	if idxs[-1] != trail_pts.size() - 1:
		idxs.append(trail_pts.size() - 1)
	for j in idxs.size():
		var k: int = idxs[j]
		var a := trail_pts[idxs[max(j - 1, 0)]]
		var b := trail_pts[idxs[min(j + 1, idxs.size() - 1)]]
		var dir := (b - a)
		dir.y = 0
		dir = dir.normalized()
		var side := Vector3(-dir.z, 0, dir.x) * w * 0.5
		var p := trail_pts[k] + Vector3(0, lift, 0)
		var l := p - side
		var r := p + side
		l.y = maxf(p.y, height_at(l.x, l.z) + 0.07 + lift)
		r.y = maxf(p.y, height_at(r.x, r.z) + 0.07 + lift)
		verts.append(l)
		verts.append(r)
		var u := trail_miles[k] / total
		uvs.append(Vector2(u, 0))
		uvs.append(Vector2(u, 1))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	var idx := PackedInt32Array()
	for j in idxs.size() - 1:
		var o := j * 2
		idx.append_array([o, o + 1, o + 2, o + 1, o + 3, o + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _build_water() -> void:
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(700, 700)
	w.mesh = pm
	w.position = Vector3(0, -0.15, 0)
	var m := Props.water_material()
	m.set_shader_parameter("wave_scale", 0.6)
	m.set_shader_parameter("speed", 0.6)
	w.material_override = m
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(w)
	# distant land skirt so the horizon to the west isn't open ocean
	var skirt := MeshInstance3D.new()
	var sm := PlaneMesh.new()
	sm.size = Vector2(500, 500)
	skirt.mesh = sm
	skirt.position = Vector3(-HALF - 250 + 2, 0.3, 0)
	skirt.material_override = Props.mat(Color(0.36, 0.42, 0.24), 1.0)
	add_child(skirt)
	var skirt2 := MeshInstance3D.new()
	skirt2.mesh = sm
	skirt2.position = Vector3(0, 0.3, -HALF - 250 + 2)
	skirt2.material_override = skirt.material_override
	add_child(skirt2)


# ------------------------------------------------------------------ forest

var conifer_mm: MultiMesh


static func merged_mesh(parts: Array) -> ArrayMesh:
	## parts: [[PrimitiveMesh, Transform3D, Color]] -> one ArrayMesh with vertex colors
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var m: PrimitiveMesh = part[0]
		var xf: Transform3D = part[1]
		var col: Color = part[2]
		var arr := m.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in idx.size():
			var k := idx[i]
			st.set_color(Color.WHITE)
			st.set_uv(Vector2(col.a, 0.0))
			st.set_normal((xf.basis * nrm[k]).normalized())
			st.add_vertex(xf * v[k])
	return st.commit()


func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var trunk := Color(0.33, 0.24, 0.17, 0.0)
	var leaf := Color(1, 1, 1, 1)
	var conifer_mesh := merged_mesh([
		[Props.cyl(0.05, 0.07, 0.35, 5), Transform3D(Basis(), Vector3(0, 0.17, 0)), trunk],
		[Props.cyl(0.0, 0.42, 0.75, 7), Transform3D(Basis(), Vector3(0, 0.62, 0)), leaf],
		[Props.cyl(0.0, 0.3, 0.55, 7), Transform3D(Basis(), Vector3(0, 0.95, 0)), leaf],
	])
	var decid_mesh := merged_mesh([
		[Props.cyl(0.05, 0.08, 0.5, 5), Transform3D(Basis(), Vector3(0, 0.25, 0)), trunk],
		[Props.sphere(0.4, 8, 5), Transform3D(Basis().scaled(Vector3(1, 0.85, 1)), Vector3(0, 0.72, 0)), leaf],
		[Props.sphere(0.26, 7, 4), Transform3D(Basis(), Vector3(0.2, 0.9, 0.08)), leaf],
	])
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage.gdshader")
	var c_xf: Array = []
	var d_xf: Array = []
	var c_col: Array = []
	var tries := 0
	while c_xf.size() + d_xf.size() < 22000 and tries < 120000:
		tries += 1
		var i := rng.randi() % trail_pts.size()
		var tp := trail_pts[i]
		var ang := rng.randf() * TAU
		var rad := 0.25 + pow(rng.randf(), 1.3) * 15.0
		var x := tp.x + cos(ang) * rad
		var z := tp.z + sin(ang) * rad
		if absf(x) > HALF - 1 or absf(z) > HALF - 1:
			continue
		var h := height_at(x, z)
		if h < 0.3:
			continue
		var d := trail_dist_at(x, z)
		var belt := smoothstep(15.0, 2.5, d)
		if rng.randf() > belt * 1.1:
			continue
		var hn := h / max_height
		var north := clampf((-z + 55.0) / 110.0, 0.0, 1.0)
		if hn + north * 0.12 - (1.0 - north) * 0.15 > 0.86:
			continue   # above treeline
		var conifer := rng.randf() < clampf(0.1 + north * 0.4 + hn * 0.5, 0.0, 0.92)
		var sc := rng.randf_range(0.13, 0.22)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * (1.25 if conifer else 1.0), sc))
		var xf := Transform3D(basis, Vector3(x, h - 0.02, z))
		if conifer:
			c_xf.append(xf)
			c_col.append(Props.conifer_color(rng))
		else:
			d_xf.append(xf)
			tree_info.append([north, false, rng.randi()])
	conifer_mm = MultiMesh.new()
	tree_mm = MultiMesh.new()
	for mm in [conifer_mm, tree_mm]:
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
	conifer_mm.mesh = conifer_mesh
	tree_mm.mesh = decid_mesh
	conifer_mm.instance_count = c_xf.size()
	tree_mm.instance_count = d_xf.size()
	for j in c_xf.size():
		conifer_mm.set_instance_transform(j, c_xf[j])
		conifer_mm.set_instance_color(j, c_col[j])
	for j in d_xf.size():
		tree_mm.set_instance_transform(j, d_xf[j])
		tree_mm.set_instance_color(j, Color(0.3, 0.5, 0.2))
	for mm in [conifer_mm, tree_mm]:
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = mat
		add_child(inst)


func set_day_of_year(doy: int) -> void:
	terrain_mat.set_shader_parameter("doy", float(doy))
	# snow on the high summits in early spring and late fall
	var snow := 1.4
	if doy < 70:
		snow = 0.72
	elif doy < 100:
		snow = lerpf(0.78, 1.05, (doy - 70) / 30.0)
	elif doy > 292:
		snow = lerpf(1.05, 0.8, clampf((doy - 292) / 18.0, 0.0, 1.0))
	terrain_mat.set_shader_parameter("snow_level", snow)
	if absi(doy - _last_doy) < 3 and _last_doy >= 0:
		return
	_last_doy = doy
	var rng := RandomNumberGenerator.new()
	for i in tree_info.size():
		rng.seed = tree_info[i][2]
		tree_mm.set_instance_color(i, Props.foliage_color(Props.seasons(doy, tree_info[i][0]), rng))


# ------------------------------------------------------------------ landmarks & towns

func _build_landmarks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in TrailData.LANDMARKS.size():
		var lm: Dictionary = TrailData.LANDMARKS[i]
		var p := position_for_miles(lm["mile"])
		var node := Node3D.new()
		node.position = p
		add_child(node)
		var col := Color(0.95, 0.6, 0.2)
		match lm["type"]:
			"town":
				col = Color(0.35, 0.7, 1.0)
			"start", "finish":
				col = Color(1.0, 0.85, 0.3)
			"river":
				col = Color(0.3, 0.85, 0.85)
		node.add_child(Props.mi(Props.cyl(0.012, 0.012, 0.8, 5), Props.mat(Color(0.9, 0.9, 0.9)), Vector3(0, 0.4, 0)))
		node.add_child(Props.mi(Props.sphere(0.065, 10, 5), Props.mat(col, 0.4, 1.6), Vector3(0, 0.82, 0)))
		if lm["type"] == "town":
			var side := Vector3(0.6, 0, 0.3)
			for h in rng.randi_range(3, 6):
				var hp := side + Vector3(rng.randf_range(-0.45, 0.45), 0, rng.randf_range(-0.45, 0.45))
				var walls: Array = [Color(0.92, 0.9, 0.85), Color(0.75, 0.3, 0.25), Color(0.85, 0.78, 0.6), Color(0.6, 0.7, 0.8)]
				var hs := Props.house(walls[rng.randi() % walls.size()], Color(0.3, 0.25, 0.25))
				hs.scale = Vector3.ONE * 0.13
				hs.position = hp
				hs.position.y = height_at(p.x + hp.x, p.z + hp.z) - p.y
				hs.rotation.y = rng.randf() * TAU
				node.add_child(hs)
		var lbl := Label3D.new()
		lbl.text = lm["name"]
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 40
		lbl.outline_size = 14
		lbl.fixed_size = true
		lbl.pixel_size = 0.00055
		lbl.position = Vector3(0, 1.05, 0)
		lbl.modulate = Color(1, 1, 1, 1)
		lbl.outline_modulate = Color(0.05, 0.06, 0.05, 0.9)
		lbl.no_depth_test = true
		lbl.render_priority = 10
		lbl.outline_render_priority = 9
		lbl.visibility_range_end = 26.0 if lm["type"] != "finish" and lm["type"] != "start" else 400.0
		lbl.visibility_range_end_margin = 6.0
		lbl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		lbl.font = UiTheme.body_font()
		node.add_child(lbl)
		landmark_nodes.append(node)


# ------------------------------------------------------------------ party

func _build_party() -> void:
	party_node = Node3D.new()
	party_node.name = "Party"
	add_child(party_node)
	party_ring = Props.mi(Props.cyl(0.22, 0.22, 0.015, 24), Props.mat(Color(1.0, 0.72, 0.3), 0.4, 0.7), Vector3(0, 0.02, 0))
	party_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	party_node.add_child(party_ring)
	party_pin = Node3D.new()
	party_pin.add_child(Props.mi(Props.sphere(0.12, 4, 2), Props.mat(Color(1.0, 0.78, 0.3), 0.3, 1.2), Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.6, 1)))
	party_pin.position = Vector3(0, 0.85, 0)
	party_node.add_child(party_pin)
	campfire = Props.campfire()
	campfire.scale = Vector3.ONE * 0.25
	campfire.position = Vector3(0.25, 0, 0.18)
	party_node.add_child(campfire)
	set_party_size(4)


const SHIRTS := [Color(0.85, 0.3, 0.25), Color(0.25, 0.55, 0.85), Color(0.95, 0.75, 0.2), Color(0.45, 0.75, 0.4), Color(0.7, 0.4, 0.8)]
const PACKS := [Color(0.3, 0.35, 0.3), Color(0.55, 0.35, 0.2), Color(0.2, 0.3, 0.45), Color(0.45, 0.2, 0.2), Color(0.4, 0.4, 0.4)]


func set_party_size(n: int) -> void:
	for h in party_hikers:
		h.queue_free()
	party_hikers.clear()
	for i in n:
		var h := Props.hiker(SHIRTS[i % SHIRTS.size()], PACKS[i % PACKS.size()])
		h.scale = Vector3.ONE * 0.2
		h.position = Vector3(0, 0, i * 0.17 - (n - 1) * 0.085)
		party_node.add_child(h)
		party_hikers.append(h)


func position_for_miles(m: float) -> Vector3:
	var lo := 0
	var hi := trail_miles.size() - 1
	if m <= trail_miles[0]:
		return trail_pts[0]
	if m >= trail_miles[hi]:
		return trail_pts[hi]
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if trail_miles[mid] <= m:
			lo = mid
		else:
			hi = mid
	var span := trail_miles[hi] - trail_miles[lo]
	var t := 0.0 if span <= 0.0 else (m - trail_miles[lo]) / span
	return trail_pts[lo].lerp(trail_pts[hi], t)


func set_party_miles(m: float) -> void:
	party_miles = m
	var p := position_for_miles(m)
	var ahead := position_for_miles(minf(m + 2.0, TrailData.TOTAL_MILES))
	if ahead.distance_to(p) < 0.01:
		ahead = p + (p - position_for_miles(maxf(m - 2.0, 0.0)))
	party_node.position = p
	var dir := ahead - p
	dir.y = 0
	if dir.length() > 0.001:
		party_node.rotation.y = atan2(-dir.x, -dir.z)
	for i in party_hikers.size():
		var h: Node3D = party_hikers[i]
		var local := Vector3(-0.09 if i % 2 == 0 else 0.09, 0, i * 0.24 - (party_hikers.size() - 1) * 0.12)
		var wp := party_node.transform * local
		h.position = local
		h.position.y = height_at(wp.x, wp.z) - p.y
		h.set_meta("base_y", h.position.y)
		h.rotation.y = PI
	trail_mat.set_shader_parameter("progress", m / TrailData.TOTAL_MILES)


func set_campfire(on: bool) -> void:
	campfire.visible = on


# ------------------------------------------------------------------ camera

func set_overview(on: bool) -> void:
	overview = on
	if on:
		cam_yaw = 0.0
	_goal_dist = 140.0 if on else 8.0


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_goal_dist = maxf(3.0, _goal_dist * 0.88)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_goal_dist = minf(170.0, _goal_dist * 1.13)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		cam_yaw -= mm.relative.x * 0.006
		cam_pitch = clampf(cam_pitch + mm.relative.y * 0.004, 0.2, 1.45)


func _process(delta: float) -> void:
	if party_node == null:
		return
	if input_enabled:
		if Input.is_key_pressed(KEY_Q):
			cam_yaw += delta * 1.5
		if Input.is_key_pressed(KEY_E):
			cam_yaw -= delta * 1.5
		if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
			_goal_dist = maxf(3.0, _goal_dist * (1.0 - delta * 1.5))
		if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
			_goal_dist = minf(170.0, _goal_dist * (1.0 + delta * 1.5))
	if orbit_auto:
		cam_yaw += delta * 0.04
	_update_camera(delta)
	trail_far.visible = cam_dist > 38.0
	trail_near.visible = cam_dist <= 38.0
	# thin the fog out when zoomed out so the whole range stays visible
	var fs := clampf(9.0 / cam_dist, 0.06, 1.0)
	if absf(fs - atmos.fog_scale) > 0.02:
		atmos.fog_scale = fs
		atmos.apply()
	# walking animation
	if walking:
		_walk_t += delta * 9.0
		for i in party_hikers.size():
			var h: Node3D = party_hikers[i]
			h.rotation.z = sin(_walk_t + i) * 0.08
			h.position.y = float(h.get_meta("base_y", 0.0)) + absf(sin(_walk_t + i)) * 0.012
	if party_ring != null:
		var s := 1.0 + sin(Time.get_ticks_msec() * 0.004) * 0.12
		party_ring.scale = Vector3(s, 1, s)
		var ps := clampf(cam_dist / 9.0, 0.6, 14.0)
		party_pin.scale = Vector3.ONE * ps
		party_pin.position.y = 0.55 + 0.35 * ps + sin(Time.get_ticks_msec() * 0.003) * 0.06 * ps
		party_pin.rotation.y += delta * 1.5
	if campfire.visible:
		var fl: Node3D = campfire.get_node("Flame")
		fl.scale = Vector3(1, 1.0 + sin(Time.get_ticks_msec() * 0.02) * 0.2, 1)
		var light: OmniLight3D = campfire.get_node("FireLight")
		light.light_energy = (1.0 - atmos.daylight()) * 2.2 * (0.85 + randf() * 0.3)


func _update_camera(delta: float) -> void:
	cam_dist = lerpf(cam_dist, _goal_dist, clampf(delta * 4.0, 0.0, 1.0))
	var goal_target := party_node.position
	if overview or cam_dist > 60.0:
		var w := clampf((cam_dist - 30.0) / 100.0, 0.0, 1.0)
		goal_target = party_node.position.lerp(Vector3(2, 0, 4), w)
	cam_target = cam_target.lerp(goal_target, clampf(delta * 3.0, 0.0, 1.0))
	# blend toward a top-down view when zoomed far out
	var pitch := lerpf(cam_pitch, 1.22, clampf((cam_dist - 25.0) / 70.0, 0.0, 1.0))
	var off := Vector3(sin(cam_yaw) * cos(pitch), sin(pitch), cos(cam_yaw) * cos(pitch)) * cam_dist
	var pos := cam_target + off
	var ground := height_at(pos.x, pos.z) + 0.8
	if pos.y < ground:
		pos.y = ground
	camera.position = pos
	camera.look_at(cam_target + Vector3(0, 0.3, 0), Vector3.UP)
