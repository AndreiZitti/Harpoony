extends Node

# Signals
signal compute_changed(amount: float)
signal stage_changed(stage_index: int)
signal accuracy_changed(accuracy: float)
signal network_changed()

# Game state
var compute: float = 0.0
var current_stage: int = 0
var accuracy: float = 0.0
var training_round: int = 0
var is_epoch_active: bool = false

# Network structure
var neurons_per_layer: int = 1
var num_hidden_layers: int = 1

# Upgrade levels
var upgrade_levels: Dictionary = {
	"nodes": 0,
	"layers": 0,
	"dataset_size": 0,
	"data_quality": 0,
	"cursor_size": 0,
	"label_speed": 0,
	"activation_func": 0,
	"learning_rate": 0,
	"aug_chance": 0,
	"aug_quality": 0,
	"batch_label": 0,
}

# Prerequisites — empty string means always available
var upgrade_prerequisites: Dictionary = {
	"nodes": "",
	"layers": "",
	"dataset_size": "",
	"data_quality": "",
	"cursor_size": "",
	"label_speed": "",
	"activation_func": "",
	"learning_rate": "",
	"aug_chance": "",
	"aug_quality": "aug_chance",
	"batch_label": "",
}

# Stage definitions
var stages: Array = [
	{
		"name": "Binary",
		"label_time": 2.0,
		"compute_per_point": 1,
		"accuracy_needed": 50,
		"output_nodes": 2,
		"color": Color(0.3, 0.8, 1.0),
	},
	{
		"name": "Numbers",
		"label_time": 1.5,
		"compute_per_point": 5,
		"accuracy_needed": 120,
		"output_nodes": 10,
		"color": Color(0.3, 1.0, 0.5),
	},
	{
		"name": "Images",
		"label_time": 1.0,
		"compute_per_point": 25,
		"accuracy_needed": 300,
		"output_nodes": 10,
		"color": Color(1.0, 0.8, 0.2),
	},
	{
		"name": "Faces",
		"label_time": 2.0,
		"compute_per_point": 150,
		"accuracy_needed": 600,
		"output_nodes": 10,
		"color": Color(1.0, 0.4, 0.3),
	},
	{
		"name": "AGI",
		"label_time": 3.0,
		"compute_per_point": 1000,
		"accuracy_needed": 1500,
		"output_nodes": 10,
		"color": Color(1.0, 0.3, 1.0),
	},
]

# Upgrade definitions
var upgrades: Dictionary = {
	"nodes": {
		"name": "Nodes",
		"description": "+1 neuron to every hidden layer",
		"max_level": 5,
		"costs": [20, 50, 120, 300, 800],
		"stage_available": 0,
	},
	"layers": {
		"name": "Layers",
		"description": "Add a hidden layer",
		"max_level": 3,
		"costs": [100, 400, 1500],
		"stage_available": 0,
	},
	"dataset_size": {
		"name": "Dataset Size",
		"description": "More data points per round",
		"max_level": 8,
		"costs": [15, 40, 100, 250, 600, 1500, 4000, 10000],
		"stage_available": 0,
	},
	"data_quality": {
		"name": "Data Quality",
		"description": "Each labeled point earns more Compute",
		"max_level": 5,
		"costs": [25, 60, 150, 400, 1000],
		"stage_available": 0,
	},
	"cursor_size": {
		"name": "Cursor Size",
		"description": "Larger scanning area",
		"max_level": 5,
		"costs": [10, 30, 80, 200, 500],
		"stage_available": 0,
	},
	"label_speed": {
		"name": "Label Speed",
		"description": "Discover data faster",
		"max_level": 8,
		"costs": [10, 25, 60, 150, 400, 1000, 2500, 6000],
		"stage_available": 0,
	},
	"activation_func": {
		"name": "Activation",
		"description": "Activation functions multiply Compute output",
		"max_level": 4,
		"costs": [60, 200, 600, 2000],
		"stage_available": 1,
	},
	"learning_rate": {
		"name": "Learn Rate",
		"description": "Flat Compute multiplier per level",
		"max_level": 5,
		"costs": [50, 150, 450, 1200, 3500],
		"stage_available": 1,
	},
	"aug_chance": {
		"name": "Aug. Chance",
		"description": "Chance for bonus augmented data on label",
		"max_level": 5,
		"costs": [80, 200, 500, 1200, 3000],
		"stage_available": 1,
	},
	"aug_quality": {
		"name": "Aug. Quality",
		"description": "Augmented data worth more",
		"max_level": 3,
		"costs": [200, 600, 2000],
		"stage_available": 1,
	},
	"batch_label": {
		"name": "Batch Label",
		"description": "Labelling may auto-label same-class data nearby",
		"max_level": 5,
		"costs": [40, 120, 350, 900, 2500],
		"stage_available": 1,
	},
}


# --- Label Speed ---
func get_label_time() -> float:
	var base = stages[current_stage]["label_time"]
	var reduction = 1.0 - upgrade_levels["label_speed"] * 0.08
	return base * maxf(reduction, 0.2)


func get_processing_speed() -> float:
	return 200.0 + upgrade_levels["label_speed"] * 40.0


# --- Cursor Size ---
func get_cursor_radius() -> float:
	return 25.0 + upgrade_levels["cursor_size"] * 8.0


# --- Dataset Size ---
func get_dataset_size() -> int:
	return 10 + upgrade_levels["dataset_size"] * 5


# --- Augmentation ---
func get_aug_chance() -> float:
	return upgrade_levels["aug_chance"] * 0.15


func get_aug_quality_multiplier() -> float:
	return 1.0 + upgrade_levels["aug_quality"] * 0.5


# --- Data Quality ---
func get_data_quality_multiplier() -> float:
	return 1.0 + upgrade_levels["data_quality"] * 0.25


# --- Activation ---
func get_activation_multiplier() -> float:
	return 1.0 + upgrade_levels["activation_func"] * 0.3


# --- Learning Rate ---
func get_learning_rate_multiplier() -> float:
	return 1.0 + upgrade_levels["learning_rate"] * 0.2


# --- Batch Label ---
func get_batch_label_chance() -> float:
	return upgrade_levels["batch_label"] * 0.12


# --- Accuracy Scaling ---
func get_accuracy_per_point() -> float:
	var base = 0.5
	var node_bonus = upgrade_levels["nodes"] * 0.15
	var layer_bonus = upgrade_levels["layers"] * 0.1
	return base + node_bonus + layer_bonus


# --- Network ---
func get_output_count() -> int:
	return stages[current_stage]["output_nodes"]


func get_network_multiplier() -> int:
	return int(pow(neurons_per_layer, num_hidden_layers))


func get_compute_per_point() -> int:
	var base = stages[current_stage]["compute_per_point"]
	var network_mult = get_network_multiplier()
	var quality_mult = get_data_quality_multiplier()
	var activation_mult = get_activation_multiplier()
	var lr_mult = get_learning_rate_multiplier()
	return int(base * network_mult * quality_mult * activation_mult * lr_mult)


func get_stage() -> Dictionary:
	return stages[current_stage]


func get_training_duration() -> float:
	return 30.0


func get_accuracy_percent() -> float:
	var needed = stages[current_stage]["accuracy_needed"]
	if needed <= 0:
		return 100.0
	return clampf((accuracy / needed) * 100.0, 0.0, 100.0)


func add_compute(amount: float) -> void:
	compute += amount
	compute_changed.emit(compute)


func add_accuracy(amount: float) -> void:
	accuracy += amount
	var needed = stages[current_stage]["accuracy_needed"]
	if accuracy >= needed and current_stage < stages.size() - 1:
		accuracy -= needed
		current_stage += 1
		stage_changed.emit(current_stage)
	accuracy_changed.emit(accuracy)


func is_upgrade_visible(key: String) -> bool:
	var upgrade = upgrades[key]
	return current_stage >= upgrade["stage_available"]

func is_upgrade_unlocked(key: String) -> bool:
	if not is_upgrade_visible(key):
		return false
	var prereq = upgrade_prerequisites[key]
	if prereq == "":
		return true
	return upgrade_levels[prereq] > 0


func can_buy_upgrade(upgrade_key: String) -> bool:
	if not is_upgrade_visible(upgrade_key):
		return false
	if not is_upgrade_unlocked(upgrade_key):
		return false
	var level = upgrade_levels[upgrade_key]
	var upgrade = upgrades[upgrade_key]
	if level >= upgrade["max_level"]:
		return false
	return compute >= upgrade["costs"][level]


func buy_upgrade(upgrade_key: String) -> bool:
	if not can_buy_upgrade(upgrade_key):
		return false
	var level = upgrade_levels[upgrade_key]
	var cost = upgrades[upgrade_key]["costs"][level]
	compute -= cost
	upgrade_levels[upgrade_key] += 1

	if upgrade_key == "nodes":
		neurons_per_layer += 1
		network_changed.emit()
	elif upgrade_key == "layers":
		num_hidden_layers += 1
		network_changed.emit()

	compute_changed.emit(compute)
	return true


func get_upgrade_cost(upgrade_key: String) -> int:
	var level = upgrade_levels[upgrade_key]
	var upgrade = upgrades[upgrade_key]
	if level >= upgrade["max_level"]:
		return -1
	return upgrade["costs"][level]
