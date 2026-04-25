extends Node2D

@onready var diver: Node2D = $Diver
@onready var fish_spawner: Node2D = $FishSpawner
@onready var oxygen_timer: Timer = $OxygenTimer
@onready var hud: CanvasLayer = $HUD
@onready var upgrade_shop: CanvasLayer = $UpgradeShop
@onready var day_summary: CanvasLayer = $DaySummary

const DIVE_TRAVEL_DURATION = 1.5
const RESURFACE_TRAVEL_DURATION = 1.0
var travel_timer: float = 0.0
var _hit_stop_active: bool = false

# Dev mode
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
]
var dev_mode_active: bool = false
var _dev_layer: CanvasLayer = null
var _dev_panel: Control = null
var _dev_toggle_button: Button = null


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.04, 0.08, 0.14))

	upgrade_shop.next_dive_pressed.connect(_on_dive_pressed)
	day_summary.next_day_pressed.connect(_on_next_day_pressed)
	oxygen_timer.timeout.connect(_on_oxygen_tick)

	GameData.set_dive_state(GameData.DiveState.SURFACE)
	upgrade_shop.show_shop()
	day_summary.hide_summary()
	if diver.has_method("set_visible_in_water"):
		diver.set_visible_in_water(false)

	_build_dev_panel()


func _build_dev_panel() -> void:
	_dev_layer = CanvasLayer.new()
	_dev_layer.layer = 100
	add_child(_dev_layer)

	# Always-visible toggle button in top-right corner
	_dev_toggle_button = Button.new()
	_dev_toggle_button.text = "DEV"
	_dev_toggle_button.position = Vector2(1216, 8)
	_dev_toggle_button.size = Vector2(56, 28)
	_dev_toggle_button.modulate = Color(1, 1, 1, 0.7)
	_dev_toggle_button.pressed.connect(_toggle_dev_mode)
	_dev_layer.add_child(_dev_toggle_button)

	# Expandable panel with species buttons
	_dev_panel = Control.new()
	_dev_panel.position = Vector2(1036, 44)
	_dev_panel.size = Vector2(236, 460)
	_dev_layer.add_child(_dev_panel)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.position = Vector2.ZERO
	bg.size = Vector2(236, 460)
	_dev_panel.add_child(bg)

	var title = Label.new()
	title.text = "DEV MODE"
	title.position = Vector2(12, 8)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_dev_panel.add_child(title)

	var hint = Label.new()
	hint.text = "Click or press 1–9"
	hint.position = Vector2(12, 32)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	hint.add_theme_font_size_override("font_size", 11)
	_dev_panel.add_child(hint)

	var y = 60
	for i in DEV_SPECIES_LIST.size():
		var entry = DEV_SPECIES_LIST[i]
		var btn = Button.new()
		btn.text = "%d  %s" % [i + 1, entry[0]]
		btn.position = Vector2(12, y)
		btn.size = Vector2(212, 30)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var species_id: String = entry[1]
		btn.pressed.connect(func(): _dev_spawn(species_id))
		_dev_panel.add_child(btn)
		y += 34

	var oxy_note = Label.new()
	oxy_note.text = "Oxygen paused while open"
	oxy_note.position = Vector2(12, y + 8)
	oxy_note.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	oxy_note.add_theme_font_size_override("font_size", 11)
	_dev_panel.add_child(oxy_note)

	_dev_panel.visible = false


func _dev_spawn(species: String) -> void:
	if fish_spawner.has_method("dev_spawn"):
		fish_spawner.dev_spawn(species)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var kb = event as InputEventKey
		if not kb.pressed or kb.echo:
			return
		if kb.keycode == KEY_QUOTELEFT or kb.keycode == KEY_F1:
			_toggle_dev_mode()
			get_viewport().set_input_as_handled()
			return
		if dev_mode_active and DEV_KEYMAP.has(kb.keycode):
			var species: String = DEV_KEYMAP[kb.keycode]
			if fish_spawner.has_method("dev_spawn"):
				fish_spawner.dev_spawn(species)
			get_viewport().set_input_as_handled()


func _toggle_dev_mode() -> void:
	dev_mode_active = not dev_mode_active
	if _dev_panel:
		_dev_panel.visible = dev_mode_active
	if _dev_toggle_button:
		_dev_toggle_button.modulate = Color(1, 0.85, 0.4, 1.0) if dev_mode_active else Color(1, 1, 1, 0.7)
	oxygen_timer.paused = dev_mode_active


func _process(delta: float) -> void:
	match GameData.dive_state:
		GameData.DiveState.DIVING:
			travel_timer += delta
			if diver.has_method("update_dive_travel"):
				diver.update_dive_travel(clampf(travel_timer / DIVE_TRAVEL_DURATION, 0.0, 1.0))
			if travel_timer >= DIVE_TRAVEL_DURATION:
				_enter_underwater()

		GameData.DiveState.UNDERWATER:
			pass

		GameData.DiveState.RESURFACING:
			travel_timer += delta
			if diver.has_method("update_resurface_travel"):
				diver.update_resurface_travel(clampf(travel_timer / RESURFACE_TRAVEL_DURATION, 0.0, 1.0))
			if travel_timer >= RESURFACE_TRAVEL_DURATION:
				_enter_surface()

	queue_redraw()


func _on_dive_pressed() -> void:
	GameData.start_dive()
	travel_timer = 0.0
	upgrade_shop.hide_shop()
	if diver.has_method("set_visible_in_water"):
		diver.set_visible_in_water(true)


func _enter_underwater() -> void:
	GameData.set_dive_state(GameData.DiveState.UNDERWATER)
	oxygen_timer.start()
	if fish_spawner.has_method("start_spawning"):
		fish_spawner.start_spawning()
	if diver.has_method("enable_fishing"):
		diver.enable_fishing(true)


func _on_oxygen_tick() -> void:
	if GameData.dive_state != GameData.DiveState.UNDERWATER:
		return
	GameData.set_oxygen(GameData.oxygen - 1.0)
	if GameData.oxygen <= 0.0:
		_begin_resurface()


func begin_manual_resurface() -> void:
	if GameData.dive_state == GameData.DiveState.UNDERWATER:
		_begin_resurface()


func _begin_resurface() -> void:
	oxygen_timer.stop()
	if fish_spawner.has_method("stop_spawning"):
		fish_spawner.stop_spawning()
	if diver.has_method("enable_fishing"):
		diver.enable_fishing(false)
	GameData.set_dive_state(GameData.DiveState.RESURFACING)
	travel_timer = 0.0


func hit_stop(duration: float = 0.08, time_scale: float = 0.05) -> void:
	if _hit_stop_active:
		return
	if GameData.dive_state != GameData.DiveState.UNDERWATER:
		return
	_hit_stop_active = true
	Engine.time_scale = time_scale
	# Timer ignores time_scale so pause is real-time
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hit_stop_active = false


func _enter_surface() -> void:
	GameData.finish_dive()
	if diver.has_method("set_visible_in_water"):
		diver.set_visible_in_water(false)
	if GameData.is_day_over():
		day_summary.show_summary()
	else:
		upgrade_shop.show_shop()


func _on_next_day_pressed() -> void:
	day_summary.hide_summary()
	GameData.advance_to_next_day()
	upgrade_shop.show_shop()


func _draw() -> void:
	var viewport = get_viewport_rect().size
	var water_surface_y = 140.0
	# Sky always uses surface phase palette. Water uses current zone underwater,
	# and surface-phase palette while on the boat.
	var phase_palette = GameData.PHASE_PALETTES[GameData.get_current_phase()]
	var underwater = GameData.dive_state != GameData.DiveState.SURFACE
	var water_top: Color
	var water_bottom: Color
	if underwater:
		var zone: ZoneConfig = GameData.get_current_zone()
		water_top = zone.water_top
		water_bottom = zone.water_bottom
	else:
		water_top = phase_palette["water_top"]
		water_bottom = phase_palette["water_bottom"]

	# Sky gradient
	for i in 8:
		var t = i / 8.0
		var y = t * water_surface_y
		var band_h = water_surface_y / 8.0
		var c = phase_palette["sky_top"].lerp(phase_palette["sky_bottom"], t)
		draw_rect(Rect2(0, y, viewport.x, band_h + 1), c)

	# Water gradient
	for i in 12:
		var t = i / 12.0
		var y = water_surface_y + t * (viewport.y - water_surface_y)
		var band_h = (viewport.y - water_surface_y) / 12.0
		var c = water_top.lerp(water_bottom, t)
		draw_rect(Rect2(0, y, viewport.x, band_h + 1), c)

	# Water surface line
	draw_line(Vector2(0, water_surface_y), Vector2(viewport.x, water_surface_y), Color(0.6, 0.8, 1.0, 0.4), 1.5)

	# Boat silhouette (surface / transitioning only)
	if GameData.dive_state != GameData.DiveState.UNDERWATER:
		var boat_x = viewport.x * 0.5
		var boat_y = water_surface_y
		var boat_w = 180.0
		draw_polygon(
			PackedVector2Array([
				Vector2(boat_x - boat_w * 0.5, boat_y),
				Vector2(boat_x - boat_w * 0.3, boat_y - 25),
				Vector2(boat_x + boat_w * 0.3, boat_y - 25),
				Vector2(boat_x + boat_w * 0.5, boat_y),
			]),
			PackedColorArray([Color(0.2, 0.15, 0.12)])
		)
		draw_line(Vector2(boat_x, boat_y - 25), Vector2(boat_x, boat_y - 90), Color(0.3, 0.25, 0.2), 3.0)

		# Depth lever silhouette on the deck
		if not GameData.zones.is_empty():
			var lever_x = boat_x + boat_w * 0.18
			var deck_y = boat_y - 25.0
			draw_rect(Rect2(lever_x - 8, deck_y - 4, 16, 4), Color(0.45, 0.35, 0.2))
			var n = max(1, GameData.zones.size())
			var lt = float(GameData.selected_zone_index) / float(max(1, n - 1))
			var ang = lerpf(-PI * 0.35, PI * 0.35, lt)
			var llen = 18.0
			var base = Vector2(lever_x, deck_y - 4)
			var tip = base + Vector2(sin(ang) * llen, -cos(ang) * llen)
			draw_line(base, tip, Color(0.85, 0.7, 0.3), 3.0)
			draw_circle(tip, 3.0, Color(1.0, 0.9, 0.4))
