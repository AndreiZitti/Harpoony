extends Node2D

@onready var network: Node2D = $Network
@onready var data_spawner: Node2D = $DataSpawner
@onready var cursor: Area2D = $Cursor
@onready var hud: CanvasLayer = $HUD
@onready var upgrade_shop: CanvasLayer = $UpgradeShop
@onready var training_timer: Timer = $EpochTimer

var round_ended: bool = false


func _ready() -> void:
	# Dark background
	RenderingServer.set_default_clear_color(Color(0.04, 0.04, 0.08))

	# Connect signals
	upgrade_shop.next_epoch_pressed.connect(_start_training)
	GameData.stage_changed.connect(_on_stage_changed)
	training_timer.timeout.connect(_on_training_timeout)
	data_spawner.batch_complete.connect(_on_batch_complete)

	# Position network at screen center
	var viewport_size = get_viewport_rect().size
	network.position = viewport_size / 2.0

	# Show upgrade tree first — player starts here
	cursor.visible = false
	upgrade_shop.show_shop()


func _process(_delta: float) -> void:
	if GameData.is_epoch_active:
		hud.update_timer(training_timer.time_left)
		hud.update_batch_count(data_spawner.get_remaining_count(), data_spawner.batch_total)


func _start_training() -> void:
	round_ended = false
	GameData.is_epoch_active = true
	GameData.training_round += 1

	# Compute resets each round
	GameData.compute = 0.0
	GameData.compute_changed.emit(GameData.compute)

	var duration = GameData.get_training_duration()
	training_timer.wait_time = duration
	training_timer.one_shot = true
	training_timer.start()

	# Start the batch
	data_spawner.start_batch()

	cursor.visible = true


func _end_round() -> void:
	if round_ended:
		return
	round_ended = true

	GameData.is_epoch_active = false
	cursor.visible = false
	training_timer.stop()
	hud.update_timer(0.0)

	# Clear remaining data points
	data_spawner.clear_all_points()

	# Show upgrade shop
	upgrade_shop.show_shop()


func _on_training_timeout() -> void:
	_end_round()


func _on_batch_complete() -> void:
	# All data consumed — end round early
	_end_round()


func _on_stage_changed(stage_index: int) -> void:
	network.on_stage_changed()
	print("Stage advanced to: ", GameData.stages[stage_index]["name"])
