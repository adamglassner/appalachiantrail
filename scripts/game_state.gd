extends Node
## Global game state: party, supplies, calendar, daily simulation, events and saving.

signal state_changed
signal journal_added(entry: Dictionary)

const SAVE_PATH := "user://appalachian_trail_save.json"
const TOTAL_MILES := 2198.0

const PACE_NAMES := ["Slow", "Steady", "Push"]
const PACE_MILES := [12.0, 17.0, 22.0]
const RATION_NAMES := ["Full", "Half", "Bare"]
const RATION_LBS := [2.0, 1.3, 0.8]
const WATER_PER_HIKER := 3.0

const PROFESSIONS := [
	{"name": "Software Engineer", "sub": "on sabbatical", "money": 2800, "mult": 1.0,
		"desc": "Plenty of savings for hostels and town food. Score ×1."},
	{"name": "Schoolteacher", "sub": "with the summer off (and then some)", "money": 2300, "mult": 2.0,
		"desc": "A modest budget that needs careful planning. Score ×2."},
	{"name": "Recent Grad", "sub": "living on ramen and hope", "money": 1900, "mult": 3.0,
		"desc": "Every dollar counts — expect to forage. Score ×3."},
]

const START_DATES := [
	{"label": "March 1", "month": 3, "day": 1, "note": "Cold and quiet. Expect snow in the Smokies, but plenty of time."},
	{"label": "March 20", "month": 3, "day": 20, "note": "The classic start — crowded shelters and lots of trail magic."},
	{"label": "April 15", "month": 4, "day": 15, "note": "Warmer weather, but less margin before Katahdin closes."},
	{"label": "May 15", "month": 5, "day": 15, "note": "A late start. You'll have to push hard to beat October 15."},
]

const STORE_ITEMS := {
	"food": {"name": "Trail food", "unit": "lb", "price": 2.75, "step": 10,
		"desc": "Tortillas, peanut butter, ramen, candy bars. About 2 lb per hiker per day on full rations."},
	"water_cap": {"name": "Water bottles", "unit": "L of capacity", "price": 3.0, "step": 1,
		"desc": "Carry more water through dry stretches. Each hiker needs ~3 L a day."},
	"fuel": {"name": "Stove fuel", "unit": "canister", "price": 7.0, "step": 1,
		"desc": "Hot dinners keep morale up. One canister lasts about 10 hiker-days."},
	"first_aid": {"name": "First-aid kits", "unit": "kit", "price": 25.0, "step": 1,
		"desc": "Treats injuries and illnesses so they heal much faster."},
	"shoes": {"name": "Trail runners", "unit": "pair", "price": 110.0, "step": 1,
		"desc": "A pair lasts ~500 miles. Worn-out shoes mean blisters and slow going."},
}

const CONDITIONS := {
	"blisters": {"name": "blisters", "drain": 2.0, "days": 4, "pace": 0.92},
	"shin": {"name": "shin splints", "drain": 2.5, "days": 5, "pace": 0.85},
	"sprain": {"name": "a sprained ankle", "drain": 3.5, "days": 6, "pace": 0.65},
	"giardia": {"name": "giardia", "drain": 6.0, "days": 7, "pace": 0.75},
	"noro": {"name": "norovirus", "drain": 9.0, "days": 3, "pace": 0.5},
	"lyme": {"name": "Lyme disease", "drain": 4.5, "days": 10, "pace": 0.85},
	"hypothermia": {"name": "hypothermia", "drain": 11.0, "days": 2, "pace": 0.6},
	"heat": {"name": "heat exhaustion", "drain": 8.0, "days": 2, "pace": 0.7},
	"fracture": {"name": "a broken wrist", "drain": 5.0, "days": 12, "pace": 0.8},
	"food_poison": {"name": "food poisoning", "drain": 7.0, "days": 2, "pace": 0.6},
}

var party: Array = []
var money: float = 0.0
var supplies := {"food": 0.0, "water": 0.0, "water_cap": 0.0, "fuel": 0, "first_aid": 0, "shoes": 0}
var gear: float = 100.0
var shoe_miles: float = 0.0
var day: int = 1
var start_unix: int = 0
var miles: float = 0.0
var pace: int = 1
var rations: int = 0
var next_landmark: int = 1
var at_landmark: int = 0
var profession: int = 0
var weather := "clear"
var temperature: float = 55.0
var journal: Array = []
var flags := {}
var finished := false
var game_over_reason := ""
var no_water_days := 0
var days_hiked := 0
var zero_days := 0

var events: TrailEvents


func _ready() -> void:
	randomize()
	events = TrailEvents.new(self)


# ---------------------------------------------------------------- setup

func new_game(prof: int, names: Array, start_idx: int) -> void:
	profession = prof
	money = PROFESSIONS[prof]["money"] * names.size()
	party.clear()
	for n in names:
		party.append({"name": n, "trail_name": "", "health": 100.0, "morale": 80.0, "hunger": 10.0,
			"conditions": [], "active": true, "left_reason": "", "low_morale_days": 0})
	supplies = {"food": 0.0, "water": 0.0, "water_cap": 2.0 * names.size(), "fuel": 0, "first_aid": 0, "shoes": 0}
	gear = 100.0
	shoe_miles = 0.0
	day = 1
	var sd: Dictionary = START_DATES[start_idx]
	start_unix = Time.get_unix_time_from_datetime_dict({"year": 2027, "month": sd["month"], "day": sd["day"], "hour": 12, "minute": 0, "second": 0})
	miles = 0.0
	pace = 1
	rations = 0
	next_landmark = 1
	at_landmark = 0
	weather = "clear"
	temperature = 50.0
	journal.clear()
	flags = {}
	finished = false
	game_over_reason = ""
	no_water_days = 0
	days_hiked = 0
	zero_days = 0
	log_entry("Signed the register at Springer Mountain. %d hiker%s, %s. Katahdin is 2,198 miles north." % [names.size(), "" if names.size() == 1 else "s", PROFESSIONS[prof]["name"].to_lower() + " budget"])
	state_changed.emit()


# ---------------------------------------------------------------- helpers

func active_members() -> Array:
	return party.filter(func(m): return m["active"])


func active_count() -> int:
	return active_members().size()


func display_name(m: Dictionary) -> String:
	if m["trail_name"] != "":
		return "%s \"%s\"" % [m["name"], m["trail_name"]]
	return m["name"]


func short_name(m: Dictionary) -> String:
	return m["trail_name"] if m["trail_name"] != "" else m["name"]


func random_member() -> Dictionary:
	var a := active_members()
	if a.is_empty():
		return {}
	return a[randi() % a.size()]


func date_dict(offset_days: int = 0) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(start_unix + (day - 1 + offset_days) * 86400)


func date_string(offset_days: int = 0) -> String:
	var d := date_dict(offset_days)
	return "%s %d, %d" % [TrailData.MONTHS[d["month"] - 1], d["day"], d["year"]]


func short_date() -> String:
	var d := date_dict()
	return "%s %d" % [TrailData.MONTHS[d["month"] - 1].substr(0, 3), d["day"]]


func month() -> int:
	return date_dict()["month"]


func season_amount() -> float:
	# 0 = early spring (bare / budding), 0.33 = summer green, 0.66+ = autumn colors
	var d := date_dict()
	var doy: float = (d["month"] - 1) * 30.4 + d["day"]
	# factor in latitude: north greens later, turns earlier
	var lat_shift := (miles / TOTAL_MILES) * 18.0
	var v := (doy - 60.0 - lat_shift * 0.5) / 210.0 + lat_shift / 400.0
	return clampf(v, 0.0, 1.0)


func next_landmark_data() -> Dictionary:
	return TrailData.LANDMARKS[min(next_landmark, TrailData.LANDMARKS.size() - 1)]


func miles_to_next() -> float:
	return maxf(0.0, next_landmark_data()["mile"] - miles)


func log_entry(text: String) -> void:
	var e := {"day": day, "date": short_date(), "miles": int(miles), "text": text}
	journal.append(e)
	journal_added.emit(e)


func add_condition(m: Dictionary, cid: String) -> String:
	var c: Dictionary = CONDITIONS[cid]
	var days: int = c["days"]
	var extra := ""
	for existing in m["conditions"]:
		if existing["id"] == cid:
			existing["days"] = max(existing["days"], days)
			return "%s's %s got worse." % [short_name(m), c["name"]]
	if c["drain"] >= 3.0 and supplies["first_aid"] > 0:
		supplies["first_aid"] -= 1
		days = int(ceil(days / 2.0))
		extra = " A first-aid kit helps."
	m["conditions"].append({"id": cid, "days": days})
	return "%s has %s.%s" % [short_name(m), c["name"], extra]


func has_condition(cid: String) -> bool:
	for m in active_members():
		for c in m["conditions"]:
			if c["id"] == cid:
				return true
	return false


func average(stat: String) -> float:
	var a := active_members()
	if a.is_empty():
		return 0.0
	var s := 0.0
	for m in a:
		s += m[stat]
	return s / a.size()


func health_word(h: float) -> String:
	if h >= 75:
		return "good"
	if h >= 50:
		return "fair"
	if h >= 25:
		return "poor"
	return "very poor"


func pace_factor() -> float:
	var f := 1.0
	for m in active_members():
		for c in m["conditions"]:
			f = minf(f, CONDITIONS[c["id"]]["pace"])
	return f


func change_all(stat: String, amount: float) -> void:
	for m in active_members():
		m[stat] = clampf(m[stat] + amount, 0.0, 100.0)


func food_days() -> float:
	var n := active_count()
	if n == 0:
		return 0.0
	return supplies["food"] / (RATION_LBS[rations] * n)


# ---------------------------------------------------------------- weather

func roll_weather() -> void:
	var m := month()
	var base_temp := {3: 42, 4: 54, 5: 63, 6: 71, 7: 76, 8: 74, 9: 66, 10: 52, 11: 40}
	var t: float = base_temp.get(m, 50)
	t -= (miles / TOTAL_MILES) * 9.0
	t += TrailData.elevation_bonus(miles)
	t += randf_range(-9.0, 9.0)
	temperature = t
	if randf() < 0.35 and weather != "storm":
		# weather often persists
		if weather == "snow" and t > 36:
			weather = "rain"
		return
	var precip := randf() < (0.34 if m < 9 else 0.26)
	if precip:
		if t < 34.0:
			weather = "snow"
		elif m >= 5 and m <= 8 and randf() < 0.4:
			weather = "storm"
		else:
			weather = "rain"
	else:
		var r := randf()
		if t >= 82.0 and r < 0.6:
			weather = "hot"
		elif r < 0.12:
			weather = "fog"
		elif r < 0.45:
			weather = "cloudy"
		else:
			weather = "clear"


func weather_label() -> String:
	match weather:
		"clear":
			return "Clear"
		"cloudy":
			return "Cloudy"
		"rain":
			return "Rain"
		"storm":
			return "Thunderstorms"
		"snow":
			return "Snow"
		"fog":
			return "Fog"
		"hot":
			return "Hot & humid"
	return weather.capitalize()


# ---------------------------------------------------------------- daily simulation

## mode: "hike", "rest", "forage", "town"
func advance_day(mode: String = "hike") -> Dictionary:
	var result := {"messages": [], "choice": {}, "arrived": -1, "game_over": "", "miles_today": 0.0}
	if finished or game_over_reason != "":
		return result
	roll_weather()
	var n := active_count()
	var terrain := TrailData.terrain_at(miles)

	# ---- distance
	var dist := 0.0
	if mode == "hike":
		var h := average("health")
		var health_f := 0.55 + 0.45 * clampf(h / 80.0, 0.0, 1.0)
		var weather_f := 1.0
		match weather:
			"rain":
				weather_f = 0.88
			"storm":
				weather_f = 0.75
			"snow":
				weather_f = 0.6
			"hot":
				weather_f = 0.85
			"fog":
				weather_f = 0.95
		var shoe_f := 1.0 if (shoe_miles < 500.0) else 0.88
		var gear_f := 1.0 if gear > 20.0 else 0.85
		dist = PACE_MILES[pace] / terrain * health_f * weather_f * shoe_f * gear_f * pace_factor()
		dist *= randf_range(0.9, 1.1)
		if supplies["food"] <= 0.0:
			dist *= 0.7
		dist = maxf(dist, 2.0)
		# don't overshoot the next landmark
		var lm_mile: float = next_landmark_data()["mile"]
		if miles + dist >= lm_mile:
			dist = lm_mile - miles
			result["arrived"] = next_landmark
		miles += dist
		shoe_miles += dist
		days_hiked += 1
	else:
		zero_days += 1
	result["miles_today"] = dist
	flags["last_dist"] = dist

	# ---- food
	var lbs_each: float = RATION_LBS[rations]
	var need := lbs_each * n
	var ate_fraction := 1.0
	if mode == "town":
		need = 0.0  # eating town food
	if need > 0.0:
		if supplies["food"] >= need:
			supplies["food"] -= need
		else:
			ate_fraction = supplies["food"] / need if need > 0 else 0.0
			supplies["food"] = 0.0
	var hunger_delta := 0.0
	if mode == "town":
		hunger_delta = -30.0
	else:
		match rations:
			0:
				hunger_delta = -14.0
			1:
				hunger_delta = 6.0
			2:
				hunger_delta = 15.0
		if ate_fraction < 1.0:
			hunger_delta = lerpf(30.0, hunger_delta, ate_fraction)
		if mode == "hike" and pace == 2:
			hunger_delta += 5.0
		if mode == "rest":
			hunger_delta -= 4.0

	# ---- water
	var water_need := WATER_PER_HIKER * n * (1.5 if weather == "hot" else 1.0)
	var refill_chance := 0.9
	var reg := TrailData.region_for(miles)
	var m := month()
	if (reg == "virginia" or reg == "mid") and m >= 7 and m <= 9:
		refill_chance = 0.62
	if mode != "hike":
		refill_chance = 1.0
	var dehydrated := false
	if supplies["water"] >= water_need:
		supplies["water"] -= water_need
	else:
		dehydrated = true
		supplies["water"] = 0.0
	if randf() < refill_chance:
		supplies["water"] = supplies["water_cap"]
		if dehydrated:
			dehydrated = false  # found a spring in time
		# untreated water risk when gear (filter) is in bad shape
		if gear < 30.0 and randf() < 0.08:
			var victim := random_member()
			if not victim.is_empty():
				result["messages"].append({"text": "Your water filter is clogged and cracked. " + add_condition(victim, "giardia"), "major": true, "title": "Bad Water", "scene": "injury"})
	if dehydrated:
		no_water_days += 1
		change_all("health", -8.0)
		change_all("morale", -6.0)
		result["messages"].append({"text": "The springs on this ridge are dry. The party is dehydrated.", "major": no_water_days >= 2, "title": "No Water", "scene": "vista"})
	else:
		no_water_days = 0

	# ---- fuel
	var cold_dinner := false
	if n > 0:
		var fuel_use := n / 10.0
		var fuel_left: float = supplies["fuel"] - fuel_use + flags.get("fuel_frac", 0.0)
		if fuel_left < 0.0:
			cold_dinner = true
			supplies["fuel"] = 0
			flags["fuel_frac"] = 0.0
		else:
			supplies["fuel"] = int(floor(fuel_left))
			flags["fuel_frac"] = fuel_left - floor(fuel_left)

	# ---- gear wear
	if mode == "hike":
		var wear := 0.25 + dist * 0.025 * terrain
		if miles > 1150 and miles < 1300:
			wear *= 1.8  # Pennsylvania rocks
		if weather == "rain" or weather == "storm" or weather == "snow":
			wear *= 1.3
		gear = maxf(0.0, gear - wear)

	# shoes
	if shoe_miles >= 500.0:
		if supplies["shoes"] >= n and n > 0:
			supplies["shoes"] -= n
			shoe_miles = 0.0
			result["messages"].append({"text": "The party laces up fresh pairs of trail runners. The old ones are held together with duct tape.", "major": false})
		elif not flags.get("shoe_warned", false):
			flags["shoe_warned"] = true
			result["messages"].append({"text": "Everyone's shoes are worn through. Without new pairs, blisters are inevitable.", "major": false})

	# ---- per-member health and morale
	for mem in active_members():
		var dh := 1.5
		var dm := 0.0
		match mode:
			"rest":
				dh += 7.0
				dm += 8.0
			"town":
				dh += 9.0
				dm += 12.0
			"forage":
				dh += 3.0
				dm += 3.0
		if mode == "hike":
			dm += 2.0  # trail life agrees with you
			if pace == 2:
				dh -= 3.0
				dm -= 2.0
			elif pace == 0:
				dh += 1.5
				dm += 1.0
		mem["hunger"] = clampf(mem["hunger"] + hunger_delta, 0.0, 100.0)
		if mem["hunger"] > 55.0:
			dh -= (mem["hunger"] - 55.0) / 6.0
			dm -= 2.0
		match weather:
			"clear":
				dm += 2.0
			"rain":
				dm -= 3.0
			"storm":
				dm -= 5.0
			"snow":
				dm -= 3.0
			"hot":
				dm -= 2.0
		if temperature < 35.0 and gear < 40.0:
			dh -= 3.0
		if cold_dinner:
			dm -= 3.0
		if mem["morale"] < 20.0:
			dh -= 1.5
		# conditions
		var still: Array = []
		for c in mem["conditions"]:
			dh -= CONDITIONS[c["id"]]["drain"] * (0.5 if mode != "hike" else 1.0)
			c["days"] -= 2 if mode != "hike" else 1
			if c["days"] > 0:
				still.append(c)
			else:
				result["messages"].append({"text": "%s has recovered from %s." % [short_name(mem), CONDITIONS[c["id"]]["name"]], "major": false})
		mem["conditions"] = still
		mem["health"] = clampf(mem["health"] + dh, 0.0, 100.0)
		mem["morale"] = clampf(mem["morale"] + dm, 0.0, 100.0)

	# ---- random events (only while hiking or foraging)
	if mode == "hike" or mode == "forage":
		var ev := events.roll_daily(mode, result["arrived"] != -1)
		if not ev.is_empty():
			if ev.has("choices"):
				result["choice"] = ev
			else:
				result["messages"].append(ev)

	# ---- trail names (once each, after the first ~60 miles)
	if mode == "hike" and miles > 60.0:
		for mem in active_members():
			if mem["trail_name"] == "" and randf() < 0.06:
				var used := party.map(func(p): return p["trail_name"])
				var pool := TrailData.TRAIL_NAMES.filter(func(t): return not used.has(t))
				mem["trail_name"] = pool[randi() % pool.size()]
				result["messages"].append({"text": "Other hikers have started calling %s \"%s.\" The trail name sticks." % [mem["name"], mem["trail_name"]], "major": false})
				break

	# ---- departures
	for mem in active_members():
		if mem["morale"] <= 0.0:
			mem["low_morale_days"] += 1
		else:
			mem["low_morale_days"] = 0
		if mem["health"] <= 0.0:
			var cause := "exhaustion"
			if not mem["conditions"].is_empty():
				cause = CONDITIONS[mem["conditions"][0]["id"]]["name"]
			mem["active"] = false
			mem["left_reason"] = "Evacuated with %s" % cause
			result["messages"].append({"text": "%s collapsed from %s. A ranger arranges an evacuation — %s's hike is over." % [short_name(mem), cause, short_name(mem)], "major": true, "title": "Off the Trail", "scene": "injury"})
			log_entry("%s left the trail (%s)." % [display_name(mem), cause])
		elif mem["low_morale_days"] >= 3:
			mem["active"] = false
			mem["left_reason"] = "Went home"
			result["messages"].append({"text": "%s has had enough. They hitch to the nearest town and catch a bus home." % short_name(mem), "major": true, "title": "Off the Trail", "scene": "town"})
			log_entry("%s quit the trail and went home." % display_name(mem))

	day += 1

	# ---- journal summary
	if mode == "hike":
		log_entry("Hiked %.1f miles in %s. %s." % [dist, weather_label().to_lower(), TrailData.state_at(miles)])
	elif mode == "rest":
		log_entry("Zero day. Rested and ate.")
	for msg in result["messages"]:
		if msg.get("major", false) and not msg["text"].ends_with("is over."):
			log_entry(msg["text"])

	# ---- end checks
	if active_count() == 0:
		game_over_reason = "Every member of your party has left the trail."
		result["game_over"] = game_over_reason
	else:
		var d := date_dict()
		if (d["month"] > 10 or (d["month"] == 10 and d["day"] > 15)) and not finished:
			game_over_reason = "Baxter State Park has closed Katahdin for the season. You'll have to come back next year."
			result["game_over"] = game_over_reason

	if result["arrived"] != -1:
		at_landmark = result["arrived"]
		next_landmark = min(result["arrived"] + 1, TrailData.LANDMARKS.size() - 1)
		var lm: Dictionary = TrailData.LANDMARKS[at_landmark]
		log_entry("Arrived at %s, %s (mile %d)." % [lm["name"], lm["state"], int(lm["mile"])])
	state_changed.emit()
	return result


# ---------------------------------------------------------------- town & store

func store_price(item: String) -> float:
	var mult: float = TrailData.LANDMARKS[at_landmark].get("store", 1.0)
	if at_landmark == 0:
		mult = 1.0
	return snappedf(STORE_ITEMS[item]["price"] * mult, 0.01)


func buy(item: String, qty: int) -> bool:
	var cost := store_price(item) * qty
	if cost > money + 0.001 or qty <= 0:
		return false
	money -= cost
	supplies[item] += qty
	if item == "water_cap":
		supplies["water"] = supplies["water_cap"]
	state_changed.emit()
	return true


func gear_repair_cost() -> float:
	return snappedf((100.0 - gear) * 2.5, 1.0)


func repair_gear() -> bool:
	var c := gear_repair_cost()
	if c <= 0 or c > money:
		return false
	money -= c
	gear = 100.0
	log_entry("Replaced worn gear at the outfitter ($%d)." % int(c))
	state_changed.emit()
	return true


func town_service(kind: String) -> String:
	var n := active_count()
	match kind:
		"hostel":
			var cost := 35.0 * n
			if money < cost:
				return "You can't afford a hostel bunk."
			money -= cost
			var r := advance_day("town")
			for mem in active_members():
				mem["morale"] = clampf(mem["morale"] + 10.0, 0, 100)
			log_entry("Took a zero at the hostel. Hot showers, laundry, real beds.")
			supplies["water"] = supplies["water_cap"]
			return "A zero day at the hostel: hot showers, laundry, and a real mattress. Everyone feels human again." + _town_extra(r)
		"meal":
			var cost2 := 22.0 * n
			if money < cost2:
				return "You can't afford a restaurant meal."
			money -= cost2
			for mem in active_members():
				mem["hunger"] = 0.0
				mem["morale"] = clampf(mem["morale"] + 12.0, 0, 100)
				mem["health"] = clampf(mem["health"] + 3.0, 0, 100)
			log_entry("Demolished an all-you-can-eat buffet.")
			state_changed.emit()
			return "The party demolishes an all-you-can-eat buffet. The staff look concerned."
	return ""


func _town_extra(r: Dictionary) -> String:
	if r.get("game_over", "") != "":
		return "\n\n" + r["game_over"]
	return ""


func chatter() -> Array:
	var list: Array = TrailData.CHATTER[TrailData.region_for(miles)]
	return list[randi() % list.size()]


# ---------------------------------------------------------------- forage

func apply_forage(lbs: float, toxic: int) -> Dictionary:
	var result := advance_day("forage")
	var cap := 30.0
	var kept := minf(lbs, cap)
	supplies["food"] += kept
	var text := ""
	if lbs <= 0.1:
		text = "You spent the day searching but came back empty-handed."
	else:
		text = "You gathered %.0f lb of wild food." % lbs
		if lbs > cap:
			text += " You can only pack out %.0f lb." % cap
	if toxic > 0:
		var victim := random_member()
		if not victim.is_empty():
			text += "\n\nSomething you picked wasn't edible. " + add_condition(victim, "food_poison")
	log_entry("Foraged for the day: %.0f lb of food." % kept)
	result["forage_text"] = text
	state_changed.emit()
	return result


# ---------------------------------------------------------------- scoring

func score_breakdown() -> Dictionary:
	var lines: Array = []
	var total := 0
	for mem in party:
		if mem["active"]:
			var pts := 500 if mem["health"] >= 75 else (350 if mem["health"] >= 50 else 200)
			lines.append(["%s (%s health)" % [display_name(mem), health_word(mem["health"])], pts])
			total += pts
	var food_pts := int(supplies["food"])
	var kit_pts: int = supplies["first_aid"] * 20
	var money_pts := int(money / 5.0)
	var gear_pts := int(gear * 2.0)
	var days := day - 1
	var speed_pts: int = max(0, 190 - days) * 8
	lines.append(["Food left (%d lb)" % int(supplies["food"]), food_pts])
	lines.append(["First-aid kits (%d)" % supplies["first_aid"], kit_pts])
	lines.append(["Cash ($%d)" % int(money), money_pts])
	lines.append(["Gear condition (%d%%)" % int(gear), gear_pts])
	lines.append(["Speed bonus (%d days)" % days, speed_pts])
	total += food_pts + kit_pts + money_pts + gear_pts + speed_pts
	var mult: float = PROFESSIONS[profession]["mult"]
	var final := int(total * mult)
	return {"lines": lines, "subtotal": total, "mult": mult, "total": final}


# ---------------------------------------------------------------- save / load

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var data := {
		"version": 1, "party": party, "money": money, "supplies": supplies, "gear": gear,
		"shoe_miles": shoe_miles, "day": day, "start_unix": start_unix, "miles": miles,
		"pace": pace, "rations": rations, "next_landmark": next_landmark, "at_landmark": at_landmark,
		"profession": profession, "weather": weather, "temperature": temperature,
		"journal": journal, "flags": flags, "no_water_days": no_water_days,
		"days_hiked": days_hiked, "zero_days": zero_days,
		"saved_at": Time.get_datetime_string_from_system(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	party = d["party"]
	for mem in party:
		for c in mem["conditions"]:
			c["days"] = int(c["days"])
		mem["low_morale_days"] = int(mem.get("low_morale_days", 0))
	money = float(d["money"])
	supplies = d["supplies"]
	for k in ["fuel", "first_aid", "shoes"]:
		supplies[k] = int(supplies[k])
	gear = float(d["gear"])
	shoe_miles = float(d["shoe_miles"])
	day = int(d["day"])
	start_unix = int(d["start_unix"])
	miles = float(d["miles"])
	pace = int(d["pace"])
	rations = int(d["rations"])
	next_landmark = int(d["next_landmark"])
	at_landmark = int(d["at_landmark"])
	profession = int(d["profession"])
	weather = d.get("weather", "clear")
	temperature = float(d.get("temperature", 55.0))
	journal = d["journal"]
	flags = d.get("flags", {})
	no_water_days = int(d.get("no_water_days", 0))
	days_hiked = int(d.get("days_hiked", 0))
	zero_days = int(d.get("zero_days", 0))
	finished = false
	game_over_reason = ""
	state_changed.emit()
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func saved_summary() -> String:
	if not has_save():
		return ""
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var lm_idx := int(parsed.get("at_landmark", 0))
	var names: Array = []
	for mem in parsed.get("party", []):
		names.append(mem["name"])
	return "Day %d · Mile %d · near %s · %s" % [int(parsed["day"]), int(parsed["miles"]),
		TrailData.LANDMARKS[lm_idx]["name"], ", ".join(names)]
