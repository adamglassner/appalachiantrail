class_name TrailData
extends RefCounted
## Static data for the trail: landmarks, towns, map coordinates and hiker chatter.

# type: start / town / landmark / river / finish
# terrain: difficulty multiplier for the stretch AFTER this point (1.0 = average)
# store: price multiplier for the town store (0 = no store)
# lat/lon: approximate real coordinates, used to draw the trail on the 3D map
const LANDMARKS := [
	{"name": "Springer Mountain", "state": "GA", "mile": 0.0, "type": "start", "terrain": 1.1, "lat": 34.63, "lon": -84.19,
		"desc": "A bronze plaque and the first white blaze. Two thousand miles of ridgeline stretch north from this summit."},
	{"name": "Neel Gap", "state": "GA", "mile": 31.0, "type": "town", "store": 1.25, "terrain": 1.1, "lat": 34.73, "lon": -83.92,
		"desc": "Mountain Crossings outfitter — the trail runs right through the building. The tree out front is hung with boots from hikers who quit here."},
	{"name": "Hiawassee", "state": "GA", "mile": 69.0, "type": "town", "store": 1.0, "terrain": 1.1, "lat": 34.92, "lon": -83.68,
		"desc": "A hitch down from Dicks Creek Gap. Grocery store, buffet, and a motel full of hikers airing out their tents."},
	{"name": "Georgia–North Carolina Line", "state": "NC", "mile": 78.0, "type": "landmark", "terrain": 1.15, "lat": 34.99, "lon": -83.55,
		"desc": "A small wooden sign on a gnarled tree. One state down, thirteen to go."},
	{"name": "Franklin", "state": "NC", "mile": 110.0, "type": "town", "store": 1.0, "terrain": 1.15, "lat": 35.12, "lon": -83.52,
		"desc": "A trail town that loves hikers. The shuttle from Winding Stair Gap drops you at the outfitter."},
	{"name": "Nantahala Outdoor Center", "state": "NC", "mile": 137.0, "type": "town", "store": 1.2, "terrain": 1.25, "lat": 35.33, "lon": -83.59,
		"desc": "Whitewater rafters and thru-hikers share the riverside burgers. The 3,000-foot climb out of the gorge is infamous."},
	{"name": "Fontana Dam", "state": "NC", "mile": 165.0, "type": "landmark", "special": "smokies_enter", "terrain": 1.25, "lat": 35.45, "lon": -83.81,
		"desc": "The 'Fontana Hilton' shelter overlooks the dam. Across it lies Great Smoky Mountains National Park."},
	{"name": "Clingmans Dome", "state": "TN", "mile": 198.0, "type": "landmark", "special": "clingmans", "terrain": 1.15, "lat": 35.56, "lon": -83.50,
		"desc": "At 6,643 feet, the highest point on the entire Appalachian Trail. A concrete spiral tower rises above the spruce-fir forest."},
	{"name": "Newfound Gap", "state": "TN", "mile": 207.0, "type": "town", "store": 1.15, "terrain": 1.2, "lat": 35.61, "lon": -83.43,
		"desc": "The highway pass over the Smokies. Tourists offer snacks; a hitch to Gatlinburg brings pancakes and resupply."},
	{"name": "Standing Bear Farm", "state": "NC", "mile": 240.0, "type": "town", "store": 1.3, "special": "smokies_exit", "terrain": 1.15, "lat": 35.76, "lon": -83.11,
		"desc": "A ramshackle hiker hostel just past the Smokies. Bunkhouses, a tiny resupply shed, and a creek to soak sore feet."},
	{"name": "Hot Springs", "state": "NC", "mile": 275.0, "type": "town", "store": 1.0, "terrain": 1.1, "lat": 35.89, "lon": -82.83,
		"desc": "The trail follows the sidewalk down Main Street. Mineral hot tubs on the French Broad River await."},
	{"name": "Erwin", "state": "TN", "mile": 343.0, "type": "town", "store": 1.0, "terrain": 1.15, "lat": 36.11, "lon": -82.42,
		"desc": "Uncle Johnny's and the Nolichucky River. Hikers swap stories while their laundry spins."},
	{"name": "Roan Highlands", "state": "TN", "mile": 380.0, "type": "landmark", "special": "roan", "terrain": 1.05, "lat": 36.10, "lon": -82.13,
		"desc": "Open grassy balds roll for miles above 5,000 feet. Glorious views — and nowhere to hide from lightning."},
	{"name": "Damascus", "state": "VA", "mile": 470.0, "type": "town", "store": 0.95, "terrain": 1.0, "lat": 36.63, "lon": -81.79,
		"desc": "'Trail Town USA.' Every May, thousands gather here for Trail Days."},
	{"name": "Grayson Highlands", "state": "VA", "mile": 500.0, "type": "landmark", "special": "ponies", "terrain": 1.0, "lat": 36.63, "lon": -81.52,
		"desc": "Rocky alpine meadows where shaggy wild ponies graze — and lick the salt off hikers' legs."},
	{"name": "Atkins", "state": "VA", "mile": 545.0, "type": "town", "store": 1.05, "terrain": 0.95, "lat": 36.87, "lon": -81.42,
		"desc": "The Barn restaurant is legendary for its breakfast. The trail ducks under I-81 here."},
	{"name": "Pearisburg", "state": "VA", "mile": 635.0, "type": "town", "store": 1.0, "terrain": 1.0, "lat": 37.33, "lon": -80.74,
		"desc": "A quiet town on the New River with a full grocery store and a church hostel."},
	{"name": "McAfee Knob", "state": "VA", "mile": 710.0, "type": "landmark", "special": "mcafee", "terrain": 1.0, "lat": 37.38, "lon": -80.04,
		"desc": "A dramatic rock ledge jutting over the Catawba Valley. The most photographed spot on the trail."},
	{"name": "Daleville", "state": "VA", "mile": 727.0, "type": "town", "store": 1.0, "terrain": 1.0, "lat": 37.41, "lon": -79.91,
		"desc": "Motels, fast food, and an outfitter right off the trail. Easy resupply after the Triple Crown of Virginia."},
	{"name": "Waynesboro", "state": "VA", "mile": 865.0, "type": "town", "store": 0.95, "special": "shenandoah", "terrain": 0.85, "lat": 38.03, "lon": -78.86,
		"desc": "Gateway to Shenandoah National Park. The YMCA lets hikers camp and shower."},
	{"name": "Big Meadows", "state": "VA", "mile": 915.0, "type": "landmark", "special": "wayside", "terrain": 0.85, "lat": 38.52, "lon": -78.44,
		"desc": "Skyline Drive waysides sell blackberry milkshakes. Deer and bears wander the meadows at dusk."},
	{"name": "Front Royal", "state": "VA", "mile": 970.0, "type": "town", "store": 1.0, "terrain": 0.95, "lat": 38.92, "lon": -78.19,
		"desc": "The northern gate of Shenandoah. A free shuttle runs to the supermarkets."},
	{"name": "Harpers Ferry", "state": "WV", "mile": 1025.0, "type": "town", "store": 1.0, "special": "harpers", "terrain": 0.9, "lat": 39.33, "lon": -77.74,
		"desc": "The 'psychological halfway point.' Get your photo taken at the Appalachian Trail Conservancy headquarters."},
	{"name": "Pine Grove Furnace", "state": "PA", "mile": 1095.0, "type": "landmark", "special": "halfgallon", "terrain": 0.9, "lat": 40.03, "lon": -77.30,
		"desc": "The true halfway point. Tradition says you must eat a half gallon of ice cream at the general store."},
	{"name": "Duncannon", "state": "PA", "mile": 1150.0, "type": "town", "store": 0.95, "terrain": 1.15, "lat": 40.40, "lon": -77.03,
		"desc": "The trail crosses the wide Susquehanna on a highway bridge. North of here, the rocks begin."},
	{"name": "Lehigh Gap", "state": "PA", "mile": 1260.0, "type": "landmark", "special": "rocks", "terrain": 1.3, "lat": 40.78, "lon": -75.61,
		"desc": "Rocksylvania at its worst: a hand-over-hand climb up a scarred, boulder-strewn slope. Shoes go here to die."},
	{"name": "Delaware Water Gap", "state": "PA", "mile": 1295.0, "type": "town", "store": 1.0, "terrain": 1.05, "lat": 40.98, "lon": -75.14,
		"desc": "A church hostel and a famous bakery. Cross the Delaware River into New Jersey."},
	{"name": "Bear Mountain", "state": "NY", "mile": 1405.0, "type": "landmark", "special": "bearmtn", "terrain": 1.05, "lat": 41.31, "lon": -73.99,
		"desc": "The very first section of the AT, built in 1923. The trail passes through a zoo at the lowest point on the trail."},
	{"name": "Kent", "state": "CT", "mile": 1460.0, "type": "town", "store": 1.15, "terrain": 1.05, "lat": 41.72, "lon": -73.48,
		"desc": "A pretty, pricey New England village with an outfitter and a good coffee shop."},
	{"name": "Dalton", "state": "MA", "mile": 1585.0, "type": "town", "store": 1.0, "terrain": 1.05, "lat": 42.47, "lon": -73.17,
		"desc": "The trail walks right down the sidewalks. Locals famously let hikers camp in their yards."},
	{"name": "Mount Greylock", "state": "MA", "mile": 1595.0, "type": "landmark", "special": "greylock", "terrain": 1.05, "lat": 42.64, "lon": -73.17,
		"desc": "Massachusetts' highest peak, crowned by a granite war memorial tower."},
	{"name": "Manchester Center", "state": "VT", "mile": 1650.0, "type": "town", "store": 1.05, "terrain": 1.1, "lat": 43.16, "lon": -73.00,
		"desc": "Outlet stores and a big grocery. Vermont's mud and roots slow everyone down."},
	{"name": "Hanover", "state": "NH", "mile": 1750.0, "type": "town", "store": 1.1, "terrain": 1.2, "lat": 43.70, "lon": -72.29,
		"desc": "Home of Dartmouth College. Local businesses offer hikers a free slice of pizza or a donut."},
	{"name": "Mount Moosilauke", "state": "NH", "mile": 1790.0, "type": "landmark", "special": "whites", "terrain": 1.45, "lat": 44.02, "lon": -71.83,
		"desc": "Your first climb above treeline. Welcome to the White Mountains, where miles get slow and the weather gets serious."},
	{"name": "Franconia Ridge", "state": "NH", "mile": 1825.0, "type": "landmark", "special": "franconia", "terrain": 1.45, "lat": 44.16, "lon": -71.64,
		"desc": "A knife-edge ridge walk across Lincoln and Lafayette with alpine flowers clinging to the rocks."},
	{"name": "Mount Washington", "state": "NH", "mile": 1865.0, "type": "landmark", "special": "washington", "terrain": 1.45, "lat": 44.27, "lon": -71.30,
		"desc": "Home of the 'world's worst weather.' Winds once hit 231 mph here. A sign warns hikers to turn back if the weather is bad."},
	{"name": "Gorham", "state": "NH", "mile": 1895.0, "type": "town", "store": 1.05, "terrain": 1.5, "lat": 44.39, "lon": -71.17,
		"desc": "The last big town before Maine. Resupply here for the hardest stretch on the trail."},
	{"name": "Mahoosuc Notch", "state": "ME", "mile": 1915.0, "type": "landmark", "special": "mahoosuc", "terrain": 1.35, "lat": 44.52, "lon": -71.03,
		"desc": "The 'hardest mile' on the AT: a jumble of house-sized boulders in a deep ravine, with ice lingering in the caves even in summer."},
	{"name": "Rangeley", "state": "ME", "mile": 1970.0, "type": "town", "store": 1.1, "terrain": 1.25, "lat": 44.97, "lon": -70.64,
		"desc": "A lake town with a hiker hostel. Loons call across the water at night."},
	{"name": "Kennebec River", "state": "ME", "mile": 2045.0, "type": "river", "special": "kennebec", "terrain": 1.05, "lat": 45.23, "lon": -69.99,
		"desc": "Too wide and dangerous to ford — upstream dams release water without warning. A canoe ferry is the official trail route."},
	{"name": "Monson", "state": "ME", "mile": 2080.0, "type": "town", "store": 1.15, "special": "wilderness", "terrain": 1.1, "lat": 45.29, "lon": -69.50,
		"desc": "Last town before the 100-Mile Wilderness. There is no resupply ahead until Abol Bridge."},
	{"name": "Abol Bridge", "state": "ME", "mile": 2183.0, "type": "town", "store": 1.4, "terrain": 1.3, "lat": 45.84, "lon": -68.97,
		"desc": "A tiny camp store at the edge of Baxter State Park. Katahdin fills the horizon."},
	{"name": "Mount Katahdin", "state": "ME", "mile": 2198.0, "type": "finish", "special": "katahdin", "lat": 45.90, "lon": -68.92,
		"desc": "Baxter Peak, 5,267 feet. The weathered wooden sign at the top marks the end of the Appalachian Trail."},
]

const TOTAL_MILES := 2198.0

# Advice from fellow hikers ("talk to people", Oregon Trail style). Keyed by region.
const CHATTER := {
	"south": [
		["Rook", "Everybody packs too much at first. Mail some of it home from Neel Gap — your knees will thank you."],
		["Banjo", "The Smokies make you stay in shelters, and the bears know it. Hang your food on the cables."],
		["Pickles", "If you start in March, bring warm layers. It snowed on me at Clingmans Dome last year."],
		["Sunny", "Don't push big miles in the first few weeks. That's how people end up with shin splints."],
		["Moxie", "Trail magic is real. Somebody left a cooler of sodas at Unicoi Gap yesterday."],
	],
	"virginia": [
		["Old Growth", "Virginia is flat they say. Virginia is lying. But Shenandoah really is easy walking."],
		["Gadget", "Ticks get bad from here to New England. Check yourself every night — Lyme is no joke."],
		["Lucky", "Grab a blackberry shake at every wayside in Shenandoah. That's the rule."],
		["Mango", "Watch for rattlesnakes sunning on the rocks once it warms up."],
		["Hobo Joe", "Lots of folks get the Virginia Blues around here. Keep your spirits up — take a zero if you need it."],
	],
	"mid": [
		["Stitches", "Pennsylvania is where boots go to die. Make sure your shoes have life in them before the rocks."],
		["Pepper", "Water's scarce on the ridges in summer. Carry an extra liter."],
		["Wren", "Half-gallon challenge at Pine Grove — I did it in 22 minutes and regretted nothing. Mostly."],
		["Tinman", "New Jersey has more bears than you'd think. Seriously."],
		["Doc", "Use your first-aid kits early. A small blister turns into a big problem fast."],
	],
	"new_england": [
		["Sherpa", "The Whites will cut your daily miles in half. Plan your food for it."],
		["Kestrel", "Check the forecast before Mount Washington. If it's bad, wait. The mountain will still be there."],
		["Ladybug", "The AMC huts let a couple of thru-hikers work for their stay. Ask early."],
		["Mud Puppy", "Vermont is mud season all summer long. Embrace it."],
		["Bones", "Baxter closes Katahdin October 15. Keep an eye on the calendar."],
	],
	"maine": [
		["Grizz", "Mahoosuc Notch took me three hours for one mile. Take it slow and watch your ankles."],
		["Paddles", "Do NOT ford the Kennebec. Wait for the ferry. People have died trying."],
		["Loon", "Carry eight or ten days of food into the 100-Mile Wilderness. There's nothing out there."],
		["Pine", "The rivers in Maine come up fast after rain. Sometimes waiting a day is the smart move."],
		["Summit", "When you see Katahdin from Abol Bridge... I cried. You will too."],
	],
}

const TRAIL_NAMES := ["Switchback", "Cheese Wheel", "Lightning", "Moonpie", "Tumbleweed", "Ramen", "Huckleberry",
	"Pathfinder", "Spoons", "Blue Jay", "Sparky", "Tortuga", "Wildflower", "Sasquatch", "Dingo", "Mountain Goat",
	"Firefly", "Pockets", "Nightcrawler", "Cliffhanger", "Pop-Tart", "Ziploc", "Dutch", "Soggy Bottom", "Compass"]

const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August",
	"September", "October", "November", "December"]


static func region_for(miles: float) -> String:
	if miles < 470.0:
		return "south"
	if miles < 1025.0:
		return "virginia"
	if miles < 1650.0:
		return "mid"
	if miles < 1895.0:
		return "new_england"
	return "maine"


static func region_label(miles: float) -> String:
	match region_for(miles):
		"south":
			return "Southern Appalachians"
		"virginia":
			return "Virginia"
		"mid":
			return "Mid-Atlantic & Southern New England"
		"new_england":
			return "Vermont & the White Mountains"
	return "Maine"


static func state_at(miles: float) -> String:
	var s: String = LANDMARKS[0]["state"]
	for lm in LANDMARKS:
		if lm["mile"] <= miles:
			s = lm["state"]
	return s


static func terrain_at(miles: float) -> float:
	var t := 1.0
	for lm in LANDMARKS:
		if lm["mile"] <= miles and lm.has("terrain"):
			t = lm["terrain"]
	return t


static func is_exposed(miles: float) -> bool:
	# Stretches with long sections above treeline or on open balds
	return (miles > 190 and miles < 215) or (miles > 375 and miles < 395) or (miles > 495 and miles < 510) \
		or (miles > 1785 and miles < 1900) or miles > 2190


static func elevation_bonus(miles: float) -> float:
	# Rough "how high and cold is it here" for weather
	if miles > 160 and miles < 240:
		return -8.0
	if miles > 1785 and miles < 1900:
		return -10.0
	if miles > 2185:
		return -8.0
	if miles > 370 and miles < 510:
		return -4.0
	return 0.0
