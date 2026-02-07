extends Node

# Signals
signal cash_changed(amount: float)
signal stage_changed(stage_index: int)
signal accuracy_changed(accuracy: float)
signal network_changed()

# Game state
var cash: float = 0.0
var current_stage: int = 0
var accuracy: float = 0.0
var training_round: int = 0
var is_epoch_active: bool = false
const COMBO_MULTIPLIER: float = 2.0

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
	"training_time": 0,
	"transfer_learning": 0,
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
	"training_time": "",
	"transfer_learning": "",
}

# Stage definitions
var stages: Array = [
	{
		"name": "Binary",
		"label_time": 2.0,
		"cash_per_point": 1,
		"accuracy_needed": 50,
		"output_nodes": 2,
		"color": Color(0.3, 0.8, 1.0),
	},
	{
		"name": "Numbers",
		"label_time": 1.5,
		"cash_per_point": 5,
		"accuracy_needed": 120,
		"output_nodes": 10,
		"color": Color(0.3, 1.0, 0.5),
	},
	{
		"name": "Math",
		"label_time": 1.0,
		"cash_per_point": 25,
		"accuracy_needed": 300,
		"output_nodes": 3,
		"color": Color(0.7, 0.3, 1.0),
	},
	{
		"name": "Faces",
		"label_time": 2.0,
		"cash_per_point": 150,
		"accuracy_needed": 600,
		"output_nodes": 10,
		"color": Color(1.0, 0.4, 0.3),
	},
	{
		"name": "AGI",
		"label_time": 3.0,
		"cash_per_point": 1000,
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
		"description": "Each labeled point earns more cash",
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
		"description": "Activation functions multiply cash output",
		"max_level": 4,
		"costs": [60, 200, 600, 2000],
		"stage_available": 1,
	},
	"learning_rate": {
		"name": "Learn Rate",
		"description": "Flat cash multiplier per level",
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
	"training_time": {
		"name": "Train Time",
		"description": "Extend training round duration",
		"max_level": 4,
		"costs": [60, 180, 500, 1500],
		"stage_available": 1,
	},
	"transfer_learning": {
		"name": "Transfer",
		"description": "Carry over cash when advancing to next stage",
		"max_level": 3,
		"costs": [300, 900, 3000],
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


func get_cash_per_point() -> int:
	var base = stages[current_stage]["cash_per_point"]
	var network_mult = get_network_multiplier()
	var quality_mult = get_data_quality_multiplier()
	var activation_mult = get_activation_multiplier()
	var lr_mult = get_learning_rate_multiplier()
	return int(base * network_mult * quality_mult * activation_mult * lr_mult)


func get_combo_cash(individual_count: int) -> int:
	var per_point = get_cash_per_point()
	return int(per_point * individual_count * COMBO_MULTIPLIER)


func get_stage() -> Dictionary:
	return stages[current_stage]


func get_training_duration() -> float:
	return 30.0 + upgrade_levels["training_time"] * 5.0


func get_transfer_learning_percent() -> float:
	return upgrade_levels["transfer_learning"] * 0.10


func get_accuracy_percent() -> float:
	var needed = stages[current_stage]["accuracy_needed"]
	if needed <= 0:
		return 100.0
	return clampf((accuracy / needed) * 100.0, 0.0, 100.0)


func add_cash(amount: float) -> void:
	cash += amount
	cash_changed.emit(cash)


func add_accuracy(amount: float) -> void:
	accuracy += amount
	var needed = stages[current_stage]["accuracy_needed"]
	if accuracy >= needed and current_stage < stages.size() - 1:
		accuracy -= needed
		# Transfer Learning: carry over a % of cash to the next stage
		var keep = cash * get_transfer_learning_percent()
		cash = keep
		cash_changed.emit(cash)
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
	return cash >= upgrade["costs"][level]


func buy_upgrade(upgrade_key: String) -> bool:
	if not can_buy_upgrade(upgrade_key):
		return false
	var level = upgrade_levels[upgrade_key]
	var cost = upgrades[upgrade_key]["costs"][level]
	cash -= cost
	upgrade_levels[upgrade_key] += 1

	if upgrade_key == "nodes":
		neurons_per_layer += 1
		network_changed.emit()
	elif upgrade_key == "layers":
		num_hidden_layers += 1
		network_changed.emit()

	cash_changed.emit(cash)
	return true


func get_upgrade_cost(upgrade_key: String) -> int:
	var level = upgrade_levels[upgrade_key]
	var upgrade = upgrades[upgrade_key]
	if level >= upgrade["max_level"]:
		return -1
	return upgrade["costs"][level]


func get_effect_preview(key: String) -> Array:
	var level = upgrade_levels[key]
	var max_level = upgrades[key]["max_level"]
	var is_maxed = level >= max_level

	match key:
		"nodes":
			var cur = neurons_per_layer
			if is_maxed:
				return ["Neurons/layer: %d" % cur]
			return ["Neurons/layer: %d → %d" % [cur, cur + 1]]
		"layers":
			var cur = num_hidden_layers
			if is_maxed:
				return ["Hidden layers: %d" % cur]
			return ["Hidden layers: %d → %d" % [cur, cur + 1]]
		"dataset_size":
			var cur = get_dataset_size()
			if is_maxed:
				return ["Points/round: %d" % cur]
			return ["Points/round: %d → %d" % [cur, cur + 5]]
		"data_quality":
			var cur = get_data_quality_multiplier()
			if is_maxed:
				return ["Quality mult: x%.2f" % cur]
			var nxt = 1.0 + (level + 1) * 0.25
			return ["Quality mult: x%.2f → x%.2f" % [cur, nxt]]
		"cursor_size":
			var cur = get_cursor_radius()
			if is_maxed:
				return ["Cursor radius: %dpx" % int(cur)]
			var nxt = 25.0 + (level + 1) * 8.0
			return ["Cursor radius: %dpx → %dpx" % [int(cur), int(nxt)]]
		"label_speed":
			var cur_time = get_label_time()
			if is_maxed:
				return ["Label time: %.1fs" % cur_time]
			var base = stages[current_stage]["label_time"]
			var nxt_reduction = 1.0 - (level + 1) * 0.08
			var nxt_time = base * maxf(nxt_reduction, 0.2)
			return ["Label time: %.1fs → %.1fs" % [cur_time, nxt_time]]
		"activation_func":
			var cur = get_activation_multiplier()
			if is_maxed:
				return ["Activation mult: x%.1f" % cur]
			var nxt = 1.0 + (level + 1) * 0.3
			return ["Activation mult: x%.1f → x%.1f" % [cur, nxt]]
		"learning_rate":
			var cur = get_learning_rate_multiplier()
			if is_maxed:
				return ["LR mult: x%.1f" % cur]
			var nxt = 1.0 + (level + 1) * 0.2
			return ["LR mult: x%.1f → x%.1f" % [cur, nxt]]
		"aug_chance":
			var cur = get_aug_chance() * 100.0
			if is_maxed:
				return ["Aug chance: %d%%" % int(cur)]
			var nxt = (level + 1) * 15.0
			return ["Aug chance: %d%% → %d%%" % [int(cur), int(nxt)]]
		"aug_quality":
			var cur = get_aug_quality_multiplier()
			if is_maxed:
				return ["Aug mult: x%.1f" % cur]
			var nxt = 1.0 + (level + 1) * 0.5
			return ["Aug mult: x%.1f → x%.1f" % [cur, nxt]]
		"batch_label":
			var cur = get_batch_label_chance() * 100.0
			if is_maxed:
				return ["Batch chance: %d%%" % int(cur)]
			var nxt = (level + 1) * 12.0
			return ["Batch chance: %d%% → %d%%" % [int(cur), int(nxt)]]
		"training_time":
			var cur = get_training_duration()
			if is_maxed:
				return ["Round time: %ds" % int(cur)]
			var nxt = 30.0 + (level + 1) * 5.0
			return ["Round time: %ds → %ds" % [int(cur), int(nxt)]]
		"transfer_learning":
			var cur = get_transfer_learning_percent() * 100.0
			if is_maxed:
				return ["Cash kept: %d%%" % int(cur)]
			var nxt = (level + 1) * 10.0
			return ["Cash kept: %d%% → %d%%" % [int(cur), int(nxt)]]
	return []