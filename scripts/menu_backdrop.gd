class_name MenuBackdrop
extends Control
## Painted Appalachian title wallpaper (art/menu/*, made by tools/gen_wallpaper.py).
## Layers shift slightly with the mouse for depth, and mist drifts through the valleys.

const SRC := Vector2(2560, 1440)
# layer name, parallax strength (px at full mouse offset)
const LAYERS := [["sky", 4.0], ["far", 10.0], ["mist_a", 14.0], ["mid", 18.0], ["mist_b", 24.0], ["near", 28.0], ["fore", 44.0]]
# mist bands: vertical centre in source-image pixels, drift speed px/s, opacity
const MIST := {"mist_a": [0.655 * 1440.0, 9.0, 0.55], "mist_b": [0.775 * 1440.0, -6.0, 0.6]}

var _tex := {}
var _par := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for n in ["sky", "far", "mid", "near", "fore", "mist"]:
		var path := "res://art/menu/%s.png" % n
		if ResourceLoader.exists(path):
			_tex[n] = load(path)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var vp := get_viewport_rect().size
	var m := get_viewport().get_mouse_position()
	var goal := Vector2.ZERO
	if vp.x > 0 and vp.y > 0:
		goal = ((m / vp) - Vector2(0.5, 0.5)) * -2.0
		goal = goal.clamp(Vector2(-1, -1), Vector2(1, 1))
	# a gentle idle sway so it feels alive even without the mouse
	goal += Vector2(sin(_t * 0.13), sin(_t * 0.09) * 0.4) * 0.25
	_par = _par.lerp(goal, clampf(delta * 2.0, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	var sz := size
	if sz.x <= 0:
		return
	var sc := maxf(sz.x / SRC.x, sz.y / SRC.y) * 1.06
	var dim := SRC * sc
	var origin := (sz - dim) * 0.5
	for entry in LAYERS:
		var name: String = entry[0]
		var off: Vector2 = _par * float(entry[1]) * Vector2(1.0, 0.5)
		if name.begins_with("mist"):
			_draw_mist(name, origin + off, sc, dim)
			continue
		if not _tex.has(name):
			continue
		draw_texture_rect(_tex[name], Rect2(origin + off, dim), false)


func _draw_mist(name: String, origin: Vector2, sc: float, dim: Vector2) -> void:
	if not _tex.has("mist"):
		return
	var tex: Texture2D = _tex["mist"]
	var cfg: Array = MIST[name]
	var h := tex.get_height() * sc
	var w := tex.get_width() * sc
	var y := origin.y + float(cfg[0]) * sc - h * 0.5
	var x0 := fposmod(_t * float(cfg[1]) * sc, w) - w
	var col := Color(1, 1, 1, float(cfg[2]) * (0.85 + 0.15 * sin(_t * 0.2 + y)))
	var x := origin.x + x0 - w
	while x < origin.x + dim.x + w:
		draw_texture_rect(tex, Rect2(Vector2(x, y), Vector2(w, h)), false, col)
		x += w
