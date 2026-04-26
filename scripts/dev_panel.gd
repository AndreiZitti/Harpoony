extends CanvasLayer

# Toggleable full-screen tuning panel for live game-balance work.
# Phase 1: Presets + Game + Spawn tabs. Spears / Fish / Costs come later.
#
# Layered above HUD/shop but below GameMenu's pause overlay so ESC still works.
# PROCESS_MODE_ALWAYS so it can be opened/closed while the game tree is paused.

const STAGE_PRESETS = [
	{"label": "Z1 Fresh", "stage": 0, "level": &"fresh"},
	{"label": "Z1 Maxed", "stage": 0, "level": &"maxed"},
	{"label": "Z2 Fresh", "stage": 1, "level": &"fresh"},
	{"label": "Z2 Maxed", "stage": 1, "level": &"maxed"},
	{"label": "Z3 Fresh", "stage": 2, "level": &"fresh"},
	{"label": "Z3 Maxed", "stage": 2, "level": &"maxed"},
	{"label": "Z4 Fresh", "stage": 3, "level": &"fresh"},
	{"label": "Z4 Whale Ready", "stage": 3, "level": &"whale_ready"},
]

const TAB_NAMES = ["Presets", "Spears", "Fish", "Costs", "Game", "Spawn"]

# Order matches the species list in fish.gd::setup. Sub-tabs render in this order.
const FISH_SPECIES = [
	"sardine", "grouper", "tuna", "pufferfish", "mahimahi",
	"squid", "lanternfish", "anglerfish", "triggerfish",
	"marlin", "jellyfish", "whitewhale",
]

# Mirrors GameMenu's spawn list so the dev panel can re-expose the same buttons.
const DEV_SPECIES_LIST = [
	["Sardine school", "sardine"],
	["Pufferfish", "pufferfish"],
	["Mahi-mahi", "mahimahi"],
	["Squid", "squid"],
	["Lanternfish school", "lanternfish"],
	["Anglerfish", "anglerfish"],
	["Marlin", "marlin"],
	["Grouper", "grouper"],
	["Tuna", "tuna"],
]

var _root: Control
var _tab_container: TabContainer
var _is_visible: bool = false
var _dev_spawn_callable: Callable = Callable()

# Game-tab live controls (kept around so we can refresh them on open).
var _cash_spin: SpinBox = null
var _oxygen_cap_spin: SpinBox = null
var _bag_cap_spin: SpinBox = null
var _dive_dur_spin: SpinBox = null
var _force_spears_check: CheckBox = null
var _force_zones_check: CheckBox = null
var _infinite_oxy_check: CheckBox = null
var _skip_shop_check: CheckBox = null
var _state_label: Label = null


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false


func set_dev_spawn_callable(c: Callable) -> void:
	_dev_spawn_callable = c


func toggle() -> void:
	_is_visible = not _is_visible
	_root.visible = _is_visible
	if _is_visible:
		_refresh_state_label()
		_refresh_game_tab_values()


func close() -> void:
	if _is_visible:
		toggle()


func is_open() -> bool:
	return _is_visible


# --- UI build ---

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.07, 0.10, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(960, 560)
	# Center the panel by offsetting half its size — PRESET_CENTER alone leaves
	# the top-left corner at center, not the panel center.
	panel.position = Vector2(-480, -280)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.18, 0.97)
	sb.border_color = Color(0.85, 0.78, 0.45, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	# Top bar with title + close
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := Label.new()
	title.text = "DEV PANEL  (F2 to toggle)"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	top.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(toggle)
	top.add_child(close_btn)

	# Persistent state-summary line (visible across tabs)
	_state_label = Label.new()
	_state_label.add_theme_font_size_override("font_size", 12)
	_state_label.add_theme_color_override("font_color", Color(0.7, 0.78, 0.92))
	v.add_child(_state_label)

	# Tab container
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_tab_container)

	_build_presets_tab()
	_build_spears_tab()
	_build_fish_tab()
	_build_placeholder_tab("Costs", "Phase 4 — edit upgrade cost ladders. Coming soon.")
	_build_game_tab()
	_build_spawn_tab()


func _build_presets_tab() -> void:
	var page := _make_tab_page("Presets")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	page.add_child(v)

	var blurb := Label.new()
	blurb.text = "One-click stage setups. Sets zone, unlocks, cash, and upgrade levels."
	blurb.add_theme_color_override("font_color", Color(0.75, 0.8, 0.92))
	v.add_child(blurb)

	# 4 columns × 2 rows = 8 presets
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)

	for entry in STAGE_PRESETS:
		var btn := Button.new()
		btn.text = entry["label"]
		btn.custom_minimum_size = Vector2(200, 56)
		btn.add_theme_font_size_override("font_size", 14)
		var stage_idx: int = entry["stage"]
		var level: StringName = entry["level"]
		btn.pressed.connect(func(): _on_preset_pressed(stage_idx, level))
		grid.add_child(btn)


func _build_game_tab() -> void:
	var page := _make_tab_page("Game")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	# Cash setter
	_cash_spin = _add_spin_row(v, "Cash", 0, 99999, 100, GameData.cash, _on_cash_changed)

	# Oxygen capacity override (-1 means use level-based formula).
	# UI shows 0 = "no override"; we map 0 -> -1 internally.
	_oxygen_cap_spin = _add_spin_row(v, "Oxygen capacity (s, 0=auto)", 0, 120, 1,
		max(0, GameData.oxygen_capacity_override), _on_oxygen_cap_changed)

	# Bag capacity override (0 = auto).
	_bag_cap_spin = _add_spin_row(v, "Bag capacity (0=auto)", 0, 30, 1,
		max(0, GameData.bag_capacity_override), _on_bag_cap_changed)

	# Dive travel duration (seconds).
	_dive_dur_spin = _add_spin_row(v, "Dive travel duration (s)", 0.1, 10.0, 0.1,
		GameData.dive_travel_duration, _on_dive_duration_changed)
	# Re-config the duration spin for floats
	_dive_dur_spin.step = 0.1

	v.add_child(HSeparator.new())

	_force_spears_check = _add_check_row(v, "Force unlock all spears",
		GameData.unlocked_spear_types.size() >= 3, _on_force_spears_toggled)
	_force_zones_check = _add_check_row(v, "Force unlock all zones",
		GameData.unlocked_zone_index >= GameData.zones.size() - 1, _on_force_zones_toggled)
	_infinite_oxy_check = _add_check_row(v, "Infinite oxygen (no depletion)",
		GameData.dev_infinite_oxygen, _on_infinite_oxygen_toggled)
	_skip_shop_check = _add_check_row(v, "Skip shop after dive (auto re-dive)",
		GameData.dev_skip_shop, _on_skip_shop_toggled)


func _build_spawn_tab() -> void:
	var page := _make_tab_page("Spawn")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	page.add_child(v)

	var blurb := Label.new()
	blurb.text = "Spawn fish on demand. Underwater only — surface ignores spawns."
	blurb.add_theme_color_override("font_color", Color(0.75, 0.8, 0.92))
	v.add_child(blurb)

	# Per-species buttons
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)

	for entry in DEV_SPECIES_LIST:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(220, 30)
		btn.add_theme_font_size_override("font_size", 12)
		var species_id: String = entry[1]
		btn.pressed.connect(func(): _spawn(species_id))
		grid.add_child(btn)

	v.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)

	var clear_btn := Button.new()
	clear_btn.text = "Clear all fish"
	clear_btn.custom_minimum_size = Vector2(160, 32)
	clear_btn.pressed.connect(_on_clear_fish_pressed)
	row.add_child(clear_btn)

	var whale_btn := Button.new()
	whale_btn.text = "Force spawn White Whale"
	whale_btn.custom_minimum_size = Vector2(220, 32)
	whale_btn.pressed.connect(func(): _spawn("whitewhale"))
	row.add_child(whale_btn)


func _build_fish_tab() -> void:
	# Per-species sub-tabs. Sliders write to GameData.fish_stat_overrides AND
	# patch every live fish of that species so changes are visible instantly.
	var page := _make_tab_page("Fish")
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(v)

	var blurb := Label.new()
	blurb.text = "Live-tune each species. Overrides apply to spawned fish + future spawns until reset."
	blurb.add_theme_color_override("font_color", Color(0.75, 0.8, 0.92))
	v.add_child(blurb)

	var sub_tabs := TabContainer.new()
	sub_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sub_tabs)

	for species in FISH_SPECIES:
		var sub_page := MarginContainer.new()
		sub_page.name = species.capitalize()
		sub_page.add_theme_constant_override("margin_left", 6)
		sub_page.add_theme_constant_override("margin_right", 6)
		sub_page.add_theme_constant_override("margin_top", 6)
		sub_page.add_theme_constant_override("margin_bottom", 6)
		sub_tabs.add_child(sub_page)
		sub_page.add_child(_build_fish_subtab(species))


func _build_fish_subtab(species: String) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	# Header: name + reset-overrides button.
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	v.add_child(hdr)
	var name_lbl := Label.new()
	name_lbl.text = species.capitalize()
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	hdr.add_child(name_lbl)
	var spc := Control.new()
	spc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(spc)
	var reset_btn := Button.new()
	reset_btn.text = "Reset overrides"
	reset_btn.pressed.connect(func(): _reset_fish_overrides(species))
	hdr.add_child(reset_btn)

	v.add_child(_section_label("Base Stats (live overrides)"))

	var defaults: Dictionary = _fish_defaults_for(species)

	_add_slider_row(v, "base_value", 1.0, 1500.0, 1.0,
		func(): return _get_fish_override(species, "base_value", defaults["base_value"]),
		func(val): _set_fish_override(species, "base_value", val))
	_add_slider_row(v, "speed", 0.0, 400.0, 5.0,
		func(): return _get_fish_override(species, "speed", defaults["speed"]),
		func(val): _set_fish_override(species, "speed", val))
	_add_slider_row(v, "hit_radius", 4.0, 60.0, 1.0,
		func(): return _get_fish_override(species, "hit_radius", defaults["hit_radius"]),
		func(val): _set_fish_override(species, "hit_radius", val))
	_add_slider_row(v, "wave_amplitude", 0.0, 50.0, 1.0,
		func(): return _get_fish_override(species, "wave_amplitude", defaults["wave_amplitude"]),
		func(val): _set_fish_override(species, "wave_amplitude", val))
	_add_slider_row(v, "wave_frequency", 0.1, 8.0, 0.1,
		func(): return _get_fish_override(species, "wave_frequency", defaults["wave_frequency"]),
		func(val): _set_fish_override(species, "wave_frequency", val))

	return scroll


func _get_fish_override(species: String, field: String, fallback: float) -> float:
	if not GameData.fish_stat_overrides.has(species):
		return fallback
	var ov: Dictionary = GameData.fish_stat_overrides[species]
	return float(ov.get(field, fallback))


func _set_fish_override(species: String, field: String, value: float) -> void:
	if not GameData.fish_stat_overrides.has(species):
		GameData.fish_stat_overrides[species] = {}
	GameData.fish_stat_overrides[species][field] = value
	_apply_to_existing_fish(species, field, value)


func _apply_to_existing_fish(species: String, field: String, value: float) -> void:
	for f in get_tree().get_nodes_in_group("fish"):
		if f is Fish and f.species == species:
			match field:
				"base_value": f.base_value = int(value)
				"speed": f.speed = value
				"hit_radius":
					f.hit_radius = value
					f._update_collision_radius()
				"wave_amplitude": f.wave_amplitude = value
				"wave_frequency": f.wave_frequency = value


func _reset_fish_overrides(species: String) -> void:
	GameData.fish_stat_overrides.erase(species)
	GameData.request_dev_tuning_save()
	# Re-close + re-open to refresh slider readouts back to defaults.
	if is_open():
		close()
		toggle()


func _fish_defaults_for(species: String) -> Dictionary:
	# Mirrors fish.gd::setup so sliders show the actual baseline before any
	# override is applied. wave_amplitude defaults to 20.0 unless setup overrides it.
	match species:
		"sardine": return {"base_value": 4, "speed": 160.0, "hit_radius": 10.0, "wave_amplitude": 20.0, "wave_frequency": 5.5}
		"grouper": return {"base_value": 15, "speed": 80.0, "hit_radius": 18.0, "wave_amplitude": 20.0, "wave_frequency": 2.8}
		"tuna": return {"base_value": 40, "speed": 120.0, "hit_radius": 24.0, "wave_amplitude": 20.0, "wave_frequency": 3.6}
		"pufferfish": return {"base_value": 12, "speed": 50.0, "hit_radius": 13.0, "wave_amplitude": 20.0, "wave_frequency": 1.5}
		"mahimahi": return {"base_value": 25, "speed": 90.0, "hit_radius": 16.0, "wave_amplitude": 20.0, "wave_frequency": 4.0}
		"squid": return {"base_value": 18, "speed": 0.0, "hit_radius": 13.0, "wave_amplitude": 20.0, "wave_frequency": 1.0}
		"lanternfish": return {"base_value": 5, "speed": 130.0, "hit_radius": 9.0, "wave_amplitude": 20.0, "wave_frequency": 4.5}
		"anglerfish": return {"base_value": 50, "speed": 30.0, "hit_radius": 16.0, "wave_amplitude": 20.0, "wave_frequency": 0.9}
		"triggerfish": return {"base_value": 30, "speed": 70.0, "hit_radius": 16.0, "wave_amplitude": 8.0, "wave_frequency": 1.6}
		"marlin": return {"base_value": 60, "speed": 280.0, "hit_radius": 22.0, "wave_amplitude": 20.0, "wave_frequency": 1.0}
		"jellyfish": return {"base_value": 18, "speed": 30.0, "hit_radius": 16.0, "wave_amplitude": 8.0, "wave_frequency": 1.0}
		"whitewhale": return {"base_value": 800, "speed": 60.0, "hit_radius": 40.0, "wave_amplitude": 30.0, "wave_frequency": 0.6}
	return {"base_value": 10, "speed": 100.0, "hit_radius": 12.0, "wave_amplitude": 20.0, "wave_frequency": 2.0}


func _build_spears_tab() -> void:
	# Per-spear sub-tabs: live sliders/spinboxes/checks for every base stat,
	# plus per-upgrade-key level spinners. Stats apply LIVE — no apply button.
	var page := _make_tab_page("Spears")
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(v)

	var blurb := Label.new()
	blurb.text = "Live-tune each spear's base stats and upgrade levels. Changes apply instantly."
	blurb.add_theme_color_override("font_color", Color(0.75, 0.8, 0.92))
	v.add_child(blurb)

	var sub_tabs := TabContainer.new()
	sub_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sub_tabs)

	for t in GameData.spear_types:
		var sub_page := MarginContainer.new()
		sub_page.name = t.display_name if t.display_name != "" else String(t.id)
		sub_page.add_theme_constant_override("margin_left", 6)
		sub_page.add_theme_constant_override("margin_right", 6)
		sub_page.add_theme_constant_override("margin_top", 6)
		sub_page.add_theme_constant_override("margin_bottom", 6)
		sub_tabs.add_child(sub_page)
		sub_page.add_child(_build_spear_subtab(t.id))


func _build_spear_subtab(spear_id: StringName) -> Control:
	var t: SpearType = null
	for s in GameData.spear_types:
		if s.id == spear_id:
			t = s
			break
	if t == null:
		return Control.new()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	# --- Header: name + reset-to-disk button
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	v.add_child(hdr)
	var name_lbl := Label.new()
	name_lbl.text = t.display_name if t.display_name != "" else String(t.id)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	hdr.add_child(name_lbl)
	var spc := Control.new()
	spc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(spc)
	var reset_btn := Button.new()
	reset_btn.text = "Reset to .tres"
	reset_btn.pressed.connect(func(): _reset_spear_to_disk(spear_id))
	hdr.add_child(reset_btn)

	# --- Base stats
	v.add_child(_section_label("Base Stats"))
	_add_slider_row(v, "speed_mult", 0.3, 3.0, 0.05,
		func(): return t.speed_mult,
		func(val): t.speed_mult = val)
	_add_slider_row(v, "reel_speed_mult", 0.3, 3.0, 0.05,
		func(): return t.reel_speed_mult,
		func(val): t.reel_speed_mult = val)
	_add_slider_row(v, "hit_radius_bonus", -10.0, 50.0, 1.0,
		func(): return t.hit_radius_bonus,
		func(val): t.hit_radius_bonus = val)
	_add_slider_row(v, "value_bonus", 0.5, 5.0, 0.05,
		func(): return t.value_bonus,
		func(val): t.value_bonus = val)
	_add_spin_row(v, "pierce_count", 1, 6, 1, t.pierce_count,
		func(val): t.pierce_count = int(val))
	_add_slider_row(v, "net_radius", 0.0, 200.0, 5.0,
		func(): return t.net_radius,
		func(val): t.net_radius = val)
	_add_spin_row(v, "net_max_catch", 1, 15, 1, t.net_max_catch,
		func(val): t.net_max_catch = int(val))
	_add_slider_row(v, "crit_chance", 0.0, 1.0, 0.01,
		func(): return t.crit_chance,
		func(val): t.crit_chance = val)

	# --- Toggles (binary flags, some stored as int 0/1)
	v.add_child(_section_label("Flags"))
	_add_check_row(v, "catches_medium",
		t.catches_medium == 1,
		func(on): t.catches_medium = 1 if on else 0)
	_add_check_row(v, "bypasses_defenses",
		t.bypasses_defenses,
		func(on): t.bypasses_defenses = on)
	_add_check_row(v, "twin_shot",
		t.twin_shot == 1,
		func(on): t.twin_shot = 1 if on else 0)
	_add_check_row(v, "perfect_strike",
		t.perfect_strike == 1,
		func(on): t.perfect_strike = 1 if on else 0)
	_add_check_row(v, "sonic_boom",
		t.sonic_boom == 1,
		func(on): t.sonic_boom = 1 if on else 0)
	_add_check_row(v, "lure_net",
		t.lure_net == 1,
		func(on): t.lure_net = 1 if on else 0)

	# --- Upgrade levels (current level for each key)
	v.add_child(_section_label("Upgrade Levels"))
	if t.upgrades.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "(no upgrades defined)"
		none_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.78))
		v.add_child(none_lbl)
	else:
		for key in t.upgrades.keys():
			var def: Dictionary = t.upgrades[key]
			var max_lv: int = int(def.get("max_level", 1))
			var name_text: String = String(def.get("name", str(key)))
			var label_text: String = "%s [%s] (max %d)" % [name_text, str(key), max_lv]
			var current: int = GameData.get_spear_upgrade_level(spear_id, String(key))
			var key_str: String = String(key)
			var sid: StringName = spear_id
			_add_spin_row(v, label_text, 0, max_lv, 1, current,
				func(val):
					if not GameData.spear_upgrade_levels.has(sid):
						GameData.spear_upgrade_levels[sid] = {}
					GameData.spear_upgrade_levels[sid][key_str] = int(val)
					GameData.spear_upgrade_changed.emit(sid, key_str, int(val)))

	return scroll


func _reset_spear_to_disk(spear_id: StringName) -> void:
	# Re-load the SpearType from its .tres and copy tunable fields back onto the
	# live instance. Upgrade dict (cost ladder) is intentionally untouched —
	# that's Phase 4's job.
	var path := "res://data/spears/%s.tres" % str(spear_id)
	var fresh: SpearType = load(path)
	if fresh == null:
		return
	var live: SpearType = null
	for s in GameData.spear_types:
		if s.id == spear_id:
			live = s
			break
	if live == null:
		return
	var fields: Array[StringName] = [
		&"speed_mult", &"reel_speed_mult", &"hit_radius_bonus",
		&"value_bonus", &"pierce_count", &"net_radius",
		&"net_max_catch", &"crit_chance", &"catches_medium",
		&"bypasses_defenses", &"twin_shot", &"perfect_strike",
		&"sonic_boom", &"lure_net",
	]
	for prop in fields:
		live.set(prop, fresh.get(prop))
	GameData.request_dev_tuning_save()
	# Easiest way to refresh visible slider values: close + reopen the panel.
	# (Re-builds the whole UI tree, picking up the new values.)
	if is_open():
		close()
		toggle()


func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.78, 0.45))
	return lbl


func _build_placeholder_tab(label: String, message: String) -> void:
	var page := _make_tab_page(label)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(v)

	var msg := Label.new()
	msg.text = message
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 14)
	msg.add_theme_color_override("font_color", Color(0.6, 0.65, 0.78))
	v.add_child(msg)


func _make_tab_page(tab_name: String) -> Control:
	var page := MarginContainer.new()
	page.name = tab_name
	page.add_theme_constant_override("margin_left", 8)
	page.add_theme_constant_override("margin_right", 8)
	page.add_theme_constant_override("margin_top", 8)
	page.add_theme_constant_override("margin_bottom", 8)
	_tab_container.add_child(page)
	return page


# --- Row helpers ---

func _add_spin_row(parent: Node, label_text: String, min_v: float, max_v: float,
		step: float, value: float, on_change: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(280, 0)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	row.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = value
	spin.custom_minimum_size = Vector2(140, 0)
	spin.value_changed.connect(func(v: float):
		on_change.call(v)
		GameData.request_dev_tuning_save())
	row.add_child(spin)
	return spin


func _add_slider_row(parent: Node, label_text: String, lo: float, hi: float,
		step: float, getter: Callable, setter: Callable) -> HSlider:
	# Slider + live numeric readout. Getter is called once to seed the value;
	# setter is called on every drag tick so changes apply LIVE.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(180, 0)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = float(getter.call())
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(220, 0)
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text = "%.2f" % slider.value
	val_lbl.custom_minimum_size = Vector2(60, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.6))
	row.add_child(val_lbl)

	slider.value_changed.connect(func(v: float):
		setter.call(v)
		val_lbl.text = "%.2f" % v
		GameData.request_dev_tuning_save())
	return slider


func _add_check_row(parent: Node, label_text: String, initial: bool,
		on_toggle: Callable) -> CheckBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var cb := CheckBox.new()
	cb.text = label_text
	cb.button_pressed = initial
	cb.add_theme_font_size_override("font_size", 13)
	cb.toggled.connect(func(pressed: bool):
		on_toggle.call(pressed)
		GameData.request_dev_tuning_save())
	row.add_child(cb)
	return cb


# --- Handlers ---

func _on_preset_pressed(stage: int, level: StringName) -> void:
	GameData.apply_stage_preset(stage, level)
	GameData.request_dev_tuning_save()
	_refresh_state_label()
	_refresh_game_tab_values()
	close()


func _on_cash_changed(value: float) -> void:
	GameData.cash = value
	GameData.cash_changed.emit(GameData.cash)
	_refresh_state_label()


func _on_oxygen_cap_changed(value: float) -> void:
	# 0 in the UI = "no override"; map back to -1 internally.
	GameData.oxygen_capacity_override = -1.0 if value <= 0.0 else value
	# Re-clamp current oxygen to the new capacity.
	GameData.set_oxygen(GameData.oxygen)
	_refresh_state_label()


func _on_bag_cap_changed(value: float) -> void:
	GameData.bag_capacity_override = -1 if int(value) <= 0 else int(value)
	GameData.clamp_bag_loadout()
	GameData.bag_loadout_changed.emit()
	_refresh_state_label()


func _on_dive_duration_changed(value: float) -> void:
	GameData.dive_travel_duration = max(0.1, value)


func _on_force_spears_toggled(pressed: bool) -> void:
	if pressed:
		var ids: Array[StringName] = []
		for t in GameData.spear_types:
			ids.append(t.id)
		GameData.unlocked_spear_types = ids
		for id in ids:
			GameData.spear_type_unlocked.emit(id)
	else:
		GameData.unlocked_spear_types = [&"normal"]
	GameData.cash_changed.emit(GameData.cash)  # nudge shop UI to refresh
	_refresh_state_label()


func _on_force_zones_toggled(pressed: bool) -> void:
	if pressed:
		GameData.unlocked_zone_index = GameData.zones.size() - 1
	else:
		GameData.unlocked_zone_index = max(0, GameData.selected_zone_index)
	for i in range(GameData.unlocked_zone_index + 1):
		GameData.zone_unlocked.emit(i)
	GameData.cash_changed.emit(GameData.cash)
	_refresh_state_label()


func _on_infinite_oxygen_toggled(pressed: bool) -> void:
	GameData.dev_infinite_oxygen = pressed


func _on_skip_shop_toggled(pressed: bool) -> void:
	GameData.dev_skip_shop = pressed


func _spawn(species: String) -> void:
	if _dev_spawn_callable.is_valid():
		_dev_spawn_callable.call(species)


func _on_clear_fish_pressed() -> void:
	for f in get_tree().get_nodes_in_group("fish"):
		if is_instance_valid(f):
			f.queue_free()


# --- Refresh ---

func _refresh_state_label() -> void:
	if _state_label == null:
		return
	var zone_name := "?"
	var z: ZoneConfig = GameData.get_current_zone()
	if z != null and z.display_name != "":
		zone_name = z.display_name
	var spears: Array[String] = []
	for s in GameData.unlocked_spear_types:
		spears.append(String(s))
	_state_label.text = "Stage: Z%d %s  ·  Cash: $%d  ·  Dive: %d  ·  Spears: %s" % [
		GameData.selected_zone_index + 1,
		zone_name,
		int(GameData.cash),
		GameData.dive_number,
		", ".join(spears),
	]


func _refresh_game_tab_values() -> void:
	if _cash_spin:
		_cash_spin.set_value_no_signal(GameData.cash)
	if _oxygen_cap_spin:
		_oxygen_cap_spin.set_value_no_signal(max(0, GameData.oxygen_capacity_override))
	if _bag_cap_spin:
		_bag_cap_spin.set_value_no_signal(max(0, GameData.bag_capacity_override))
	if _dive_dur_spin:
		_dive_dur_spin.set_value_no_signal(GameData.dive_travel_duration)
	if _force_spears_check:
		_force_spears_check.set_pressed_no_signal(GameData.unlocked_spear_types.size() >= GameData.spear_types.size())
	if _force_zones_check:
		_force_zones_check.set_pressed_no_signal(GameData.unlocked_zone_index >= GameData.zones.size() - 1)
	if _infinite_oxy_check:
		_infinite_oxy_check.set_pressed_no_signal(GameData.dev_infinite_oxygen)
	if _skip_shop_check:
		_skip_shop_check.set_pressed_no_signal(GameData.dev_skip_shop)
