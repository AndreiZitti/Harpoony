extends Node


func _ready() -> void:
	for key in upgrades.keys():
		assert(key in upgrade_levels, "upgrade_levels missing key: %s" % key)
	_load_zones()
	_load_spear_types()
	set_oxygen(get_oxygen_capacity())
	set_dive_state(DiveState.SURFACE)


enum DiveState { SURFACE, DIVING, UNDERWATER, RESURFACING }

# Signals
signal cash_changed(amount: float)
signal oxygen_changed(oxygen: float)
signal dive_state_changed(state: int)  # DiveState
signal zone_changed(zone: ZoneConfig)
signal zone_unlocked(idx: int)
signal spear_type_unlocked(id: StringName)
signal spear_upgrade_changed(id: StringName, key: String, level: int)
signal bag_loadout_changed

# Persistent state
var cash: float = 0.0
var cheat_mode: bool = false
var zones: Array[ZoneConfig] = []
var selected_zone_index: int = 0
var unlocked_zone_index: int = 0  # highest unlocked index (0..zones.size()-1)

# Spear types
var spear_types: Array[SpearType] = []
var unlocked_spear_types: Array[StringName] = [&"normal"]
var spear_upgrade_levels: Dictionary = {}      # id -> { upgrade_key: level }
var bag_loadout: Dictionary = {}               # id -> int (in bag for next dive)
var bag_queue: Array[StringName] = []          # built at start_dive
var bag_index: int = 0

# Per-dive state
var dive_cash: float = 0.0
var oxygen: float = 10.0
var dive_state: int = DiveState.SURFACE
var active_spear_count: int = 0  # spears currently in flight or reeling
var dive_shots_fired: int = 0
var dive_fish_caught: int = 0
# Snapshotted at end-of-dive so the surface summary can read it.
var last_dive_cash: int = 0
var last_dive_shots: int = 0
var last_dive_fish: int = 0

# Upgrade levels (leveled, multi-purchase)
var upgrade_levels: Dictionary = {
	"oxygen": 0,
	"spear_bag": 0,
}

# Upgrade definitions
var upgrades: Dictionary = {
	"oxygen": {
		"name": "Tank Capacity",
		"description": "+2s dive time per level (base 10s)",
		"max_level": 10,
		"costs": [20, 40, 80, 150, 300, 500, 800, 1200, 2000, 3500],
	},
	"spear_bag": {
		"name": "Spear Bag",
		"description": "+2 bag capacity per level (base 3)",
		"max_level": 5,  # 3 base → 13 max
		"costs": [40, 100, 250, 700, 1800],
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

# Spear types loaded from data/spears/*.tres
const SPEAR_TYPE_PATHS = [
	"res://data/spears/normal.tres",
	"res://data/spears/net.tres",
	"res://data/spears/heavy.tres",
]

# Surface palette — single fixed look (day/night phases removed).
const SURFACE_PALETTE := {
	"sky_top": Color(0.4, 0.6, 0.85),
	"sky_bottom": Color(0.1, 0.3, 0.55),
	"water_top": Color(0.08, 0.2, 0.4),
	"water_bottom": Color(0.02, 0.05, 0.12),
}

# --- Derived getters ---

func get_oxygen_capacity() -> float:
	return 10.0 + upgrade_levels["oxygen"] * 2.0


func get_spear_count() -> int:
	return 1


func get_bag_capacity() -> int:
	return 3 + upgrade_levels["spear_bag"] * 2


# Base values used when applying per-type multipliers.
const BASE_SPEAR_SPEED := 800.0
const BASE_REEL_SPEED := 320.0


# Effective travel speed for the given spear type.
func get_effective_spear_speed(id: StringName) -> float:
	var mult := get_effective_spear_stat(id, "speed_mult")
	if mult <= 0.0:
		mult = 1.0
	return BASE_SPEAR_SPEED * mult


# Effective reel speed for the given spear type.
func get_effective_reel_speed(id: StringName) -> float:
	var mult := get_effective_spear_stat(id, "reel_speed_mult")
	if mult <= 0.0:
		mult = 1.0
	return BASE_REEL_SPEED * mult


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


# Resolve a hit's final cash value. Returned shape kept for caller compatibility.
func register_hit(base_value: int) -> Dictionary:
	return {"value": base_value, "crit": false, "streak": 0}


# Kept as a no-op for caller compatibility — nothing currently depends on misses.
func register_miss() -> void:
	pass


# --- Spear types ---

func _load_spear_types() -> void:
	spear_types.clear()
	for path in SPEAR_TYPE_PATHS:
		var t: SpearType = load(path)
		assert(t != null, "Failed to load spear type: %s" % path)
		spear_types.append(t)
		if not spear_upgrade_levels.has(t.id):
			var levels := {}
			for k in t.upgrades.keys():
				levels[k] = 0
			spear_upgrade_levels[t.id] = levels
	bag_loadout = {}
	_auto_fill_bag()


func get_spear_type(id: StringName) -> SpearType:
	for t in spear_types:
		if t.id == id:
			return t
	return null


func is_spear_type_unlocked(id: StringName) -> bool:
	return id in unlocked_spear_types


func can_unlock_spear_type(id: StringName) -> bool:
	if is_spear_type_unlocked(id):
		return false
	var t := get_spear_type(id)
	if t == null:
		return false
	if cheat_mode:
		return true
	return cash >= t.unlock_cost


func unlock_spear_type(id: StringName) -> bool:
	if not can_unlock_spear_type(id):
		return false
	var t := get_spear_type(id)
	if not cheat_mode:
		cash -= t.unlock_cost
	unlocked_spear_types.append(id)
	cash_changed.emit(cash)
	spear_type_unlocked.emit(id)
	return true


func get_spear_upgrade_level(id: StringName, key: String) -> int:
	var levels: Dictionary = spear_upgrade_levels.get(id, {})
	return int(levels.get(key, 0))


func can_buy_spear_upgrade(id: StringName, key: String) -> bool:
	var t := get_spear_type(id)
	if t == null or not t.upgrades.has(key):
		return false
	var def: Dictionary = t.upgrades[key]
	var level := get_spear_upgrade_level(id, key)
	if level >= int(def["max_level"]):
		return false
	if cheat_mode:
		return true
	return cash >= int((def["costs"] as Array)[level])


func buy_spear_upgrade(id: StringName, key: String) -> bool:
	if not can_buy_spear_upgrade(id, key):
		return false
	var t := get_spear_type(id)
	var def: Dictionary = t.upgrades[key]
	var level := get_spear_upgrade_level(id, key)
	if not cheat_mode:
		cash -= int((def["costs"] as Array)[level])
	spear_upgrade_levels[id][key] = level + 1
	cash_changed.emit(cash)
	spear_upgrade_changed.emit(id, key, level + 1)
	return true


# Returns the value of a SpearType property after applying that type's leveled upgrades.
func get_effective_spear_stat(id: StringName, field: String) -> float:
	var t := get_spear_type(id)
	if t == null:
		return 0.0
	var base: float = float(t.get(field))
	for key in t.upgrades.keys():
		var def: Dictionary = t.upgrades[key]
		if def.get("field", "") != field:
			continue
		var level := get_spear_upgrade_level(id, key)
		base += level * float(def.get("step", 0.0))
	return base


# --- Bag ---

func _bag_loaded_total() -> int:
	var n := 0
	for k in bag_loadout.keys():
		n += int(bag_loadout[k])
	return n


func get_bag_loaded_count() -> int:
	return _bag_loaded_total()


func can_increment_bag(id: StringName) -> bool:
	if not is_spear_type_unlocked(id):
		return false
	if _bag_loaded_total() >= get_bag_capacity():
		return false
	return true


func increment_bag(id: StringName) -> bool:
	if not can_increment_bag(id):
		return false
	bag_loadout[id] = int(bag_loadout.get(id, 0)) + 1
	bag_loadout_changed.emit()
	return true


func decrement_bag(id: StringName) -> bool:
	var current: int = int(bag_loadout.get(id, 0))
	if current <= 0:
		return false
	bag_loadout[id] = current - 1
	bag_loadout_changed.emit()
	return true


func clear_bag_loadout() -> void:
	bag_loadout.clear()
	bag_loadout_changed.emit()


# Greedy fill: keeps existing selections, then tops up the first unlocked type until capacity.
func _auto_fill_bag() -> void:
	var cap := get_bag_capacity()
	if _bag_loaded_total() >= cap:
		return
	for t in spear_types:
		if not is_spear_type_unlocked(t.id):
			continue
		var current: int = int(bag_loadout.get(t.id, 0))
		while _bag_loaded_total() < cap:
			current += 1
			bag_loadout[t.id] = current
		break
	bag_loadout_changed.emit()


func auto_fill_bag() -> void:
	_auto_fill_bag()


# Re-clamps bag total against current capacity (after a capacity downgrade — rare).
func clamp_bag_loadout() -> void:
	var changed := false
	var cap := get_bag_capacity()
	while _bag_loaded_total() > cap:
		var biggest: StringName = &""
		var biggest_n := 0
		for id in bag_loadout.keys():
			var v: int = int(bag_loadout[id])
			if v > biggest_n:
				biggest_n = v
				biggest = id
		if biggest_n <= 0:
			break
		bag_loadout[biggest] = biggest_n - 1
		changed = true
	if changed:
		bag_loadout_changed.emit()


# Builds + shuffles the firing queue from bag_loadout. Falls back to one Normal if empty.
func _build_bag_queue() -> void:
	bag_queue.clear()
	for id in bag_loadout.keys():
		var n: int = int(bag_loadout[id])
		for _i in n:
			bag_queue.append(id)
	if bag_queue.is_empty():
		bag_queue.append(&"normal")
	bag_queue.shuffle()
	bag_index = 0


# Returns the next spear type id, advancing the queue. Returns &"" if the round
# is exhausted; caller must wait for spears to return + a reshuffle before firing again.
func draw_next_spear_type() -> StringName:
	if bag_queue.is_empty():
		_build_bag_queue()
	if bag_index >= bag_queue.size():
		return &""
	var id: StringName = bag_queue[bag_index]
	bag_index += 1
	return id


# True when the current shuffled round is fully drawn — fire should be blocked.
func bag_is_exhausted() -> bool:
	return not bag_queue.is_empty() and bag_index >= bag_queue.size()


# Reshuffles only if the round is drained AND no spears are still in flight.
# Spears call this on arrive; the last one back triggers the new round.
func reshuffle_if_round_complete() -> void:
	if bag_is_exhausted() and active_spear_count <= 0:
		bag_queue.shuffle()
		bag_index = 0


# Legacy alias kept for any old callers — equivalent to round-complete check.
func reshuffle_if_exhausted() -> void:
	reshuffle_if_round_complete()


func note_spear_fired() -> void:
	active_spear_count += 1
	dive_shots_fired += 1


func note_spear_returned() -> void:
	active_spear_count = max(0, active_spear_count - 1)
	reshuffle_if_round_complete()


func note_fish_caught() -> void:
	dive_fish_caught += 1


# Returns the remaining spear ids in the current round (no wrap). Empty when the
# round is exhausted — HUD shows that as a dimmed preview waiting for reshuffle.
func peek_bag_queue(count: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if bag_queue.is_empty():
		# Surface preview: pull from loadout in iteration order.
		if bag_loadout.is_empty():
			return out
		for id in bag_loadout.keys():
			var n: int = int(bag_loadout[id])
			for _i in n:
				out.append(id)
				if out.size() >= count:
					return out
		return out
	var i := bag_index
	while i < bag_queue.size() and out.size() < count:
		out.append(bag_queue[i])
		i += 1
	return out


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


# --- Dive lifecycle ---

func start_dive() -> void:
	dive_cash = 0.0
	active_spear_count = 0
	dive_shots_fired = 0
	dive_fish_caught = 0
	clamp_bag_loadout()
	_build_bag_queue()
	set_oxygen(get_oxygen_capacity())
	set_dive_state(DiveState.DIVING)


func finish_dive() -> void:
	# Snapshot for the surface summary toast before clearing per-dive fields.
	last_dive_cash = int(dive_cash)
	last_dive_shots = dive_shots_fired
	last_dive_fish = dive_fish_caught
	cash += dive_cash
	dive_cash = 0.0
	dive_shots_fired = 0
	dive_fish_caught = 0
	bag_queue.clear()
	bag_index = 0
	active_spear_count = 0
	cash_changed.emit(cash)
	set_dive_state(DiveState.SURFACE)


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
