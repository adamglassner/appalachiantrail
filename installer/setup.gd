extends Control
## The Appalachian Trail — Windows setup program (an Ironite game).
##
## A per-user installer (no administrator rights needed). It unpacks the game from
## res://payload/game.zip into %LOCALAPPDATA%\Programs\The Appalachian Trail, creates
## Start Menu / Desktop shortcuts, and registers an uninstaller under
## Settings → Apps. Built by tools/build_release.sh.
##
## Test switches (after `--`):  --dry-run  --dir=PATH  --auto   (dry-run skips registry and shortcuts)

const APP_NAME := "The Appalachian Trail"
const PUBLISHER := "Ironite"
const EXE_NAME := "AppalachianTrail.exe"
const REG_KEY := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Ironite.AppalachianTrail"
const PS_KEY := "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Ironite.AppalachianTrail"
const HOME_URL := "https://github.com/adamglassner/appalachiantrail"
const PAYLOAD := "res://payload/game.zip"

const GREEN := Color(0.0, 0.231, 0.184)
const MINT := Color(0.816, 0.925, 0.867)
const BG := Color(0.07, 0.095, 0.09)
const PANEL := Color(0.1, 0.13, 0.12)
const TEXT := Color(0.94, 0.92, 0.86)
const DIM := Color(0.68, 0.71, 0.67)
const ACCENT := Color(0.93, 0.7, 0.3)
const RED := Color(0.92, 0.45, 0.4)

var version := "1.0.0"
var install_dir := ""
var make_desktop := true
var make_start := true
var launch_after := true
var existing_version := ""
var dry_run := false
var auto := false

var page := 0
var content: VBoxContainer
var btn_back: Button
var btn_next: Button
var btn_cancel: Button
var dir_edit: LineEdit
var progress: ProgressBar
var status_lbl: Label
var log_lbl: Label
var _thread: Thread
var _done_ok := false
var _error := ""
var _file_dialog: FileDialog

var font_body: SystemFont
var font_bold: SystemFont
var font_title: SystemFont


func _ready() -> void:
	version = str(ProjectSettings.get_setting("application/config/version", version))
	for a in OS.get_cmdline_user_args():
		if a == "--dry-run":
			dry_run = true
		elif a == "--auto":
			auto = true
		elif a.begins_with("--dir="):
			install_dir = a.substr(6)
	if not _is_windows():
		dry_run = true
	_detect_existing()
	if install_dir == "":
		install_dir = _default_dir()
	_fonts()
	_build_frame()
	_show_page(0)
	for a in OS.get_cmdline_user_args():
		if a == "--print-scripts":
			print(_tasks_script(install_dir))
			print(_uninstall_script())
			get_tree().quit()
			return
		if a.begins_with("--screens="):
			_screens(a.substr(10))
			return
	if auto:
		_auto_run()


func _is_windows() -> bool:
	return OS.get_name() == "Windows"


func _default_dir() -> String:
	if _is_windows():
		var base := OS.get_environment("LOCALAPPDATA")
		if base == "":
			base = OS.get_environment("USERPROFILE").path_join("AppData/Local")
		return (base.path_join("Programs").path_join(APP_NAME)).replace("/", "\\")
	return OS.get_user_data_dir().path_join("install_test")


func _detect_existing() -> void:
	if not _is_windows():
		return
	var out: Array = []
	var code := OS.execute("reg", ["query", REG_KEY], out, true)
	if code != 0 or out.is_empty():
		return
	for line in str(out[0]).split("\n"):
		var l := line.strip_edges()
		if l.begins_with("InstallLocation"):
			var parts := l.split("REG_SZ", false, 1)
			if parts.size() == 2:
				install_dir = parts[1].strip_edges()
		elif l.begins_with("DisplayVersion"):
			var p2 := l.split("REG_SZ", false, 1)
			if p2.size() == 2:
				existing_version = p2[1].strip_edges()


# ------------------------------------------------------------------ look & feel

func _fonts() -> void:
	font_body = SystemFont.new()
	font_body.font_names = PackedStringArray(["Segoe UI", "Inter", "Noto Sans", "DejaVu Sans", "Arial", "Sans-Serif"])
	font_bold = SystemFont.new()
	font_bold.font_names = font_body.font_names
	font_bold.font_weight = 600
	font_title = SystemFont.new()
	font_title.font_names = PackedStringArray(["Georgia", "Cambria", "DejaVu Serif", "Serif"])
	font_title.font_weight = 700
	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "Button", _box(Color(0.17, 0.21, 0.19), 8))
	t.set_stylebox("hover", "Button", _box(Color(0.24, 0.3, 0.26), 8, Color(ACCENT, 0.5)))
	t.set_stylebox("pressed", "Button", _box(Color(0.3, 0.25, 0.15), 8, ACCENT))
	t.set_stylebox("disabled", "Button", _box(Color(0.13, 0.15, 0.14), 8))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), 8, Color(ACCENT, 0.7)))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.52, 0.5))
	t.set_font("font", "Button", font_bold)
	t.set_stylebox("normal", "LineEdit", _box(Color(0.06, 0.08, 0.07), 6))
	t.set_stylebox("focus", "LineEdit", _box(Color(0.06, 0.08, 0.07), 6, ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	var bgp := StyleBoxFlat.new()
	bgp.bg_color = Color(1, 1, 1, 0.08)
	bgp.set_corner_radius_all(5)
	t.set_stylebox("background", "ProgressBar", bgp)
	var fg := StyleBoxFlat.new()
	fg.bg_color = ACCENT
	fg.set_corner_radius_all(5)
	t.set_stylebox("fill", "ProgressBar", fg)
	t.set_font_size("font_size", "ProgressBar", 1)
	theme = t


func _box(c: Color, r: int, border := Color(1, 1, 1, 0.07)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	s.border_color = border
	s.set_border_width_all(1)
	return s


func _label(text: String, size := 15, color := TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _build_frame() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	# left: painted banner with the Ironite logo
	var left := Control.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.clip_contents = true
	row.add_child(left)
	var banner := TextureRect.new()
	banner.texture = load("res://assets/banner.jpg")
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left.add_child(banner)
	var shade := ColorRect.new()
	shade.color = Color(GREEN, 0.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left.add_child(shade)
	var tag := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(GREEN, 0.88)
	tsb.content_margin_left = 18
	tsb.content_margin_right = 18
	tsb.content_margin_top = 12
	tsb.content_margin_bottom = 12
	tag.add_theme_stylebox_override("panel", tsb)
	tag.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tag.grow_vertical = Control.GROW_DIRECTION_BEGIN
	left.add_child(tag)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	tag.add_child(tv)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/ironite_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.custom_minimum_size = Vector2(150, 39)
	tv.add_child(logo)
	tv.add_child(_label("Setup  ·  version %s" % version, 12, Color(MINT, 0.8)))
	# right: page content + buttons
	var right := MarginContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		right.add_theme_constant_override("margin_" + side, 30)
	row.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 14)
	right.add_child(rv)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	rv.add_child(content)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.08)
	sep.custom_minimum_size = Vector2(0, 1)
	rv.add_child(sep)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	rv.add_child(bar)
	btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.pressed.connect(_on_cancel)
	bar.add_child(btn_cancel)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	btn_back = Button.new()
	btn_back.text = "Back"
	btn_back.pressed.connect(func(): _show_page(page - 1))
	bar.add_child(btn_back)
	btn_next = Button.new()
	btn_next.custom_minimum_size.x = 130
	btn_next.add_theme_stylebox_override("normal", _box(Color(0.78, 0.52, 0.18), 8, Color(1, 0.85, 0.5, 0.6)))
	btn_next.add_theme_stylebox_override("hover", _box(Color(0.88, 0.62, 0.24), 8, Color(1, 0.9, 0.6, 0.9)))
	btn_next.add_theme_stylebox_override("pressed", _box(Color(0.65, 0.42, 0.12), 8))
	btn_next.add_theme_color_override("font_color", Color(0.1, 0.07, 0.03))
	btn_next.add_theme_color_override("font_hover_color", Color(0.05, 0.03, 0.0))
	btn_next.pressed.connect(_on_next)
	bar.add_child(btn_next)


func _clear() -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()


# ------------------------------------------------------------------ pages

func _show_page(p: int) -> void:
	page = clampi(p, 0, 3)
	_clear()
	btn_back.visible = page == 1
	btn_cancel.visible = page < 2
	btn_next.disabled = false
	match page:
		0:
			_page_welcome()
		1:
			_page_options()
		2:
			_page_install()
		3:
			_page_finish()


func _heading(kicker: String, title: String) -> void:
	content.add_child(_label(kicker.to_upper(), 12, ACCENT, font_bold))
	content.add_child(_label(title, 28, TEXT, font_title))


func _page_welcome() -> void:
	_heading("Welcome", APP_NAME)
	content.add_child(_label("A thru-hike from Springer Mountain, Georgia to Mount Katahdin, Maine — 2,198 miles of ridgelines, trail towns, bears, river crossings and trail magic.", 16, TEXT))
	if existing_version != "":
		content.add_child(_label("Version %s is already installed. Setup will update it to version %s. Your saved hikes, Hall of Fame and settings are kept." % [existing_version, version], 15, MINT))
	else:
		content.add_child(_label("This will install version %s on your computer. No administrator rights are needed — the game is installed just for you." % version, 15, DIM))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	content.add_child(_label("© 2026 Ironite. All rights reserved. Built with the Godot Engine (MIT license).", 12, Color(DIM, 0.8)))
	btn_next.text = "Next"


func _page_options() -> void:
	_heading("Options", "Where should it go?")
	content.add_child(_label("Install folder", 13, DIM, font_bold))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	dir_edit = LineEdit.new()
	dir_edit.text = install_dir
	dir_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dir_edit.text_changed.connect(func(t): install_dir = t.strip_edges())
	row.add_child(dir_edit)
	var browse := Button.new()
	browse.text = "Browse…"
	browse.pressed.connect(_browse)
	row.add_child(browse)
	content.add_child(_label("About 105 MB of disk space is required.", 13, DIM))
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	content.add_child(gap)
	content.add_child(_label("Shortcuts", 13, DIM, font_bold))
	var c1 := CheckBox.new()
	c1.text = "Create a desktop shortcut"
	c1.button_pressed = make_desktop
	c1.toggled.connect(func(v): make_desktop = v)
	content.add_child(c1)
	var c2 := CheckBox.new()
	c2.text = "Add to the Start menu (Ironite folder)"
	c2.button_pressed = make_start
	c2.toggled.connect(func(v): make_start = v)
	content.add_child(c2)
	if dry_run:
		content.add_child(_label("Test mode: shortcuts and the Windows uninstall entry are skipped.", 12, RED))
	btn_next.text = "Update" if existing_version != "" else "Install"


func _page_install() -> void:
	_heading("Installing", "Lacing up your boots…")
	status_lbl = _label("Preparing…", 15, TEXT)
	content.add_child(status_lbl)
	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 12)
	progress.max_value = 100
	progress.show_percentage = false
	content.add_child(progress)
	log_lbl = _label("", 13, DIM)
	content.add_child(log_lbl)
	btn_next.text = "Next"
	btn_next.disabled = true
	_start_install()


func _page_finish() -> void:
	if _done_ok:
		_heading("All set", "Ready for the trail")
		content.add_child(_label("%s %s has been installed to:" % [APP_NAME, version], 15, TEXT))
		content.add_child(_label(install_dir, 14, MINT))
		content.add_child(_label("You can uninstall it any time from Settings → Apps, or from the Ironite folder in the Start menu. Your saved hikes live in %APPDATA%\\Godot\\app_userdata\\The Appalachian Trail.", 13, DIM))
		var c := CheckBox.new()
		c.text = "Launch The Appalachian Trail now"
		c.button_pressed = launch_after
		c.toggled.connect(func(v): launch_after = v)
		content.add_child(c)
	else:
		_heading("Something went wrong", "Setup couldn't finish")
		content.add_child(_label(_error, 15, RED))
		content.add_child(_label("If the game is running, close it and run Setup again.", 14, DIM))
	btn_next.text = "Finish"


func _on_next() -> void:
	match page:
		0:
			_show_page(1)
		1:
			if install_dir.strip_edges() == "":
				return
			_show_page(2)
		2:
			_show_page(3)
		3:
			if _done_ok and launch_after and not dry_run:
				OS.create_process(install_dir.path_join(EXE_NAME), [])
			get_tree().quit()


func _on_cancel() -> void:
	get_tree().quit()


func _browse() -> void:
	var start := install_dir.get_base_dir() if install_dir != "" else OS.get_environment("USERPROFILE")
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Choose an install folder", start, "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, PackedStringArray(), _on_native_dir)
		return
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_file_dialog.title = "Choose an install folder"
		_file_dialog.dir_selected.connect(_set_dir_from_picker)
		add_child(_file_dialog)
	_file_dialog.current_dir = start
	_file_dialog.popup_centered(Vector2i(640, 420))


func _on_native_dir(ok: bool, paths: PackedStringArray, _filter: int) -> void:
	if ok and paths.size() > 0:
		_set_dir_from_picker(paths[0])


func _set_dir_from_picker(d: String) -> void:
	# install into a subfolder named after the game unless the user already picked one
	if not d.get_file().to_lower().contains("appalachian"):
		d = d.path_join(APP_NAME)
	if _is_windows():
		d = d.replace("/", "\\")
	install_dir = d
	if dir_edit != null:
		dir_edit.text = d


# ------------------------------------------------------------------ installing

func _start_install() -> void:
	_thread = Thread.new()
	_thread.start(_install_worker)


func _ui(status: String, pct: float, log_line := "") -> void:
	if status_lbl:
		status_lbl.text = status
	if progress:
		progress.value = pct
	if log_line != "" and log_lbl:
		log_lbl.text = log_line


func _install_worker() -> void:
	var ok := _install()
	call_deferred("_install_finished", ok)


func _install_finished(ok: bool) -> void:
	_thread.wait_to_finish()
	_done_ok = ok
	if ok:
		_ui("Installation complete.", 100.0)
	btn_next.disabled = false
	if auto:
		print("SETUP RESULT ok=", ok, " dir=", install_dir, " error=", _error)
		get_tree().quit(0 if ok else 1)
		return
	_show_page(3)


func _fail(msg: String) -> bool:
	_error = msg
	call_deferred("_ui", "Setup failed.", 0.0, msg)
	return false


func _install() -> bool:
	var dir := install_dir
	call_deferred("_ui", "Creating the install folder…", 2.0, dir)
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		return _fail("Couldn't create the folder:\n" + dir)
	var zip := ZIPReader.new()
	if zip.open(PAYLOAD) != OK:
		return _fail("The installer's game data is missing or damaged.")
	var files := zip.get_files()
	var n := files.size()
	for i in n:
		var f: String = files[i]
		if f.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(dir.path_join(f))
			continue
		call_deferred("_ui", "Copying files… (%d of %d)" % [i + 1, n], 5.0 + 80.0 * i / maxf(1.0, n), f)
		var data := zip.read_file(f)
		var target := dir.path_join(f)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var fa := FileAccess.open(target, FileAccess.WRITE)
		if fa == null:
			zip.close()
			return _fail("Couldn't write %s.\nIs the game still running?" % f)
		fa.store_buffer(data)
		fa.close()
	zip.close()
	call_deferred("_ui", "Writing the uninstaller…", 88.0, "uninstall.ps1")
	var un := FileAccess.open(dir.path_join("uninstall.ps1"), FileAccess.WRITE)
	if un == null:
		return _fail("Couldn't write the uninstaller.")
	un.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
	un.store_string(_uninstall_script())
	un.close()
	if dry_run:
		call_deferred("_ui", "Test mode: skipping shortcuts and registry.", 95.0, "")
		return true
	call_deferred("_ui", "Creating shortcuts and registering with Windows…", 92.0, "")
	var tasks := dir.path_join("setup_tasks.ps1")
	var tf := FileAccess.open(tasks, FileAccess.WRITE)
	if tf == null:
		return _fail("Couldn't write the setup script.")
	tf.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
	tf.store_string(_tasks_script(dir))
	tf.close()
	var out: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", tasks], out, true)
	DirAccess.remove_absolute(tasks)
	if code != 0:
		return _fail("Couldn't create shortcuts (code %d).\n%s" % [code, "\n".join(out).strip_edges().left(400)])
	return true


func _ps(s: String) -> String:
	# single-quoted PowerShell literal
	return "'" + s.replace("'", "''") + "'"


func _tasks_script(dir: String) -> String:
	var size_kb := 0
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			var fa := FileAccess.open(dir.path_join(f), FileAccess.READ)
			if fa:
				size_kb += int(fa.get_length() / 1024)
				fa.close()
	var lines := PackedStringArray([
		"$ErrorActionPreference = 'Stop'",
		"$dir = " + _ps(dir),
		"$exe = Join-Path $dir " + _ps(EXE_NAME),
		"$ico = Join-Path $dir 'game.ico'",
		"$un = Join-Path $dir 'uninstall.ps1'",
		"$ws = New-Object -ComObject WScript.Shell",
		"function New-Link($path, $target, $linkArgs, $desc) {",
		"  $l = $ws.CreateShortcut($path)",
		"  $l.TargetPath = $target",
		"  if ($linkArgs) { $l.Arguments = $linkArgs }",
		"  $l.WorkingDirectory = $dir",
		"  $l.IconLocation = \"$ico,0\"",
		"  $l.Description = $desc",
		"  $l.Save()",
		"}",
		"$psExe = Join-Path $env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe'",
		"$unArgs = \"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `\"$un`\"\"",
		"$desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'The Appalachian Trail.lnk'",
		"$startDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'Ironite'",
	])
	if make_desktop:
		lines.append("New-Link $desktopLink $exe $null 'A thru-hike from Georgia to Maine'")
	else:
		lines.append("if (Test-Path $desktopLink) { Remove-Item $desktopLink -Force }")
	if make_start:
		lines.append_array(PackedStringArray([
			"New-Item -ItemType Directory -Force -Path $startDir | Out-Null",
			"New-Link (Join-Path $startDir 'The Appalachian Trail.lnk') $exe $null 'A thru-hike from Georgia to Maine'",
			"New-Link (Join-Path $startDir 'Uninstall The Appalachian Trail.lnk') $psExe $unArgs 'Remove The Appalachian Trail'",
		]))
	lines.append_array(PackedStringArray([
		"$key = " + _ps(PS_KEY),
		"New-Item -Path $key -Force | Out-Null",
		"Set-ItemProperty -Path $key -Name DisplayName -Value " + _ps(APP_NAME),
		"Set-ItemProperty -Path $key -Name DisplayVersion -Value " + _ps(version),
		"Set-ItemProperty -Path $key -Name Publisher -Value " + _ps(PUBLISHER),
		"Set-ItemProperty -Path $key -Name InstallLocation -Value $dir",
		"Set-ItemProperty -Path $key -Name DisplayIcon -Value $ico",
		"Set-ItemProperty -Path $key -Name URLInfoAbout -Value " + _ps(HOME_URL),
		"Set-ItemProperty -Path $key -Name InstallDate -Value (Get-Date -Format 'yyyyMMdd')",
		"Set-ItemProperty -Path $key -Name UninstallString -Value \"`\"$psExe`\" $unArgs\"",
		"New-ItemProperty -Path $key -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null",
		"New-ItemProperty -Path $key -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null",
		"New-ItemProperty -Path $key -Name EstimatedSize -Value %d -PropertyType DWord -Force | Out-Null" % size_kb,
		"exit 0",
	]))
	return "\r\n".join(lines) + "\r\n"


func _uninstall_script() -> String:
	var s := """# Uninstaller for The Appalachian Trail (an Ironite game). Created by Setup.
Add-Type -AssemblyName System.Windows.Forms
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$title = 'Uninstall The Appalachian Trail'
$r = [System.Windows.Forms.MessageBox]::Show('Remove The Appalachian Trail from this computer?', $title, 'YesNo', 'Question')
if ($r -ne 'Yes') { exit 1 }
Get-Process -Name 'AppalachianTrail' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'The Appalachian Trail.lnk'
$startDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'Ironite'
foreach ($p in @($desktopLink, (Join-Path $startDir 'The Appalachian Trail.lnk'), (Join-Path $startDir 'Uninstall The Appalachian Trail.lnk'))) {
  if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
}
if ((Test-Path $startDir) -and -not (Get-ChildItem $startDir -Force)) { Remove-Item $startDir -Force -ErrorAction SilentlyContinue }
Remove-Item -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Ironite.AppalachianTrail' -Recurse -Force -ErrorAction SilentlyContinue
$saves = Join-Path $env:APPDATA 'Godot\\app_userdata\\The Appalachian Trail'
if (Test-Path $saves) {
  $r2 = [System.Windows.Forms.MessageBox]::Show('Also delete your saved hikes, Hall of Fame and settings?', $title, 'YesNo', 'Question', 'Button2')
  if ($r2 -eq 'Yes') { Remove-Item $saves -Recurse -Force -ErrorAction SilentlyContinue }
}
# the folder holds this script, so remove it a moment after we exit
Start-Process -FilePath 'cmd.exe' -ArgumentList "/c timeout /t 2 /nobreak >nul & rmdir /s /q `"$dir`"" -WindowStyle Hidden
[System.Windows.Forms.MessageBox]::Show('The Appalachian Trail has been removed. Thanks for hiking!', $title, 'OK', 'Information') | Out-Null
"""
	return s.replace("\n", "\r\n")


# ------------------------------------------------------------------ automated test run

func _auto_run() -> void:
	await get_tree().create_timer(0.3).timeout
	_show_page(1)
	await get_tree().create_timer(0.3).timeout
	_show_page(2)


func _screens(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for p in [0, 1]:
		_show_page(p)
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("setup_%d.png" % p))
	_done_ok = true
	_show_page(3)
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("setup_3.png"))
	get_tree().quit()
