extends Node2D

const Spear = preload("res://scenes/spear.tscn")

var spears: Array = []  # Array of Spear nodes
var fishing_enabled: bool = false
var surface_y: float = 100.0
var underwater_y: float = 400.0
var in_water: bool = false


func _ready() -> void:
	var viewport = get_viewport_rect().size
	surface_y = 100.0
	underwater_y = viewport.y * 0.5
	position = Vector2(viewport.x * 0.5, surface_y)
	_rebuild_spears()


func set_visible_in_water(flag: bool) -> void:
	in_water = flag
	visible = flag
	if not flag:
		# Recall all spears instantly on surfacing
		for s in spears:
			if is_instance_valid(s):
				s.recall_instant()


func update_dive_travel(t: float) -> void:
	# Interpolate from above-water to underwater mid-screen
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


func _unhandled_input(event: InputEvent) -> void:
	if not fishing_enabled:
		return
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_try_throw(get_viewport().get_mouse_position())


func _try_throw(world_target: Vector2) -> void:
	for s in spears:
		if is_instance_valid(s) and s.is_ready():
			s.throw_at(world_target)
			return


func _draw() -> void:
	# Simple diver silhouette — circle head + rectangle body
	if not visible:
		return
	draw_circle(Vector2(0, -12), 10, Color(0.9, 0.85, 0.6))   # head
	draw_rect(Rect2(-8, -2, 16, 24), Color(0.2, 0.3, 0.5))    # body
	draw_circle(Vector2(-4, -12), 3, Color(0.2, 0.6, 1.0, 0.6))  # mask
