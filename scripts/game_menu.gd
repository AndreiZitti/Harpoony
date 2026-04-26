class_name GameMenu
extends CanvasLayer

# ESC opens a pause overlay. Resume / Reset Session / Cheat / Dev Mode toggles.
# Dev mode (when enabled) shows a small spawn panel in top-right that persists
# even after closing the menu, and unlocks the 1–9 hotkeys for spawning fish.

signal dev_mode_toggled(active: bool)
signal session_reset_requested
signal dev_panel_toggle_requested
signal bestiary_pressed

const DEV_KEYMAP = {
	KEY_1: "sardine",
	KEY_2: "pufferfish",
	KEY_3: "mahimahi",
	KEY_4: "squid",
	KEY_5: "lanternfish",
	KEY_6: "anglerfish",
	KEY_7: "marlin",
	KEY_8: "grouper",
	KEY_9: "tuna",
	KEY_0: "bonito",
	KEY_MINUS: "blockfish",
}
const DEV_SPECIES_LIST = [
	["Sardine school", "sardine"],
	["Pufferfish", "pufferfish"],
	["Mahi-mahi", "mahimahi"],
	["Squid", "squid"],
	["Lanternfish school", "lanternfish"],
	["Anglerfish", "anglerfish"],
	["Marlin", "marlin"],
	["Grouper", "grouper"],
	["Tuna", "tuna"],
	["Bonito streak", "bonito"],
	["Blockfish", "blockfish"],
]

var menu_overlay: ColorRect
var menu_panel: PanelContainer
var dev_panel: PanelContainer
var resume_button: Button
var reset_button: Button
var dev_toggle_button: Button
var cheat_toggle_button: Button
var dev_panel_button: Button
var dev_mode_active: bool = false
var dev_spawn_callable: Callable = Callable()


func _ready() -> void:
	layer = 60  # above HUD (default 0) and shop (10)
	# Keep processing inputs while the tree is paused so ESC can close the menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_set_menu_open(false)


func _build_ui() -> void:
	# Dim overlay behind the menu — only visible when paused.
	menu_overlay = ColorRect.new()
	menu_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_overlay.color = Color(0, 0, 0, 0.55)
	menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(menu_overlay)

	menu_panel = _build_menu_panel()
	menu_overlay.add_child(menu_panel)

	dev_panel = _build_dev_panel()
	add_child(dev_panel)
	dev_panel.visible = false


func _build_menu_panel() -> PanelContainer:
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360, 380)
	panel.position = Vector2(-180, -190)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.14, 0.96)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.5, 0.6, 0.8, 0.6)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var hint = Label.new()
	hint.text = "ESC to resume"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.82))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	vbox.add_child(HSeparator.new())

	resume_button = _make_menu_button("Resume", close)
	vbox.add_child(resume_button)

	var bestiary_button := _make_menu_button("Bestiary", _on_bestiary_pressed)
	vbox.add_child(bestiary_button)

	reset_button = _make_menu_button("Reset Session", _on_reset_pressed)
	vbox.add_child(reset_button)

	cheat_toggle_button = _make_menu_button("", _on_cheat_pressed)
	vbox.add_child(cheat_toggle_button)

	dev_toggle_button = _make_menu_button("", _on_dev_toggle_pressed)
	vbox.add_child(dev_toggle_button)

	# Opens the full-screen tuning panel. Dev mode auto-opens it on entry.
	dev_panel_button = _make_menu_button("Open Dev Panel", _on_dev_panel_pressed)
	vbox.add_child(dev_panel_button)

	_refresh_button_text()
	return panel


func _make_menu_button(text: String, handler: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 38)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(handler)
	return btn


func _build_dev_panel() -> PanelContainer:
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-256, 16)
	panel.custom_minimum_size = Vector2(240, 0)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.95)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(1.0, 0.85, 0.4, 0.8)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "DEV MODE"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vbox.add_child(title)

	var hint = Label.new()
	hint.text = "Click or press 1–9 / 0 underwater"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
	vbox.add_child(hint)

	for i in DEV_SPECIES_LIST.size():
		var entry = DEV_SPECIES_LIST[i]
		var btn = Button.new()
		btn.text = "%d  %s" % [i + 1, entry[0]]
		btn.custom_minimum_size = Vector2(0, 26)
		btn.add_theme_font_size_override("font_size", 12)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var species_id: String = entry[1]
		btn.pressed.connect(func(): _dev_spawn(species_id))
		vbox.add_child(btn)

	return panel


func set_dev_spawn_callable(c: Callable) -> void:
	dev_spawn_callable = c


func _dev_spawn(species: String) -> void:
	if dev_spawn_callable.is_valid():
		dev_spawn_callable.call(species)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var kb = event as InputEventKey
		if not kb.pressed or kb.echo:
			return
		if kb.keycode == KEY_ESCAPE:
			toggle()
			get_viewport().set_input_as_handled()
			return
		# F1 / backtick: quick dev toggle without opening the full menu.
		if kb.keycode == KEY_QUOTELEFT or kb.keycode == KEY_F1:
			_set_dev_mode(not dev_mode_active)
			get_viewport().set_input_as_handled()
			return
		if dev_mode_active and DEV_KEYMAP.has(kb.keycode):
			var species: String = DEV_KEYMAP[kb.keycode]
			_dev_spawn(species)
			get_viewport().set_input_as_handled()


func toggle() -> void:
	_set_menu_open(not menu_overlay.visible)


func close() -> void:
	_set_menu_open(false)


func is_open() -> bool:
	return menu_overlay.visible


func _set_menu_open(open: bool) -> void:
	menu_overlay.visible = open
	# Pause the world (not this menu) while open so the timer/oxygen don't tick.
	get_tree().paused = open
	if open:
		_refresh_button_text()


func _set_dev_mode(active: bool) -> void:
	dev_mode_active = active
	dev_panel.visible = active
	_refresh_button_text()
	dev_mode_toggled.emit(active)


func _refresh_button_text() -> void:
	if cheat_toggle_button:
		cheat_toggle_button.text = "Cheat Mode: %s" % ("ON" if GameData.cheat_mode else "OFF")
	if dev_toggle_button:
		dev_toggle_button.text = "Dev Spawn Panel: %s" % ("ON" if dev_mode_active else "OFF")


func _on_reset_pressed() -> void:
	session_reset_requested.emit()
	close()


func _on_cheat_pressed() -> void:
	GameData.toggle_cheat_mode()
	_refresh_button_text()


func _on_dev_toggle_pressed() -> void:
	_set_dev_mode(not dev_mode_active)


# Bestiary opens on top of the pause menu (layer 85 vs 60). Tree stays paused;
# closing the bestiary brings the player back to the pause menu, not gameplay.
func _on_bestiary_pressed() -> void:
	bestiary_pressed.emit()


# Routes through main.gd which owns the DevPanel CanvasLayer. Closes this
# pause menu first so the panel isn't trapped under it.
func _on_dev_panel_pressed() -> void:
	close()
	dev_panel_toggle_requested.emit()


# Programmatic entry point — lets MainMenu's "Dev Mode" button open the dev
# spawn panel directly without going through the pause overlay. Routes through
# the same _set_dev_mode() path as the in-menu toggle.
func enable_dev_mode() -> void:
	if not dev_mode_active:
		_set_dev_mode(true)
