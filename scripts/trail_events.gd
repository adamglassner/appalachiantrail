class_name TrailEvents
extends RefCounted
## Random daily events, landmark challenges and the outcomes of player choices.
##
## Event dictionaries:
##   message: {"title", "text", "scene", "major": bool}
##   choice:  {"id", "title", "text", "scene", "choices": [String, ...]}  -> resolve(ev, idx)

var g  # the GameState autoload

const JOINERS := ["Maya", "Theo", "Priya", "Luis", "Hannah", "Kofi", "Rosa", "Eli", "June", "Sam"]


func _init(game) -> void:
	g = game


# ------------------------------------------------------------------ helpers

func _msg(title: String, text: String, scene: String, major := true) -> Dictionary:
	return {"title": title, "text": text, "scene": scene, "major": major}


func _choice(id: String, title: String, text: String, scene: String, choices: Array, data := {}) -> Dictionary:
	return {"id": id, "title": title, "text": text, "scene": scene, "choices": choices, "data": data}


func _who() -> Dictionary:
	return g.random_member()


func _n(m: Dictionary) -> String:
	return g.short_name(m)


func _last_landmark_mile() -> float:
	return TrailData.LANDMARKS[max(g.next_landmark - 1, 0)]["mile"]


func _lose_miles(x: float) -> float:
	var floor_m := _last_landmark_mile()
	var before: float = g.miles
	g.miles = maxf(floor_m, g.miles - x)
	return before - g.miles


func _lose_food(frac: float, min_lbs := 0.0) -> float:
	var lost: float = minf(g.supplies["food"], maxf(g.supplies["food"] * frac, min_lbs))
	g.supplies["food"] -= lost
	return lost


func _in(a: float, b: float) -> bool:
	return g.miles >= a and g.miles < b


func bear_country() -> bool:
	return _in(160, 245) or _in(860, 975) or _in(1290, 1410)


# ------------------------------------------------------------------ daily roll

func roll_daily(mode: String, arriving: bool) -> Dictionary:
	var chance := 0.30 if mode == "hike" else 0.18
	if randf() > chance:
		return {}
	var w := {}  # id -> weight
	var reg := TrailData.region_for(g.miles)
	var mon: int = g.month()
	var exposed := TrailData.is_exposed(g.miles)
	var worn_shoes: bool = g.shoe_miles >= 500.0

	w["blisters"] = 6.0 + (8.0 if worn_shoes else 0.0) + (4.0 if g.pace == 2 else 0.0) + (4.0 if g.weather == "rain" else 0.0)
	w["shin"] = (5.0 if g.miles < 400 else 1.5) * (2.5 if g.pace == 2 else 1.0)
	var rocky := _in(1150, 1300) or _in(1785, 1960)
	w["sprain"] = 2.5 + (6.0 if rocky else 0.0) + (2.0 if g.weather == "rain" or g.weather == "snow" else 0.0)
	w["giardia"] = 2.0 + (3.0 if g.gear < 40 else 0.0)
	w["noro"] = 3.0 if g.miles < 1100 and mon <= 5 else 1.0
	if reg != "south" and mon >= 5 and mon <= 8:
		w["lyme"] = 2.5
	if g.weather == "hot":
		w["heat"] = 8.0
	if g.temperature < 45.0 and (g.weather == "rain" or g.weather == "snow"):
		w["hypothermia"] = 6.0 + (6.0 if exposed else 0.0)
	w["fracture"] = 0.6 + (1.5 if rocky else 0.0)
	w["magic"] = 7.0 + (4.0 if reg == "south" else 0.0)
	w["mice"] = 4.0
	w["tentpole"] = 3.0
	w["sunrise"] = 4.0 if g.weather == "clear" else 0.0
	w["friends"] = 3.0
	w["soaked"] = 6.0 if g.weather == "rain" or g.weather == "storm" else 0.0
	w["lost_fuel"] = 1.5 if g.supplies["fuel"] > 0 else 0.0
	w["found"] = 2.0
	if reg == "virginia" or reg == "mid":
		w["snake"] = 3.0 if mon >= 5 and mon <= 9 else 0.5
	# choice events
	w["bear"] = 4.0 + (10.0 if bear_country() else 0.0)
	w["bear_camp"] = 2.0 + (5.0 if bear_country() else 0.0)
	if not arriving:
		if exposed or g.weather == "storm":
			w["storm_ridge"] = 14.0 if g.weather == "storm" else (3.0 if g.weather == "rain" else 0.0)
		w["stream"] = 3.0 + (8.0 if reg == "maine" or reg == "new_england" else 0.0) + (6.0 if g.weather == "rain" or g.weather == "storm" else 0.0)
		if g.weather == "fog":
			w["lost"] = 10.0
		else:
			w["lost"] = 1.5
	w["sick_hiker"] = 2.0
	if g.active_count() < 4 and g.miles < 1600:
		w["joiner"] = 1.2

	if mode == "forage":
		# foraging days only roll a few kinds of events
		for k in w.keys():
			if not ["bear", "snake", "sprain", "magic", "sunrise", "giardia"].has(k):
				w.erase(k)
	var total := 0.0
	for k in w:
		total += w[k]
	if total <= 0.0:
		return {}
	var r := randf() * total
	var pick := ""
	for k in w:
		r -= w[k]
		if r <= 0.0:
			pick = k
			break
	if pick == "":
		pick = w.keys()[0]
	return _make(pick)


func _make(id: String) -> Dictionary:
	var m := _who()
	if m.is_empty():
		return {}
	match id:
		"blisters":
			var t := "Hot spots turned into blisters."
			if g.shoe_miles >= 500.0:
				t = "Worn-out shoes have rubbed %s's heels raw." % _n(m)
			return _msg("Blisters", t + " " + g.add_condition(m, "blisters"), "injury", false)
		"shin":
			return _msg("Shin Splints", "Too many miles too soon. " + g.add_condition(m, "shin"), "injury", false)
		"sprain":
			var where := "a wet root"
			if _in(1150, 1300):
				where = "a wobbly Pennsylvania rock"
			elif g.miles >= 1785:
				where = "a slick granite slab"
			return _msg("Sprained Ankle", "%s rolled an ankle on %s. %s" % [_n(m), where, g.add_condition(m, "sprain")], "injury")
		"giardia":
			return _msg("Bad Water", "Someone skipped filtering at a murky spring. " + g.add_condition(m, "giardia"), "injury")
		"noro":
			var t2: String = "Norovirus is tearing through the shelters. " + g.add_condition(m, "noro")
			if randf() < 0.4:
				var m2 := _who()
				if m2 != m:
					t2 += " " + g.add_condition(m2, "noro")
			return _msg("Norovirus Outbreak", t2, "camp")
		"lyme":
			return _msg("Tick Bite", "A bullseye rash appears on %s's leg. %s" % [_n(m), g.add_condition(m, "lyme")], "injury")
		"heat":
			return _msg("Heat Exhaustion", "The humidity is brutal. " + g.add_condition(m, "heat"), "vista")
		"hypothermia":
			return _msg("Hypothermia", "Cold rain soaks through every layer. %s can't stop shivering. %s" % [_n(m), g.add_condition(m, "hypothermia")], "storm")
		"fracture":
			return _msg("Bad Fall", "%s slipped and landed hard on an outstretched hand. %s" % [_n(m), g.add_condition(m, "fracture")], "injury")
		"magic":
			var gifts := [
				["A cooler of cold sodas and snacks sits at a road crossing, with a note: 'Happy hiking! — The Bakers.'", 8.0],
				["A trail angel grills hot dogs at the gap and hands out fresh fruit.", 10.0],
				["A former thru-hiker parked at the trailhead with homemade cookies and a box of resupply leftovers.", 14.0],
				["A church group is serving pancakes at the trailhead. Everyone eats until they can't move.", 6.0],
			]
			var gft: Array = gifts[randi() % gifts.size()]
			g.supplies["food"] += gft[1]
			g.change_all("morale", 12.0)
			g.change_all("hunger", -20.0)
			return _msg("Trail Magic!", "%s\n\n+%d lb food, morale up." % [gft[0], int(gft[1])], "magic")
		"mice":
			var lost := _lose_food(0.0, randf_range(2.0, 5.0))
			g.change_all("morale", -3.0)
			return _msg("Shelter Mice", "Mice chewed through a food bag overnight. Lost %.0f lb of food." % lost, "camp", false)
		"tentpole":
			g.gear = maxf(0.0, g.gear - 12.0)
			return _msg("Gear Failure", "A tent pole snapped in the wind. Duct tape will have to do. Gear −12%.", "camp", false)
		"sunrise":
			g.change_all("morale", 8.0)
			return _msg("Sunrise", "A sea of clouds fills the valleys below as the sun comes up. Nobody says a word for a while.", "vista", false)
		"friends":
			g.change_all("morale", 7.0)
			var hk: Array = g.chatter()
			return _msg("New Friends", "You share a shelter with a hiker called %s. Around the fire they say: \"%s\"" % [hk[0], hk[1]], "camp", false)
		"soaked":
			g.gear = maxf(0.0, g.gear - 4.0)
			g.change_all("morale", -4.0)
			return _msg("Soaked", "Everything is wet: socks, sleeping bags, spirits. Gear −4%.", "storm", false)
		"lost_fuel":
			g.supplies["fuel"] = max(0, g.supplies["fuel"] - 1)
			return _msg("Lost Fuel", "A fuel canister fell out of a side pocket somewhere back down the trail.", "forest", false)
		"found":
			if randf() < 0.5:
				g.supplies["food"] += 4.0
				return _msg("Hiker Box", "The shelter's hiker box is full of extra ramen and oatmeal. +4 lb food.", "camp", false)
			g.supplies["first_aid"] += 1
			return _msg("Lucky Find", "Someone left a sealed first-aid kit at the shelter with a note: 'Take me.' +1 kit.", "camp", false)
		"snake":
			if randf() < 0.15:
				g.change_all("morale", -6.0)
				return _msg("Rattlesnake!", "A timber rattlesnake strikes at %s's boot. It misses — barely. Everyone watches every step for the rest of the day." % _n(m), "snake")
			return _msg("Rattlesnake", "A timber rattlesnake is sunning itself across the trail. You give it a wide berth.", "snake", false)
		"bear":
			return _choice("bear", "Bear on the Trail!", "A black bear steps onto the trail thirty yards ahead and stares at you. It's not leaving.", "bear",
				["Make noise, stand tall, and back away slowly", "Toss some food and retreat", "Run!", "Try to get a photo"])
		"bear_camp":
			return _choice("bear_camp", "Visitor in the Night", "Snuffling and the snap of twigs wake you after midnight. Something big is circling camp — and your food bag is still in the vestibule.", "bear",
				["Bang pots and shout", "Hang the bag now, in the dark", "Stay quiet and hope it leaves"])
		"storm_ridge":
			return _choice("storm_ridge", "Lightning on the Ridge", "Thunder cracks close by. Dark clouds are piling up and the trail ahead runs along an exposed ridge with nowhere to hide.", "storm",
				["Push across the ridge quickly", "Retreat below treeline and wait it out"])
		"stream":
			var swollen: bool = g.weather == "rain" or g.weather == "storm"
			var desc := "The stream ahead is running high and fast from the rain. The rocks you'd normally hop across are underwater." if swollen \
				else "The trail drops to a wide, knee-deep stream crossing. The water is cold and the stones are slick."
			return _choice("stream", "River Crossing", desc, "river",
				["Ford it", "Wait a day for the water to drop", "Search upstream for a log crossing"], {"swollen": swollen})
		"lost":
			return _choice("lost", "Lost the Blazes", "In the thick fog, you realize you haven't seen a white blaze in a long time. This might not be the trail.", "forest",
				["Backtrack to the last blaze", "Push on by map and compass"])
		"sick_hiker":
			return _choice("sick_hiker", "Hiker in Trouble", "You find a solo hiker sitting by the trail, pale and limping. They've run out of supplies and ask if you can spare anything.", "camp",
				["Give them a first-aid kit", "Share some food", "Wish them luck and move on"])
		"joiner":
			var used: Array = g.party.map(func(p): return p["name"])
			var pool: Array = JOINERS.filter(func(nm): return not used.has(nm))
			if pool.is_empty():
				return {}
			var nm: String = pool[randi() % pool.size()]
			return _choice("joiner", "A New Hiker", "%s has been leapfrogging with your group for days. Tonight at the shelter they ask if they can hike with you." % nm, "camp",
				["Welcome them to the group", "Politely say no"], {"name": nm})
	return {}


# ------------------------------------------------------------------ landmarks

func landmark_event(idx: int) -> Dictionary:
	var lm: Dictionary = TrailData.LANDMARKS[idx]
	var sp: String = lm.get("special", "")
	match sp:
		"smokies_enter":
			var fee: float = 40.0 * g.active_count()
			return _choice("smokies", "Great Smoky Mountains", lm["desc"] + "\n\nThru-hikers need a $40 permit each to enter the park. Rangers do check.", "bear",
				["Pay the permit ($%d)" % int(fee), "Skip it and hope for the best"], {"fee": fee})
		"clingmans":
			g.change_all("morale", 10.0)
			var extra := ""
			if g.month() <= 4 and randf() < 0.55:
				extra = "\n\nRime ice coats every branch and snow drifts across the trail. It's beautiful and bitterly cold."
				g.weather = "snow"
			return _msg("Clingmans Dome", lm["desc"] + extra, "summit")
		"roan":
			g.change_all("morale", 8.0)
			return _msg("Roan Highlands", lm["desc"], "vista")
		"ponies":
			g.change_all("morale", 12.0)
			return _msg("Grayson Highlands", lm["desc"] + "\n\nA pony nibbles the salt off %s's trekking pole. Morale soars." % _n(_who()), "ponies")
		"mcafee":
			g.change_all("morale", 12.0)
			return _msg("McAfee Knob", lm["desc"] + "\n\nYou take the classic photo dangling your feet over the edge.", "vista")
		"wayside":
			return _choice("wayside", "Big Meadows Wayside", lm["desc"], "town",
				["Blackberry milkshakes for everyone ($%d)" % (7 * g.active_count()), "Keep walking"], {"cost": 7.0 * g.active_count()})
		"halfgallon":
			return _choice("halfgallon", "The Half-Gallon Challenge", lm["desc"], "town",
				["Take the challenge ($%d)" % (10 * g.active_count()), "No thanks"], {"cost": 10.0 * g.active_count()})
		"rocks":
			g.gear = maxf(0.0, g.gear - 10.0)
			g.shoe_miles += 80.0
			g.change_all("morale", -5.0)
			return _msg("Lehigh Gap", lm["desc"] + "\n\nThe rocks shred your shoes and gear. Gear −10%.", "rocks")
		"bearmtn":
			g.change_all("morale", 5.0)
			return _msg("Bear Mountain", lm["desc"] + "\n\nThe Manhattan skyline glimmers on the southern horizon.", "vista")
		"greylock":
			g.change_all("morale", 6.0)
			return _msg("Mount Greylock", lm["desc"], "summit")
		"whites":
			return _msg("The White Mountains", lm["desc"] + "\n\nThe next 100 miles are the hardest yet. Expect your daily mileage to drop sharply.", "summit")
		"franconia":
			g.change_all("morale", 10.0)
			return _msg("Franconia Ridge", lm["desc"], "summit")
		"washington":
			var bad: bool = g.weather in ["rain", "storm", "snow", "fog"]
			if bad:
				return _choice("washington", "Mount Washington", lm["desc"] + "\n\nThe forecast posted at Lakes of the Clouds hut: wind 70 mph, visibility near zero, wind chill below freezing.", "storm",
					["Wait at the hut for a better day", "Go for it anyway"])
			g.change_all("morale", 12.0)
			return _msg("Mount Washington", lm["desc"] + "\n\nBy some miracle, the summit is clear. You can see all the way to the Atlantic.", "summit")
		"mahoosuc":
			return _choice("mahoosuc", "Mahoosuc Notch", lm["desc"], "rocks",
				["Take it slow and careful (costs a day)", "Scramble through fast"])
		"kennebec":
			return _choice("kennebec", "Kennebec River", lm["desc"], "river",
				["Wait for the canoe ferry (next morning)", "Ford the river"])
		"wilderness":
			var fd: float = g.food_days()
			var warn := "You're carrying about %d days of food." % int(fd)
			if fd < 8:
				warn += " That may not be enough — stock up before you go."
			return _msg("The 100-Mile Wilderness", lm["desc"] + "\n\n" + warn, "forest")
		"harpers":
			g.change_all("morale", 10.0)
			return _msg("Harpers Ferry", lm["desc"] + "\n\nThe staff snap your photo for the hiker album. You're thru-hiker #%d this year." % (800 + randi() % 900), "town")
		"smokies_exit":
			g.change_all("morale", 6.0)
			return {}
		"shenandoah":
			return {}
	if lm["type"] == "landmark":
		g.change_all("morale", 4.0)
		return _msg(lm["name"], lm["desc"], "vista")
	return {}


# ------------------------------------------------------------------ resolution

func resolve(ev: Dictionary, idx: int) -> Dictionary:
	var out := _resolve_inner(ev, idx)
	if out.has("text"):
		g.log_entry(out["text"].split("\n")[0])
	g.state_changed.emit()
	return out


func _resolve_inner(ev: Dictionary, idx: int) -> Dictionary:
	var m := _who()
	var data: Dictionary = ev.get("data", {})
	var title: String = ev.get("title", "")
	if m.is_empty():
		return {"title": title, "text": "", "scene": ev.get("scene", "forest")}
	match ev["id"]:
		"bear":
			match idx:
				0:
					if randf() < 0.85:
						g.change_all("morale", -2.0)
						return _r(title, "You raise your poles, talk loudly, and back away. After a long moment the bear huffs and lumbers off into the laurel.", "bear")
					g.change_all("morale", -10.0)
					return _r(title, "The bear bluff-charges, stopping ten feet short, then crashes away into the brush. Hearts pounding, you continue.", "bear")
				1:
					var lost := _lose_food(0.0, randf_range(6.0, 10.0))
					g.change_all("morale", -4.0)
					return _r(title, "You toss a food bag and back off. The bear tears into it happily. Lost %.0f lb of food — and you've taught a bear a bad habit." % lost, "bear")
				2:
					g.change_all("morale", -8.0)
					if randf() < 0.5:
						return _r(title, "Never run from a bear. In the panic, %s trips over a root. %s The bear, confused, wanders away." % [_n(m), g.add_condition(m, "sprain")], "injury")
					return _r(title, "You scramble back down the trail. Luckily the bear isn't interested. It takes an hour to work up the nerve to continue.", "bear")
				3:
					if randf() < 0.6:
						g.change_all("morale", 8.0)
						return _r(title, "From a safe distance you get a perfect shot of the bear munching on acorns. It's going to be your phone background for years.", "bear")
					g.change_all("morale", -10.0)
					var t := "The bear doesn't like the attention and bluff-charges!"
					if randf() < 0.35:
						t += " Scrambling backward, " + g.add_condition(m, "sprain")
					return _r(title, t, "bear")
		"bear_camp":
			match idx:
				0:
					if randf() < 0.75:
						return _r(title, "The racket works. Heavy footsteps retreat into the dark. Nobody sleeps much after that.", "camp")
					var lost2 := _lose_food(0.3, 5.0)
					return _r(title, "The bear isn't impressed. It grabs a food bag and vanishes. Lost %.0f lb of food." % lost2, "bear")
				1:
					if randf() < 0.8:
						g.change_all("morale", 2.0)
						return _r(title, "Fumbling with a headlamp, you get the bag hung from a high branch. The bear sniffs around and gives up.", "camp")
					return _r(title, "You trip in the dark hanging the bag. " + g.add_condition(m, "sprain"), "injury")
				2:
					if randf() < 0.45:
						return _r(title, "After a few tense minutes, the noises fade. Lucky.", "camp")
					var lost3 := _lose_food(0.45, 6.0)
					g.gear = maxf(0.0, g.gear - 8.0)
					g.change_all("morale", -8.0)
					return _r(title, "In the morning, the vestibule is shredded and %.0f lb of food is gone. Gear −8%%." % lost3, "bear")
		"storm_ridge":
			if idx == 0:
				var roll := randf()
				if roll < 0.22:
					m["health"] = maxf(0.0, m["health"] - 28.0)
					g.change_all("morale", -15.0)
					return _r(title, "A blinding flash. Lightning strikes a rock just yards away and the shock knocks %s to the ground. They're dazed and burned, but alive." % _n(m), "storm")
				if roll < 0.45 and g.temperature < 60.0:
					return _r(title, "You make it across, but the wind-driven rain chills everyone to the bone. " + g.add_condition(m, "hypothermia"), "storm")
				g.change_all("morale", 4.0)
				return _r(title, "Heads down, you race across the ridge as thunder rolls overhead. You make it to the trees soaked but safe.", "storm")
			var lost_mi := _lose_miles(float(g.flags.get("last_dist", 10.0)) * 0.45)
			g.change_all("morale", -3.0)
			return _r(title, "You drop below treeline and huddle under a tarp while the storm passes. Safe, but you lose %.1f miles of progress." % lost_mi, "storm")
		"stream":
			var swollen: bool = data.get("swollen", false)
			match idx:
				0:
					var risk := 0.55 if swollen else 0.25
					if TrailData.region_for(g.miles) == "maine":
						risk += 0.1
					if randf() > risk:
						g.change_all("morale", -1.0)
						return _r(title, "You unbuckle hip belts, face upstream, and shuffle across. Cold feet, but everyone makes it.", "river")
					var roll2 := randf()
					if roll2 < 0.45:
						var lf := _lose_food(0.2, 3.0)
						g.gear = maxf(0.0, g.gear - 10.0)
						return _r(title, "%s loses their footing and their pack goes under. Lost %.0f lb of food to the current; soggy gear −10%%." % [_n(m), lf], "river")
					if roll2 < 0.8:
						return _r(title, "The current sweeps %s's feet out from under them. They crash into the rocks. %s" % [_n(m), g.add_condition(m, "sprain")], "river")
					m["health"] = maxf(0.0, m["health"] - 20.0)
					return _r(title, "%s is swept downstream before grabbing a branch. Dragged out shaking and frozen. %s" % [_n(m), g.add_condition(m, "hypothermia")], "river")
				1:
					var r: Dictionary = g.advance_day("rest")
					g.change_all("morale", -3.0)
					return _r(title, "You camp by the bank. By morning the water has dropped and you cross easily." + _extra(r), "river")
				2:
					var lm2 := _lose_miles(randf_range(2.0, 4.0))
					g.gear = maxf(0.0, g.gear - 3.0)
					return _r(title, "After a long bushwhack upstream you find a fallen tree spanning the water. Safe, but it costs %.1f miles." % lm2, "river")
		"lost":
			if idx == 0:
				var lm3 := _lose_miles(randf_range(1.5, 3.0))
				return _r(title, "You retrace your steps and find the white blaze you missed at a turn. Lost %.1f miles." % lm3, "forest")
			if randf() < 0.5:
				return _r(title, "Your compass work pays off — you pop out right on the trail.", "forest")
			var lm4 := _lose_miles(randf_range(4.0, 7.0))
			g.change_all("morale", -6.0)
			return _r(title, "You end up at a forest service road miles from the trail. By the time you're back, you've lost %.1f miles." % lm4, "forest")
		"sick_hiker":
			match idx:
				0:
					if g.supplies["first_aid"] <= 0:
						g.change_all("morale", -2.0)
						return _r(title, "You don't have any first-aid kits to give. You point them toward the next road crossing.", "camp")
					g.supplies["first_aid"] -= 1
					g.change_all("morale", 10.0)
					return _r(title, "You patch them up and they hike on gratefully. Days later, you find a thank-you note in a shelter log addressed to your group.", "camp")
				1:
					var lf2 := _lose_food(0.0, 5.0)
					g.change_all("morale", 6.0)
					return _r(title, "You share %.0f lb of food. They promise to pay it forward." % lf2, "camp")
				2:
					g.change_all("morale", -4.0)
					return _r(title, "You hike on, but nobody feels great about it.", "forest")
		"joiner":
			if idx == 0:
				var nm: String = data["name"]
				g.party.append({"name": nm, "trail_name": "", "health": 85.0, "morale": 85.0, "hunger": 20.0,
					"conditions": [], "active": true, "left_reason": "", "low_morale_days": 0})
				g.change_all("morale", 5.0)
				return _r(title, "%s joins the group! One more mouth to feed, but the miles go by faster with company." % nm, "camp")
			return _r(title, "They understand. You'll probably see them in the next town.", "camp")
		"smokies":
			if idx == 0:
				g.money -= data["fee"]
				return _r(title, "Permit in hand, you cross Fontana Dam into the park. Bears are common in the Smokies — keep your food hung.", "bear")
			if randf() < 0.4:
				g.money = maxf(0.0, g.money - 150.0)
				g.change_all("morale", -6.0)
				return _r(title, "A ranger at Mollies Ridge shelter checks permits. You don't have one. Fine: $150.", "camp")
			return _r(title, "You slip into the park without a permit. Nobody checks... this time.", "bear")
		"wayside":
			if idx == 0 and g.money >= data["cost"]:
				g.money -= data["cost"]
				g.change_all("morale", 10.0)
				g.change_all("hunger", -15.0)
				return _r(title, "The blackberry shakes are everything you were promised.", "town")
			return _r(title, "You walk past the smell of french fries. It hurts.", "forest")
		"halfgallon":
			if idx == 0 and g.money >= data["cost"]:
				g.money -= data["cost"]
				var lines: Array = []
				for mem in g.active_members():
					mem["hunger"] = 0.0
					if randf() < 0.6:
						mem["morale"] = clampf(mem["morale"] + 15.0, 0, 100)
						lines.append("%s finishes in %d minutes and earns the wooden spoon!" % [_n(mem), 18 + randi() % 40])
					else:
						mem["morale"] = clampf(mem["morale"] + 5.0, 0, 100)
						mem["health"] = clampf(mem["health"] - 3.0, 0, 100)
						lines.append("%s taps out with a quarter left and a stomachache." % _n(mem))
				return _r(title, "\n".join(lines), "town")
			return _r(title, "You skip the ice cream. The general store clerk looks disappointed in you.", "town")
		"washington":
			if idx == 0:
				var r2: Dictionary = g.advance_day("rest")
				g.weather = "clear"
				g.change_all("morale", 8.0)
				return _r(title, "You work for your stay at the hut, washing dishes for leftovers. The next morning dawns clear and calm, and you cross the summit easily." + _extra(r2), "summit")
			g.gear = maxf(0.0, g.gear - 15.0)
			g.change_all("morale", -10.0)
			if randf() < 0.45:
				return _r(title, "Winds knock you off your feet on the summit cone. Visibility is zero; you navigate cairn to cairn. " + g.add_condition(m, "hypothermia") + " Gear −15%.", "storm")
			return _r(title, "It's terrifying, but you crawl over the summit and down the other side. Gear −15%.", "storm")
		"mahoosuc":
			if idx == 0:
				var r3: Dictionary = g.advance_day("rest")
				g.change_all("health", -6.0)
				return _r(title, "You spend the whole day squeezing under and over boulders, passing packs hand to hand. One mile, eight hours — but no injuries." + _extra(r3), "rocks")
			if randf() < 0.4:
				return _r(title, "Moving fast, %s's foot slips into a crevice. %s" % [_n(m), g.add_condition(m, "sprain")], "injury")
			g.gear = maxf(0.0, g.gear - 10.0)
			return _r(title, "You scramble through in record time, scraping packs and shins on the granite. Gear −10%.", "rocks")
		"kennebec":
			if idx == 0:
				var r4: Dictionary = g.advance_day("rest")
				g.change_all("morale", 5.0)
				return _r(title, "The ferryman paddles you across one at a time. There's a white blaze painted on the floor of the canoe." + _extra(r4), "river")
			if randf() < 0.55:
				var lf3 := _lose_food(0.3, 5.0)
				m["health"] = maxf(0.0, m["health"] - 30.0)
				return _r(title, "Halfway across, the dam upstream releases. The river surges. %s is swept away and barely makes it to shore. Lost %.0f lb of food. %s" % [_n(m), lf3, g.add_condition(m, "hypothermia")], "river")
			return _r(title, "You make it across the chest-deep river, but it was a foolish risk.", "river")
	return {"title": title, "text": "", "scene": ev.get("scene", "forest")}


func _r(title: String, text: String, scene: String) -> Dictionary:
	return {"title": title, "text": text, "scene": scene}


func _extra(r: Dictionary) -> String:
	if r.get("game_over", "") != "":
		return "\n\n" + r["game_over"]
	return ""
