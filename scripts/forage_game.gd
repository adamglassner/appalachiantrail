class_name ForageGame
extends Control
## Foraging minigame: walk a forest clearing gathering wild food before time runs out.
## WASD / arrows to move, left-click to walk to a spot, Space to shout at bears.
## Watch out for red-capped Amanita mushrooms (poisonous) and hungry bears.

signal finished(lbs: float, toxic: int)

const DURATION := 45.0
const CARRY_LIMIT := 30.0
const ARENA := 13.0
const SPEED := 4.2

var vp: SubViewport
var world: Node3D
var cam: Camera3D
var atmos: Atmosphere
var player: Node3D
var bear: Node3D
var items: Array = []     # {node, kind, lbs, toxic, pos}
var trees: Array = []     # [Vector3 pos, radius]
var floaters: Array = []  # [Label3D, age]
var rng := RandomNumberGenerator.new()

var time_left := DURATION
var gathered := 0.0
var toxic := 0
var running := false
var move_target := Vector3.INF
var bear_state := "away"   # away / wander / chase / flee
var bear_timer := 14.0
var shout_cd := 0.0
var _t := 0.0
var doy := 150
var kinds: Array = []

var hud_time: Label
var hud_lbs: Label
var hud_msg: Label
var hud_bar: ProgressBar
var end_panel: PanelContainer
var _msg_t := 0.0


func start(day_of_year: int, weather: String, north: float) -> void:
	doy = day_of_year
	rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	world = Node3D.new()
	vp.add_child(world)
	atmos = Atmosphere.new()
	world.add_child(atmos)
	atmos.precip_offset = Vector3(0, 10, 0)
	atmos.setup(14.0, 0.6, 1.4)
	atmos.set_hour(11.5)
	atmos.set_weather("rain" if weather == "storm" else weather)
	cam = Camera3D.new()
	cam.fov = 48
	world.add_child(cam)
	cam.current = true
	_build_clearing(north)
	player = Props.hiker(WorldMap.SHIRTS[0], WorldMap.PACKS[0])
	world.add_child(player)
	atmos.follow = player
	bear = Props.bear(0.75)
	bear.visible = false
	world.add_child(bear)
	_choose_kinds()
	for i in 22:
		_spawn_item(false)
	for i in 6:
		_spawn_item(true)
	_build_hud()
	running = true
	_flash("Gather wild food! Avoid red-capped mushrooms.", 3.5)


# ------------------------------------------------------------------ world

func _build_clearing(north: float) -> void:
	var season := Props.seasons(doy, north)
	var ground_col := Color(0.42, 0.36, 0.26).lerp(Color(0.32, 0.45, 0.22), season.x).lerp(Color(0.5, 0.38, 0.2), season.y * 0.6)
	var g := Props.mi(Props.cyl(ARENA + 6, ARENA + 6, 0.4, 48), Props.mat(ground_col, 1.0), Vector3(0, -0.2, 0))
	world.add_child(g)
	# leaf litter / moss patches
	for i in 80:
		var a := rng.randf() * TAU
		var d := rng.randf() * (ARENA + 4)
		var c := ground_col.lightened(rng.randf_range(-0.1, 0.12))
		world.add_child(Props.mi(Props.cyl(rng.randf_range(0.4, 1.2), rng.randf_range(0.5, 1.3), 0.02, 10), Props.mat(c, 1.0), Vector3(cos(a) * d, 0.01, sin(a) * d)))
	# perimeter forest
	for i in 90:
		var a := rng.randf() * TAU
		var d := rng.randf_range(ARENA + 0.5, ARENA + 6)
		_add_tree(Vector3(cos(a) * d, 0, sin(a) * d), season)
	# a few trees inside the clearing
	for i in 12:
		var a := rng.randf() * TAU
		var d := rng.randf_range(3.0, ARENA - 1.5)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		_add_tree(p, season)
		trees.append([p, 0.55])
	for i in 10:
		var rk := Props.rock(rng.randf_range(0.3, 0.7), rng)
		var a := rng.randf() * TAU
		var d := rng.randf_range(2.0, ARENA - 1)
		rk.position = Vector3(cos(a) * d, 0.05, sin(a) * d)
		world.add_child(rk)
		trees.append([rk.position, 0.6])
	# a stream along one side
	var water := Props.mi(Props.box(Vector3(3.0, 0.1, 40.0)), Props.water_material(), Vector3(ARENA + 1.5, 0.0, 0), Vector3(0, 0.3, 0))
	world.add_child(water)


func _add_tree(p: Vector3, season: Vector2) -> void:
	var h := rng.randf_range(2.2, 3.6)
	var t: Node3D
	if rng.randf() < 0.45:
		t = Props.conifer(h * 1.3, rng)
	else:
		t = Props.deciduous(h, Props.foliage_color(season, rng))
	t.position = p
	t.rotation.y = rng.randf() * TAU
	world.add_child(t)


func _choose_kinds() -> void:
	# [name, lbs, weight, doy_from, doy_to]
	var all := [
		["Wintergreen berries", 0.5, 3.0, 0, 366],
		["Ramps (wild leeks)", 1.0, 5.0, 85, 150],
		["Fiddleheads", 0.8, 4.0, 95, 145],
		["Morels", 0.8, 3.0, 95, 135],
		["Chanterelles", 1.3, 5.0, 165, 275],
		["Blackberries", 2.0, 6.0, 185, 245],
		["Blueberries", 1.6, 6.0, 190, 255],
		["Wild apples", 2.2, 5.0, 240, 310],
		["Hickory nuts", 1.0, 3.0, 255, 320],
	]
	for k in all:
		if doy >= k[3] and doy <= k[4]:
			kinds.append(k)


func _spawn_item(is_toxic: bool) -> void:
	var pos := Vector3.ZERO
	for attempt in 20:
		var a := rng.randf() * TAU
		var d := rng.randf_range(2.0, ARENA - 1.0)
		pos = Vector3(cos(a) * d, 0, sin(a) * d)
		var ok := true
		for t in trees:
			if pos.distance_to(t[0]) < t[1] + 0.6:
				ok = false
		if ok:
			break
	var node: Node3D
	var kind := "Amanita"
	var lbs := 0.0
	if is_toxic:
		node = Props.mushroom(true, 1.6)
	else:
		var total := 0.0
		for k in kinds:
			total += k[2]
		var r := rng.randf() * total
		var pick: Array = kinds[0]
		for k in kinds:
			r -= k[2]
			if r <= 0:
				pick = k
				break
		kind = pick[0]
		lbs = pick[1]
		match kind:
			"Ramps (wild leeks)":
				node = Props.ramps(1.6)
			"Fiddleheads":
				node = Props.ramps(1.4)
				for c in node.get_children():
					(c as MeshInstance3D).material_override = Props.mat(Color(0.45, 0.65, 0.25))
			"Morels":
				node = Props.mushroom(false, 1.5)
				(node.get_child(1) as MeshInstance3D).material_override = Props.mat(Color(0.55, 0.45, 0.3))
			"Chanterelles":
				node = Props.mushroom(false, 1.6)
			"Blackberries":
				node = Props.bush(0.45, Color(0.22, 0.42, 0.2), Color(0.12, 0.05, 0.15))
			"Blueberries":
				node = Props.bush(0.4, Color(0.25, 0.45, 0.25), Color(0.25, 0.3, 0.75))
			"Wild apples":
				node = Node3D.new()
				for i in 4:
					node.add_child(Props.mi(Props.sphere(0.1, 8, 4), Props.mat(Color(0.8, 0.15, 0.1), 0.4), Vector3(rng.randf_range(-0.3, 0.3), 0.1, rng.randf_range(-0.3, 0.3))))
			"Hickory nuts":
				node = Node3D.new()
				for i in 5:
					node.add_child(Props.mi(Props.sphere(0.07, 6, 3), Props.mat(Color(0.5, 0.42, 0.25)), Vector3(rng.randf_range(-0.25, 0.25), 0.07, rng.randf_range(-0.25, 0.25))))
			_:
				node = Props.bush(0.3, Color(0.15, 0.35, 0.2), Color(0.85, 0.1, 0.1))
	node.position = pos
	node.rotation.y = rng.randf() * TAU
	world.add_child(node)
	# a soft glint ring so items are easy to spot
	var ring := Props.mi(Props.cyl(0.5, 0.5, 0.01, 20), Props.mat(Color(1, 0.93, 0.65, 1), 0.6, 0.15), Vector3(0, 0.015, 0))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.transparency = 0.55
	node.add_child(ring)
	items.append({"node": node, "kind": kind, "lbs": lbs, "toxic": is_toxic, "pos": pos})


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	var top := UiTheme.panel(UiTheme.BG, 12, 14)
	top.position = Vector2(20, 20)
	add_child(top)
	var v := UiTheme.vbox(6)
	top.add_child(v)
	v.add_child(UiTheme.caps("Foraging", UiTheme.ACCENT))
	hud_time = UiTheme.label("", 24, UiTheme.TEXT, UiTheme.bold_font())
	v.add_child(hud_time)
	hud_lbs = UiTheme.label("", 18)
	v.add_child(hud_lbs)
	hud_bar = UiTheme.bar(0, UiTheme.GREEN, 10)
	hud_bar.custom_minimum_size = Vector2(220, 10)
	v.add_child(hud_bar)
	var help := UiTheme.panel(UiTheme.BG, 12, 12)
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.position.y -= 20
	add_child(help)
	help.add_child(UiTheme.label("WASD / Arrows or Left-click: move     Space: blow whistle at bears     Esc: head back to camp", 15, UiTheme.DIM))
	hud_msg = UiTheme.label("", 26, UiTheme.TEXT, UiTheme.bold_font())
	hud_msg.add_theme_constant_override("outline_size", 8)
	hud_msg.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	hud_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud_msg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_msg.position.y = 30
	add_child(hud_msg)
	_update_hud()


func _update_hud() -> void:
	hud_time.text = "%d s left" % int(ceil(time_left))
	hud_lbs.text = "%.1f / %d lb gathered" % [gathered, int(CARRY_LIMIT)]
	if toxic > 0:
		hud_lbs.text += "   (%d mystery mushroom%s)" % [toxic, "" if toxic == 1 else "s"]
	hud_bar.value = gathered / CARRY_LIMIT * 100.0


func _flash(text: String, dur := 2.0) -> void:
	hud_msg.text = text
	hud_msg.modulate.a = 1.0
	_msg_t = dur


func _floater(text: String, pos: Vector3, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.008
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = col
	l.outline_size = 10
	l.no_depth_test = true
	l.font = UiTheme.bold_font()
	l.position = pos + Vector3(0, 1.6, 0)
	world.add_child(l)
	floaters.append([l, 0.0])


# ------------------------------------------------------------------ loop

func _unhandled_input(event: InputEvent) -> void:
	if not running:
		if event is InputEventKey and event.pressed and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER):
			_finish()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp := get_local_mouse_position() * (Vector2(vp.size) / size)
		var from := cam.project_ray_origin(mp)
		var dir := cam.project_ray_normal(mp)
		if absf(dir.y) > 0.001:
			var t := -from.y / dir.y
			var hit := from + dir * t
			hit.y = 0
			if hit.length() < ARENA:
				move_target = hit
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_shout()
		elif event.keycode == KEY_ESCAPE:
			time_left = 0.0


func _shout() -> void:
	if shout_cd > 0.0:
		return
	shout_cd = 2.5
	Audio.sfx("whistle", -2.0)
	_floater("HEY BEAR!", player.position, Color(1, 0.9, 0.5))
	if bear.visible and bear.position.distance_to(player.position) < 7.0 and bear_state != "flee":
		bear_state = "flee"
		_flash("The bear turns and lumbers away.", 2.0)


func _process(delta: float) -> void:
	if player == null:
		return
	_t += delta
	_update_floaters(delta)
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t < 0.5:
			hud_msg.modulate.a = maxf(0.0, _msg_t / 0.5)
	cam.position = cam.position.lerp(player.position + Vector3(0, 13.0, 8.5), clampf(delta * 5.0, 0, 1)) if _t > 0.1 else player.position + Vector3(0, 13.0, 8.5)
	cam.look_at(player.position + Vector3(0, 0.5, 0), Vector3.UP)
	if not running:
		return
	time_left -= delta
	shout_cd = maxf(0.0, shout_cd - delta)
	# movement
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if dir != Vector3.ZERO:
		move_target = Vector3.INF
	elif move_target != Vector3.INF:
		var to := move_target - player.position
		to.y = 0
		if to.length() < 0.15:
			move_target = Vector3.INF
		else:
			dir = to
	if dir.length() > 0.0:
		dir = dir.normalized()
		var np := player.position + dir * SPEED * delta
		for t in trees:
			var tp: Vector3 = t[0]
			var off := np - tp
			off.y = 0
			var rr: float = t[1] + 0.3
			if off.length() < rr:
				np = tp + off.normalized() * rr
		if np.length() > ARENA:
			np = np.normalized() * ARENA
		player.position = np
		player.rotation.y = lerp_angle(player.rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 12.0, 0, 1))
		player.position.y = absf(sin(_t * 9.0)) * 0.06
		player.rotation.z = sin(_t * 9.0) * 0.06
	# pick up
	for it in items.duplicate():
		if player.position.distance_to(it["pos"]) < 0.8:
			_collect(it)
	# respawn trickle
	if items.size() < 16 and rng.randf() < delta * 0.8:
		_spawn_item(rng.randf() < 0.22)
	_update_bear(delta)
	if time_left <= 0.0 or gathered >= CARRY_LIMIT:
		time_left = maxf(time_left, 0.0)
		_end()
	_update_hud()


func _collect(it: Dictionary) -> void:
	items.erase(it)
	(it["node"] as Node3D).queue_free()
	if it["toxic"]:
		toxic += 1
		Audio.sfx("toxic", -2.0)
		_floater("?? mushroom", it["pos"], Color(1.0, 0.5, 0.45))
		return
	Audio.sfx("pickup", -3.0, 0.12)
	var add: float = minf(it["lbs"], CARRY_LIMIT - gathered)
	gathered += add
	_floater("+%.1f lb %s" % [add, it["kind"]], it["pos"], Color(0.7, 1.0, 0.6))


func _update_floaters(delta: float) -> void:
	for f in floaters.duplicate():
		f[1] += delta
		var l: Label3D = f[0]
		l.position.y += delta * 1.2
		l.modulate.a = 1.0 - f[1] / 1.4
		if f[1] > 1.4:
			l.queue_free()
			floaters.erase(f)


func _update_bear(delta: float) -> void:
	match bear_state:
		"away":
			bear_timer -= delta
			if bear_timer <= 0.0:
				var a := rng.randf() * TAU
				bear.position = Vector3(cos(a), 0, sin(a)) * (ARENA - 0.5)
				bear.visible = true
				bear_state = "wander"
				bear_timer = 6.0
				_flash("A black bear wanders into the clearing!", 2.5)
				Audio.sfx("bear", -4.0)
		"wander", "chase":
			var to := player.position - bear.position
			to.y = 0
			var d := to.length()
			bear_state = "chase" if d < 6.5 else "wander"
			var spd := 3.4 if bear_state == "chase" else 1.4
			var dir := to.normalized()
			if bear_state == "wander":
				dir = dir.rotated(Vector3.UP, sin(_t * 0.7) * 1.2)
			bear.position += dir * spd * delta
			bear.rotation.y = lerp_angle(bear.rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 6.0, 0, 1))
			if d < 1.1:
				var lost := gathered * 0.4
				gathered -= lost
				bear_state = "flee"
				Audio.sfx("bear", 2.0)
				_flash("The bear knocks you down and runs off with %.1f lb of food!" % lost, 3.0)
		"flee":
			var away := bear.position - player.position
			away.y = 0
			var dir2 := away.normalized()
			bear.position += dir2 * 4.0 * delta
			bear.rotation.y = lerp_angle(bear.rotation.y, atan2(-dir2.x, -dir2.z), clampf(delta * 6.0, 0, 1))
			if bear.position.length() > ARENA + 4:
				bear.visible = false
				bear_state = "away"
				bear_timer = rng.randf_range(10.0, 18.0)


func _end() -> void:
	running = false
	end_panel = UiTheme.panel(UiTheme.BG_SOLID, 16, 24)
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(end_panel)
	var v := UiTheme.vbox(12)
	end_panel.add_child(v)
	v.add_child(UiTheme.title("Back to Camp", 28))
	var t := "You gathered %.1f lb of wild food." % gathered
	if toxic > 0:
		t += "\nYou also picked %d mushroom%s you couldn't quite identify..." % [toxic, "" if toxic == 1 else "s"]
	var l := UiTheme.wrap_label(t, 18)
	l.custom_minimum_size.x = 380
	v.add_child(l)
	v.add_child(UiTheme.button("Continue  [Space]", _finish, true))


func _finish() -> void:
	if end_panel == null:
		return
	end_panel = null
	finished.emit(gathered, toxic)
