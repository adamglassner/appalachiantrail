extends Node
## Developer tool, only active when launched with `-- --shots=DIR` or `-- --sim=N`.
## Captures screenshots of every screen, or runs automated balance simulations.

var main: Node
var out_dir := ""


func run_shots(m: Node, dir: String) -> void:
	main = m
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(dir)
	await _wait(1.5)
	await _shot("01_title")
	Game.new_game(0, ["Adam", "Bea", "Cal", "Dee"], 1)
	for k in ["food", "fuel", "first_aid", "shoes"]:
		Game.buy(k, {"food": 40, "fuel": 2, "first_aid": 2, "shoes": 4}[k])
	Game.buy("water_cap", 6)
	main._enter_trail()
	await _wait(1.0)
	await _shot("02_hud_start")
	main.toggle_travel()
	await _wait(1.0)
	await _shot("03_walking")
	await _wait(1.6)
	main.auto_travel = false
	await _wait(3.0)
	main.close_modal()
	main.state = "idle"
	# jump ahead to the Smokies in summer storm
	Game.miles = 200.0
	Game.next_landmark = 9
	Game.at_landmark = 8
	Game.day = 40
	Game.weather = "storm"
	main.hour = 13.0
	main._sync_map_env()
	main.map.atmos.set_hour(13.0)
	main.refresh_hud()
	await _wait(1.0)
	await _shot("04_smokies_storm")
	Game.weather = "snow"
	main._sync_map_env()
	await _wait(1.0)
	await _shot("05_snow")
	Game.weather = "clear"
	main._sync_map_env()
	main.map.atmos.set_hour(19.2)
	await _wait(0.5)
	await _shot("06_sunset")
	main.map.atmos.set_hour(23.0)
	main.map.set_campfire(true)
	await _wait(0.5)
	await _shot("07_night")
	main.map.atmos.set_hour(10.0)
	main.map.set_overview(true)
	await _wait(2.5)
	await _shot("08_overview")
	main.map.set_overview(false)
	# autumn in Maine
	Game.miles = 2000.0
	Game.day = 200
	main._sync_map_env()
	main.refresh_hud()
	await _wait(2.0)
	await _shot("09_maine_autumn")
	var scenes: Array = ["river", "bear", "storm", "injury", "magic", "vista", "camp", "summit", "ponies", "rocks", "snake", "forest"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenes="):
			scenes = Array(a.substr(9).split(",")) if a.substr(9) != "" else []
	Game.day = 90
	Game.miles = 900
	for s in scenes:
		Game.weather = "rain" if s == "river" else "clear"
		main.show_scene_card(main._kicker(), "Scene: " + s, "Lorem trail text for the %s diorama. The party presses on along the ridge." % s, s,
			[["First option", func(): pass], ["Second option", func(): pass]])
		await _wait(0.6)
		await _shot("10_scene_" + s)
	main.show_scene_card(main._kicker(), "You Made It!", "Final score demo", "summit", [["OK", func(): pass]], {"finish": true, "hour": 10.0})
	await _wait(0.6)
	await _shot("11_katahdin")
	main.open_town(1, "A sample info message from the town.")
	await _wait(0.6)
	await _shot("12_town")
	main.open_store("Resupply", "Stock up for the next stretch.", func(): pass)
	await _wait(0.4)
	await _shot("13_store")
	main.close_modal()
	main.state = "idle"
	main.show_journal()
	await _wait(0.3)
	await _shot("14_journal")
	main.close_modal()
	main.state = "idle"
	Game.day = 200
	main.do_forage()
	await _wait(3.5)
	await _shot("15_forage")
	main.forage_game.time_left = 0.0
	await _wait(0.3)
	await _shot("16_forage_end")
	main.forage_game._finish()
	await _wait(0.5)
	await _shot("17_after_forage")
	main.close_modal()
	main.state = "idle"
	main.start_setup()
	await _wait(0.3)
	await _shot("18_setup")
	main._setup_names()
	await _wait(0.3)
	await _shot("19_names")
	main.setup_names = ["Adam", "Bea"]
	Game.new_game(1, ["Adam", "Bea"], 1)
	main._setup_store()
	await _wait(0.3)
	await _shot("20_start_store")
	get_tree().quit()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


# ------------------------------------------------------------------ balance simulation

func run_sim(n: int, policy: String) -> void:
	var finished := 0
	var days_total := 0
	var reasons := {}
	var scores: Array = []
	var miles_total := 0.0
	for run in n:
		var prof := run % 3
		var start := 1 if policy != "late" else 3
		Game.new_game(prof, ["A", "B", "C"], start)
		_ai_shop(true)
		Game.supplies["water"] = Game.supplies["water_cap"]
		var guard := 0
		while guard < 400:
			guard += 1
			if Game.game_over_reason != "":
				break
			# simple AI
			var low := false
			for m in Game.active_members():
				if m["health"] < 40:
					low = true
			Game.pace = 0 if low else (2 if policy == "push" else 1)
			Game.rations = 0 if Game.food_days() > 3 else 1
			if Game.money < 150:
				Game.rations = 1
			var res: Dictionary
			if Game.food_days() < 2.0 and Game.money < 150:
				res = Game.apply_forage(randf_range(8.0, 22.0), 1 if randf() < 0.15 else 0)
			elif low and randf() < 0.5:
				res = Game.advance_day("rest")
			else:
				res = Game.advance_day("hike")
			if not res["choice"].is_empty():
				var ev: Dictionary = res["choice"]
				Game.events.resolve(ev, 0 if randf() < 0.7 else randi() % ev["choices"].size())
			if res["arrived"] != -1:
				var lm: Dictionary = TrailData.LANDMARKS[res["arrived"]]
				if lm["type"] == "finish":
					Game.finished = true
					break
				var ev2: Dictionary = Game.events.landmark_event(res["arrived"])
				if ev2.has("choices"):
					Game.events.resolve(ev2, 0)
				if lm["type"] == "town":
					_ai_shop(false)
					if Game.average("health") < 60 or Game.average("morale") < 50:
						_svc("hostel")
					if Game.money > 1500:
						_svc("meal")
					if Game.gear < 50:
						Game.repair_gear()
		reasons["prof%d_%s" % [prof, "ok" if Game.finished else "fail"]] = reasons.get("prof%d_%s" % [prof, "ok" if Game.finished else "fail"], 0) + 1
		if not Game.finished:
			reasons["broke" if Game.money < 60 else "had_money"] = reasons.get("broke" if Game.money < 60 else "had_money", 0) + 1
		if Game.finished:
			finished += 1
			days_total += Game.day - 1
			scores.append(Game.score_breakdown()["total"])
		else:
			var r: String = Game.game_over_reason.substr(0, 40)
			reasons[r] = reasons.get(r, 0) + 1
		miles_total += Game.miles
		for m in Game.party:
			if not m["active"]:
				var lr: String = m["left_reason"]
				reasons["member: " + lr] = reasons.get("member: " + lr, 0) + 1
		if run < 3:
			print("run ", run, " day ", Game.day, " miles ", int(Game.miles), " money ", int(Game.money), " food ", int(Game.supplies["food"]), " gear ", int(Game.gear))
	print("policy=%s runs=%d finished=%d (%.0f%%) avg_days=%.1f avg_miles=%.0f" % [policy, n, finished, 100.0 * finished / n,
		float(days_total) / maxi(1, finished), miles_total / n])
	scores.sort()
	if not scores.is_empty():
		print("  scores min=%d median=%d max=%d" % [scores[0], scores[scores.size() / 2], scores[-1]])
	print("  failures: ", reasons)
	for k in spend:
		spend[k] = int(spend[k] / n)
	print("  avg spend/run: ", spend)


var spend := {}


func _buy(k: String, q: int) -> void:
	var before: float = Game.money
	Game.buy(k, q)
	spend[k] = spend.get(k, 0.0) + before - Game.money


func _svc(k: String) -> void:
	var before: float = Game.money
	if k == "repair":
		Game.repair_gear()
	else:
		Game.town_service(k)
	spend[k] = spend.get(k, 0.0) + before - Game.money


func _ai_shop(start: bool) -> void:
	var n := Game.active_count()
	# food to reach the next town + margin
	var nxt := 0.0
	for j in range(Game.at_landmark + 1, TrailData.LANDMARKS.size()):
		var l: Dictionary = TrailData.LANDMARKS[j]
		if l["type"] == "town" or l["type"] == "finish":
			nxt = l["mile"] - Game.miles
			break
	var days_needed := nxt / 11.0 + 2.0
	var want_food: float = days_needed * 2.0 * n - Game.supplies["food"]
	if want_food > 0:
		_buy("food", int(ceil(want_food / 10.0)) * 10)
	if start:
		_buy("water_cap", n)
		_buy("first_aid", 2)
		_buy("fuel", 2)
		_buy("shoes", n)
	else:
		if Game.supplies["fuel"] < 1:
			_buy("fuel", 1)
		if Game.supplies["first_aid"] < 1:
			_buy("first_aid", 1)
		if Game.supplies["shoes"] < n and Game.shoe_miles > 300:
			_buy("shoes", n - Game.supplies["shoes"])


# ------------------------------------------------------------------ UI autoplay (drives the real screens)

func run_autoplay(m: Node, games: int) -> void:
	main = m
	Engine.time_scale = 40.0
	await _wait(0.5)
	var done := 0
	var steps := 0
	var max_day := 0
	var visited_towns := 0
	var forages := 0
	while done < games and steps < 40000:
		steps += 1
		await get_tree().process_frame
		match main.state:
			"title":
				main.start_setup()
			"setup":
				main.setup_prof = done % 3
				main.setup_names = ["Ann", "Ben", "Cy"]
				Game.new_game(done % 3, main.setup_names, 1)
				main._setup_store()
				# buy a sensible kit through the store's own Enter handler
				for k in ["food", "fuel", "first_aid", "shoes", "water_cap"]:
					Game.buy(k, {"food": 40, "fuel": 2, "first_aid": 2, "shoes": 3, "water_cap": 3}[k])
				main.modal_keys[KEY_ENTER].call()
			"idle":
				if Game.supplies["food"] < 10 and Game.money < 100 and randf() < 0.5:
					forages += 1
					main.do_forage()
				else:
					var low := false
					for mem in Game.active_members():
						if mem["health"] < 40:
							low = true
					if low and randf() < 0.4:
						main.do_rest()
					else:
						main.toggle_travel()
			"forage":
				if main.forage_game != null:
					if main.forage_game.running:
						main.forage_game.gathered = randf_range(5, 20)
						main.forage_game.time_left = 0.0
					elif main.forage_game.end_panel != null:
						main.forage_game._finish()
			"modal", "end":
				if main.modal_keys.is_empty():
					continue
				max_day = maxi(max_day, Game.day)
				# in town: shop for food first, then leave
				var keys: Array = main.modal_keys.keys()
				if main.state == "end":
					print("GAME END: prof=", Game.profession, " finished=", Game.finished, " day=", Game.day, " miles=", int(Game.miles), " money=", int(Game.money), " food=", int(Game.supplies["food"]), " shoes=", Game.supplies["shoes"], " shoe_miles=", int(Game.shoe_miles), " gear=", int(Game.gear))
					for mem in Game.party:
						print("   ", mem["name"], ": ", mem["left_reason"], " h=", int(mem["health"]), " m=", int(mem["morale"]), " hunger=", int(mem["hunger"]))
					var tail: Array = Game.journal.slice(max(0, Game.journal.size() - 12))
					for e in tail:
						print("      j: ", e["text"])
					done += 1
					main.show_title()
					continue
				if keys.has(KEY_6) and keys.has(KEY_1) and main.modal_keys.size() >= 12:
					visited_towns += 1
					# town menu: buy food via store then leave
					var need: float = maxf(0.0, 2.0 * Game.active_count() * 14.0 - Game.supplies["food"])
					if Game.gear < 50:
						Game.repair_gear()
					Game.buy("food", int(ceil(need / 10.0)) * 10)
					if Game.shoe_miles > 350 and Game.supplies["shoes"] < Game.active_count():
						Game.buy("shoes", Game.active_count())
					main.modal_keys[KEY_6].call()
				elif keys.has(KEY_1):
					main.modal_keys[KEY_1].call()
				elif keys.has(KEY_SPACE):
					main.modal_keys[KEY_SPACE].call()
				elif keys.has(KEY_ENTER):
					main.modal_keys[KEY_ENTER].call()
				else:
					main.modal_keys[keys[0]].call()
	print("AUTOPLAY done games=", done, " steps=", steps, " towns=", visited_towns, " forages=", forages)
	get_tree().quit()


func run_audio_check(m: Node) -> void:
	main = m
	await _wait(0.5)
	var bad := 0
	for dir in ["music", "amb", "sfx"]:
		var d := DirAccess.open("res://audio/" + dir)
		for f in d.get_files():
			if f.ends_with(".import"):
				f = f.trim_suffix(".import")
			if not f.ends_with(".ogg"):
				continue
			var s = load("res://audio/%s/%s" % [dir, f])
			if s == null:
				bad += 1
				print("FAILED ", f)
	print("audio files ok, failures=", bad, " title music=", Audio.current_music())
	Game.new_game(0, ["A", "B"], 1)
	main._enter_trail()
	await _wait(0.5)
	print("trail music=", Audio.current_music(), " amb=", Audio._amb_name)
	main.open_town(1)
	await _wait(0.3)
	print("town music=", Audio.current_music(), " amb=", Audio._amb_name)
	main._leave_town()
	Game.weather = "storm"
	await _wait(0.3)
	print("storm amb=", Audio._amb_name, " music=", Audio.current_music())
	get_tree().quit()


func run_brand_shots(m: Node, dir: String) -> void:
	main = m
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(dir)
	await _shot("b0_loading")
	await _wait(2.5)
	await _shot("b1_title")
	main._show_changelog()
	await _wait(0.5)
	await _shot("b2_whats_new")
	main._show_credits()
	await _wait(1.0)
	main._credits_auto = false
	main._credits_scroll.scroll_vertical = 250
	await _wait(0.3)
	await _shot("b3_credits_top")
	main._credits_scroll.scroll_vertical = 1300
	await _wait(0.3)
	await _shot("b4_credits_mid")
	main._credits_scroll.scroll_vertical = 2400
	await _wait(0.3)
	await _shot("b5_credits_late")
	main._credits_scroll.scroll_vertical = 99999
	await _wait(0.3)
	await _shot("b6_credits_end")
	get_tree().quit()
