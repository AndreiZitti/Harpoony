extends Node

const DEV_TUNING_PATH := "user://dev_tuning.json"
const RUN_HISTORY_PATH := "user://run_history.json"
const RUN_HISTORY_MAX := 200  # cap so the file doesn't grow forever
const DISCOVERED_SPECIES_PATH := "user://discovered_species.json"
var _dev_save_timer: Timer = null


func _ready() -> void:
	for key in upgrades.keys():
		assert(key in upgrade_levels, "upgrade_levels missing key: %s" % key)
	_load_zones()
	_load_spear_types()
	_load_species()
	load_run_history()
	load_discovered_species()
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
signal whitewhale_caught_signal
signal dive_number_changed(n: int)
signal species_discovered(id: StringName)
# Reload state — fired on transitions only. HUD reads reload_remaining /
# reload_total each frame for the progress visual.
signal reload_state_changed(reloading: bool)

# Persistent state
var cash: float = 0.0
var cheat_mode: bool = false
var whitewhale_caught: bool = false

# --- Dev-mode tunables (set via DevPanel; safe defaults preserve old behavior) ---
var dev_infinite_oxygen: bool = false       # main.gd's oxygen tick respects this
var dev_skip_shop: bool = false              # main.gd's _enter_surface re-dives instead
var oxygen_capacity_override: float = -1.0   # ≥0 overrides level-based capacity
var bag_capacity_override: int = -1          # ≥0 overrides level-based bag size
var dive_travel_duration: float = 1.5        # was a const in main.gd; tunable here
# Multiplier on the fish_spawner interval. >1.0 = faster spawns (more fish),
# <1.0 = slower. Reserved as the hookup point for a future "Reef Density"
# style upgrade — for now it stays at 1.0 by default.
var spawn_rate_multiplier: float = 1.0

# Per-species runtime overrides written by the dev panel Fish tab.
# Keys: species name (String). Values: { field_name: value } dict.
# fish.gd::setup applies these after its species match block, so future spawns
# pick them up automatically. The dev panel also pushes changes to live fish
# already in the scene so tweaks feel immediate.
var fish_stat_overrides: Dictionary = {}

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
# Reload (reshuffle delay between rounds) — base 0.25s per spear in the bag,
# reduced by the Quick Hands boat upgrade. While `reloading` is true the bag
# rejects new draws so firing is gated until the round is ready again.
const RELOAD_PER_SPEAR := 0.5
var reloading: bool = false
var reload_remaining: float = 0.0
var reload_total: float = 0.0
var dive_shots_fired: int = 0
var dive_fish_caught: int = 0
# Per-dive breakdowns for the summary screen.
var dive_shots_by_spear: Dictionary = {}     # spear_id (String) -> int
var dive_hits_by_spear: Dictionary = {}      # spear_id (String) -> int (fish landed)
var dive_catches_by_fish: Dictionary = {}    # species (String) -> { count: int, value: int }
var dive_zone_id: String = ""
var dive_start_msec: int = 0
# Seismic Roar (Heavy keystone): when a Heavy hit fires while the keystone is
# owned, all defended fish on screen lose their defenses for SEISMIC_DURATION
# seconds. Fish.deflects_spear() consults is_seismic_active() before applying
# any defense. Reset to 0 at dive start.
const SEISMIC_DURATION := 10.0
var seismic_roar_until_msec: int = 0
# Snapshotted at end-of-dive so the surface summary can read it.
var last_dive_cash: int = 0
var last_dive_shots: int = 0
var last_dive_fish: int = 0
var last_dive_shots_by_spear: Dictionary = {}
var last_dive_hits_by_spear: Dictionary = {}
var last_dive_catches_by_fish: Dictionary = {}
var last_dive_zone_id: String = ""
var last_dive_duration: float = 0.0
# Persistent run history. Each entry is a frozen copy of the last_dive_* fields.
var run_history: Array = []
# Campaign progress: increments at the start of each dive (soft target = 100).
var dive_number: int = 0

# Upgrade levels (leveled, multi-purchase)
var upgrade_levels: Dictionary = {
	"oxygen": 0,
	"spear_bag": 0,
	"reload_speed": 0,
}

# Upgrade definitions
var upgrades: Dictionary = {
	"oxygen": {
		"name": "Tank Capacity",
		"description": "+3s dive time per level (base 30s)",
		"max_level": 10,
		"costs": [40, 80, 160, 320, 600, 1000, 1600, 2400, 3500, 5000],
	},
	"spear_bag": {
		"name": "Spear Bag",
		"description": "+2 bag capacity per level (base 3)",
		"max_level": 5,  # 3 base → 13 max
		"costs": [40, 100, 250, 700, 1800],
	},
	"reload_speed": {
		"name": "Quick Hands",
		"description": "+25% faster spear reload per level (base 0.5s/spear)",
		"max_level": 4,  # 1.0× → 2.0× speed (50% reload time)
		"costs": [80, 220, 550, 1300],
	},
}

# Zones loaded from data/zones/*.tres
const ZONE_PATHS = [
	"res://data/zones/01_reef.tres",
	"res://data/zones/02_kelp.tres",
	"res://data/zones/03_open_blue.tres",
	"res://data/zones/04_abyss.tres",
]

# Spear types loaded from data/spears/*.tres
const SPEAR_TYPE_PATHS = [
	"res://data/spears/normal.tres",
	"res://data/spears/net.tres",
	"res://data/spears/heavy.tres",
]

# Species data loaded from data/species/*.tres — single source of truth for
# display name, description, recommended spear, and the bestiary registry.
const SPECIES_PATHS = [
	"res://data/species/sardine.tres",
	"res://data/species/grouper.tres",
	"res://data/species/tuna.tres",
	"res://data/species/pufferfish.tres",
	"res://data/species/mahimahi.tres",
	"res://data/species/squid.tres",
	"res://data/species/lanternfish.tres",
	"res://data/species/anglerfish.tres",
	"res://data/species/triggerfish.tres",
	"res://data/species/marlin.tres",
	"res://data/species/whitewhale.tres",
	"res://data/species/jellyfish.tres",
	"res://data/species/bonito.tres",
	"res://data/species/blockfish.tres",
]
var species_list: Array[SpeciesData] = []
var species_by_id: Dictionary = {}  # StringName -> SpeciesData
# Discovered species map: keys are species id (String), value = first-caught
# dive number. Persists across sessions; cleared by Reset Session.
var discovered_species: Dictionary = {}

# Surface palette — single fixed look (day/night phases removed).
const SURFACE_PALETTE := {
	"sky_top": Color(0.4, 0.6, 0.85),
	"sky_bottom": Color(0.1, 0.3, 0.55),
	"water_top": Color(0.08, 0.2, 0.4),
	"water_bottom": Color(0.02, 0.05, 0.12),
}

# --- Derived getters ---

func get_oxygen_capacity() -> float:
	if oxygen_capacity_override >= 0.0:
		return oxygen_capacity_override
	return 30.0 + upgrade_levels["oxygen"] * 3.0


func get_spear_count() -> int:
	return 1


func get_bag_capacity() -> int:
	if bag_capacity_override >= 0:
		return bag_capacity_override
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


# Trophy hook — fired from Spear once the trophy fish is actually landed (post-defense).
# First catch sets the persistent flag and emits the campaign-win signal.
func note_trophy_caught(species: StringName) -> void:
	if species == &"whitewhale" and not whitewhale_caught:
		whitewhale_caught = true
		whitewhale_caught_signal.emit()


# Kept as a no-op for caller compatibility — nothing currently depends on misses.
func register_miss() -> void:
	pass


# --- Species ---

func _load_species() -> void:
	species_list.clear()
	species_by_id.clear()
	for path in SPECIES_PATHS:
		var s: SpeciesData = load(path)
		assert(s != null, "Failed to load species: %s" % path)
		species_list.append(s)
		species_by_id[s.id] = s


func get_species(id: StringName) -> SpeciesData:
	return species_by_id.get(id, null)


func get_all_species() -> Array[SpeciesData]:
	return species_list


func is_species_discovered(id: StringName) -> bool:
	return discovered_species.has(str(id))


func mark_species_discovered(id: StringName) -> void:
	var key := str(id)
	if discovered_species.has(key):
		return
	discovered_species[key] = dive_number
	species_discovered.emit(id)
	save_discovered_species()


func save_discovered_species() -> void:
	var f := FileAccess.open(DISCOVERED_SPECIES_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"version": 1, "discovered": discovered_species}, "  "))


func load_discovered_species() -> void:
	if not FileAccess.file_exists(DISCOVERED_SPECIES_PATH):
		return
	var f := FileAccess.open(DISCOVERED_SPECIES_PATH, FileAccess.READ)
	if f == null:
		return
	var raw = JSON.parse_string(f.get_as_text())
	if not (raw is Dictionary):
		return
	var d = raw.get("discovered", {})
	if d is Dictionary:
		discovered_species = d


func clear_discovered_species() -> void:
	discovered_species.clear()
	save_discovered_species()


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
	if not is_spear_type_unlocked(id):
		return false
	var t := get_spear_type(id)
	if t == null or not t.upgrades.has(key):
		return false
	var def: Dictionary = t.upgrades[key]
	var level := get_spear_upgrade_level(id, key)
	if level >= int(def["max_level"]):
		return false
	if not are_spear_upgrade_parents_satisfied(id, key):
		return false
	if cheat_mode:
		return true
	return cash >= int((def["costs"] as Array)[level])


# True when every parent upgrade key listed in the def has at least level 1.
# Empty/missing parent list = always satisfied (root-tier nodes).
func are_spear_upgrade_parents_satisfied(id: StringName, key: String) -> bool:
	var t := get_spear_type(id)
	if t == null or not t.upgrades.has(key):
		return false
	var def: Dictionary = t.upgrades[key]
	var parents = def.get("parents", [])
	if typeof(parents) != TYPE_ARRAY:
		return true
	for p in parents:
		if get_spear_upgrade_level(id, str(p)) < 1:
			return false
	return true


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


# --- Seismic Roar (Heavy keystone) ---

func is_seismic_active() -> bool:
	return Time.get_ticks_msec() < seismic_roar_until_msec


func trigger_seismic_roar() -> void:
	seismic_roar_until_msec = Time.get_ticks_msec() + int(SEISMIC_DURATION * 1000.0)


# --- Tagging Net (Net keystone) ---
# Maps fish instance_id -> bonus multiplier. consume_fish_tag returns 0.0 when
# no tag is set, so callers can branch cheaply. Cleared at dive start.
const TAGGING_NET_BONUS := 2.0
var tagged_fish: Dictionary = {}


func tag_fish(fish_instance_id: int) -> void:
	tagged_fish[fish_instance_id] = TAGGING_NET_BONUS


func consume_fish_tag(fish_instance_id: int) -> float:
	if not tagged_fish.has(fish_instance_id):
		return 0.0
	var mult: float = float(tagged_fish[fish_instance_id])
	tagged_fish.erase(fish_instance_id)
	return mult


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
# is exhausted OR the bag is mid-reload — caller must wait for spears to return
# AND the reload timer to expire before firing again.
func draw_next_spear_type() -> StringName:
	# Block new shots once the tank is dry — any in-flight spears finish their
	# reel, then main._drain_oxygen triggers the resurface.
	if oxygen <= 0.0:
		return &""
	if reloading:
		return &""
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


# Called when the last in-flight spear has returned with the bag exhausted.
# Starts the reload timer; tick_reload finishes the reshuffle when it hits zero.
func reshuffle_if_round_complete() -> void:
	if bag_is_exhausted() and active_spear_count <= 0 and not reloading:
		_start_reload()


func reshuffle_if_exhausted() -> void:
	reshuffle_if_round_complete()


# Sets up the reload timer based on bag size and the Quick Hands upgrade.
# Each upgrade level adds +25% reload speed (Lv 4 → 50% reload time).
func _start_reload() -> void:
	var bag_total: int = max(1, _bag_loaded_total())
	var lvl: int = int(upgrade_levels.get("reload_speed", 0))
	var speed_mult: float = 1.0 + lvl * 0.25
	reload_total = max(0.05, float(bag_total) * RELOAD_PER_SPEAR / speed_mult)
	reload_remaining = reload_total
	reloading = true
	reload_state_changed.emit(true)


# Called from main._process while underwater. Counts down and reshuffles the
# bag when the timer expires so firing reopens.
func tick_reload(delta: float) -> void:
	if not reloading:
		return
	reload_remaining -= delta
	if reload_remaining <= 0.0:
		reload_remaining = 0.0
		reloading = false
		bag_queue.shuffle()
		bag_index = 0
		reload_state_changed.emit(false)


func reload_progress() -> float:
	if reload_total <= 0.0:
		return 1.0
	return clampf(1.0 - (reload_remaining / reload_total), 0.0, 1.0)


func note_spear_fired(spear_id: StringName = &"") -> void:
	active_spear_count += 1
	dive_shots_fired += 1
	if spear_id != &"":
		var key := str(spear_id)
		dive_shots_by_spear[key] = int(dive_shots_by_spear.get(key, 0)) + 1


func note_spear_returned() -> void:
	active_spear_count = max(0, active_spear_count - 1)
	reshuffle_if_round_complete()


# Records a successful catch — invoked from Spear._award_fish / _pierce_through.
# Tracks per-spear hit count and per-fish (count, value) for the summary screen.
func note_fish_caught(spear_id: StringName = &"", species: StringName = &"", value: int = 0) -> void:
	dive_fish_caught += 1
	if spear_id != &"":
		var sk := str(spear_id)
		dive_hits_by_spear[sk] = int(dive_hits_by_spear.get(sk, 0)) + 1
	if species != &"":
		var fk := str(species)
		var entry: Dictionary = dive_catches_by_fish.get(fk, {"count": 0, "value": 0})
		entry["count"] = int(entry.get("count", 0)) + 1
		entry["value"] = int(entry.get("value", 0)) + value
		dive_catches_by_fish[fk] = entry
		mark_species_discovered(species)


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
	dive_number += 1
	dive_number_changed.emit(dive_number)
	dive_cash = 0.0
	active_spear_count = 0
	dive_shots_fired = 0
	dive_fish_caught = 0
	dive_shots_by_spear.clear()
	dive_hits_by_spear.clear()
	dive_catches_by_fish.clear()
	dive_zone_id = str(get_current_zone().id) if get_current_zone() else ""
	dive_start_msec = Time.get_ticks_msec()
	seismic_roar_until_msec = 0
	tagged_fish.clear()
	reloading = false
	reload_remaining = 0.0
	reload_total = 0.0
	clamp_bag_loadout()
	_build_bag_queue()
	set_oxygen(get_oxygen_capacity())
	set_dive_state(DiveState.DIVING)


func finish_dive() -> void:
	# Snapshot for the surface summary screen before clearing per-dive fields.
	last_dive_cash = int(dive_cash)
	last_dive_shots = dive_shots_fired
	last_dive_fish = dive_fish_caught
	last_dive_shots_by_spear = dive_shots_by_spear.duplicate(true)
	last_dive_hits_by_spear = dive_hits_by_spear.duplicate(true)
	last_dive_catches_by_fish = dive_catches_by_fish.duplicate(true)
	last_dive_zone_id = dive_zone_id
	last_dive_duration = max(0.0, (Time.get_ticks_msec() - dive_start_msec) / 1000.0)
	# Append to persistent history (keeps the last RUN_HISTORY_MAX entries).
	run_history.append({
		"dive_n": dive_number,
		"zone_id": last_dive_zone_id,
		"cash": last_dive_cash,
		"fish": last_dive_fish,
		"shots": last_dive_shots,
		"shots_by_spear": last_dive_shots_by_spear.duplicate(true),
		"hits_by_spear": last_dive_hits_by_spear.duplicate(true),
		"catches_by_fish": last_dive_catches_by_fish.duplicate(true),
		"duration": last_dive_duration,
		"timestamp": Time.get_unix_time_from_system(),
	})
	if run_history.size() > RUN_HISTORY_MAX:
		run_history = run_history.slice(run_history.size() - RUN_HISTORY_MAX)
	save_run_history()
	cash += dive_cash
	dive_cash = 0.0
	dive_shots_fired = 0
	dive_fish_caught = 0
	dive_shots_by_spear.clear()
	dive_hits_by_spear.clear()
	dive_catches_by_fish.clear()
	bag_queue.clear()
	bag_index = 0
	active_spear_count = 0
	cash_changed.emit(cash)
	set_dive_state(DiveState.SURFACE)


# --- Run history persistence ---

func save_run_history() -> void:
	var f := FileAccess.open(RUN_HISTORY_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Failed to open run history save path")
		return
	f.store_string(JSON.stringify({"version": 1, "entries": run_history}, "  "))
	f.close()


func load_run_history() -> void:
	if not FileAccess.file_exists(RUN_HISTORY_PATH):
		return
	var f := FileAccess.open(RUN_HISTORY_PATH, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var entries = (parsed as Dictionary).get("entries", [])
	if typeof(entries) == TYPE_ARRAY:
		run_history = entries


func clear_run_history() -> void:
	run_history.clear()
	save_run_history()


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


# --- Dev: stage presets ---
#
# Wipes & rebuilds run state to a known testing baseline. Driven by DevPanel.
# `stage_index` selects the zone (0..3). `level` is one of:
#   &"fresh"       — bare minimum: zone unlocked, only the spears reachable at
#                    that stage available, all upgrade levels at 0, $50 buffer.
#   &"maxed"       — every upgrade maxed, $5000 wallet, full bag size.
#   &"whale_ready" — Z4-targeted loadout to test whale fights without grinding.
func apply_stage_preset(stage_index: int, level: StringName) -> void:
	# Zone selection + unlock floor.
	var clamped: int = clampi(stage_index, 0, zones.size() - 1)
	selected_zone_index = clamped
	unlocked_zone_index = max(unlocked_zone_index, clamped)

	# Spear unlocks scale with stage: Z1=normal only, Z2=+net, Z3=+heavy, Z4=all.
	unlocked_spear_types = [&"normal"]
	if clamped >= 1:
		unlocked_spear_types.append(&"net")
	if clamped >= 2:
		unlocked_spear_types.append(&"heavy")
	# Whale-ready also unlocks everything regardless of stage_index.
	if level == &"whale_ready":
		unlocked_spear_types = [&"normal", &"net", &"heavy"]

	# Reset spear upgrade levels to zero, then apply preset overrides.
	spear_upgrade_levels.clear()
	for t in spear_types:
		var levels := {}
		for k in t.upgrades.keys():
			levels[k] = 0
		spear_upgrade_levels[t.id] = levels
	var preset_levels := _preset_upgrade_levels(clamped, level)
	for spear_id in preset_levels.keys():
		if not spear_upgrade_levels.has(spear_id):
			continue
		for k in preset_levels[spear_id].keys():
			# Clamp to that upgrade's max_level so a preset can't exceed the cap.
			var t := get_spear_type(spear_id)
			var cap: int = int(t.upgrades[k]["max_level"]) if t and t.upgrades.has(k) else int(preset_levels[spear_id][k])
			spear_upgrade_levels[spear_id][k] = min(int(preset_levels[spear_id][k]), cap)

	# Cash + global upgrades.
	cash = _preset_cash(stage_index, level)
	upgrade_levels = {
		"oxygen": _preset_oxygen_lvl(stage_index, level),
		"spear_bag": _preset_bag_lvl(stage_index, level),
	}

	# Refill consumables and re-emit signals so HUD/shop refresh.
	bag_loadout.clear()
	auto_fill_bag()
	set_oxygen(get_oxygen_capacity())
	cash_changed.emit(cash)
	zone_changed.emit(get_current_zone())
	for i in range(unlocked_zone_index + 1):
		zone_unlocked.emit(i)
	for sid in unlocked_spear_types:
		spear_type_unlocked.emit(sid)
	for sid in spear_upgrade_levels.keys():
		for k in spear_upgrade_levels[sid].keys():
			spear_upgrade_changed.emit(sid, k, int(spear_upgrade_levels[sid][k]))


func _preset_upgrade_levels(_stage: int, level: StringName) -> Dictionary:
	# Returns a per-spear-id dict of { upgrade_key: level } overrides. Empty
	# means "leave at zero" (used by &"fresh").
	if level == &"fresh":
		return {}
	if level == &"maxed":
		var max_lv := {}
		for t in spear_types:
			max_lv[t.id] = {}
			for k in t.upgrades.keys():
				max_lv[t.id][k] = int(t.upgrades[k]["max_level"])
		return max_lv
	if level == &"whale_ready":
		# Light loadout aimed at the whale fight: heavy carries the work, normal
		# is a backup. Net is unlocked but not specifically tuned.
		return {
			&"heavy": {"speed_mult": 1, "crit_chance": 1, "pierce_count": 1, "value_bonus": 1},
			&"normal": {"speed_mult": 1, "value_bonus": 1},
		}
	return {}


func _preset_cash(_stage: int, level: StringName) -> float:
	if level == &"fresh":
		return 50.0
	if level == &"maxed":
		return 5000.0
	if level == &"whale_ready":
		return 500.0
	return 0.0


func _preset_oxygen_lvl(_stage: int, level: StringName) -> int:
	if level == &"maxed":
		return int(upgrades["oxygen"]["max_level"])
	if level == &"whale_ready":
		return 3
	return 0


func _preset_bag_lvl(_stage: int, level: StringName) -> int:
	if level == &"maxed":
		return int(upgrades["spear_bag"]["max_level"])
	if level == &"whale_ready":
		return 2
	return 0


# --- Dev tuning autosave/autoload ---
#
# DevPanel mutations push tuning state to user://dev_tuning.json so balance work
# survives restarts. Source .tres files are NEVER modified — autosave only writes
# the JSON; reset paths reload .tres-on-disk separately.

const _SPEAR_TUNABLE_FIELDS := [
	"speed_mult", "reel_speed_mult", "hit_radius_bonus",
	"value_bonus", "pierce_count", "net_radius",
	"net_max_catch", "crit_chance", "catches_medium",
	"bypasses_defenses", "twin_shot", "perfect_strike",
	"sonic_boom", "lure_net",
]


func _save_setup_dev_tuning_timer() -> void:
	# Lazy-create a one-shot debounce timer.
	if _dev_save_timer != null:
		return
	_dev_save_timer = Timer.new()
	_dev_save_timer.one_shot = true
	_dev_save_timer.wait_time = 0.4
	_dev_save_timer.timeout.connect(save_dev_tuning)
	add_child(_dev_save_timer)


func request_dev_tuning_save() -> void:
	# Restarting an active timer collapses N rapid changes into a single write.
	_save_setup_dev_tuning_timer()
	_dev_save_timer.start()


func save_dev_tuning() -> void:
	var data := {
		"version": 1,
		"game": {
			"dev_infinite_oxygen": dev_infinite_oxygen,
			"dev_skip_shop": dev_skip_shop,
			"oxygen_capacity_override": oxygen_capacity_override,
			"bag_capacity_override": bag_capacity_override,
			"dive_travel_duration": dive_travel_duration,
		},
		"fish_stat_overrides": fish_stat_overrides.duplicate(true),
		"spear_upgrade_levels": spear_upgrade_levels.duplicate(true),
		"spears": _serialize_spears(),
	}
	var f := FileAccess.open(DEV_TUNING_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Failed to open dev tuning save path")
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()


func load_dev_tuning() -> void:
	if not FileAccess.file_exists(DEV_TUNING_PATH):
		return
	var f := FileAccess.open(DEV_TUNING_PATH, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Dev tuning file invalid; ignoring")
		return
	var data: Dictionary = parsed
	# Game-tab tunables.
	var g: Dictionary = data.get("game", {})
	dev_infinite_oxygen = g.get("dev_infinite_oxygen", dev_infinite_oxygen)
	dev_skip_shop = g.get("dev_skip_shop", dev_skip_shop)
	oxygen_capacity_override = float(g.get("oxygen_capacity_override", oxygen_capacity_override))
	bag_capacity_override = int(g.get("bag_capacity_override", bag_capacity_override))
	dive_travel_duration = float(g.get("dive_travel_duration", dive_travel_duration))
	# Fish overrides — wholesale replace (dict shape).
	var fov = data.get("fish_stat_overrides", {})
	if typeof(fov) == TYPE_DICTIONARY:
		fish_stat_overrides = fov
	# Spear upgrade levels — merge so unknown saved keys don't blow away schema.
	var lv = data.get("spear_upgrade_levels", {})
	if typeof(lv) == TYPE_DICTIONARY:
		for spear_id in lv.keys():
			if not spear_upgrade_levels.has(spear_id):
				spear_upgrade_levels[spear_id] = {}
			for k in lv[spear_id].keys():
				spear_upgrade_levels[spear_id][k] = int(lv[spear_id][k])
	# Spear base fields — apply onto live SpearType resources (no .tres write).
	var sd = data.get("spears", {})
	if typeof(sd) == TYPE_DICTIONARY:
		_apply_spear_fields(sd)


func _serialize_spears() -> Dictionary:
	var out := {}
	for s in spear_types:
		var d := {}
		for fld in _SPEAR_TUNABLE_FIELDS:
			d[fld] = s.get(fld)
		out[str(s.id)] = d
	return out


func _apply_spear_fields(sd: Dictionary) -> void:
	for s in spear_types:
		var key := str(s.id)
		if not sd.has(key):
			continue
		var d: Dictionary = sd[key]
		for fld in _SPEAR_TUNABLE_FIELDS:
			if d.has(fld):
				s.set(fld, d[fld])
