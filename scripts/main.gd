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
const DevPanelScript = preload("res://scripts/dev_panel.gd")
const DiveSummaryScript = preload("res://scripts/dive_summary.gd")
const BestiaryScript = preload("res://scripts/bestiary.gd")
const BoatTexture = preload("res://assets/boat/boat.png")
const BOAT_DRAW_WIDTH = 240.0  # screen width — bumped from 180 for the new asset
var _bubble_field: Node2D = null
var _game_menu: CanvasLayer = null
var _ending_screen: CanvasLayer = null
var _dev_panel: CanvasLayer = null
var _dive_summary: CanvasLayer = null
var _bestiary: CanvasLayer = null
var _zone_background: Sprite2D = null

# Dive travel duration is tunable from DevPanel; lives on GameData so it
# persists across reloads of this scene. Resurface stays a const for now.
const RESURFACE_TRAVEL_DURATION = 1.0
var travel_timer: float = 0.0
var _hit_stop_active: bool = false

# Boat horizontal offset for the title-screen "set sail" intro animation.
# main.gd._draw renders the boat at viewport.x*0.5 + _boat_offset_x. Tweened by
# slide_boat_for_intro() and reset by reset_boat_position().
var _boat_offset_x: float = 0.0
const BOAT_INTRO_SLIDE_DURATION = 1.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.04, 0.08, 0.14))
	# Restore last dev-panel tuning (silent no-op on first run / no file).
	GameData.load_dev_tuning()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	upgrade_shop.next_dive_pressed.connect(_on_dive_pressed)
	upgrade_shop.new_game_requested.connect(_on_session_reset)
	oxygen_timer.timeout.connect(_on_oxygen_tick)

	GameData.set_dive_state(GameData.DiveState.SURFACE)
	if diver.has_method("set_visible_in_water"):
		diver.set_visible_in_water(false)

	# Zone background sprite — sits behind everything else, only shown
	# underwater when the current zone has a background_texture set.
	_zone_background = Sprite2D.new()
	_zone_background.name = "ZoneBackground"
	_zone_background.centered = false
	_zone_background.position = Vector2.ZERO
	_zone_background.z_index = -10
	_zone_background.visible = false
	add_child(_zone_background)
	move_child(_zone_background, 0)
	GameData.zone_changed.connect(_on_zone_changed)
	GameData.dive_state_changed.connect(_on_dive_state_changed)
	_refresh_zone_background()

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
	_game_menu.bestiary_pressed.connect(_on_bestiary_requested)

	# Ending screen — celebration overlay on the first White Whale catch.
	_ending_screen = CanvasLayer.new()
	_ending_screen.set_script(EndingScreenScript)
	_ending_screen.name = "EndingScreen"
	add_child(_ending_screen)
	_ending_screen.reset_requested.connect(_on_session_reset)

	# Dev tuning panel — opened automatically on Dev Mode entry, also reachable
	# from GameMenu's "Open Dev Panel" button.
	_dev_panel = CanvasLayer.new()
	_dev_panel.set_script(DevPanelScript)
	_dev_panel.name = "DevPanel"
	add_child(_dev_panel)
	if _dev_panel.has_method("set_dev_spawn_callable"):
		_dev_panel.set_dev_spawn_callable(_dev_spawn)
	if _game_menu and _game_menu.has_signal("dev_panel_toggle_requested"):
		_game_menu.dev_panel_toggle_requested.connect(_on_dev_panel_toggle_requested)
	# HUD's floating DEV button (visible in cheat mode) opens the same panel.
	if hud and hud.has_signal("dev_panel_button_pressed"):
		hud.dev_panel_button_pressed.connect(_on_dev_panel_toggle_requested)

	GameData.whitewhale_caught_signal.connect(_on_whitewhale_caught)

	# Post-dive summary screen — shown between resurface and the shop. Continue
	# button proceeds to the shop (or, in dev_skip_shop mode, the next dive).
	_dive_summary = CanvasLayer.new()
	_dive_summary.set_script(DiveSummaryScript)
	_dive_summary.name = "DiveSummary"
	add_child(_dive_summary)
	_dive_summary.continue_requested.connect(_on_dive_summary_continue)

	# Bestiary — fish codex with locked-silhouette discovery. Opened from the
	# main menu, the upgrade shop, and the pause menu via show_bestiary().
	_bestiary = CanvasLayer.new()
	_bestiary.set_script(BestiaryScript)
	_bestiary.name = "Bestiary"
	add_child(_bestiary)

	# Opening flow: MainMenu → (Splash on Normal) → UpgradeShop.
	# HUD is hidden on the title screen so the boot frame stays clean — restored
	# when a mode is selected.
	if hud:
		hud.visible = false
	_show_main_menu()


func _show_main_menu() -> void:
	var menu := CanvasLayer.new()
	menu.set_script(MainMenuScript)
	menu.name = "MainMenu"
	add_child(menu)
	menu.mode_selected.connect(_on_mode_selected)
	menu.bestiary_pressed.connect(_on_bestiary_requested)


func _on_bestiary_requested() -> void:
	if _bestiary and _bestiary.has_method("show_bestiary"):
		_bestiary.show_bestiary()


func _on_mode_selected(mode: StringName) -> void:
	if mode == &"dev":
		# Dev mode = the tuning experience. Skip the shop entirely; the dev panel
		# IS the UI. Default flags are tuned for nonstop fishing iteration.
		GameData.cheat_mode = true
		GameData.dev_infinite_oxygen = true
		GameData.dev_skip_shop = true
		# Force unlock everything so the player can swap spears and zones freely.
		GameData.unlocked_zone_index = max(GameData.unlocked_zone_index, GameData.zones.size() - 1)
		GameData.unlocked_spear_types = [&"normal", &"net", &"heavy"]
		GameData.cash_changed.emit(GameData.cash)
		GameData.zone_changed.emit(GameData.get_current_zone())
		if _game_menu and _game_menu.has_method("enable_dev_mode"):
			_game_menu.enable_dev_mode()
		# Auto-open the dev panel — that's the dev-mode entry point now.
		if _dev_panel and _dev_panel.has_method("toggle"):
			_dev_panel.toggle()
		# Skip the boat slide for dev — straight to the dive loop.
		if hud:
			hud.visible = true
		_on_dive_pressed()
		return
	# Normal mode: boat sails right, splash plays, boat resets, shop opens.
	slide_boat_for_intro(func():
		var splash := CanvasLayer.new()
		splash.set_script(SplashScript)
		splash.name = "Splash"
		add_child(splash)
		splash.finished.connect(func():
			reset_boat_position()
			if hud:
				hud.visible = true
			upgrade_shop.show_shop()
		)
	)


func slide_boat_for_intro(on_finished: Callable) -> void:
	var viewport := get_viewport_rect().size
	var target: float = viewport.x * 0.6 + BOAT_DRAW_WIDTH
	var tw := create_tween()
	tw.tween_property(self, "_boat_offset_x", target, BOAT_INTRO_SLIDE_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(on_finished)


func reset_boat_position() -> void:
	_boat_offset_x = 0.0
	queue_redraw()


func _dev_spawn(species: String) -> void:
	if fish_spawner.has_method("dev_spawn"):
		fish_spawner.dev_spawn(species)


# Reset session: zero cash, clear upgrades + unlocks, fresh bag, back to surface.
func _on_session_reset() -> void:
	GameData.cash = 0.0
	GameData.dive_number = 0
	GameData.dive_number_changed.emit(0)
	GameData.upgrade_levels = {"oxygen": 0, "spear_bag": 0, "reload_speed": 0}
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
	GameData.clear_run_history()
	GameData.clear_discovered_species()
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
				diver.update_dive_travel(clampf(travel_timer / GameData.dive_travel_duration, 0.0, 1.0))
			if travel_timer >= GameData.dive_travel_duration:
				_enter_underwater()

		GameData.DiveState.UNDERWATER:
			GameData.tick_reload(delta)

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
	# Dev mode: keep the tank topped up so the dive never auto-ends.
	if GameData.dev_infinite_oxygen:
		GameData.set_oxygen(GameData.get_oxygen_capacity())
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
	# Dev shortcut: skip the post-dive screen + shop, dive again immediately.
	if GameData.dev_skip_shop:
		call_deferred("_on_dive_pressed")
		return
	if _dive_summary and _dive_summary.has_method("show_summary"):
		_dive_summary.show_summary()
	else:
		upgrade_shop.show_shop()


func _on_dive_summary_continue() -> void:
	upgrade_shop.show_shop()


func _on_dev_panel_toggle_requested() -> void:
	if _dev_panel and _dev_panel.has_method("toggle"):
		_dev_panel.toggle()


func _on_zone_changed(_zone: ZoneConfig) -> void:
	_refresh_zone_background()


func _on_dive_state_changed(_state: int) -> void:
	_refresh_zone_background()


func _refresh_zone_background() -> void:
	if _zone_background == null:
		return
	var zone: ZoneConfig = GameData.get_current_zone()
	var underwater := GameData.dive_state != GameData.DiveState.SURFACE
	if zone == null or zone.background_texture == null or not underwater:
		_zone_background.visible = false
		return
	_zone_background.texture = zone.background_texture
	_zone_background.visible = true
	# Cover-fit: scale so the texture always fills the viewport on both axes;
	# overflow gets clipped. Wider-than-tall images fit height with horizontal
	# crop; taller-than-wide images fit width with top/bottom crop.
	var viewport := get_viewport_rect().size
	var tex_size := zone.background_texture.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return
	var scale_x: float = viewport.x / tex_size.x
	var scale_y: float = viewport.y / tex_size.y
	var s: float = max(scale_x, scale_y)
	_zone_background.scale = Vector2(s, s)
	var scaled := tex_size * s
	_zone_background.position = (viewport - scaled) * 0.5


func _draw() -> void:
	var viewport = get_viewport_rect().size
	var water_surface_y = 140.0
	# Surface uses a fixed palette. Underwater pulls colors from the current zone.
	var palette = GameData.SURFACE_PALETTE
	var underwater = GameData.dive_state != GameData.DiveState.SURFACE
	var zone: ZoneConfig = null
	var water_top: Color
	var water_bottom: Color
	if underwater:
		zone = GameData.get_current_zone()
		water_top = zone.water_top
		water_bottom = zone.water_bottom
	else:
		water_top = palette["water_top"]
		water_bottom = palette["water_bottom"]

	# When a zone supplies a hand-drawn background, the Sprite2D handles the
	# underwater fill and the procedural gradient is redundant.
	var has_bg := underwater and zone != null and zone.background_texture != null

	# Sky gradient + water gradient + surface line — all skipped when a zone
	# background is showing, so the bg image reaches edge-to-edge.
	if not has_bg:
		for i in 8:
			var t = i / 8.0
			var y = t * water_surface_y
			var band_h = water_surface_y / 8.0
			var c = palette["sky_top"].lerp(palette["sky_bottom"], t)
			draw_rect(Rect2(0, y, viewport.x, band_h + 1), c)

		for i in 12:
			var t = i / 12.0
			var y = water_surface_y + t * (viewport.y - water_surface_y)
			var band_h = (viewport.y - water_surface_y) / 12.0
			var c = water_top.lerp(water_bottom, t)
			draw_rect(Rect2(0, y, viewport.x, band_h + 1), c)

		draw_line(Vector2(0, water_surface_y), Vector2(viewport.x, water_surface_y), Color(0.6, 0.8, 1.0, 0.4), 1.5)

	# Boat (surface / transitioning only). Sprite replaces the old polygon —
	# zone selection now lives in the upgrade shop, so the procedural depth
	# lever previously drawn on the deck is gone. _boat_offset_x is tweened by
	# slide_boat_for_intro to "set sail" off the right edge on Start Run.
	if GameData.dive_state != GameData.DiveState.UNDERWATER:
		var boat_x: float = viewport.x * 0.5 + _boat_offset_x
		var boat_y: float = water_surface_y
		var tex_size := BoatTexture.get_size()
		var aspect: float = tex_size.y / tex_size.x
		var draw_w: float = BOAT_DRAW_WIDTH
		var draw_h: float = draw_w * aspect
		# Anchor so the hull bottom kisses the waterline (small +offset for the
		# tiny reflection rim on the asset).
		var rect := Rect2(boat_x - draw_w * 0.5, boat_y - draw_h + 8, draw_w, draw_h)
		draw_texture_rect(BoatTexture, rect, false)
