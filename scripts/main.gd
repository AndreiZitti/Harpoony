extends Node2D

@onready var diver: Node2D = $Diver
@onready var fish_spawner: Node2D = $FishSpawner
@onready var oxygen_timer: Timer = $OxygenTimer
@onready var hud: CanvasLayer = $HUD
@onready var upgrade_shop: CanvasLayer = $UpgradeShop

# Fade transition
var phase_fade: float = 0.0
const PHASE_FADE_DURATION = 0.4
var pending_state: String = ""

const DIVE_TRAVEL_DURATION = 1.5
const RESURFACE_TRAVEL_DURATION = 1.0
var travel_timer: float = 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.04, 0.08, 0.14))

	upgrade_shop.next_dive_pressed.connect(_on_dive_pressed)
	oxygen_timer.timeout.connect(_on_oxygen_tick)

	# Start on surface with shop open
	GameData.set_dive_state("surface")
	upgrade_shop.show_shop()
	if diver.has_method("set_visible_in_water"):
		diver.set_visible_in_water(false)


func _process(delta: float) -> void:
	match GameData.dive_state:
		"diving":
			travel_timer += delta
			# Diver travels from top to center — managed in diver.gd via a t in [0,1]
			if diver.has_method("update_dive_travel"):
				diver.update_dive_travel(clampf(travel_timer / DIVE_TRAVEL_DURATION, 0.0, 1.0))
			if travel_timer >= DIVE_TRAVEL_DURATION:
				_enter_underwater()

		"underwater":
			# Oxygen drains via OxygenTimer (1/sec); nothing to tick here
			pass

		"resurfacing":
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
	GameData.set_dive_state("underwater")
	oxygen_timer.start()
	if fish_spawner.has_method("start_spawning"):
		fish_spawner.start_spawning()
	if diver.has_method("enable_fishing"):
		diver.enable_fishing(true)


func _on_oxygen_tick() -> void:
	if GameData.dive_state != "underwater":
		return
	GameData.set_oxygen(GameData.oxygen - 1.0)
	if GameData.oxygen <= 0.0:
		_begin_resurface(true)


func begin_manual_resurface() -> void:
	if GameData.dive_state == "underwater":
		_begin_resurface(false)


func _begin_resurface(lost_oxygen: bool) -> void:
	oxygen_timer.stop()
	if fish_spawner.has_method("stop_spawning"):
		fish_spawner.stop_spawning()
	if diver.has_method("enable_fishing"):
		diver.enable_fishing(false)
	GameData.set_dive_state("resurfacing")
	travel_timer = 0.0
	# Cache whether oxygen was lost to be handled in _enter_surface
	set_meta("lost_oxygen", lost_oxygen)


func _enter_surface() -> void:
	var lost_oxygen = get_meta("lost_oxygen", false)
	GameData.finish_dive(lost_oxygen)
	if diver.has_method("set_visible_in_water"):
		diver.set_visible_in_water(false)
	upgrade_shop.show_shop()


func _draw() -> void:
	var viewport = get_viewport_rect().size
	var water_surface_y = 140.0

	# Sky gradient (top)
	for i in 8:
		var t = i / 8.0
		var y = t * water_surface_y
		var band_h = water_surface_y / 8.0
		var c = Color(0.4, 0.6, 0.85).lerp(Color(0.1, 0.3, 0.55), t)
		draw_rect(Rect2(0, y, viewport.x, band_h + 1), c)

	# Water (below surface)
	for i in 12:
		var t = i / 12.0
		var y = water_surface_y + t * (viewport.y - water_surface_y)
		var band_h = (viewport.y - water_surface_y) / 12.0
		var c = Color(0.08, 0.2, 0.4).lerp(Color(0.02, 0.05, 0.12), t)
		draw_rect(Rect2(0, y, viewport.x, band_h + 1), c)

	# Water surface line
	draw_line(Vector2(0, water_surface_y), Vector2(viewport.x, water_surface_y), Color(0.6, 0.8, 1.0, 0.4), 1.5)

	# Boat silhouette (only visible when surface or transitioning)
	if GameData.dive_state in ["surface", "diving", "resurfacing"]:
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
		# Mast
		draw_line(Vector2(boat_x, boat_y - 25), Vector2(boat_x, boat_y - 90), Color(0.3, 0.25, 0.2), 3.0)
