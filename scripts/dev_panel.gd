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
	_build_placeholder_tab("Spears", "Phase 2 — sliders for all spear base stats. Coming soon.")
	_build_placeholder_tab("Fish", "Phase 3 — sliders for fish base values, speed, hit radius. Coming soon.")
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
	spin.value_changed.connect(on_change)
	row.add_child(spin)
	return spin


func _add_check_row(parent: Node, label_text: String, initial: bool,
		on_toggle: Callable) -> CheckBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var cb := CheckBox.new()
	cb.text = label_text
	cb.button_pressed = initial
	cb.add_theme_font_size_override("font_size", 13)
	cb.toggled.connect(on_toggle)
	row.add_child(cb)
	return cb


# --- Handlers ---

func _on_preset_pressed(stage: int, level: StringName) -> void:
	GameData.apply_stage_preset(stage, level)
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
