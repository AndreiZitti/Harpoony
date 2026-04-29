extends CanvasLayer

# Toggleable full-screen tuning panel for live game-balance work.
# Phase 1: Presets + Game + Spawn tabs. Spears / Fish / Costs come later.
#
# Layered above HUD/shop but below GameMenu's pause overlay so ESC still works.
# PROCESS_MODE_ALWAYS so it can be opened/closed while the game tree is paused.

# Scenarios are the front door of the dev panel — plain-English jumps to a known
# game state. `apply_zone` snaps the current selected zone to that stage so the
# player lands directly in the relevant water on the next dive. `extras` adds
# light follow-on actions ("spawn whale", "block fish spawns") so a tester can
# get to the moment they care about in one click.
const SCENARIOS = [
	{
		"label": "Fresh start in Zone 1",
		"subtitle": "Empty wallet, no upgrades, default spear",
		"stage": 0, "level": &"fresh",
	},
	{
		"label": "Mid-game Zone 2",
		"subtitle": "$500, oxygen lvl 2, normal + net spears",
		"stage": 1, "level": &"whale_ready",
	},
	{
		"label": "Late-game Zone 3",
		"subtitle": "$2000, all spears unlocked, mid-tier upgrades",
		"stage": 2, "level": &"whale_ready", "cash_override": 2000.0,
	},
	{
		"label": "Whale hunt ready",
		"subtitle": "$500, heavy spear maxed, full oxygen",
		"stage": 3, "level": &"whale_ready",
	},
	{
		"label": "Maxed everything",
		"subtitle": "All zones, all spears at max, $5000",
		"stage": 3, "level": &"maxed",
	},
	{
		"label": "Just the whale",
		"subtitle": "Whale-ready loadout + spawns the whale immediately on dive",
		"stage": 3, "level": &"whale_ready", "extras": &"spawn_whale",
	},
	{
		"label": "Empty scene",
		"subtitle": "Current zone, no fish spawning (test UI / oxygen)",
		"stage": -1, "level": &"none", "extras": &"no_spawns",
	},
]

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
	["Bonito streak", "bonito"],
	["Blockfish", "blockfish"],
]

var _root: Control
var _tab_container: TabContainer
var _is_visible: bool = false
var _dev_spawn_callable: Callable = Callable()

# Live-tweaks tab controls (kept around so we can refresh them on open).
var _cash_spin: SpinBox = null
var _oxygen_cap_spin: SpinBox = null
var _bag_cap_spin: SpinBox = null
var _dive_dur_spin: SpinBox = null
var _force_spears_check: CheckBox = null
var _force_zones_check: CheckBox = null
var _infinite_oxy_check: CheckBox = null
var _skip_shop_check: CheckBox = null
var _state_label: Label = null
# Toast lives in the panel header so scenario buttons can confirm what loaded.
var _toast_label: Label = null
var _toast_tween: Tween = null


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

	# Top bar with title + reset-all + export + close
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	var title := Label.new()
	title.text = "DEV PANEL"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	top.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var reset_all_btn := Button.new()
	reset_all_btn.text = "Reset all dev tuning"
	reset_all_btn.tooltip_text = "Wipes dev_tuning.json + clears live tweaks. Does not touch your saved progress."
	reset_all_btn.pressed.connect(_on_reset_all_pressed)
	top.add_child(reset_all_btn)
	var export_btn := Button.new()
	export_btn.text = "Export to clipboard"
	export_btn.pressed.connect(func(): _on_export_pressed(export_btn))
	top.add_child(export_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(toggle)
	top.add_child(close_btn)

	# Persistent state-summary line (visible across tabs)
	_state_label = Label.new()
	_state_label.add_theme_font_size_override("font_size", 12)
	_state_label.add_theme_color_override("font_color", Color(0.7, 0.78, 0.92))
	v.add_child(_state_label)

	# Toast — sits in the panel header, fades in on scenario load and out 2s later.
	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 13)
	_toast_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7))
	_toast_label.modulate.a = 0.0
	v.add_child(_toast_label)

	# Tab container — Scenarios is the default front door; balance is buried last.
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_tab_container)

	_build_scenarios_tab()
	_build_live_tweaks_tab()
	_build_spawn_tab()
	_build_balance_tab()


func _build_scenarios_tab() -> void:
	var page := _make_tab_page("Scenarios")
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	var blurb := Label.new()
	blurb.text = "Jump straight into a known game state. Click a scenario, dive, playtest."
	blurb.add_theme_color_override("font_color", Color(0.75, 0.8, 0.92))
	v.add_child(blurb)

	for entry in SCENARIOS:
		v.add_child(_make_scenario_button(entry))


func _make_scenario_button(entry: Dictionary) -> Control:
	# Each scenario is a stacked Label inside a Button so we get a clickable row
	# with title + subtitle. Button.text alone can't hold two font sizes.
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 56)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 1)  # hide native text channel
	btn.pressed.connect(func(): _on_scenario_pressed(entry))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_right = -14
	box.offset_top = 6
	box.offset_bottom = -6
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)

	var title := Label.new()
	title.text = String(entry["label"])
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.93, 0.6))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)

	var sub := Label.new()
	sub.text = String(entry.get("subtitle", ""))
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.78, 0.84, 0.95, 0.85))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sub)

	return btn


func _build_live_tweaks_tab() -> void:
	var page := _make_tab_page("Live tweaks")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	var blurb := Label.new()
	blurb.text = "Knobs that change the run in flight. Default values are shown in grey."
	blurb.add_theme_color_override("font_color", Color(0.75, 0.8, 0.92))
	v.add_child(blurb)

	# Cash setter — default is 0, but we don't show a "default" hint here since
	# cash is genuinely arbitrary, not a tuning knob.
	_cash_spin = _add_spin_row(v, "Cash: $", 0, 99999, 100, GameData.cash, _on_cash_changed)

	# Oxygen capacity override (-1 = no override). UI maps 0 -> -1 internally.
	_oxygen_cap_spin = _add_spin_row_with_default(v, "Oxygen seconds", "s", 0, 120, 1,
		max(0, GameData.oxygen_capacity_override), 0, "0 = use level-based formula",
		_on_oxygen_cap_changed)

	_bag_cap_spin = _add_spin_row_with_default(v, "Bag capacity", "spears", 0, 30, 1,
		max(0, GameData.bag_capacity_override), 0, "0 = use level-based formula",
		_on_bag_cap_changed)

	_dive_dur_spin = _add_spin_row_with_default(v, "Dive travel", "s", 0.1, 10.0, 0.1,
		GameData.dive_travel_duration, 1.5, "default 1.5s", _on_dive_duration_changed)
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


func _build_balance_tab() -> void:
	# Balance is the dense tuning surface. We hide it behind collapsed sections
	# so a non-programmer using Scenarios + Live tweaks never has to look at it.
	var page := _make_tab_page("Balance")
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)

	var blurb := Label.new()
	blurb.text = "Deep tuning. Click a section to expand. Each has its own reset."
	blurb.add_theme_color_override("font_color", Color(0.75, 0.8, 0.92))
	v.add_child(blurb)

	# Spears section: per-spear sub-tabs (existing build kept verbatim).
	var spears_content := _build_spears_content()
	v.add_child(_make_collapsible_section("Spears",
		"Per-spear stats and upgrade levels", spears_content,
		_on_reset_all_spears_pressed))

	# Fish section: per-species sub-tabs.
	var fish_content := _build_fish_content()
	v.add_child(_make_collapsible_section("Fish",
		"Per-species value, speed, hit radius, motion", fish_content,
		_on_reset_all_fish_pressed))

	# Costs placeholder — kept so the structure matches the design doc.
	var costs_msg := Label.new()
	costs_msg.text = "Phase 4 — edit upgrade cost ladders. Coming soon."
	costs_msg.add_theme_color_override("font_color", Color(0.6, 0.65, 0.78))
	costs_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_make_collapsible_section("Costs",
		"Upgrade cost ladders", costs_msg, Callable()))


# A header-button + toggleable content body. Body starts hidden ("collapsed by
# default" per the design). The button text shows ▶/▼ to telegraph state.
# `on_reset` is optional; when valid, an inline "Reset section" button appears
# in the header next to the toggle.
func _make_collapsible_section(title: String, subtitle: String, content: Control,
		on_reset: Callable) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 2)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	section.add_child(header_row)

	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = false
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.text = "▶  %s — %s" % [title, subtitle]
	toggle.add_theme_font_size_override("font_size", 14)
	header_row.add_child(toggle)

	if on_reset.is_valid():
		var reset := Button.new()
		reset.text = "Reset section"
		reset.pressed.connect(on_reset)
		header_row.add_child(reset)

	# Wrap content so we can toggle visibility on a stable parent regardless of
	# what `content` actually is.
	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 12)
	body.add_theme_constant_override("margin_top", 4)
	body.add_theme_constant_override("margin_bottom", 4)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	body.visible = false
	section.add_child(body)

	toggle.toggled.connect(func(pressed: bool):
		body.visible = pressed
		toggle.text = ("▼  " if pressed else "▶  ") + "%s — %s" % [title, subtitle])

	return section


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


func _build_fish_content() -> Control:
	# Per-species sub-tabs. Sliders write to GameData.fish_stat_overrides AND
	# patch every live fish of that species so changes are visible instantly.
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(0, 360)

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
	return v


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


func _build_spears_content() -> Control:
	# Per-spear sub-tabs: live sliders/spinboxes/checks for every base stat,
	# plus per-upgrade-key level spinners. Stats apply LIVE — no apply button.
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(0, 360)

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
	return v


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

	# Defaults from the .tres on disk so "(default X)" reads honestly even after
	# the user has tweaked the live instance.
	var fresh: SpearType = load("res://data/spears/%s.tres" % str(spear_id))
	var d_speed: float = float(fresh.speed_mult) if fresh else 1.0
	var d_reel: float = float(fresh.reel_speed_mult) if fresh else 1.0
	var d_radius: float = float(fresh.hit_radius_bonus) if fresh else 0.0
	var d_value: float = float(fresh.value_bonus) if fresh else 1.0
	var d_pierce: float = float(fresh.pierce_count) if fresh else 1.0
	var d_netr: float = float(fresh.net_radius) if fresh else 0.0
	var d_netmax: float = float(fresh.net_max_catch) if fresh else 1.0
	var d_crit: float = float(fresh.crit_chance) if fresh else 0.0

	v.add_child(_section_label("Base Stats"))
	_add_humanized_slider_row(v, "Spear speed", 0.3, 3.0, 0.05,
		func(): return t.speed_mult,
		func(val): t.speed_mult = val,
		_fmt_percent_delta, d_speed)
	_add_humanized_slider_row(v, "Reel speed", 0.3, 3.0, 0.05,
		func(): return t.reel_speed_mult,
		func(val): t.reel_speed_mult = val,
		_fmt_percent_delta, d_reel)
	_add_humanized_slider_row(v, "Hit radius bonus", -10.0, 50.0, 1.0,
		func(): return t.hit_radius_bonus,
		func(val): t.hit_radius_bonus = val,
		_fmt_pixels, d_radius)
	_add_humanized_slider_row(v, "Value bonus", 0.5, 5.0, 0.05,
		func(): return t.value_bonus,
		func(val): t.value_bonus = val,
		_fmt_value_bonus, d_value)
	_add_humanized_slider_row(v, "Pierces", 1.0, 6.0, 1.0,
		func(): return float(t.pierce_count),
		func(val): t.pierce_count = int(val),
		_fmt_count, d_pierce)
	_add_humanized_slider_row(v, "Net radius", 0.0, 200.0, 5.0,
		func(): return t.net_radius,
		func(val): t.net_radius = val,
		_fmt_pixels, d_netr)
	_add_humanized_slider_row(v, "Net max catch", 1.0, 15.0, 1.0,
		func(): return float(t.net_max_catch),
		func(val): t.net_max_catch = int(val),
		_fmt_count, d_netmax)
	_add_humanized_slider_row(v, "Crit chance", 0.0, 1.0, 0.01,
		func(): return t.crit_chance,
		func(val): t.crit_chance = val,
		_fmt_percent, d_crit)

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
	# Default formatter: 2-decimal raw float. For humanized labels (percent,
	# seconds, additive bonuses), use _add_humanized_slider_row.
	return _add_humanized_slider_row(parent, label_text, lo, hi, step, getter, setter,
		func(v: float): return "%.2f" % v, NAN)


# Humanized slider: label + slider + formatted live value + (optional) faded
# default. `format_value(v)` returns the user-facing string (e.g. "+20%", "30s").
# `default_v` (NAN to skip) is rendered to the right of the live readout in a
# dimmer color so a non-programmer can see how far they've drifted.
func _add_humanized_slider_row(parent: Node, label_text: String,
		lo: float, hi: float, step: float,
		getter: Callable, setter: Callable,
		format_value: Callable, default_v: float) -> HSlider:
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
	val_lbl.text = String(format_value.call(slider.value))
	val_lbl.custom_minimum_size = Vector2(80, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.6))
	row.add_child(val_lbl)

	if not is_nan(default_v):
		var def_lbl := Label.new()
		def_lbl.text = "(default %s)" % String(format_value.call(default_v))
		def_lbl.custom_minimum_size = Vector2(120, 0)
		def_lbl.add_theme_font_size_override("font_size", 11)
		def_lbl.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
		row.add_child(def_lbl)

	slider.value_changed.connect(func(v: float):
		setter.call(v)
		val_lbl.text = String(format_value.call(v))
		GameData.request_dev_tuning_save())
	return slider


# Spin row variant that shows a "(default X)" hint to its right, mirroring the
# humanized slider treatment. Used by Live tweaks where the values are integers
# (oxygen seconds, dive travel seconds, bag slots).
func _add_spin_row_with_default(parent: Node, label_text: String, unit: String,
		min_v: float, max_v: float, step: float, value: float,
		_default_v: float, hint: String, on_change: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(180, 0)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	row.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = value
	spin.suffix = unit
	spin.custom_minimum_size = Vector2(140, 0)
	spin.value_changed.connect(func(v: float):
		on_change.call(v)
		GameData.request_dev_tuning_save())
	row.add_child(spin)

	if hint != "":
		var hint_lbl := Label.new()
		hint_lbl.text = hint
		hint_lbl.custom_minimum_size = Vector2(180, 0)
		hint_lbl.add_theme_font_size_override("font_size", 11)
		hint_lbl.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
		row.add_child(hint_lbl)
	return spin


# --- Humanized formatters for slider rows ---

func _fmt_percent_delta(v: float) -> String:
	# 1.0 baseline + delta multiplier → "+X%" / "-X%". Used for *_mult fields.
	var pct: int = int(round((v - 1.0) * 100.0))
	if pct == 0: return "+0%"
	return "%+d%%" % pct


func _fmt_percent(v: float) -> String:
	# 0.0..1.0 raw probability → "X%". Used for crit_chance.
	return "%d%%" % int(round(v * 100.0))


func _fmt_pixels(v: float) -> String:
	return "%dpx" % int(round(v))


func _fmt_count(v: float) -> String:
	return "%d" % int(round(v))


func _fmt_value_bonus(v: float) -> String:
	# value_bonus is "additive multiplier on top of base value" — 1.0 means +0%.
	return _fmt_percent_delta(v)


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

func _on_scenario_pressed(entry: Dictionary) -> void:
	# "Empty scene" doesn't touch progression — it just suppresses spawns on the
	# next dive. Stage = -1 signals "leave state alone".
	var stage_idx: int = int(entry.get("stage", -1))
	var level: StringName = StringName(entry.get("level", &"none"))
	if stage_idx >= 0 and level != &"none":
		GameData.apply_stage_preset(stage_idx, level)
		var cash_override = entry.get("cash_override", null)
		if cash_override != null:
			GameData.cash = float(cash_override)
			GameData.cash_changed.emit(GameData.cash)

	# Extras: one-shot flags consumed by main.gd on the next UNDERWATER transition.
	GameData.dev_spawn_whale_on_dive = false
	GameData.dev_suppress_spawns_on_dive = false
	var extras: StringName = StringName(entry.get("extras", &""))
	if extras == &"spawn_whale":
		GameData.dev_spawn_whale_on_dive = true
	elif extras == &"no_spawns":
		GameData.dev_suppress_spawns_on_dive = true

	GameData.request_dev_tuning_save()
	_refresh_state_label()
	_refresh_game_tab_values()
	_show_toast("Scenario loaded: %s" % String(entry["label"]))
	close()


func _show_toast(text: String) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_label.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_label, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_interval(2.2)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.4)


# Wipes dev_tuning.json from disk AND restores all in-memory dev tunables to a
# vanilla state — including the live-tweak toggles. Does NOT touch progress.json.
func _on_reset_all_pressed() -> void:
	if FileAccess.file_exists(GameData.DEV_TUNING_PATH):
		DirAccess.remove_absolute(GameData.DEV_TUNING_PATH)
	GameData.dev_infinite_oxygen = false
	GameData.dev_skip_shop = false
	GameData.oxygen_capacity_override = -1.0
	GameData.bag_capacity_override = -1
	GameData.dive_travel_duration = 1.5
	GameData.fish_stat_overrides.clear()
	# Reset every live SpearType resource to its on-disk .tres baseline.
	_reset_all_spears_in_memory()
	# Clear scenario-extra flags too — they're part of "vanilla dev state".
	GameData.dev_spawn_whale_on_dive = false
	GameData.dev_suppress_spawns_on_dive = false
	_show_toast("Dev tuning reset to defaults")
	# Easiest visual refresh: close and reopen, which rebuilds the entire UI.
	if is_open():
		close()
		toggle()


func _on_reset_all_spears_pressed() -> void:
	_reset_all_spears_in_memory()
	GameData.request_dev_tuning_save()
	_show_toast("Spear stats reset")
	if is_open():
		close()
		toggle()


func _on_reset_all_fish_pressed() -> void:
	GameData.fish_stat_overrides.clear()
	GameData.request_dev_tuning_save()
	_show_toast("Fish overrides reset")
	if is_open():
		close()
		toggle()


func _reset_all_spears_in_memory() -> void:
	var fields: Array[StringName] = [
		&"speed_mult", &"reel_speed_mult", &"hit_radius_bonus",
		&"value_bonus", &"pierce_count", &"net_radius",
		&"net_max_catch", &"crit_chance", &"catches_medium",
		&"bypasses_defenses", &"twin_shot", &"perfect_strike",
		&"sonic_boom", &"lure_net",
	]
	for live in GameData.spear_types:
		var fresh: SpearType = load("res://data/spears/%s.tres" % str(live.id))
		if fresh == null:
			continue
		for prop in fields:
			live.set(prop, fresh.get(prop))


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


# --- Export ---

func _on_export_pressed(btn: Button) -> void:
	var snippet := _build_export_snippet()
	DisplayServer.clipboard_set(snippet)
	var orig := btn.text
	btn.text = "Copied ✓"
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(btn):
		btn.text = orig


func _build_export_snippet() -> String:
	var lines: PackedStringArray = []
	lines.append("## Dev Tuning Export")
	lines.append("*Generated from in-game dev panel*")
	lines.append("")
	# Game section
	lines.append("### Game")
	var ox_ov: float = GameData.oxygen_capacity_override
	lines.append("- Oxygen capacity (override): %s" % ("none" if ox_ov < 0.0 else str(ox_ov)))
	var bag_ov: int = GameData.bag_capacity_override
	lines.append("- Bag capacity (override): %s" % ("none" if bag_ov < 0 else str(bag_ov)))
	lines.append("- Dive travel duration: %.2f" % GameData.dive_travel_duration)
	lines.append("- Infinite oxygen: %s" % str(GameData.dev_infinite_oxygen))
	lines.append("- Skip shop: %s" % str(GameData.dev_skip_shop))
	lines.append("")
	# Spears section
	lines.append("### Spears")
	lines.append("")
	for s in GameData.spear_types:
		lines.append("**%s** (id `%s`)" % [s.display_name, str(s.id)])
		lines.append("| Field | Value | Default |")
		lines.append("|---|---|---|")
		var fresh: SpearType = load("res://data/spears/%s.tres" % str(s.id))
		for f in [&"speed_mult", &"reel_speed_mult", &"hit_radius_bonus",
				&"value_bonus", &"pierce_count", &"net_radius",
				&"net_max_catch", &"crit_chance", &"catches_medium",
				&"bypasses_defenses"]:
			var cur = s.get(f)
			var def = fresh.get(f) if fresh else cur
			lines.append("| %s | %s | %s |" % [str(f), str(cur), str(def)])
		# Current upgrade levels
		var lv_dict: Dictionary = GameData.spear_upgrade_levels.get(s.id, {})
		var lv_strs: PackedStringArray = []
		for k in lv_dict.keys():
			var lvl := int(lv_dict[k])
			if lvl > 0:
				lv_strs.append("%s=%d" % [str(k), lvl])
		var lv_line := "(none)" if lv_strs.is_empty() else ", ".join(lv_strs)
		lines.append("")
		lines.append("Upgrade levels: `%s`" % lv_line)
		lines.append("")
	# Fish overrides
	lines.append("### Fish overrides")
	if GameData.fish_stat_overrides.is_empty():
		lines.append("*None — all species at defaults.*")
	else:
		lines.append("| Species | Field | Override | Default |")
		lines.append("|---|---|---|---|")
		for species in GameData.fish_stat_overrides.keys():
			var ov: Dictionary = GameData.fish_stat_overrides[species]
			var defaults: Dictionary = _fish_defaults_for(species)
			for field in ov.keys():
				var cur = ov[field]
				var def = defaults.get(field, "?")
				lines.append("| %s | %s | %s | %s |" % [species, field, str(cur), str(def)])
	lines.append("")
	# Footer
	var zone_name: String = "—"
	var z = GameData.get_current_zone()
	if z != null:
		zone_name = z.display_name
	lines.append("### Cash: $%d · Zone: %s · Dive #: %d" % [int(GameData.cash), zone_name, GameData.dive_number])
	return "\n".join(lines)
