extends Node2D

@onready var diver: Node2D = $Diver
@onready var fish_spawner: Node2D = $FishSpawner
@onready var oxygen_timer: Timer = $OxygenTimer
@onready var hud: CanvasLayer = $HUD
@onready var upgrade_shop: CanvasLayer = $UpgradeShop

const BubbleFieldScript = preload("res://scripts/bubble_field.gd")
const GameMenuScript = preload("res://scripts/game_menu.gd")
const EndingScreenScript = preload("res://scripts/ending_screen.gd")
const MainMenuScript = preload("res://scripts/main_menu.gd")
const SplashScript = preload("res://scripts/splash_screen.gd")
var _bubble_field: Node2D = null
var _game_menu: CanvasLayer = null
var _ending_screen: CanvasLayer = null

const DIVE_TRAVEL_DURATION = 1.5
const RESURFACE_TRAVEL_DURATION = 1.0
var travel_timer: float = 0.0
var _hit_stop_active: bool = false


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.04, 0.08, 0.14))

	upgrade_shop.next_dive_pressed.connect(_on_dive_pressed)
	oxygen_timer.timeout.connect(_on_oxygen_tick)

	GameData.set_dive_state(GameData.DiveState.SURFACE)
	if diver.has_method("set_visible_in_water"):
		diver.set_visible_in_water(false)

	# BubbleField sits behind the diver/fish but on top of the water gradient.
	_bubble_field = Node2D.new()
	_bubble_field.set_script(BubbleFieldScript)
	_bubble_field.name = "BubbleField"
	add_child(_bubble_field)
	move_child(_bubble_field, 0)

	# Pause/dev menu — ESC to toggle. Owns the dev spawn panel.
	_game_menu = CanvasLayer.new()
	_game_menu.set_script(GameMenuScript)
	_game_menu.name = "GameMenu"
	add_child(_game_menu)
	_game_menu.set_dev_spawn_callable(_dev_spawn)
	_game_menu.session_reset_requested.connect(_on_session_reset)

	# Ending screen — celebration overlay on the first White Whale catch.
	_ending_screen = CanvasLayer.new()
	_ending_screen.set_script(EndingScreenScript)
	_ending_screen.name = "EndingScreen"
	add_child(_ending_screen)
	_ending_screen.reset_requested.connect(_on_session_reset)

	GameData.whitewhale_caught_signal.connect(_on_whitewhale_caught)

	# Opening flow: MainMenu → (Splash on Normal) → UpgradeShop.
	_show_main_menu()


func _show_main_menu() -> void:
	var menu := CanvasLayer.new()
	menu.set_script(MainMenuScript)
	menu.name = "MainMenu"
	add_child(menu)
	menu.mode_selected.connect(_on_mode_selected)


func _on_mode_selected(mode: StringName) -> void:
	if mode == &"dev":
		GameData.cheat_mode = true
		GameData.cash_changed.emit(GameData.cash)
		if _game_menu and _game_menu.has_method("enable_dev_mode"):
			_game_menu.enable_dev_mode()
		upgrade_shop.show_shop()
		return
	# Normal mode: play splash, then open shop.
	var splash := CanvasLayer.new()
	splash.set_script(SplashScript)
	splash.name = "Splash"
	add_child(splash)
	splash.finished.connect(func(): upgrade_shop.show_shop())


func _dev_spawn(species: String) -> void:
	if fish_spawner.has_method("dev_spawn"):
		fish_spawner.dev_spawn(species)


# Reset session: zero cash, clear upgrades + unlocks, fresh bag, back to surface.
func _on_session_reset() -> void:
	GameData.cash = 0.0
	GameData.dive_number = 0
	GameData.dive_number_changed.emit(0)
	GameData.upgrade_levels = {"oxygen": 0, "spear_bag": 0}
	GameData.unlocked_zone_index = 0
	GameData.selected_zone_index = 0
	GameData.unlocked_spear_types = [&"normal"]
	GameData.spear_upgrade_levels.clear()
	for t in GameData.spear_types:
		var levels := {}
		for k in t.upgrades.keys():
			levels[k] = 0
		GameData.spear_upgrade_levels[t.id] = levels
	GameData.bag_loadout.clear()
	GameData.auto_fill_bag()
	GameData.cash_changed.emit(0.0)
	GameData.zone_changed.emit(GameData.get_current_zone())
	# If a dive is in progress, abort cleanly back to surface.
	if GameData.dive_state != GameData.DiveState.SURFACE:
		fish_spawner.stop_spawning()
		oxygen_timer.stop()
		if diver.has_method("set_visible_in_water"):
			diver.set_visible_in_water(false)
		GameData.set_dive_state(GameData.DiveState.SURFACE)
	upgrade_shop.show_shop()


func _on_whitewhale_caught() -> void:
	# Let the cash popup play before the ending lands.
	await get_tree().create_timer(1.5).timeout
	if _ending_screen and _ending_screen.has_method("show_ending"):
		_ending_screen.show_ending()


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
	Sfx.splash()
	if diver.has_method("set_visible_in_water"):
		diver.set_visible_in_water(true)
	if diver.has_method("reload_spear_types"):
		diver.reload_spear_types()


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
	Sfx.resurface()


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
	if hud and hud.has_method("show_dive_summary"):
		hud.show_dive_summary(GameData.last_dive_cash, GameData.last_dive_fish, GameData.last_dive_shots)
	upgrade_shop.show_shop()


func _draw() -> void:
	var viewport = get_viewport_rect().size
	var water_surface_y = 140.0
	# Surface uses a fixed palette. Underwater pulls colors from the current zone.
	var palette = GameData.SURFACE_PALETTE
	var underwater = GameData.dive_state != GameData.DiveState.SURFACE
	var water_top: Color
	var water_bottom: Color
	if underwater:
		var zone: ZoneConfig = GameData.get_current_zone()
		water_top = zone.water_top
		water_bottom = zone.water_bottom
	else:
		water_top = palette["water_top"]
		water_bottom = palette["water_bottom"]

	# Sky gradient
	for i in 8:
		var t = i / 8.0
		var y = t * water_surface_y
		var band_h = water_surface_y / 8.0
		var c = palette["sky_top"].lerp(palette["sky_bottom"], t)
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
