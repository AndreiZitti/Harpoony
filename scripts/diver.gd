extends Node2D

const Spear = preload("res://scenes/spear.tscn")

var spears: Array = []
var fishing_enabled: bool = false
var surface_y: float = 100.0
var underwater_y: float = 400.0
var in_water: bool = false

var aim_angle: float = 0.0
const AIM_RADIUS = 60.0
const AIM_ANGULAR_SPEED = PI  # 1 rotation per 2 sec


func _ready() -> void:
	var viewport = get_viewport_rect().size
	surface_y = 100.0
	underwater_y = get_target_depth_y()
	position = Vector2(viewport.x * 0.5, surface_y)
	_rebuild_spears()


func get_target_depth_y() -> float:
	var viewport = get_viewport_rect().size
	var water_surface_y = 140.0
	var depth_range = viewport.y - water_surface_y
	# Map zone index 0..N-1 → fraction 0.2..0.85 of water column (visual only).
	var n = max(1, GameData.zones.size())
	var t = float(GameData.selected_zone_index) / float(max(1, n - 1))
	var frac = lerpf(0.2, 0.85, t)
	return water_surface_y + depth_range * frac


func set_visible_in_water(flag: bool) -> void:
	in_water = flag
	visible = flag
	if not flag:
		for s in spears:
			if is_instance_valid(s):
				s.recall_instant()


func update_dive_travel(t: float) -> void:
	underwater_y = get_target_depth_y()
	position.y = lerp(surface_y, underwater_y, t)
	queue_redraw()


func update_resurface_travel(t: float) -> void:
	position.y = lerp(underwater_y, surface_y, t)
	queue_redraw()


func enable_fishing(flag: bool) -> void:
	fishing_enabled = flag
	_ensure_spear_count()


func _ensure_spear_count() -> void:
	var target = GameData.get_spear_count()
	if spears.size() != target:
		_rebuild_spears()


func _rebuild_spears() -> void:
	for s in spears:
		if is_instance_valid(s):
			s.queue_free()
	spears.clear()
	var count = GameData.get_spear_count()
	for i in count:
		var spear = Spear.instantiate()
		spear.spear_index = i
		spear.diver_node = self
		add_child(spear)
		spears.append(spear)


func _process(delta: float) -> void:
	if fishing_enabled:
		aim_angle = fmod(aim_angle + AIM_ANGULAR_SPEED * delta, TAU)
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not fishing_enabled:
		return
	var fire = false
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			fire = true
	elif event is InputEventKey:
		var kb = event as InputEventKey
		if kb.pressed and not kb.echo and kb.keycode == KEY_SPACE:
			fire = true
	if fire:
		_try_fire()


func _try_fire() -> void:
	var dir = Vector2(cos(aim_angle), sin(aim_angle))
	for s in spears:
		if is_instance_valid(s) and s.is_ready():
			s.throw_in_direction(dir)
			return


func _draw() -> void:
	if not visible:
		return
	draw_circle(Vector2(0, -12), 10, Color(0.9, 0.85, 0.6))   # head
	draw_rect(Rect2(-8, -2, 16, 24), Color(0.2, 0.3, 0.5))    # body
	draw_circle(Vector2(-4, -12), 3, Color(0.2, 0.6, 1.0, 0.6))  # mask

	if fishing_enabled:
		draw_arc(Vector2.ZERO, AIM_RADIUS, 0, TAU, 64, Color(1, 1, 1, 0.15), 1.5)
		var p = Vector2(cos(aim_angle), sin(aim_angle)) * AIM_RADIUS
		draw_line(Vector2.ZERO, p, Color(1.0, 0.85, 0.3, 0.4), 2.0)
		draw_circle(p, 6, Color(1.0, 0.85, 0.3))
