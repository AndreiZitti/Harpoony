extends Node


func _ready() -> void:
	for key in upgrades.keys():
		assert(key in upgrade_levels, "upgrade_levels missing key: %s" % key)
	_load_zones()
	_begin_day()


enum DiveState { SURFACE, DIVING, UNDERWATER, RESURFACING }

# Signals
signal cash_changed(amount: float)
signal oxygen_changed(oxygen: float)
signal dive_state_changed(state: int)  # DiveState
signal day_changed(day: int)
signal tanks_changed(remaining: int, total: int)
signal zone_changed(zone: ZoneConfig)
signal zone_unlocked(idx: int)

# Persistent state
var cash: float = 0.0
var day_number: int = 1
var cheat_mode: bool = false
var zones: Array[ZoneConfig] = []
var selected_zone_index: int = 0
var unlocked_zone_index: int = 0  # highest unlocked index (0..zones.size()-1)

# Per-day state
var dive_number_today: int = 0
var tanks_remaining: int = 0
var day_cash: float = 0.0

# Per-dive state
var dive_cash: float = 0.0
var oxygen: float = 10.0
var dive_state: int = DiveState.SURFACE

# Upgrade levels (leveled, multi-purchase)
var upgrade_levels: Dictionary = {
	"oxygen": 0,
	"tanks": 0,
	"spears": 0,
	"spear_speed": 0,
	"reel_speed": 0,
	"hit_radius": 0,
	"fish_value": 0,
}

# Upgrade definitions
var upgrades: Dictionary = {
	"oxygen": {
		"name": "Tank Capacity",
		"description": "+2s dive time per level (base 10s)",
		"max_level": 10,
		"costs": [20, 40, 80, 150, 300, 500, 800, 1200, 2000, 3500],
	},
	"tanks": {
		"name": "Extra Tank",
		"description": "+1 tank per day (more dives)",
		"max_level": 4,  # 2 base → 6 max
		"costs": [100, 300, 800, 2000],
	},
	"spears": {
		"name": "Extra Spear",
		"description": "Carry more spears per dive",
		"max_level": 2,  # 1 base → 3 max
		"costs": [120, 500],
	},
	"spear_speed": {
		"name": "Spear Speed",
		"description": "+10% spear travel speed",
		"max_level": 4,
		"costs": [30, 90, 250, 700],
	},
	"reel_speed": {
		"name": "Reel Speed",
		"description": "+10% reel-in speed",
		"max_level": 4,
		"costs": [40, 120, 350, 900],
	},
	"hit_radius": {
		"name": "Spear Tip",
		"description": "Wider effective hit area",
		"max_level": 3,
		"costs": [50, 180, 500],
	},
	"fish_value": {
		"name": "Market Price",
		"description": "+10% cash per fish",
		"max_level": 5,
		"costs": [80, 220, 600, 1600, 4000],
	},
}

# Zones loaded from data/zones/*.tres
const ZONE_PATHS = [
	"res://data/zones/01_reef.tres",
	"res://data/zones/02_kelp.tres",
	"res://data/zones/03_twilight.tres",
	"res://data/zones/04_midnight.tres",
	"res://data/zones/05_abyss.tres",
	"res://data/zones/06_trench.tres",
]

# Day/night palettes — surface view only
const PHASE_PALETTES = {
	"morning": {
		"sky_top": Color(0.4, 0.6, 0.85),
		"sky_bottom": Color(0.1, 0.3, 0.55),
		"water_top": Color(0.08, 0.2, 0.4),
		"water_bottom": Color(0.02, 0.05, 0.12),
		"fish_tint": Color(1, 1, 1),
	},
	"afternoon": {
		"sky_top": Color(0.95, 0.55, 0.3),
		"sky_bottom": Color(0.5, 0.2, 0.3),
		"water_top": Color(0.15, 0.15, 0.3),
		"water_bottom": Color(0.05, 0.05, 0.15),
		"fish_tint": Color(1.0, 0.85, 0.7),
	},
	"night": {
		"sky_top": Color(0.05, 0.05, 0.15),
		"sky_bottom": Color(0.02, 0.02, 0.08),
		"water_top": Color(0.01, 0.02, 0.08),
		"water_bottom": Color(0.0, 0.0, 0.02),
		"fish_tint": Color(0.6, 0.7, 0.9),
	},
}

# --- Derived getters ---

func get_oxygen_capacity() -> float:
	return 10.0 + upgrade_levels["oxygen"] * 2.0


func get_tank_count() -> int:
	return 2 + upgrade_levels["tanks"]


func get_spear_count() -> int:
	return 1 + upgrade_levels["spears"]


func get_spear_speed() -> float:
	return 800.0 * (1.0 + upgrade_levels["spear_speed"] * 0.1)


func get_reel_speed() -> float:
	return 180.0 * (1.0 + upgrade_levels["reel_speed"] * 0.1)


func get_hit_radius_bonus() -> float:
	return upgrade_levels["hit_radius"] * 8.0


func get_fish_value_multiplier() -> float:
	return 1.0 + upgrade_levels["fish_value"] * 0.1


# --- Phase (time of day) ---

func _phase_for_dive(n: int) -> String:
	if n <= 3:
		return "morning"
	elif n <= 5:
		return "afternoon"
	else:
		return "night"


func get_current_phase() -> String:
	# Surface: phase of upcoming dive. Underwater: phase of current dive.
	var n = dive_number_today
	if dive_state == DiveState.SURFACE:
		n = dive_number_today + 1
	return _phase_for_dive(n)


func get_palette() -> Dictionary:
	return PHASE_PALETTES[get_current_phase()]


func get_fish_tint() -> Color:
	return get_palette()["fish_tint"]


# --- Zones ---

func _load_zones() -> void:
	zones.clear()
	for path in ZONE_PATHS:
		var z: ZoneConfig = load(path)
		assert(z != null, "Failed to load zone: %s" % path)
		zones.append(z)


func get_current_zone() -> ZoneConfig:
	return zones[selected_zone_index]


func get_zone_spawn_weights() -> Dictionary:
	return get_current_zone().spawn_weights


func can_select_zone(idx: int) -> bool:
	return idx >= 0 and idx <= unlocked_zone_index and idx < zones.size()


func select_zone(idx: int) -> void:
	if can_select_zone(idx) and idx != selected_zone_index:
		selected_zone_index = idx
		zone_changed.emit(get_current_zone())


func can_unlock_next_zone() -> bool:
	var next = unlocked_zone_index + 1
	if next >= zones.size():
		return false
	if cheat_mode:
		return true
	return cash >= zones[next].unlock_cost


func unlock_next_zone() -> bool:
	if not can_unlock_next_zone():
		return false
	unlocked_zone_index += 1
	if not cheat_mode:
		cash -= zones[unlocked_zone_index].unlock_cost
	cash_changed.emit(cash)
	zone_unlocked.emit(unlocked_zone_index)
	return true


func get_next_zone_cost() -> int:
	var next = unlocked_zone_index + 1
	if next >= zones.size():
		return -1
	return zones[next].unlock_cost


# --- Cash / oxygen mutators ---

func add_dive_cash(amount: float) -> void:
	dive_cash += amount
	cash_changed.emit(cash + dive_cash)


func set_oxygen(value: float) -> void:
	oxygen = clampf(value, 0.0, get_oxygen_capacity())
	oxygen_changed.emit(oxygen)


func set_dive_state(state: int) -> void:
	dive_state = state
	dive_state_changed.emit(state)


# --- Day / dive lifecycle ---

func _begin_day() -> void:
	tanks_remaining = get_tank_count()
	dive_number_today = 0
	day_cash = 0.0
	set_oxygen(get_oxygen_capacity())
	set_dive_state(DiveState.SURFACE)
	tanks_changed.emit(tanks_remaining, get_tank_count())
	day_changed.emit(day_number)


func advance_to_next_day() -> void:
	day_number += 1
	_begin_day()


func start_dive() -> void:
	if tanks_remaining <= 0:
		return
	dive_number_today += 1
	tanks_remaining -= 1
	dive_cash = 0.0
	set_oxygen(get_oxygen_capacity())
	set_dive_state(DiveState.DIVING)
	tanks_changed.emit(tanks_remaining, get_tank_count())


func finish_dive() -> void:
	cash += dive_cash
	day_cash += dive_cash
	dive_cash = 0.0
	cash_changed.emit(cash)
	set_dive_state(DiveState.SURFACE)


func is_day_over() -> bool:
	return tanks_remaining <= 0


# --- Shop ---

func can_buy_upgrade(key: String) -> bool:
	var level = upgrade_levels[key]
	var upgrade = upgrades[key]
	if level >= upgrade["max_level"]:
		return false
	if cheat_mode:
		return true
	return cash >= upgrade["costs"][level]


func buy_upgrade(key: String) -> bool:
	if not can_buy_upgrade(key):
		return false
	var level = upgrade_levels[key]
	if not cheat_mode:
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


# --- Cheat mode ---

func toggle_cheat_mode() -> void:
	cheat_mode = not cheat_mode
	cash_changed.emit(cash)
