extends Area2D

signal consumed(compute_earned: int)

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
var compute_multiplier: float = 1.0
var is_augmented: bool = false

const DRIFT_SPEED = 30.0
const ATTRACTION_STRENGTH = 5.0
const REPULSION_STRENGTH = 150.0
const GRAY_COLOR = Color(0.35, 0.35, 0.4)


func _ready() -> void:
	base_color = GameData.get_stage()["color"]
	velocity = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * DRIFT_SPEED


func _process(delta: float) -> void:
	if is_consumed:
		return

	if is_labeled:
		# Fly toward the chosen input node
		var direction = (target_position - global_position).normalized()
		var speed = GameData.get_processing_speed()
		global_position += direction * speed * delta

		if global_position.distance_to(target_position) < 15.0:
			_on_consumed()
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
	# Generate stage-appropriate data
	match GameData.current_stage:
		0:  # Binary — 0 or 1
			display_value = str(randi() % 2)
		1:  # Numbers — any digit 0-9
			display_value = str(randi() % 10)
		2:  # Images — labeled categories
			var labels = ["cat", "dog", "car", "tree", "house"]
			display_value = labels[randi() % labels.size()]
		3:  # Faces — face IDs
			display_value = "F" + str(randi() % 100)
		_:  # AGI — complex tokens
			display_value = str(randi() % 1000)
	# Pick a random input node as the target
	if input_node_positions.size() > 0:
		target_position = input_node_positions[randi() % input_node_positions.size()]
	else:
		target_position = network_center
	queue_redraw()


func _on_consumed() -> void:
	is_consumed = true
	var compute = GameData.get_compute_per_point()
	if is_augmented:
		compute = int(compute * 0.5 * compute_multiplier)
	else:
		compute = int(compute * compute_multiplier)
	consumed.emit(compute)
	queue_free()


func _draw() -> void:
	if is_consumed:
		return

	var radius = 8.0 if is_augmented else 12.0

	if is_labeled:
		# Discovered — just the raw number, no circle
		var font = ThemeDB.fallback_font
		var font_size = 13 if is_augmented else 18
		var text_size = font.get_string_size(display_value, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, Vector2(-text_size.x / 2.0, text_size.y / 3.0), display_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, base_color)
	else:
		# Undiscovered — gray
		draw_circle(Vector2.ZERO, radius, GRAY_COLOR)

		# Progress ring while being scanned
		if label_progress > 0.0:
			var required = GameData.get_label_time()
			if required > 0.0:
				var ratio = clampf(label_progress / required, 0.0, 1.0)
				var arc_end = TAU * ratio
				draw_arc(Vector2.ZERO, radius + 3, -PI / 2.0, -PI / 2.0 + arc_end, 32, base_color, 2.5)

		# Subtle inner highlight
		draw_circle(Vector2(-3, -3), radius * 0.2, Color(1, 1, 1, 0.15))
