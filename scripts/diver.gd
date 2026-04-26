extends Node2D

const SpearScene = preload("res://scenes/spear.tscn")
const DiverTexture = preload("res://assets/diver/diver_east.png")
const DIVER_SCALE = 0.85  # 124px source → ~105px on screen, fills most of the aim ring

# Spears are instantiated per fire and self-cleanup on arrival. We just track
# active ones so we can recall them when the dive ends.
var active_spears: Array = []
var fishing_enabled: bool = false
var surface_y: float = 100.0
var underwater_y: float = 400.0
var in_water: bool = false

var aim_angle: float = 0.0
const AIM_RADIUS = 60.0
const AIM_ANGULAR_SPEED = PI  # 1 rotation per 2 sec


func _ready() -> void:
	# Pixel-art sprite — disable bilinear filtering so the source pixels stay crisp.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var viewport = get_viewport_rect().size
	surface_y = 100.0
	underwater_y = get_target_depth_y()
	position = Vector2(viewport.x * 0.5, surface_y)


func get_target_depth_y() -> float:
	# Always dive to mid-screen so fish are visible above and below.
	# Zone changes the species + water tint, not the diver's screen position.
	var viewport = get_viewport_rect().size
	return viewport.y * 0.5


func set_visible_in_water(flag: bool) -> void:
	in_water = flag
	visible = flag
	if not flag:
		_cleanup_active_spears()


func _cleanup_active_spears() -> void:
	for s in active_spears:
		if is_instance_valid(s):
			s.recall_instant()
	active_spears.clear()


func update_dive_travel(t: float) -> void:
	underwater_y = get_target_depth_y()
	position.y = lerp(surface_y, underwater_y, t)
	queue_redraw()


func update_resurface_travel(t: float) -> void:
	position.y = lerp(underwater_y, surface_y, t)
	queue_redraw()


func enable_fishing(flag: bool) -> void:
	fishing_enabled = flag


# Stub kept so main.gd's existing call survives the refactor — types are now
# pulled at fire time, so there's nothing to pre-load.
func reload_spear_types() -> void:
	pass


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
	if GameData.get_bag_loaded_count() <= 0:
		return
	# Round drained — wait for the in-flight spears to return + reshuffle.
	if GameData.bag_is_exhausted():
		return
	# One spear at a time — wait for the previous shot to return.
	if active_spears.size() > 0:
		return
	var dir = Vector2(cos(aim_angle), sin(aim_angle))
	var spear = SpearScene.instantiate()
	spear.diver_node = self
	get_tree().current_scene.add_child(spear)
	spear.global_position = global_position
	if not spear.fire(dir):
		# Pull failed (e.g. queue empty mid-dive) — clean up.
		spear.queue_free()
		return
	# TODO: if drawn type's twin_shot > 0, fire a second spear at aim_angle ± small offset.
	active_spears.append(spear)
	# Auto-prune when the spear frees itself on arrival.
	spear.tree_exited.connect(_on_spear_freed.bind(spear))


func _on_spear_freed(spear: Node) -> void:
	active_spears.erase(spear)


func _draw() -> void:
	if not visible:
		return
	# Diver sprite — single static face. We can't rotate to aim direction
	# because the asset only has 8 fixed views and the animation set is incomplete.
	var tex_size := DiverTexture.get_size()
	var draw_size := tex_size * DIVER_SCALE
	draw_texture_rect(DiverTexture, Rect2(-draw_size * 0.5, draw_size), false)

	if fishing_enabled:
		# Aim indicator color shifts with fire-state so the player sees status at a glance.
		var can_fire := GameData.get_bag_loaded_count() > 0 and not GameData.bag_is_exhausted()
		var ring_alpha: float = 0.15 if can_fire else 0.08
		draw_arc(Vector2.ZERO, AIM_RADIUS, 0, TAU, 64, Color(1, 1, 1, ring_alpha), 1.5)
		var p = Vector2(cos(aim_angle), sin(aim_angle)) * AIM_RADIUS
		var line_color: Color
		var dot_color: Color
		if can_fire:
			line_color = Color(1.0, 0.85, 0.3, 0.6)
			dot_color = Color(1.0, 0.85, 0.3)
		else:
			# Cool gray when blocked — matches the dimmed queue chips.
			line_color = Color(0.55, 0.6, 0.7, 0.35)
			dot_color = Color(0.55, 0.6, 0.7, 0.7)
		draw_line(Vector2.ZERO, p, line_color, 2.0)
		draw_circle(p, 6, dot_color)
		# Pulse marker when bag is empty (waiting for spear to return).
		if not can_fire:
			var pulse := 0.5 + 0.5 * sin(aim_angle * 4.0)
			draw_arc(Vector2.ZERO, AIM_RADIUS, 0, TAU, 64, Color(0.7, 0.75, 0.85, 0.05 + 0.06 * pulse), 1.0)
