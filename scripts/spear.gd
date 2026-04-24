extends Node2D

enum State { READY, FLYING, REELING_MISS, REELING_HIT }

var state: int = State.READY
var spear_index: int = 0
var diver_node: Node2D = null
var attached_fish: Node2D = null

# Movement
var flight_dir: Vector2 = Vector2.ZERO
var flight_target: Vector2 = Vector2.ZERO
var flight_distance_remaining: float = 0.0
const MISS_OVERSHOOT = 80.0


func is_ready() -> bool:
	return state == State.READY


func _ready() -> void:
	_sync_hud()


func throw_at(world_target: Vector2) -> void:
	if state != State.READY:
		return
	# Diver is at own global position; spear starts there too
	global_position = diver_node.global_position
	flight_target = world_target
	flight_dir = (world_target - global_position).normalized()
	flight_distance_remaining = global_position.distance_to(world_target)
	state = State.FLYING
	_sync_hud()
	queue_redraw()


func attach_to_fish(fish: Node2D) -> void:
	if state != State.FLYING:
		return
	attached_fish = fish
	if fish.has_method("on_speared"):
		fish.on_speared(self)
	state = State.REELING_HIT
	_sync_hud()


func recall_instant() -> void:
	state = State.READY
	attached_fish = null
	if diver_node:
		global_position = diver_node.global_position
	_sync_hud()
	queue_redraw()


func _process(delta: float) -> void:
	match state:
		State.READY:
			# Sit on diver
			if diver_node:
				global_position = diver_node.global_position
		State.FLYING:
			var speed = GameData.get_spear_speed()
			var step = speed * delta
			global_position += flight_dir * step
			flight_distance_remaining -= step

			# Hit check against fish group
			for fish in get_tree().get_nodes_in_group("fish"):
				if not is_instance_valid(fish) or fish.speared:
					continue
				var r = fish.get_effective_hit_radius() if fish.has_method("get_effective_hit_radius") else 12.0
				if global_position.distance_to(fish.global_position) <= r:
					attach_to_fish(fish)
					return

			if flight_distance_remaining <= -MISS_OVERSHOOT:
				state = State.REELING_MISS
				_sync_hud()
		State.REELING_MISS:
			var speed = GameData.get_spear_speed()  # Miss recalls at spear speed (fast)
			_reel_toward_diver(speed, delta)
		State.REELING_HIT:
			var speed = GameData.get_reel_speed()  # Hit reels slower
			_reel_toward_diver(speed, delta)
			if attached_fish and is_instance_valid(attached_fish):
				attached_fish.global_position = global_position
	queue_redraw()


func _reel_toward_diver(speed: float, delta: float) -> void:
	if not diver_node:
		return
	var to_diver = diver_node.global_position - global_position
	var dist = to_diver.length()
	if dist < 8.0:
		_arrive()
		return
	global_position += to_diver.normalized() * speed * delta


func _arrive() -> void:
	if state == State.REELING_HIT and attached_fish and is_instance_valid(attached_fish):
		var value = attached_fish.get_cash_value() if attached_fish.has_method("get_cash_value") else 0
		GameData.add_dive_cash(value)
		attached_fish.queue_free()
		attached_fish = null
	state = State.READY
	_sync_hud()


func _sync_hud() -> void:
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud and hud.has_method("update_spear_state"):
		var hud_state = "ready"
		match state:
			State.FLYING:
				hud_state = "flying"
			State.REELING_MISS, State.REELING_HIT:
				hud_state = "reeling"
		hud.update_spear_state(spear_index, hud_state)


func _draw() -> void:
	if state == State.READY:
		return
	# Taut line from diver to spear
	if diver_node:
		var local_diver = to_local(diver_node.global_position)
		draw_line(Vector2.ZERO, local_diver, Color(0.9, 0.9, 0.95, 0.6), 1.5)
	# Spear body
	var length = 20.0
	var width = 3.0
	var angle = flight_dir.angle() if state == State.FLYING else (diver_node.global_position - global_position).angle() + PI
	draw_set_transform(Vector2.ZERO, angle, Vector2.ONE)
	draw_rect(Rect2(-length / 2, -width / 2, length, width), Color(0.85, 0.85, 0.9))
	# Tip triangle
	var tip_a = Vector2(length / 2, 0)
	var tip_b = Vector2(length / 2 - 6, -4)
	var tip_c = Vector2(length / 2 - 6, 4)
	draw_polygon(PackedVector2Array([tip_a, tip_b, tip_c]), PackedColorArray([Color(0.95, 0.9, 0.6)]))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
