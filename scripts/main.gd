extends Node
## Main controller: builds the 3D map and all UI, runs the travel loop and the event queue.

const DAY_SECONDS := 2.3
const IRONITE_GREEN := Color(0.0, 0.231, 0.184)
const IRONITE_MINT := Color(0.816, 0.925, 0.867)
const CHANGELOG_PATH := "res://CHANGELOG.md"
const HOF_PATH := "user://hall_of_fame.json"
const RANDOM_NAMES := ["Alex", "Jordan", "Casey", "Riley", "Morgan", "Avery", "Quinn", "Jamie", "Taylor", "Drew",
	"Emma", "Noah", "Olivia", "Liam", "Ava", "Mateo", "Zoe", "Ezra", "Nora", "Owen"]

var map: WorldMap
var diorama: Diorama
var ui: Control
var hud: Control
var modal_layer: Control
var toast_box: VBoxContainer
var loading: Label
var backdrop: MenuBackdrop

# hud widgets
var lbl_date: Label
var lbl_daynum: Label
var lbl_weather: Label
var lbl_miles: Label
var lbl_next: Label
var lbl_region: Label
var party_box: VBoxContainer
var supply_box: VBoxContainer
var btn_hike: Button
var btn_pace: Button
var btn_rations: Button
var btn_rest: Button
var btn_forage: Button
var btn_town: Button
var progress: TrailProgress

var state := "loading"       # loading, title, setup, idle, walking, modal, forage, end
var auto_travel := false
var queue: Array = []
var modal_open := false
var modal_keys: Dictionary = {}   # keycode -> Callable
var _anim := {}
var forage_game: ForageGame
var hour := 7.5
var _scene_amb := ""
var _in_town := false

# setup wizard state
var setup_prof := 0
var setup_names: Array = []
var setup_start := 1


func _ready() -> void:
	get_window().min_size = Vector2i(1100, 650)
	# every button in the game gets a soft click
	get_tree().node_added.connect(func(n: Node):
		if n is BaseButton:
			(n as BaseButton).pressed.connect(Audio.click))
	ui = Control.new()
	ui.theme = UiTheme.build_theme()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(ui)
	var bg := ColorRect.new()
	bg.color = IRONITE_GREEN
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.name = "LoadingBG"
	ui.add_child(bg)
	var lv := UiTheme.vbox(26)
	lv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	bg.add_child(lv)
	var logo := _ironite_logo(130)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lv.add_child(logo)
	loading = UiTheme.label("presents  ·  Mapping the trail…", 18, IRONITE_MINT.darkened(0.15))
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(loading)
	await get_tree().process_frame
	await get_tree().process_frame
	map = WorldMap.new()
	add_child(map)
	map.build()
	map.atmos.lightning.connect(func(s: float):
		if map.visible:
			Audio.thunder(s))
	diorama = Diorama.new()
	diorama.atmos.lightning.connect(func(s: float):
		if diorama.is_visible_in_tree():
			Audio.thunder(s))
	diorama.custom_minimum_size = Vector2(520, 380)
	var fade := create_tween()
	fade.tween_interval(0.4)
	fade.tween_property(bg, "modulate:a", 0.0, 0.9)
	fade.tween_callback(bg.queue_free)
	ui.move_child(bg, -1)
	backdrop = MenuBackdrop.new()
	ui.add_child(backdrop)
	ui.move_child(backdrop, 0)
	_build_hud()
	modal_layer = Control.new()
	modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(modal_layer)
	ui.move_child.call_deferred(bg, -1)
	show_title()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--brandshots="):
			var drb: Node = load("res://scripts/dev_runner.gd").new()
			add_child(drb)
			drb.run_brand_shots(self, a.substr(13))
		elif a.begins_with("--shots="):
			var dr: Node = load("res://scripts/dev_runner.gd").new()
			add_child(dr)
			dr.run_shots(self, a.substr(8))
		elif a == "--audiocheck":
			var dra: Node = load("res://scripts/dev_runner.gd").new()
			add_child(dra)
			dra.run_audio_check(self)
		elif a.begins_with("--autoplay="):
			var dr3: Node = load("res://scripts/dev_runner.gd").new()
			add_child(dr3)
			dr3.run_autoplay(self, int(a.substr(11)))
		elif a.begins_with("--sim="):
			var dr2: Node = load("res://scripts/dev_runner.gd").new()
			add_child(dr2)
			var parts := a.substr(6).split(":")
			dr2.run_sim(int(parts[0]), parts[1] if parts.size() > 1 else "steady")
			get_tree().quit()


func _exit_tree() -> void:
	if diorama != null and not diorama.is_inside_tree():
		diorama.free()


# ================================================================== helpers

func _doy() -> int:
	var d: Dictionary = Game.date_dict()
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": d["year"], "month": 1, "day": 1, "hour": 12, "minute": 0, "second": 0})
	return int((Game.start_unix + (Game.day - 1) * 86400 - jan1) / 86400) + 1


func _north() -> float:
	return clampf(Game.miles / TrailData.TOTAL_MILES, 0.0, 1.0)


func _scene_opts(extra := {}) -> Dictionary:
	var o := {"hour": clampf(hour, 7.0, 18.0) if hour < 19.5 else hour, "weather": Game.weather, "doy": _doy(),
		"north": _north(), "party": maxi(1, Game.active_count()), "seed": Game.day}
	o.merge(extra, true)
	return o


func _sync_map_env() -> void:
	map.atmos.set_weather(Game.weather)
	map.set_day_of_year(_doy())
	map.set_party_size(maxi(1, Game.active_count()))
	map.set_party_miles(Game.miles)


# ================================================================== title

func show_title() -> void:
	state = "title"
	auto_travel = false
	hud.visible = false
	close_modal()
	map.set_overview(true)
	map.orbit_auto = true
	backdrop.visible = true
	map.visible = false
	map.atmos.set_hour(18.6)
	map.atmos.set_weather("clear")
	map.set_day_of_year(285)
	map.set_campfire(false)
	Audio.music("title")
	Audio.ambience("forest")
	Audio.set_steps(false)
	var root := _modal_root(false)
	var v := UiTheme.vbox(14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(v)
	var t := UiTheme.title("The Appalachian Trail", 64)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 14)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	v.add_child(t)
	var sub := UiTheme.label("A thru-hike from Springer Mountain, Georgia to Mount Katahdin, Maine  ·  2,198 miles", 19, Color(1, 0.95, 0.85))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_constant_override("outline_size", 8)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	v.add_child(sub)
	v.add_child(UiTheme.spacer(false))
	var card := UiTheme.panel(UiTheme.BG, 16, 22)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size.x = 440
	v.add_child(card)
	var cv := UiTheme.vbox(10)
	card.add_child(cv)
	modal_keys.clear()
	if Game.has_save():
		var cb := UiTheme.button("Continue Your Hike  [C]", _continue_game, true)
		cv.add_child(cb)
		var s := UiTheme.label(Game.saved_summary(), 13, UiTheme.DIM)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(s)
		modal_keys[KEY_C] = _continue_game
	cv.add_child(UiTheme.button("Start a New Hike  [N]", start_setup, not Game.has_save()))
	cv.add_child(UiTheme.button("Hall of Fame  [H]", _show_hof))
	cv.add_child(UiTheme.button("How to Play  [?]", _show_help.bind(show_title)))
	cv.add_child(UiTheme.button("Sound Settings  [S]", _show_audio.bind(show_title)))
	modal_keys[KEY_S] = _show_audio.bind(show_title)
	var row := UiTheme.hbox(10)
	var wn := UiTheme.button("What's New  [W]", _show_changelog)
	wn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cr := UiTheme.button("Credits  [K]", _show_credits)
	cr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(wn)
	row.add_child(cr)
	cv.add_child(row)
	modal_keys[KEY_W] = _show_changelog
	modal_keys[KEY_K] = _show_credits
	cv.add_child(UiTheme.button("Quit  [Q]", func(): get_tree().quit()))
	modal_keys[KEY_N] = start_setup
	modal_keys[KEY_H] = _show_hof
	modal_keys[KEY_SLASH] = _show_help.bind(show_title)
	modal_keys[KEY_Q] = func(): get_tree().quit()
	var foot := UiTheme.hbox(14)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	foot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.position.y -= 18
	var flogo := _ironite_logo(30)
	flogo.modulate = Color(1, 1, 1, 0.85)
	foot.add_child(flogo)
	var ftxt := UiTheme.label("v%s  ·  © 2026 Ironite  ·  Built with Godot" % _version(), 13, Color(1, 1, 1, 0.7))
	ftxt.add_theme_constant_override("outline_size", 6)
	ftxt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	foot.add_child(ftxt)
	root.add_child(foot)


func _continue_game() -> void:
	if not Game.load_game():
		_toast("Couldn't read the save file.")
		return
	_enter_trail()
	_toast("Welcome back to the trail — %s." % Game.date_string())


func _enter_trail() -> void:
	close_modal()
	state = "idle"
	backdrop.visible = false
	map.visible = true
	map.orbit_auto = false
	map.set_overview(false)
	map.cam_yaw = 0.35
	map.cam_pitch = 0.75
	hour = 7.5
	map.atmos.set_hour(hour)
	map.set_campfire(false)
	_sync_map_env()
	hud.visible = true
	refresh_hud()


# ================================================================== modal plumbing

func _modal_root(dim := true) -> Control:
	close_modal()
	modal_open = true
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP if dim else Control.MOUSE_FILTER_IGNORE
	modal_layer.add_child(root)
	if dim:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.45)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(shade)
	return root


func close_modal() -> void:
	modal_open = false
	_scene_amb = ""
	_in_town = false
	modal_keys.clear()
	if diorama != null and diorama.get_parent() != null:
		diorama.get_parent().remove_child(diorama)
	if modal_layer != null:
		UiTheme.clear(modal_layer)


func _centered_panel(root: Control, min_size: Vector2) -> PanelContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var p := UiTheme.panel(UiTheme.BG_SOLID, 18, 22)
	p.custom_minimum_size = min_size
	center.add_child(p)
	return p


## A scene card: diorama on the left, text and buttons on the right.
## choices: Array of [label, Callable]
func show_scene_card(kicker: String, title: String, text: String, scene: String, choices: Array, opts := {}) -> void:
	var root := _modal_root()
	_scene_sfx(opts.get("sfx", scene), text)
	match scene:
		"river":
			_scene_amb = "river"
		"storm":
			_scene_amb = "storm"
		"camp":
			_scene_amb = "night"
		"town":
			_scene_amb = "town"
	var p := _centered_panel(root, Vector2(1080, 470))
	var h := UiTheme.hbox(22)
	p.add_child(h)
	var dframe := UiTheme.panel(Color(0, 0, 0, 0.3), 14, 0)
	dframe.clip_contents = true
	h.add_child(dframe)
	diorama.custom_minimum_size = Vector2(540, 430)
	dframe.add_child(diorama)
	diorama.show_scene(scene, _scene_opts(opts))
	var v := UiTheme.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size.x = 440
	h.add_child(v)
	v.add_child(UiTheme.caps(kicker, UiTheme.ACCENT))
	var t := UiTheme.title(title, 30)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	v.add_child(UiTheme.separator())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := UiTheme.wrap_label(text, 18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var bv := UiTheme.vbox(8)
	v.add_child(bv)
	modal_keys.clear()
	for i in choices.size():
		var c: Array = choices[i]
		var label: String = c[0]
		var cb: Callable = c[1]
		var key_label := "%d.  " % (i + 1) if choices.size() > 1 else ""
		var hint := "" if choices.size() > 1 else "   [Space]"
		var b := UiTheme.button(key_label + label + hint, cb, choices.size() == 1)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bv.add_child(b)
		modal_keys[KEY_1 + i] = cb
		modal_keys[KEY_KP_1 + i] = cb
		if choices.size() == 1:
			modal_keys[KEY_SPACE] = cb
			modal_keys[KEY_ENTER] = cb
			modal_keys[KEY_KP_ENTER] = cb


func _kicker() -> String:
	return "%s  ·  Mile %d  ·  %s" % [Game.date_string(), int(Game.miles), TrailData.state_at(Game.miles)]


# ================================================================== setup wizard

func start_setup() -> void:
	state = "setup"
	Audio.music("title")
	Audio.set_steps(false)
	setup_names = []
	_setup_profession()


func _wizard(step: int, title: String, sub: String) -> VBoxContainer:
	var root := _modal_root()
	var p := _centered_panel(root, Vector2(820, 0))
	var v := UiTheme.vbox(14)
	p.add_child(v)
	v.add_child(UiTheme.caps("New hike  ·  step %d of 4" % step, UiTheme.ACCENT))
	v.add_child(UiTheme.title(title, 32))
	if sub != "":
		v.add_child(UiTheme.wrap_label(sub, 16, UiTheme.DIM))
	v.add_child(UiTheme.separator())
	return v


func _setup_profession() -> void:
	var v := _wizard(1, "Who are you?", "Your job back home sets your trail budget. Tighter budgets earn bigger score multipliers.")
	for i in Game.PROFESSIONS.size():
		var pr: Dictionary = Game.PROFESSIONS[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 74)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%d.  %s — %s\n      $%s per hiker.  %s" % [i + 1, pr["name"], pr["sub"], _money_str(pr["money"]), pr["desc"]]
		var cb := func():
			setup_prof = i
			_setup_names()
		b.pressed.connect(cb)
		v.add_child(b)
		modal_keys[KEY_1 + i] = cb
	var back := UiTheme.button("Back  [Esc]", show_title)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(back)
	modal_keys[KEY_ESCAPE] = show_title


func _setup_names() -> void:
	var v := _wizard(2, "Your hiking party", "Name up to four hikers. You'll earn trail names along the way.")
	var edits: Array = []
	for i in 4:
		var row := UiTheme.hbox(10)
		v.add_child(row)
		var l := UiTheme.label("Hiker %d%s" % [i + 1, " (you)" if i == 0 else ""], 16, UiTheme.DIM)
		l.custom_minimum_size.x = 120
		row.add_child(l)
		var e := LineEdit.new()
		e.max_length = 14
		e.placeholder_text = "Leave blank to hike with fewer" if i > 0 else "Your name"
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i < setup_names.size():
			e.text = setup_names[i]
		row.add_child(e)
		edits.append(e)
	var err := UiTheme.label("", 15, UiTheme.RED)
	v.add_child(err)
	var row2 := UiTheme.hbox(10)
	v.add_child(row2)
	row2.add_child(UiTheme.button("Back", _setup_profession))
	row2.add_child(UiTheme.button("Random names", func():
		var pool := RANDOM_NAMES.duplicate()
		pool.shuffle()
		for i in 4:
			edits[i].text = pool[i]
	))
	row2.add_child(UiTheme.spacer())
	var go := func():
		var names: Array = []
		for e in edits:
			var t: String = e.text.strip_edges()
			if t != "":
				names.append(t)
		if names.is_empty():
			err.text = "Enter at least one name."
			return
		setup_names = names
		_setup_start()
	row2.add_child(UiTheme.button("Next  [Enter]", go, true))
	modal_keys[KEY_ENTER] = go
	modal_keys[KEY_KP_ENTER] = go
	edits[0].call_deferred("grab_focus")
	for e in edits:
		e.text_submitted.connect(func(_t): go.call())


func _setup_start() -> void:
	var v := _wizard(3, "When do you start?", "Baxter State Park closes Katahdin on October 15. Start too late and you won't make it; start too early and you'll face snow.")
	for i in Game.START_DATES.size():
		var sd: Dictionary = Game.START_DATES[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 60)
		b.text = "%d.  %s\n      %s" % [i + 1, sd["label"], sd["note"]]
		var cb := func():
			setup_start = i
			Game.new_game(setup_prof, setup_names, setup_start)
			_setup_store()
		b.pressed.connect(cb)
		v.add_child(b)
		modal_keys[KEY_1 + i] = cb
	var back := UiTheme.button("Back  [Esc]", _setup_names)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(back)
	modal_keys[KEY_ESCAPE] = _setup_names


func _setup_store() -> void:
	var n := Game.active_count()
	var tip := "Tip: you need about %d lb of food per day on full rations. Neel Gap is 31 miles away (≈3 days), Hiawassee is 69. Each hiker needs a pair of spare shoes every 500 miles, and ~3 L of water capacity." % int(2 * n)
	open_store("Gear up in Dahlonega", "The outfitter in town before the approach trail. " + tip, func():
		Game.supplies["water"] = Game.supplies["water_cap"]
		_enter_trail()
		var lm: Dictionary = TrailData.LANDMARKS[0]
		_queue_push({"type": "message", "title": "Springer Mountain", "text": lm["desc"] + "\n\nYou sign the trail register, take a photo by the plaque, and look north. Good luck!", "scene": "summit"})
		_process_queue(), 4)


# ================================================================== store

func open_store(title: String, sub: String, on_done: Callable, step := 0) -> void:
	var cart := {}
	for k in Game.STORE_ITEMS:
		cart[k] = 0
	var root := _modal_root()
	var p := _centered_panel(root, Vector2(900, 0))
	var v := UiTheme.vbox(12)
	p.add_child(v)
	if step > 0:
		v.add_child(UiTheme.caps("New hike  ·  step %d of 4" % step, UiTheme.ACCENT))
	else:
		v.add_child(UiTheme.caps("General store  ·  " + TrailData.LANDMARKS[Game.at_landmark]["name"], UiTheme.ACCENT))
	v.add_child(UiTheme.title(title, 30))
	v.add_child(UiTheme.wrap_label(sub, 15, UiTheme.DIM))
	v.add_child(UiTheme.separator())
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for hdr in ["Item", "Price", "You have", "Buy", ""]:
		grid.add_child(UiTheme.caps(hdr))
	var total_lbl := UiTheme.label("", 20, UiTheme.TEXT, UiTheme.bold_font())
	var money_lbl := UiTheme.label("", 16, UiTheme.DIM)
	var qty_labels := {}
	var update := func():
		var total := 0.0
		for k in cart:
			total += cart[k] * Game.store_price(k)
			var it: Dictionary = Game.STORE_ITEMS[k]
			qty_labels[k].text = "%d %s" % [cart[k], it["unit"]] if cart[k] > 0 else "—"
		total_lbl.text = "Total: $%s" % _money_str(total)
		total_lbl.add_theme_color_override("font_color", UiTheme.RED if total > Game.money + 0.001 else UiTheme.TEXT)
		money_lbl.text = "Cash on hand: $%s   ·   after purchase: $%s" % [_money_str(Game.money), _money_str(Game.money - total)]
	for k in Game.STORE_ITEMS:
		var it: Dictionary = Game.STORE_ITEMS[k]
		var name_box := UiTheme.vbox(0)
		name_box.add_child(UiTheme.label(it["name"], 17, UiTheme.TEXT, UiTheme.bold_font()))
		var d := UiTheme.wrap_label(it["desc"], 13, UiTheme.DIM)
		d.custom_minimum_size.x = 340
		name_box.add_child(d)
		grid.add_child(name_box)
		grid.add_child(UiTheme.label("$%s / %s" % [_money_str(Game.store_price(k)), it["unit"].split(" ")[0]], 15))
		var have := ""
		match k:
			"food":
				have = "%d lb" % int(Game.supplies["food"])
			"water_cap":
				have = "%d L" % int(Game.supplies["water_cap"])
			_:
				have = str(int(Game.supplies[k]))
		grid.add_child(UiTheme.label(have, 15, UiTheme.DIM))
		var ql := UiTheme.label("—", 16)
		ql.custom_minimum_size.x = 120
		qty_labels[k] = ql
		grid.add_child(ql)
		var pm := UiTheme.hbox(6)
		var step_n: int = it["step"]
		pm.add_child(UiTheme.button(" − ", func():
			cart[k] = max(0, cart[k] - step_n)
			update.call()))
		pm.add_child(UiTheme.button(" + ", func():
			cart[k] += step_n
			update.call()))
		grid.add_child(pm)
	v.add_child(UiTheme.separator())
	var foot := UiTheme.hbox(12)
	v.add_child(foot)
	var fv := UiTheme.vbox(2)
	fv.add_child(total_lbl)
	fv.add_child(money_lbl)
	foot.add_child(fv)
	foot.add_child(UiTheme.spacer())
	var err := UiTheme.label("", 14, UiTheme.RED)
	var done := func():
		var total := 0.0
		for k in cart:
			total += cart[k] * Game.store_price(k)
		if total > Game.money + 0.001:
			err.text = "You can't afford all that."
			return
		for k in cart:
			if cart[k] > 0:
				Game.buy(k, cart[k])
		if total > 0:
			Game.log_entry("Bought supplies for $%s." % _money_str(total))
			Audio.sfx("coin")
		on_done.call()
	foot.add_child(err)
	if step == 0:
		foot.add_child(UiTheme.button("Cancel  [Esc]", on_done))
		modal_keys[KEY_ESCAPE] = on_done
	foot.add_child(UiTheme.button("Buy & Continue  [Enter]" if step == 0 else "Begin the hike  [Enter]", done, true))
	modal_keys[KEY_ENTER] = done
	modal_keys[KEY_KP_ENTER] = done
	update.call()


func _money_str(v: float) -> String:
	var neg := v < 0
	var s := str(int(round(absf(v))))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if neg else "") + out


# ================================================================== HUD

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	hud.add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	# ---- top bar
	var top := UiTheme.panel(UiTheme.BG, 14, 12)
	col.add_child(top)
	var th := UiTheme.hbox(28)
	top.add_child(th)
	var dv := UiTheme.vbox(0)
	lbl_date = UiTheme.label("", 22, UiTheme.TEXT, UiTheme.title_font())
	lbl_daynum = UiTheme.label("", 13, UiTheme.DIM)
	dv.add_child(lbl_date)
	dv.add_child(lbl_daynum)
	th.add_child(dv)
	lbl_weather = _top_stat(th, "Weather")
	lbl_miles = _top_stat(th, "Miles hiked")
	lbl_next = _top_stat(th, "Next stop")
	th.add_child(UiTheme.spacer())
	lbl_region = _top_stat(th, "Section")
	lbl_region.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# ---- middle: party (left), toasts (center), supplies (right)
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(mid)
	var pp := UiTheme.panel(UiTheme.BG, 14, 14)
	pp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pp.custom_minimum_size.x = 300
	mid.add_child(pp)
	var ppv := UiTheme.vbox(10)
	pp.add_child(ppv)
	ppv.add_child(UiTheme.caps("Party"))
	party_box = UiTheme.vbox(12)
	ppv.add_child(party_box)
	var cmid := Control.new()
	cmid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(cmid)
	toast_box = UiTheme.vbox(8)
	toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.custom_minimum_size.x = 520
	cmid.add_child(toast_box)
	var sp := UiTheme.panel(UiTheme.BG, 14, 14)
	sp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	sp.custom_minimum_size.x = 270
	mid.add_child(sp)
	var spv := UiTheme.vbox(10)
	sp.add_child(spv)
	spv.add_child(UiTheme.caps("Supplies"))
	supply_box = UiTheme.vbox(7)
	spv.add_child(supply_box)

	# ---- bottom: progress strip and action bar
	var bottom := UiTheme.panel(UiTheme.BG, 14, 12)
	col.add_child(bottom)
	var bv := UiTheme.vbox(8)
	bottom.add_child(bv)
	progress = TrailProgress.new()
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bv.add_child(progress)
	var bar := UiTheme.hbox(8)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_child(bar)
	btn_hike = UiTheme.button("Hike On  [Space]", toggle_travel, true)
	btn_hike.custom_minimum_size.x = 210
	bar.add_child(btn_hike)
	btn_pace = UiTheme.button("", cycle_pace)
	btn_pace.tooltip_text = "Slow: ~10 mi/day, easier on the body.\nSteady: ~15 mi/day.\nPush: ~20 mi/day, but hunger, injuries and exhaustion add up."
	bar.add_child(btn_pace)
	btn_rations = UiTheme.button("", cycle_rations)
	btn_rations.tooltip_text = "Full: 2 lb/person/day.\nHalf: 1.3 lb — hunger slowly builds.\nBare: 0.8 lb — hunger builds fast and health suffers."
	bar.add_child(btn_rations)
	btn_rest = UiTheme.button("Rest  [R]", do_rest)
	btn_rest.tooltip_text = "Take a zero day: heal, recover morale. Uses food."
	bar.add_child(btn_rest)
	btn_forage = UiTheme.button("Forage  [F]", do_forage)
	btn_forage.tooltip_text = "Spend the day gathering wild food (minigame)."
	bar.add_child(btn_forage)
	btn_town = UiTheme.button("Town  [T]", func(): open_town(Game.at_landmark))
	bar.add_child(btn_town)
	bar.add_child(UiTheme.button("Journal  [J]", show_journal))
	bar.add_child(UiTheme.button("Map  [M]", toggle_overview))
	bar.add_child(UiTheme.button("Menu  [Esc]", show_pause))


func _top_stat(parent: Control, caption: String) -> Label:
	var v := UiTheme.vbox(0)
	v.add_child(UiTheme.caps(caption))
	var l := UiTheme.label("", 17)
	v.add_child(l)
	parent.add_child(v)
	return l


func refresh_hud() -> void:
	if hud == null:
		return
	lbl_date.text = Game.date_string()
	var tod := "Morning" if hour < 11 else ("Midday" if hour < 16 else ("Evening" if hour < 20.5 else "Night"))
	lbl_daynum.text = "Day %d on the trail  ·  %s" % [Game.day, tod]
	lbl_weather.text = "%s  ·  %d°F" % [Game.weather_label(), int(Game.temperature)]
	lbl_miles.text = "%s of %s" % [_money_str(Game.miles), _money_str(TrailData.TOTAL_MILES)]
	var nl: Dictionary = Game.next_landmark_data()
	if Game.miles >= TrailData.TOTAL_MILES - 0.01:
		lbl_next.text = "Katahdin!"
	else:
		lbl_next.text = "%s  ·  %.0f mi" % [nl["name"], Game.miles_to_next()]
	lbl_region.text = "%s  ·  %s" % [TrailData.region_label(Game.miles), TrailData.state_at(Game.miles)]
	# party
	UiTheme.clear(party_box)
	for m in Game.party:
		var card := UiTheme.vbox(4)
		party_box.add_child(card)
		var nm := UiTheme.label(Game.display_name(m), 16, UiTheme.TEXT if m["active"] else UiTheme.DIM, UiTheme.bold_font())
		card.add_child(nm)
		if not m["active"]:
			card.add_child(UiTheme.label(m["left_reason"], 13, UiTheme.RED))
			continue
		var conds: Array = []
		for c in m["conditions"]:
			conds.append(Game.CONDITIONS[c["id"]]["name"])
		var status := "Healthy" if conds.is_empty() else ", ".join(conds).capitalize()
		card.add_child(UiTheme.label(status, 13, UiTheme.GREEN if conds.is_empty() else UiTheme.YELLOW))
		card.add_child(_stat_row("Health", m["health"], false))
		card.add_child(_stat_row("Morale", m["morale"], false))
		card.add_child(_stat_row("Fed", 100.0 - m["hunger"], false))
	# supplies
	UiTheme.clear(supply_box)
	var s: Dictionary = Game.supplies
	var fd: float = Game.food_days()
	_supply_row("Food", "%d lb  (%.1f days)" % [int(s["food"]), fd], UiTheme.RED if fd < 2 else (UiTheme.YELLOW if fd < 4 else UiTheme.TEXT))
	_supply_row("Water", "%.0f / %.0f L" % [s["water"], s["water_cap"]], UiTheme.TEXT)
	_supply_row("Stove fuel", "%d canister%s" % [s["fuel"], "" if s["fuel"] == 1 else "s"], UiTheme.YELLOW if s["fuel"] == 0 else UiTheme.TEXT)
	_supply_row("First-aid kits", str(s["first_aid"]), UiTheme.YELLOW if s["first_aid"] == 0 else UiTheme.TEXT)
	_supply_row("Spare shoes", "%d pair%s" % [s["shoes"], "" if s["shoes"] == 1 else "s"], UiTheme.TEXT)
	var wear := clampf(Game.shoe_miles / 500.0 * 100.0, 0, 100)
	supply_box.add_child(_stat_row("Shoe life", 100.0 - wear, false))
	supply_box.add_child(_stat_row("Gear", Game.gear, false))
	supply_box.add_child(UiTheme.separator())
	_supply_row("Cash", "$" + _money_str(Game.money), UiTheme.ACCENT)
	# buttons
	btn_pace.text = "Pace: %s  [P]" % Game.PACE_NAMES[Game.pace]
	btn_rations.text = "Rations: %s  [U]" % Game.RATION_NAMES[Game.rations]
	btn_hike.text = "Stop  [Space]" if auto_travel else "Hike On  [Space]"
	var lm: Dictionary = TrailData.LANDMARKS[Game.at_landmark]
	btn_town.visible = lm["type"] == "town" and absf(Game.miles - lm["mile"]) < 0.01
	progress.set_miles(Game.miles)


func _stat_row(caption: String, v: float, invert: bool) -> HBoxContainer:
	var h := UiTheme.hbox(8)
	var l := UiTheme.label(caption, 13, UiTheme.DIM)
	l.custom_minimum_size.x = 70
	h.add_child(l)
	var b := UiTheme.bar(v, UiTheme.stat_color(v, invert), 8)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	var n := UiTheme.label("%d" % int(v), 12, UiTheme.DIM)
	n.custom_minimum_size.x = 26
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(n)
	return h


func _supply_row(caption: String, value: String, col: Color) -> void:
	var h := UiTheme.hbox(8)
	h.add_child(UiTheme.label(caption, 14, UiTheme.DIM))
	h.add_child(UiTheme.spacer())
	h.add_child(UiTheme.label(value, 14, col, UiTheme.bold_font()))
	supply_box.add_child(h)


func _toast(text: String, col := UiTheme.TEXT) -> void:
	if toast_box == null:
		return
	var p := UiTheme.panel(Color(0.06, 0.08, 0.07, 0.92), 10, 10)
	var l := UiTheme.wrap_label(text, 15, col)
	l.custom_minimum_size.x = 480
	p.add_child(l)
	toast_box.add_child(p)
	while toast_box.get_child_count() > 4:
		toast_box.get_child(0).free()
	var tw := p.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


# ================================================================== actions

func cycle_pace() -> void:
	Game.pace = (Game.pace + 1) % 3
	refresh_hud()


func cycle_rations() -> void:
	Game.rations = (Game.rations + 1) % 3
	refresh_hud()


func toggle_overview() -> void:
	map.set_overview(not map.overview)


func toggle_travel() -> void:
	if state == "walking":
		auto_travel = false
		refresh_hud()
		return
	if state != "idle":
		return
	auto_travel = true
	_start_day("hike")


func do_rest() -> void:
	if state != "idle":
		return
	auto_travel = false
	_start_day("rest")


func _start_day(mode: String) -> void:
	if Game.finished or Game.game_over_reason != "":
		return
	var from: float = Game.miles
	var res: Dictionary = Game.advance_day(mode)
	_anim = {"t": 0.0, "from": from, "to": Game.miles, "res": res, "mode": mode}
	state = "walking"
	map.walking = mode == "hike"
	map.set_campfire(false)
	map.atmos.set_weather(Game.weather)
	map.set_day_of_year(_doy())
	refresh_hud()


func _process(delta: float) -> void:
	_update_audio()
	_credits_tick(delta)
	if state == "walking":
		_anim["t"] += delta
		var ph: float = _anim["t"] / DAY_SECONDS
		if _anim["mode"] == "rest":
			ph = minf(ph * 1.3, 1.0)
		var walk_ph := clampf(ph / 0.68, 0.0, 1.0)
		var e := walk_ph * walk_ph * (3.0 - 2.0 * walk_ph)
		map.set_party_miles(lerpf(_anim["from"], _anim["to"], e))
		# 6:00 -> 20:00 while walking, then night until 6:00 the next morning
		if ph < 0.68:
			hour = 6.5 + walk_ph * 13.5
		else:
			hour = 20.0 + (ph - 0.68) / 0.32 * 10.5
		map.atmos.set_hour(hour)
		map.set_campfire(ph > 0.7 and ph < 0.97)
		map.walking = ph < 0.68 and _anim["mode"] == "hike"
		if ph >= 1.0:
			hour = 6.5
			map.atmos.set_hour(hour)
			map.walking = false
			map.set_campfire(false)
			_finish_day(_anim["res"])
	elif state == "idle" and hour < 8.5:
		hour = minf(8.5, hour + delta * 0.6)
		map.atmos.set_hour(hour)


func _finish_day(res: Dictionary) -> void:
	state = "idle"
	map.set_party_size(maxi(1, Game.active_count()))
	map.set_party_miles(Game.miles)
	refresh_hud()
	for msg in res.get("messages", []):
		if msg.get("major", false):
			_queue_push({"type": "message", "title": msg.get("title", "On the Trail"), "text": msg["text"], "scene": msg.get("scene", "forest")})
		else:
			_toast(msg["text"])
	if not res.get("choice", {}).is_empty():
		_queue_push({"type": "choice", "ev": res["choice"]})
	if res.get("arrived", -1) != -1:
		_queue_push({"type": "arrival", "idx": res["arrived"]})
	if Game.game_over_reason != "":
		_queue_push({"type": "gameover"})
	else:
		Game.save_game()
	_low_supply_warnings()
	_process_queue()


func _low_supply_warnings() -> void:
	if Game.active_count() == 0 or Game.game_over_reason != "":
		return
	var stop := false
	if Game.supplies["food"] <= 0.0:
		_toast("You're out of food! Forage, cut rations, or push hard for the next town.", UiTheme.RED)
		stop = not Game.flags.get("warned_nofood", false)
		Game.flags["warned_nofood"] = true
	elif Game.food_days() < 2.0:
		_toast("Food is running low — about %.1f days left." % Game.food_days(), UiTheme.YELLOW)
		stop = not Game.flags.get("warned_lowfood", false)
		Game.flags["warned_lowfood"] = true
	else:
		Game.flags["warned_lowfood"] = false
		Game.flags["warned_nofood"] = false
	if Game.gear < 20.0 and not Game.flags.get("warned_gear", false):
		Game.flags["warned_gear"] = true
		stop = true
		_toast("Your gear is falling apart. An outfitter in the next town can replace it.", UiTheme.YELLOW)
	elif Game.gear >= 20.0:
		Game.flags["warned_gear"] = false
	for m in Game.active_members():
		if m["health"] < 25.0 and not m.get("warned", false):
			m["warned"] = true
			stop = true
			_toast("%s is in very poor health. Consider resting." % Game.short_name(m), UiTheme.RED)
		elif m["health"] >= 40.0:
			m["warned"] = false
	if stop and auto_travel:
		auto_travel = false
		_toast("Stopped hiking so you can decide what to do.", UiTheme.DIM)


func _queue_push(item: Dictionary) -> void:
	queue.append(item)


func _process_queue() -> void:
	close_modal()
	if Game.game_over_reason != "" and not queue.any(func(q): return q["type"] == "gameover"):
		queue.append({"type": "gameover"})
	if queue.is_empty():
		state = "idle"
		refresh_hud()
		if auto_travel:
			_start_day("hike")
		return
	var item: Dictionary = queue.pop_front()
	state = "modal"
	match item["type"]:
		"message":
			auto_travel = false
			show_scene_card(_kicker(), item["title"], item["text"], item.get("scene", "forest"), [["Continue", _process_queue]], item.get("opts", {}))
		"choice":
			auto_travel = false
			_show_choice(item["ev"])
		"arrival":
			auto_travel = false
			_arrive(item["idx"])
		"gameover":
			queue.clear()
			show_game_over()
		"town":
			open_town(item["idx"])
	refresh_hud()


func _show_choice(ev: Dictionary) -> void:
	var choices: Array = []
	for i in ev["choices"].size():
		var idx: int = i
		choices.append([ev["choices"][i], func():
			var out: Dictionary = Game.events.resolve(ev, idx)
			map.set_party_size(maxi(1, Game.active_count()))
			map.set_party_miles(Game.miles)
			refresh_hud()
			if out.get("text", "") != "":
				queue.push_front({"type": "message", "title": out.get("title", ev["title"]), "text": out["text"], "scene": out.get("scene", ev["scene"])})
			_process_queue()])
	show_scene_card(_kicker(), ev["title"], ev["text"], ev.get("scene", "forest"), choices)


func _arrive(idx: int) -> void:
	var lm: Dictionary = TrailData.LANDMARKS[idx]
	if lm["type"] == "finish":
		Game.finished = true
		show_victory()
		return
	var ev: Dictionary = Game.events.landmark_event(idx)
	Audio.sfx("arrive", -2.0, 0.0)
	if lm["type"] == "town":
		queue.push_front({"type": "town", "idx": idx})
	if ev.is_empty():
		if lm["type"] == "town":
			_process_queue()
			return
		ev = {"title": lm["name"], "text": lm["desc"], "scene": "vista"}
	if ev.has("choices"):
		_show_choice(ev)
	else:
		show_scene_card("Mile %d  ·  %s" % [int(lm["mile"]), lm["state"]], ev["title"], ev["text"], ev.get("scene", "vista"), [["Continue", _process_queue]])
	Game.save_game()


# ================================================================== town

func open_town(idx: int, info := "") -> void:
	auto_travel = false
	state = "modal"
	Audio.music("town")
	var lm: Dictionary = TrailData.LANDMARKS[idx]
	var root := _modal_root()
	var p := _centered_panel(root, Vector2(1120, 520))
	var h := UiTheme.hbox(22)
	p.add_child(h)
	var dframe := UiTheme.panel(Color(0, 0, 0, 0.3), 14, 0)
	dframe.clip_contents = true
	h.add_child(dframe)
	diorama.custom_minimum_size = Vector2(500, 480)
	dframe.add_child(diorama)
	diorama.show_scene("town", _scene_opts({"hour": 15.0, "seed": idx}))
	_in_town = true
	var v := UiTheme.vbox(9)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size.x = 520
	h.add_child(v)
	v.add_child(UiTheme.caps("Trail town  ·  Mile %d  ·  %s  ·  %s" % [int(lm["mile"]), lm["state"], Game.date_string()], UiTheme.ACCENT))
	v.add_child(UiTheme.title(lm["name"], 32))
	v.add_child(UiTheme.wrap_label(lm["desc"], 16, UiTheme.DIM))
	var mult: float = lm.get("store", 1.0)
	var price_note := "Prices here are about average."
	if mult >= 1.2:
		price_note = "Prices here are steep — it's a long way from a supermarket."
	elif mult < 1.0:
		price_note = "Prices here are cheap."
	v.add_child(UiTheme.label(price_note + "   Cash: $" + _money_str(Game.money), 14, UiTheme.TEXT))
	v.add_child(UiTheme.separator())
	var n := Game.active_count()
	var opts := [
		["Buy supplies at the general store", func(): open_store("Resupply", "Stock up for the next stretch. Next town: %s." % _next_town_note(idx), func(): open_town(idx))],
		["Stay at the hostel — zero day ($%d)" % (35 * n), func():
			var m0: float = Game.money
			var msg: String = Game.town_service("hostel")
			if Game.money < m0:
				Audio.sfx("coin")
			open_town(idx, msg)],
		["Eat at the diner ($%d)" % (22 * n), func():
			var m1: float = Game.money
			var msg2: String = Game.town_service("meal")
			if Game.money < m1:
				Audio.sfx("coin")
			open_town(idx, msg2)],
		["Outfitter: repair/replace worn gear ($%d)" % int(Game.gear_repair_cost()), func():
			var ok := Game.repair_gear()
			if ok:
				Audio.sfx("coin")
			open_town(idx, "The outfitter swaps your broken gear for new. Gear restored to 100%." if ok else "You can't afford that (or your gear is fine).")],
		["Talk to other hikers", func():
			var c: Array = Game.chatter()
			open_town(idx, "%s says: \"%s\"" % [c[0], c[1]])],
		["Return to the trail", _leave_town],
	]
	modal_keys.clear()
	for i in opts.size():
		var b := UiTheme.button("%d.  %s" % [i + 1, opts[i][0]], opts[i][1], i == opts.size() - 1)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)
		modal_keys[KEY_1 + i] = opts[i][1]
		modal_keys[KEY_KP_1 + i] = opts[i][1]
	modal_keys[KEY_ESCAPE] = _leave_town
	if info != "":
		var ip := UiTheme.panel(Color(0.2, 0.17, 0.1, 0.9), 10, 12)
		ip.add_child(UiTheme.wrap_label(info, 15, Color(1, 0.93, 0.8)))
		v.add_child(ip)
	refresh_hud()
	if Game.game_over_reason != "":
		_queue_push({"type": "gameover"})
		_process_queue()


func _next_town_note(idx: int) -> String:
	for j in range(idx + 1, TrailData.LANDMARKS.size()):
		var l: Dictionary = TrailData.LANDMARKS[j]
		if l["type"] == "town":
			return "%s, %d miles ahead" % [l["name"], int(l["mile"] - TrailData.LANDMARKS[idx]["mile"])]
	return "none — this is the last one"


func _leave_town() -> void:
	Game.supplies["water"] = Game.supplies["water_cap"]
	Game.save_game()
	_process_queue()


# ================================================================== forage

func do_forage() -> void:
	if state != "idle":
		return
	auto_travel = false
	state = "forage"
	hud.visible = false
	map.input_enabled = false
	map.visible = false
	Audio.music("forage")
	Audio.ambience("forest")
	Audio.set_steps(false)
	forage_game = ForageGame.new()
	ui.add_child(forage_game)
	ui.move_child(forage_game, 0)
	forage_game.start(_doy(), Game.weather, _north())
	forage_game.finished.connect(_forage_done)


func _forage_done(lbs: float, toxic: int) -> void:
	forage_game.queue_free()
	forage_game = null
	map.visible = true
	map.input_enabled = true
	hud.visible = true
	var res: Dictionary = Game.apply_forage(lbs, toxic)
	_sync_map_env()
	hour = 6.5
	state = "idle"
	_queue_push({"type": "message", "title": "A Day of Foraging", "text": res.get("forage_text", ""), "scene": "forest"})
	_finish_day(res)


# ================================================================== journal / pause / help

func show_journal() -> void:
	if state != "idle":
		return
	Audio.sfx("page")
	state = "modal"
	var root := _modal_root()
	var p := _centered_panel(root, Vector2(760, 560))
	var v := UiTheme.vbox(10)
	p.add_child(v)
	v.add_child(UiTheme.caps("Trail journal", UiTheme.ACCENT))
	v.add_child(UiTheme.title("%s's Journal" % Game.party[0]["name"], 30))
	v.add_child(UiTheme.separator())
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size.y = 400
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := UiTheme.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var entries: Array = Game.journal.duplicate()
	entries.reverse()
	for e in entries.slice(0, 250):
		var row := UiTheme.hbox(14)
		var d := UiTheme.label("%s · mi %d" % [e["date"], int(e["miles"])], 13, UiTheme.ACCENT)
		d.custom_minimum_size.x = 120
		row.add_child(d)
		var t := UiTheme.wrap_label(e["text"], 15)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		list.add_child(row)
	var close := func():
		close_modal()
		state = "idle"
	var b := UiTheme.button("Close  [J]", close, true)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(b)
	modal_keys[KEY_J] = close
	modal_keys[KEY_ESCAPE] = close


func show_pause() -> void:
	if state != "idle":
		return
	state = "modal"
	var root := _modal_root()
	var p := _centered_panel(root, Vector2(420, 0))
	var v := UiTheme.vbox(10)
	p.add_child(v)
	v.add_child(UiTheme.title("Paused", 30))
	var info := UiTheme.label("", 14, UiTheme.GREEN)
	var resume := func():
		close_modal()
		state = "idle"
	v.add_child(UiTheme.button("Resume  [Esc]", resume, true))
	v.add_child(UiTheme.button("Save Game  [S]", func():
		info.text = "Game saved." if Game.save_game() else "Couldn't save!"))
	v.add_child(UiTheme.button("How to Play  [?]", _show_help.bind(show_pause_from_help)))
	v.add_child(UiTheme.button("Sound Settings  [V]", _show_audio.bind(show_pause_from_help)))
	v.add_child(UiTheme.button("Save & Quit to Title", func():
		Game.save_game()
		show_title()))
	v.add_child(UiTheme.button("Save & Exit Game", func():
		Game.save_game()
		get_tree().quit()))
	v.add_child(info)
	modal_keys[KEY_ESCAPE] = resume
	modal_keys[KEY_S] = func(): info.text = "Game saved." if Game.save_game() else "Couldn't save!"
	modal_keys[KEY_SLASH] = _show_help.bind(show_pause_from_help)
	modal_keys[KEY_V] = _show_audio.bind(show_pause_from_help)


func show_pause_from_help() -> void:
	close_modal()
	state = "idle"
	show_pause()


func _show_help(back: Callable) -> void:
	var root := _modal_root()
	var p := _centered_panel(root, Vector2(820, 0))
	var v := UiTheme.vbox(10)
	p.add_child(v)
	v.add_child(UiTheme.title("How to Play", 30))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(760, 0)
	rt.text = """[b]Goal:[/b] Reach Mount Katahdin, Maine before Baxter State Park closes on October 15 — with as many hikers, supplies and as much health as possible.

[b]Each day[/b] you choose your [b]pace[/b] (miles vs. wear and tear) and [b]rations[/b] (food vs. hunger). Hunger, injuries and bad weather drain health; low morale can send hikers home.

[b]Resupply[/b] in trail towns: food, water bottles, stove fuel, first-aid kits and new shoes (every ~500 miles). Hostels and diners restore health and morale. Outfitters repair worn gear.

[b]Events:[/b] bears, river crossings, lightning on exposed ridges, illness, injuries, trail magic and more. Landmarks like the Smokies, Shenandoah, Mount Washington and the 100-Mile Wilderness bring their own challenges.

[b]Foraging:[/b] spend a day gathering wild food in a minigame. Avoid red-capped mushrooms and blow your whistle to scare off bears.

[b]Controls[/b]
Space — Hike on / stop      R — Rest      F — Forage      T — Town (when in one)
P — Change pace      U — Change rations      J — Journal      M — Map overview      Esc — Menu
Mouse wheel / + − — Zoom      Right-drag or Q / E — Rotate camera      1–6 — Choose options
The game autosaves every day. Sound and music volumes are under Esc → Sound Settings."""
	v.add_child(rt)
	var b := UiTheme.button("Back  [Esc]", back, true)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(b)
	modal_keys[KEY_ESCAPE] = back
	modal_keys[KEY_ENTER] = back


# ================================================================== endings & hall of fame

func show_victory() -> void:
	state = "end"
	auto_travel = false
	var sc: Dictionary = Game.score_breakdown()
	var lines: Array = []
	for l in sc["lines"]:
		lines.append("%s  —  %d" % [l[0], l[1]])
	var days: int = Game.day - 1
	var text := "On %s, after %d days on the trail, your party touches the weathered sign on Baxter Peak. Two thousand, one hundred and ninety-eight miles.\n\n" % [Game.date_string(), days]
	text += "\n".join(lines)
	text += "\n\nSubtotal %d  ×  %.0f (%s)\n[ FINAL SCORE: %s ]" % [sc["subtotal"], sc["mult"], Game.PROFESSIONS[Game.profession]["name"], _money_str(sc["total"])]
	var rank := _add_hof(sc["total"], days)
	if rank >= 0:
		text += "\n\nYou placed #%d in the Hall of Fame!" % (rank + 1)
	Game.log_entry("Summited Katahdin! Final score %d." % sc["total"])
	Game.delete_save()
	map.set_party_miles(TrailData.TOTAL_MILES)
	Audio.music("victory", 1.0)
	Audio.set_steps(false)
	show_scene_card("Mount Katahdin, Maine  ·  Mile 2,198", "You Made It!", text, "summit",
		[["Hall of Fame", _show_hof], ["Back to Title", show_title]], {"finish": true, "hour": 10.0, "weather": "clear", "sfx": ""})


func show_game_over() -> void:
	state = "end"
	auto_travel = false
	var fates: Array = []
	for m in Game.party:
		fates.append("%s — %s" % [Game.display_name(m), m["left_reason"] if not m["active"] else "still hiking"])
	var text := "%s\n\nYou made it %d miles in %d days, as far as %s.\n\n%s" % [Game.game_over_reason, int(Game.miles), Game.day - 1, TrailData.state_at(Game.miles), "\n".join(fates)]
	Game.delete_save()
	Audio.music("gameover", 1.0)
	Audio.set_steps(false)
	show_scene_card(_kicker(), "Your Hike Has Ended", text, "camp", [["Try Again", start_setup], ["Back to Title", show_title]], {"sfx": ""})


func _load_hof() -> Array:
	if not FileAccess.file_exists(HOF_PATH):
		return []
	var f := FileAccess.open(HOF_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_ARRAY else []


func _add_hof(score: int, days: int) -> int:
	var list := _load_hof()
	var names: Array = []
	for m in Game.party:
		names.append(Game.short_name(m))
	var entry := {"name": ", ".join(names), "score": score, "days": days, "prof": Game.PROFESSIONS[Game.profession]["name"],
		"date": Time.get_date_string_from_system()}
	list.append(entry)
	list.sort_custom(func(a, b): return a["score"] > b["score"])
	list = list.slice(0, 10)
	var f := FileAccess.open(HOF_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(list, "\t"))
	return list.find(entry)


func _show_hof() -> void:
	var root := _modal_root()
	var p := _centered_panel(root, Vector2(700, 0))
	var v := UiTheme.vbox(10)
	p.add_child(v)
	v.add_child(UiTheme.caps("Thru-hikers who made it to Katahdin", UiTheme.ACCENT))
	v.add_child(UiTheme.title("Hall of Fame", 32))
	v.add_child(UiTheme.separator())
	var list := _load_hof()
	if list.is_empty():
		v.add_child(UiTheme.label("Nobody has finished yet. Will you be the first?", 16, UiTheme.DIM))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	v.add_child(grid)
	for i in list.size():
		var e: Dictionary = list[i]
		grid.add_child(UiTheme.label("#%d" % (i + 1), 16, UiTheme.ACCENT, UiTheme.bold_font()))
		grid.add_child(UiTheme.label(str(e["name"]), 16))
		grid.add_child(UiTheme.label("%d days · %s" % [int(e["days"]), e["prof"]], 14, UiTheme.DIM))
		grid.add_child(UiTheme.label(_money_str(e["score"]), 16, UiTheme.TEXT, UiTheme.bold_font()))
	var b := UiTheme.button("Back  [Esc]", show_title, true)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(b)
	modal_keys[KEY_ESCAPE] = show_title


# ================================================================== input

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if state == "forage":
		return
	if modal_open:
		# don't steal keys from a focused text field
		var f := get_viewport().gui_get_focus_owner()
		if f is LineEdit and k != KEY_ENTER and k != KEY_KP_ENTER and k != KEY_ESCAPE:
			return
		if k == KEY_QUESTION:
			k = KEY_SLASH
		if modal_keys.has(k):
			get_viewport().set_input_as_handled()
			var cb: Callable = modal_keys[k]
			cb.call()
		return
	match k:
		KEY_SPACE:
			toggle_travel()
		KEY_R:
			do_rest()
		KEY_F:
			do_forage()
		KEY_P:
			if state in ["idle", "walking"]:
				cycle_pace()
		KEY_U:
			if state in ["idle", "walking"]:
				cycle_rations()
		KEY_J:
			show_journal()
		KEY_M:
			toggle_overview()
		KEY_T:
			if btn_town.visible and state == "idle":
				open_town(Game.at_landmark)
		KEY_ESCAPE:
			if state == "walking":
				auto_travel = false
			else:
				show_pause()
		KEY_F5:
			if Game.save_game():
				Audio.sfx("page")
				_toast("Game saved.", UiTheme.GREEN)



# ================================================================== audio

func _update_audio() -> void:
	if map == null or state in ["loading", "title", "setup", "forage", "end"]:
		if state != "walking":
			Audio.set_steps(false)
		return
	Audio.set_steps(state == "walking" and map.walking)
	Audio.music("town" if _in_town else "trail")
	var amb := "forest"
	if _in_town:
		amb = "town"
	elif _scene_amb != "":
		amb = _scene_amb
	elif Game.weather == "storm":
		amb = "storm"
	elif Game.weather == "rain":
		amb = "rain"
	elif Game.weather == "snow" or (Game.weather in ["cloudy", "fog"] and TrailData.is_exposed(Game.miles)):
		amb = "wind"
	elif hour >= 20.3 or hour < 6.0:
		amb = "night"
	Audio.ambience(amb)


func _scene_sfx(kind: String, text: String) -> void:
	match kind:
		"bear":
			Audio.sfx("bear")
		"storm":
			Audio.thunder(1.0)
		"river":
			Audio.sfx("splash", -3.0)
		"magic":
			Audio.sfx("good")
		"injury":
			Audio.sfx("bad")
		"snake":
			Audio.sfx("rattle")
		"":
			pass
		_:
			Audio.sfx("event", -3.0, 0.0)
	if "photo" in text:
		Audio.sfx("camera", -2.0)


func _show_audio(back: Callable) -> void:
	var root := _modal_root()
	var p := _centered_panel(root, Vector2(520, 0))
	var v := UiTheme.vbox(14)
	p.add_child(v)
	v.add_child(UiTheme.caps("Settings", UiTheme.ACCENT))
	v.add_child(UiTheme.title("Sound", 30))
	v.add_child(UiTheme.separator())
	var labels := {"Master": "Master volume", "Music": "Music", "Ambience": "Nature & weather", "SFX": "Sound effects"}
	for bus in ["Master", "Music", "Ambience", "SFX"]:
		var row := UiTheme.hbox(14)
		var l := UiTheme.label(labels[bus], 16)
		l.custom_minimum_size.x = 170
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 100
		sl.step = 1
		sl.value = Audio.volumes[bus] * 100.0
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.custom_minimum_size.x = 220
		sl.focus_mode = Control.FOCUS_NONE
		var pct := UiTheme.label("%d%%" % int(sl.value), 14, UiTheme.DIM)
		pct.custom_minimum_size.x = 44
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var b: String = bus
		sl.value_changed.connect(func(val: float):
			Audio.set_volume(b, val / 100.0)
			pct.text = "%d%%" % int(val))
		if bus == "SFX":
			sl.drag_ended.connect(func(_c: bool): Audio.sfx("event", -3.0, 0.0))
		row.add_child(sl)
		row.add_child(pct)
		v.add_child(row)
	var btn := UiTheme.button("Done  [Esc]", back, true)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(btn)
	modal_keys[KEY_ESCAPE] = back
	modal_keys[KEY_ENTER] = back



# ================================================================== credits & changelog

func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "1.0.0"))


func _ironite_logo(height: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = load("res://branding/ironite_logo.png")
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var ratio := 903.0 / 234.0
	if tr.texture != null:
		ratio = float(tr.texture.get_width()) / tr.texture.get_height()
	tr.custom_minimum_size = Vector2(height * ratio, height)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


var _credits_scroll: ScrollContainer
var _credits_pos := 0.0
var _credits_auto := true


func _show_credits() -> void:
	var root := _modal_root()
	var bgc := ColorRect.new()
	bgc.color = Color(IRONITE_GREEN, 0.97)
	bgc.set_anchors_preset(Control.PRESET_FULL_RECT)
	bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bgc)
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	root.add_child(sc)
	var col := UiTheme.vbox(10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(col)
	var gap := func(h: float):
		var c := Control.new()
		c.custom_minimum_size.y = h
		col.add_child(c)
	var line := func(text: String, size: int, color: Color, font: Font):
		var l := UiTheme.label(text, size, color, font)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 700
		l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(l)
	var mint := IRONITE_MINT
	var dim := Color(mint, 0.65)
	gap.call(get_viewport().get_visible_rect().size.y * 0.42)
	var logo := _ironite_logo(120)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(logo)
	gap.call(10)
	line.call("presents", 18, dim, null)
	gap.call(26)
	line.call("The Appalachian Trail", 52, Color.WHITE, UiTheme.title_font())
	line.call("A thru-hike from Georgia to Maine  ·  Version %s" % _version(), 17, dim, null)
	gap.call(70)
	var roles := [
		["Created by", "Ironite"],
		["Game Design", "Ironite"],
		["Programming", "Ironite"],
		["3D Art & Visual Design", "Ironite"],
		["Title Illustration", "Ironite"],
		["User Interface", "Ironite"],
		["Original Music & Score", "Ironite"],
		["Sound Design & Ambience", "Ironite"],
		["Writing & Trail Research", "Ironite"],
		["Game Balance & Testing", "Ironite"],
		["Produced & Published by", "Ironite"],
	]
	for r in roles:
		line.call(r[0].to_upper(), 13, dim, UiTheme.bold_font())
		line.call(r[1], 28, mint, UiTheme.title_font())
		gap.call(22)
	gap.call(40)
	line.call("SOUNDTRACK", 13, dim, UiTheme.bold_font())
	for t in ["\"Springer Dawn\"", "\"Ridge Walk\"", "\"Trail Town\"", "\"Shelter Fire\"", "\"Wild Harvest\"", "\"Baxter Peak\"", "\"The Long Way Home\""]:
		line.call(t, 20, mint, null)
	line.call("Composed and produced by Ironite", 15, dim, null)
	gap.call(60)
	line.call("SPECIAL THANKS", 13, dim, UiTheme.bold_font())
	line.call("To every thru-hiker, section hiker, trail angel, ridgerunner, hostel owner and volunteer trail crew who keeps the white blazes leading north.", 19, mint, null)
	gap.call(30)
	line.call("INSPIRED BY", 13, dim, UiTheme.bold_font())
	line.call("The classic educational trail games of the 1980s and '90s: The Oregon Trail, The Amazon Trail, The Yukon Trail and African Trail.", 19, mint, null)
	gap.call(60)
	line.call("BUILT WITH", 13, dim, UiTheme.bold_font())
	line.call("Godot Engine %s" % Engine.get_version_info()["string"], 22, mint, null)
	line.call("This game uses the Godot Engine, available under the MIT license:", 14, dim, null)
	line.call(Engine.get_license_text().strip_edges(), 12, Color(mint, 0.55), null)
	gap.call(60)
	line.call("The Appalachian Trail is a game and is not affiliated with or endorsed by the Appalachian Trail Conservancy, the National Park Service or Baxter State Park. All other trademarks belong to their respective owners. Distances, towns and events are simplified for play — always check current conditions before you hike.", 13, Color(mint, 0.55), null)
	gap.call(40)
	line.call("© 2026 Ironite. All rights reserved.", 16, mint, UiTheme.bold_font())
	gap.call(30)
	var end_logo := _ironite_logo(60)
	end_logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(end_logo)
	gap.call(10)
	line.call("Thanks for hiking.", 20, mint, UiTheme.title_font())
	gap.call(get_viewport().get_visible_rect().size.y * 0.5)
	var back := UiTheme.button("Back  [Esc]", show_title, true)
	back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	back.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	back.grow_vertical = Control.GROW_DIRECTION_BEGIN
	back.position -= Vector2(24, 24)
	root.add_child(back)
	var hint := UiTheme.label("Scroll or use the arrow keys to read at your own pace", 13, Color(mint, 0.5))
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position += Vector2(24, -30)
	root.add_child(hint)
	_credits_scroll = sc
	_credits_pos = 0.0
	_credits_auto = true
	sc.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton or e is InputEventScreenDrag:
			_credits_auto = false)
	modal_keys[KEY_ESCAPE] = show_title
	modal_keys[KEY_ENTER] = show_title
	modal_keys[KEY_DOWN] = func():
		_credits_auto = false
		sc.scroll_vertical += 60
	modal_keys[KEY_UP] = func():
		_credits_auto = false
		sc.scroll_vertical -= 60
	modal_keys[KEY_SPACE] = func(): _credits_auto = not _credits_auto


func _credits_tick(delta: float) -> void:
	if _credits_scroll == null or not is_instance_valid(_credits_scroll) or not _credits_scroll.is_inside_tree():
		_credits_scroll = null
		return
	if _credits_auto:
		_credits_pos += delta * 42.0
		var maxv := _credits_scroll.get_v_scroll_bar().max_value - _credits_scroll.size.y
		if _credits_pos >= maxv and maxv > 0:
			_credits_pos = maxv
			_credits_auto = false
		_credits_scroll.scroll_vertical = int(_credits_pos)
	else:
		_credits_pos = _credits_scroll.scroll_vertical


func _changelog_bbcode() -> String:
	if not FileAccess.file_exists(CHANGELOG_PATH):
		return "No changelog found."
	var f := FileAccess.open(CHANGELOG_PATH, FileAccess.READ)
	var out := PackedStringArray()
	for raw in f.get_as_text().split("\n"):
		var ln := raw.strip_edges(false, true)
		if ln.begins_with("# ") or ln.begins_with("All notable"):
			continue
		if ln.begins_with("## "):
			out.append("\n[font_size=26][color=#%s][b]%s[/b][/color][/font_size]" % [UiTheme.ACCENT.to_html(false), ln.substr(3)])
		elif ln.begins_with("### "):
			out.append("[font_size=13][color=#%s][b]%s[/b][/color][/font_size]" % [UiTheme.DIM.to_html(false), ln.substr(4).to_upper()])
		elif ln.begins_with("  - "):
			out.append("        ◦  " + ln.substr(4))
		elif ln.begins_with("- "):
			out.append("  •  " + ln.substr(2))
		elif ln.strip_edges() != "":
			out.append(ln)
	return "\n".join(out).strip_edges()


func _show_changelog() -> void:
	var root := _modal_root()
	var p := _centered_panel(root, Vector2(820, 600))
	var v := UiTheme.vbox(10)
	p.add_child(v)
	var head := UiTheme.hbox(14)
	var hv := UiTheme.vbox(2)
	hv.add_child(UiTheme.caps("Changelog  ·  you're on v%s" % _version(), UiTheme.ACCENT))
	hv.add_child(UiTheme.title("What's New", 32))
	head.add_child(hv)
	head.add_child(UiTheme.spacer())
	var lg := _ironite_logo(34)
	lg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(lg)
	v.add_child(head)
	v.add_child(UiTheme.separator())
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.scroll_active = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.custom_minimum_size = Vector2(760, 440)
	rt.add_theme_constant_override("line_separation", 5)
	rt.text = _changelog_bbcode()
	v.add_child(rt)
	var b := UiTheme.button("Back  [Esc]", show_title, true)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(b)
	modal_keys[KEY_ESCAPE] = show_title
	modal_keys[KEY_ENTER] = show_title
