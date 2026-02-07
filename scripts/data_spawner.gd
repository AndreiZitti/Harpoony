extends Node2D

signal batch_complete

@export var data_point_scene: PackedScene

var active_points: Array = []
var batch_remaining: int = 0
var batch_total: int = 0
var spawn_timer: float = 0.0

# Combo detection
var recently_labeled: Array = []  # Array of {point, time}
const COMBO_WINDOW: float = 0.15  # Seconds within which labels count as simultaneous

const SPAWN_INTERVAL = 0.3  # Stagger spawns so they don't all appear at once


func _process(delta: float) -> void:
	if not GameData.is_epoch_active:
		return

	# Clean up expired combo buffer entries
	var now = Time.get_ticks_msec() / 1000.0
	recently_labeled = recently_labeled.filter(func(entry):
		return is_instance_valid(entry["point"]) and (now - entry["time"]) < COMBO_WINDOW
	)

	# Spawn remaining batch with stagger
	if batch_remaining > 0:
		spawn_timer -= delta
		if spawn_timer <= 0:
			spawn_timer = SPAWN_INTERVAL
			_spawn_data_point()
			batch_remaining -= 1

	# Clean up freed references
	active_points = active_points.filter(func(p): return is_instance_valid(p))

	# Check if all data has been consumed (batch done)
	# Count only points that haven't been consumed yet (animating consume doesn't count)
	var alive_count = active_points.filter(func(p): return not p.is_consumed).size()
	if batch_remaining <= 0 and alive_count == 0:
		batch_complete.emit()


func start_batch() -> void:
	batch_total = GameData.get_dataset_size()
	batch_remaining = batch_total
	spawn_timer = 0.0  # Spawn first one immediately


func get_remaining_count() -> int:
	active_points = active_points.filter(func(p): return is_instance_valid(p))
	var alive = active_points.filter(func(p): return not p.is_consumed).size()
	return batch_remaining + alive


func _spawn_data_point() -> void:
	if data_point_scene == null:
		return

	var point = data_point_scene.instantiate() as Area2D
	point.add_to_group("data_points")

	var viewport_size = get_viewport_rect().size
	var center = viewport_size / 2.0
	point.network_center = center

	# Pass network reference for traversal path + exclusion zone
	var network = get_parent().get_node_or_null("Network")
	if network:
		point.network_ref = network
		point.input_node_positions = network.get_input_node_world_positions()
		point.network_exclusion_rect = network.get_exclusion_rect()

	# Spawn at random edge
	var edge = randi() % 4
	var pos = Vector2.ZERO
	var margin = 40.0
	match edge:
		0:  # Top
			pos = Vector2(randf_range(margin, viewport_size.x - margin), margin)
		1:  # Bottom
			pos = Vector2(randf_range(margin, viewport_size.x - margin), viewport_size.y - margin)
		2:  # Left
			pos = Vector2(margin, randf_range(margin, viewport_size.y - margin))
		3:  # Right
			pos = Vector2(viewport_size.x - margin, randf_range(margin, viewport_size.y - margin))

	# Assign data class and point type
	match GameData.current_stage:
		0:  # Binary
			point.data_class = randi() % 2
		1:  # Numbers
			point.data_class = randi() % 10
		2:  # Math — 75% numbers, 25% signs
			if randf() < 0.25:
				point.point_type = "sign"
				point.data_class = 1  # Routes to Signs output node
				point.digit_value = randi() % 3  # 0=+, 1=−, 2=×
			else:
				point.point_type = "number"
				point.data_class = 0  # Routes to Numbers output node
				point.digit_value = randi() % 10  # 0-9
		_:
			point.data_class = randi() % GameData.get_output_count()

	point.global_position = pos
	point.consumed.connect(_on_point_consumed.bind(point))
	point.discovered.connect(_on_point_discovered)

	get_tree().current_scene.add_child(point)
	active_points.append(point)


func _on_point_consumed(cash_earned: int, point: Area2D) -> void:
	GameData.add_cash(cash_earned)
	GameData.add_accuracy(GameData.get_accuracy_per_point())

	# Augmentation — only non-augmented data can spawn copies
	if is_instance_valid(point) and not point.is_augmented:
		var aug_chance = GameData.get_aug_chance()
		if aug_chance > 0.0 and randf() < aug_chance:
			_spawn_aug_point()


func _spawn_aug_point() -> void:
	if data_point_scene == null:
		return

	var network = get_parent().get_node_or_null("Network")
	if not network:
		return
	var output_positions = network.get_output_node_world_positions()
	if output_positions.size() == 0:
		return

	var point = data_point_scene.instantiate() as Area2D
	point.add_to_group("data_points")

	var viewport_size = get_viewport_rect().size
	var center = viewport_size / 2.0
	point.network_center = center
	point.network_ref = network
	point.input_node_positions = network.get_input_node_world_positions()
	point.network_exclusion_rect = network.get_exclusion_rect()

	# Augmented data gets quality multiplier
	point.cash_multiplier = GameData.get_aug_quality_multiplier()
	point.is_augmented = true

	# Assign data class and point type
	match GameData.current_stage:
		0:
			point.data_class = randi() % 2
		1:
			point.data_class = randi() % 10
		2:  # Math — 75% numbers, 25% signs
			if randf() < 0.25:
				point.point_type = "sign"
				point.data_class = 1
				point.digit_value = randi() % 3
			else:
				point.point_type = "number"
				point.data_class = 0
				point.digit_value = randi() % 10
		_:
			point.data_class = randi() % GameData.get_output_count()

	# Spawn from a random output node
	point.global_position = output_positions[randi() % output_positions.size()]
	# Push it outward from center
	var outward = (point.global_position - center).normalized()
	point.velocity = outward * 80.0

	point.consumed.connect(_on_point_consumed.bind(point))
	point.discovered.connect(_on_point_discovered)

	get_tree().current_scene.add_child(point)
	active_points.append(point)


func clear_all_points() -> void:
	for point in active_points:
		if is_instance_valid(point):
			point.queue_free()
	active_points.clear()
	batch_remaining = 0


func _on_point_discovered(source_point: Area2D) -> void:
	# Flash the cursor on label
	var cursor = get_parent().get_node_or_null("Cursor")
	if cursor and cursor.has_method("on_point_labeled"):
		cursor.on_point_labeled()

	# Combo detection for Stage 2 (Math)
	if GameData.current_stage == 2 and not source_point.is_augmented:
		var now = Time.get_ticks_msec() / 1000.0
		recently_labeled.append({"point": source_point, "time": now})
		_check_combo()

	# Batch label logic (existing)
	var chance = GameData.get_batch_label_chance()
	if chance <= 0.0:
		return

	var cursor_points: Array = []
	if cursor:
		cursor_points = cursor.hovering_points.duplicate()

	var batch_delay = 0.0
	for point in active_points:
		if not is_instance_valid(point):
			continue
		if point == source_point:
			continue
		if point.is_labeled or point.is_consumed:
			continue
		if point.data_class != source_point.data_class:
			continue
		if point in cursor_points:
			continue
		if randf() < chance:
			if batch_delay > 0.0:
				_draw_chain_line(source_point.global_position, point.global_position, batch_delay)
			point._discover()
			batch_delay += 0.08


func _check_combo() -> void:
	# Need at least 3 recently labeled points
	if recently_labeled.size() < 3:
		return

	# Collect valid (not yet merging/consumed) points by type
	var numbers: Array = []
	var signs: Array = []
	for entry in recently_labeled:
		var p = entry["point"]
		if not is_instance_valid(p) or p.is_consumed:
			continue
		if p.has_meta("is_merging"):
			continue
		if p.point_type == "number":
			numbers.append(p)
		elif p.point_type == "sign":
			signs.append(p)

	# Check for valid combo: 2 numbers + 1 sign
	if numbers.size() >= 2 and signs.size() >= 1:
		var combo_numbers = [numbers[0], numbers[1]]
		var combo_sign = signs[0]
		_trigger_combo(combo_numbers, combo_sign)

		# Remove used points from buffer
		for p in combo_numbers:
			recently_labeled = recently_labeled.filter(func(e): return e["point"] != p)
		recently_labeled = recently_labeled.filter(func(e): return e["point"] != combo_sign)


func _trigger_combo(numbers: Array, sign_point: Area2D) -> void:
	var a = numbers[0].digit_value
	var b = numbers[1].digit_value
	var sign_idx = sign_point.digit_value
	var signs_display = ["+", "\u2212", "\u00d7"]
	var sign_str = signs_display[sign_idx % signs_display.size()]

	var result: int = 0
	match sign_idx:
		0: result = a + b
		1: result = a - b
		2: result = a * b

	var equation = "%d%s%d=%d" % [a, sign_str, b, result]
	print("COMBO! ", equation)

	# Mark points as merging (prevents double-combo)
	for p in numbers:
		p.set_meta("is_merging", true)
	sign_point.set_meta("is_merging", true)


func _draw_chain_line(from: Vector2, to: Vector2, delay: float) -> void:
	# Spawn a brief visual line between batch-labeled points
	var line = Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.width = 1.5
	line.default_color = Color(0.3, 1.0, 0.5, 0.5)
	get_tree().current_scene.add_child(line)

	var tween = line.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(line, "modulate:a", 0.0, 0.3)
	tween.tween_callback(line.queue_free)
