extends Node

# Signals
signal cash_changed(amount: float)
signal oxygen_changed(oxygen: float)
signal dive_state_changed(state: String)  # "surface" | "diving" | "underwater" | "resurfacing"

# Persistent state
var cash: float = 0.0
var dive_number: int = 0

# Per-dive state
var dive_cash: float = 0.0
var oxygen: float = 45.0
var dive_state: String = "surface"

# Upgrade levels
var upgrade_levels: Dictionary = {
	"oxygen": 0,
	"spears": 0,
	"spear_speed": 0,
	"reel_speed": 0,
	"hit_radius": 0,
	"lure": 0,
	"fish_value": 0,
	"trophy_room": 0,
}

# Upgrade definitions
var upgrades: Dictionary = {
	"oxygen": {
		"name": "Oxygen Tank",
		"description": "Longer dive time per tank level",
		"max_level": 5,
		"costs": [20, 50, 120, 300, 800],
	},
	"spears": {
		"name": "Spears",
		"description": "Carry more spears — fire multiple at once",
		"max_level": 4,
		"costs": [100, 300, 900, 2500],
	},
	"spear_speed": {
		"name": "Spear Speed",
		"description": "Spears fly faster",
		"max_level": 4,
		"costs": [30, 90, 250, 700],
	},
	"reel_speed": {
		"name": "Reel Speed",
		"description": "Reel fish in faster",
		"max_level": 4,
		"costs": [40, 120, 350, 900],
	},
	"hit_radius": {
		"name": "Spear Tip",
		"description": "Wider effective hit area",
		"max_level": 3,
		"costs": [50, 180, 500],
	},
	"lure": {
		"name": "Lure",
		"description": "Attract more fish per dive",
		"max_level": 4,
		"costs": [60, 180, 500, 1400],
	},
	"fish_value": {
		"name": "Market Price",
		"description": "All fish sell for more cash",
		"max_level": 5,
		"costs": [80, 220, 600, 1600, 4000],
	},
	"trophy_room": {
		"name": "Trophy Room",
		"description": "Keep a share of dive cash if oxygen runs out",
		"max_level": 3,
		"costs": [200, 600, 1800],
	},
}


# --- Derived getters ---

func get_oxygen_capacity() -> float:
	return 45.0 + upgrade_levels["oxygen"] * 10.0


func get_spear_count() -> int:
	return 1 + upgrade_levels["spears"]


func get_spear_speed() -> float:
	return 800.0 * (1.0 + upgrade_levels["spear_speed"] * 0.2)


func get_reel_speed() -> float:
	return 180.0 * (1.0 + upgrade_levels["reel_speed"] * 0.2)


func get_hit_radius_bonus() -> float:
	return upgrade_levels["hit_radius"] * 8.0


func get_spawn_rate_multiplier() -> float:
	return 1.0 + upgrade_levels["lure"] * 0.25


func get_fish_value_multiplier() -> float:
	return 1.0 + upgrade_levels["fish_value"] * 0.2


func get_trophy_room_percent() -> float:
	return upgrade_levels["trophy_room"] * 0.05


# --- Cash / oxygen mutators ---

func add_dive_cash(amount: float) -> void:
	dive_cash += amount
	cash_changed.emit(cash + dive_cash)


func set_oxygen(value: float) -> void:
	oxygen = clampf(value, 0.0, get_oxygen_capacity())
	oxygen_changed.emit(oxygen)


func start_dive() -> void:
	dive_number += 1
	dive_cash = 0.0
	set_oxygen(get_oxygen_capacity())
	set_dive_state("diving")


func finish_dive(lost_oxygen: bool) -> void:
	# Trophy Room: if oxygen ran out, keep a share of dive cash
	var kept: float = dive_cash
	if lost_oxygen:
		kept = dive_cash * get_trophy_room_percent()
	cash += kept
	dive_cash = 0.0
	cash_changed.emit(cash)
	set_dive_state("surface")


func set_dive_state(state: String) -> void:
	dive_state = state
	dive_state_changed.emit(state)


# --- Shop ---

func can_buy_upgrade(key: String) -> bool:
	var level = upgrade_levels[key]
	var upgrade = upgrades[key]
	if level >= upgrade["max_level"]:
		return false
	return cash >= upgrade["costs"][level]


func buy_upgrade(key: String) -> bool:
	if not can_buy_upgrade(key):
		return false
	var level = upgrade_levels[key]
	cash -= upgrades[key]["costs"][level]
	upgrade_levels[key] += 1
	cash_changed.emit(cash)
	return true


func get_upgrade_cost(key: String) -> int:
	var level = upgrade_levels[key]
	var upgrade = upgrades[key]
	if level >= upgrade["max_level"]:
		return -1
	return upgrade["costs"][level]
