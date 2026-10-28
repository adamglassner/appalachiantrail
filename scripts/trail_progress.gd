class_name TrailProgress
extends Control
## A slim Georgia→Maine progress strip with state lines, towns, landmarks and the party marker.

var miles := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(400, 46)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_miles(m: float) -> void:
	miles = m
	queue_redraw()


func _draw() -> void:
	var font := UiTheme.body_font()
	var w := size.x
	var y := 18.0
	var x0 := 10.0
	var x1 := w - 10.0
	var total: float = TrailData.TOTAL_MILES
	draw_line(Vector2(x0, y), Vector2(x1, y), Color(1, 1, 1, 0.18), 6.0, true)
	var px := lerpf(x0, x1, miles / total)
	draw_line(Vector2(x0, y), Vector2(px, y), UiTheme.ACCENT, 6.0, true)
	# state boundaries
	var last_state := ""
	for lm in TrailData.LANDMARKS:
		var st: String = lm["state"]
		if st != last_state:
			var sx := lerpf(x0, x1, lm["mile"] / total)
			if last_state != "":
				draw_line(Vector2(sx, y - 9), Vector2(sx, y + 9), Color(1, 1, 1, 0.25), 1.0)
			draw_string(font, Vector2(sx + 3, y + 22), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))
			last_state = st
	for lm in TrailData.LANDMARKS:
		var lx := lerpf(x0, x1, lm["mile"] / total)
		var c := UiTheme.ACCENT if lm["type"] == "landmark" else (UiTheme.BLUE if lm["type"] == "town" else Color(0.4, 0.9, 0.9))
		if lm["type"] == "start" or lm["type"] == "finish":
			c = Color(1, 0.88, 0.4)
		var done: bool = lm["mile"] <= miles
		draw_circle(Vector2(lx, y), 3.2 if lm["type"] != "town" else 2.6, c if done else c.darkened(0.45))
	# party marker
	draw_circle(Vector2(px, y), 7.0, Color(0.05, 0.05, 0.05, 0.6))
	draw_circle(Vector2(px, y), 5.5, Color.WHITE)
	draw_circle(Vector2(px, y), 3.0, UiTheme.ACCENT)
	draw_string(font, Vector2(x0, y - 9), "Springer Mtn, GA", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))
	draw_string(font, Vector2(x1 - 100, y - 9), "Katahdin, ME", HORIZONTAL_ALIGNMENT_RIGHT, 100, 11, Color(1, 1, 1, 0.55))
