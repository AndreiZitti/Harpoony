extends Node2D

signal batch_complete

@export var data_point_scene: PackedScene

var active_points: Array = []
var batch_remaining: int = 0
var batch_total: int = 0
var spawn_timer: float = 0.0

const SPAWN_INTERVAL = 0.3  # Stagger spawns so they don't all appear at once


func _process(delta: float) -> void:
	if not GameData.is_epoch_active:
		return

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
	if batch_remaining <= 0 and active_points.size() == 0:
		batch_complete.emit()


func start_batch() -> void:
	batch_total = GameData.get_dataset_size()
	batch_remaining = batch_total
	spawn_timer = 0.0  # Spawn first one immediately


func get_remaining_count() -> int:
	active_points = active_points.filter(func(p): return is_instance_valid(p))
	return batch_remaining + active_points.size()


func _spawn_data_point() -> void:
	if data_point_scene == null:
		return

	var point = data_point_scene.instantiate() as Area2D
	point.add_to_group("data_points")

	var viewport_size = get_viewport_rect().size
	var center = viewport_size / 2.0
	point.network_center = center

	# Pass input node positions and exclusion zone from the network
	var network = get_parent().get_node_or_null("Network")
	if network:
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

	# Assign data class
	match GameData.current_stage:
		0:  # Binary
			point.data_class = randi() % 2
		1:  # Numbers
			point.data_class = randi() % 10
		_:
			point.data_class = randi() % GameData.get_output_count()

	point.global_position = pos
	point.consumed.connect(_on_point_consumed.bind(point))
	point.discovered.connect(_on_point_discovered)

	get_tree().current_scene.add_child(point)
	active_points.append(point)


func _on_point_consumed(compute_earned: int, point: Area2D) -> void:
	GameData.add_compute(compute_earned)
	GameData.add_accuracy(GameData.get_accuracy_per_point())

	# Trigger network forward pass visual
	var network = get_parent().get_node_or_null("Network")
	if network and network.has_method("trigger_forward_pass"):
		network.trigger_forward_pass()

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
	point.input_node_positions = network.get_input_node_world_positions()
	point.network_exclusion_rect = network.get_exclusion_rect()

	# Augmented data gets quality multiplier
	point.compute_multiplier = GameData.get_aug_quality_multiplier()
	point.is_augmented = true

	# Assign data class
	match GameData.current_stage:
		0:
			point.data_class = randi() % 2
		1:
			point.data_class = randi() % 10
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
	var chance = GameData.get_batch_label_chance()
	if chance <= 0.0:
		return

	var cursor = get_parent().get_node_or_null("Cursor")
	var cursor_points: Array = []
	if cursor:
		cursor_points = cursor.hovering_points.duplicate()

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
			point._discover()
