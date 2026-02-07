extends Area2D

signal consumed(cash_earned: int)
signal discovered(point: Area2D)

var velocity: Vector2 = Vector2.ZERO
var is_labeled: bool = false
var is_consumed: bool = false
var label_progress: float = 0.0
var network_center: Vector2 = Vector2.ZERO
var input_node_positions: Array = []
var network_exclusion_rect: Rect2 = Rect2()
var target_position: Vector2 = Vector2.ZERO
var display_value: String = ""
var base_color: Color = Color(0.3, 0.8, 1.0)
var cash_multiplier: float = 1.0
var is_augmented: bool = false
var data_class: int = -1
var point_type: String = "number"  # "number" or "sign"
var digit_value: int = 0           # 0-9 for numbers, 0/1/2 for signs (+/−/×)

# Network traversal
var network_ref: Node2D = null
var traversal_path: Array = []  # Array of Vector2 (world positions, one per layer)
var current_waypoint: int = 0

# Animation state
var spawn_timer: float = 0.0
const SPAWN_ANIM_DURATION = 0.35
var discover_flash: float = 0.0
const DISCOVER_FLASH_DURATION = 0.3
var consume_timer: float = 0.0
const CONSUME_ANIM_DURATION = 0.25
var cached_cash_earned: int = 0

const DRIFT_SPEED = 30.0
const ATTRACTION_STRENGTH = 5.0
const REPULSION_STRENGTH = 150.0
const GRAY_COLOR = Color(0.35, 0.35, 0.4)


func _ready() -> void:
	base_color = GameData.get_stage()["color"]
	velocity = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * DRIFT_SPEED
	spawn_timer = 0.0


func _process(delta: float) -> void:
	# Spawn fade-in
	if spawn_timer < SPAWN_ANIM_DURATION:
		spawn_timer += delta

	# Discover flash decay
	if discover_flash > 0.0:
		discover_flash -= delta

	# Consume animation — expand then vanish
	if is_consumed:
		consume_timer += delta
		if consume_timer >= CONSUME_ANIM_DURATION:
			queue_free()
		queue_redraw()
		return

	if is_labeled:
		# Fly toward current waypoint
		var direction = (target_position - global_position).normalized()
		var speed = GameData.get_processing_speed()
		global_position += direction * speed * delta

		if global_position.distance_to(target_position) < 10.0:
			# Highlight the node we just reached
			if network_ref and network_ref.has_method("highlight_node_at"):
				network_ref.highlight_node_at(target_position)

			# Advance to next waypoint
			current_waypoint += 1
			if current_waypoint >= traversal_path.size():
				# Reached the output — consume
				_on_consumed()
			else:
				target_position = traversal_path[current_waypoint]

		queue_redraw()
		return

	# Slight attraction toward center (but not into the network)
	var to_center = network_center - global_position
	var dist_to_center = to_center.length()
	if dist_to_center > 200.0:
		var attraction = to_center.normalized() * ATTRACTION_STRENGTH
		velocity += attraction * delta

	# Repel from network exclusion zone
	if network_exclusion_rect.size.x > 0:
		var rect = network_exclusion_rect
		var padded = Rect2(rect.position - Vector2(20, 20), rect.size + Vector2(40, 40))
		if padded.has_point(global_position):
			var center_rect = rect.get_center()
			var away = (global_position - center_rect)
			if away.length() < 1.0:
				away = Vector2(randf_range(-1, 1), randf_range(-1, 1))
			velocity += away.normalized() * REPULSION_STRENGTH * delta

	# Clamp speed
	if velocity.length() > DRIFT_SPEED * 2:
		velocity = velocity.normalized() * DRIFT_SPEED * 2

	# Random wobble
	velocity += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 10.0 * delta

	global_position += velocity * delta

	# Bounce off screen edges
	var viewport_size = get_viewport_rect().size
	var margin = 20.0
	if global_position.x < margin or global_position.x > viewport_size.x - margin:
		velocity.x *= -1
		global_position.x = clampf(global_position.x, margin, viewport_size.x - margin)
	if global_position.y < margin or global_position.y > viewport_size.y - margin:
		velocity.y *= -1
		global_position.y = clampf(global_position.y, margin, viewport_size.y - margin)

	queue_redraw()


func apply_hover(delta: float) -> void:
	if is_labeled or is_consumed:
		return
	var required = GameData.get_label_time()
	if required <= 0.0:
		required = 0.01
	label_progress += delta
	if label_progress >= required:
		_discover()
	queue_redraw()


func _discover() -> void:
	is_labeled = true
	discover_flash = DISCOVER_FLASH_DURATION
	match GameData.current_stage:
		0:
			display_value = str(data_class)
		1:
			display_value = str(data_class)
		2:  # Math
			if point_type == "sign":
				var signs = ["+", "−", "×"]
				display_value = signs[digit_value % signs.size()]
			else:
				display_value = str(digit_value)
		3:
			display_value = "F" + str(data_class)
		_:
			display_value = str(data_class)

	# Get full traversal path through network (input -> hidden -> correct output)
	if network_ref and network_ref.has_method("get_traversal_path"):
		traversal_path = network_ref.get_traversal_path(data_class)
		current_waypoint = 0
		if traversal_path.size() > 0:
			target_position = traversal_path[0]
		else:
			target_position = network_center
	elif input_node_positions.size() > 0:
		target_position = input_node_positions[randi() % input_node_positions.size()]
	else:
		target_position = network_center

	discovered.emit(self)
	queue_redraw()


func _on_consumed() -> void:
	is_consumed = true
	consume_timer = 0.0
	var earned = GameData.get_cash_per_point()
	if is_augmented:
		earned = int(earned * 0.5 * cash_multiplier)
	else:
		earned = int(earned * cash_multiplier)
	cached_cash_earned = earned
	consumed.emit(earned)


func _draw() -> void:
	var radius = 8.0 if is_augmented else 12.0

	# Spawn fade-in scale + alpha
	var spawn_t = clampf(spawn_timer / SPAWN_ANIM_DURATION, 0.0, 1.0)
	var spawn_scale = 0.3 + 0.7 * spawn_t
	var spawn_alpha = spawn_t

	# Consume animation — burst outward then fade
	if is_consumed:
		var t = clampf(consume_timer / CONSUME_ANIM_DURATION, 0.0, 1.0)
		var burst_scale = 1.0 + t * 2.5
		var burst_alpha = 1.0 - t
		var burst_radius = radius * burst_scale

		# Expanding ring
		var ring_color = Color(base_color.r, base_color.g, base_color.b, burst_alpha * 0.6)
		draw_arc(Vector2.ZERO, burst_radius, 0, TAU, 24, ring_color, 2.0)

		# Fading core
		var core_color = Color(1.0, 1.0, 1.0, burst_alpha * 0.8)
		draw_circle(Vector2.ZERO, radius * (1.0 - t * 0.5), core_color)

		# Floating +$X text
		var font = ThemeDB.fallback_font
		var cash_text = "+$%d" % cached_cash_earned
		var text_size = font.get_string_size(cash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		var float_y = -20.0 - t * 30.0
		var text_alpha = burst_alpha
		var text_color = Color(0.3, 1.0, 0.4, text_alpha)
		draw_string(font, Vector2(-text_size.x / 2.0, float_y), cash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, text_color)
		return

	if is_labeled:
		# Discovery flash — white burst that fades
		if discover_flash > 0.0:
			var flash_t = discover_flash / DISCOVER_FLASH_DURATION
			var flash_radius = radius + 15.0 * (1.0 - flash_t)
			draw_circle(Vector2.ZERO, flash_radius * spawn_scale, Color(1, 1, 1, flash_t * 0.4))

		# Discovered — the label text
		var font = ThemeDB.fallback_font
		var font_size = 13 if is_augmented else 18
		var text_size = font.get_string_size(display_value, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_color = Color(base_color.r, base_color.g, base_color.b, spawn_alpha)

		# Slight scale pop on discover
		var label_scale = 1.0
		if discover_flash > 0.0:
			var flash_t = discover_flash / DISCOVER_FLASH_DURATION
			label_scale = 1.0 + flash_t * 0.4

		draw_set_transform(Vector2.ZERO, 0.0, Vector2(label_scale, label_scale) * spawn_scale)
		draw_string(font, Vector2(-text_size.x / 2.0, text_size.y / 3.0), display_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		# Undiscovered — gray circle with spawn scale
		var gray = Color(GRAY_COLOR.r, GRAY_COLOR.g, GRAY_COLOR.b, spawn_alpha)
		draw_circle(Vector2.ZERO, radius * spawn_scale, gray)

		# Progress ring while being scanned
		if label_progress > 0.0:
			var required = GameData.get_label_time()
			if required > 0.0:
				var ratio = clampf(label_progress / required, 0.0, 1.0)
				var arc_end = TAU * ratio
				var ring_color = Color(base_color.r, base_color.g, base_color.b, spawn_alpha)
				draw_arc(Vector2.ZERO, (radius + 3) * spawn_scale, -PI / 2.0, -PI / 2.0 + arc_end, 32, ring_color, 2.5)

		# Subtle inner highlight
		draw_circle(Vector2(-3, -3) * spawn_scale, radius * 0.2 * spawn_scale, Color(1, 1, 1, 0.15 * spawn_alpha))
