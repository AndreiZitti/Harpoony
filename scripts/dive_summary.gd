extends CanvasLayer

# Post-dive summary screen — shown between resurface and the upgrade shop.
# Reads GameData.last_dive_* fields for the current dive, plus run_history for
# the History view. Emits `continue_requested` when the player clicks Continue;
# main.gd hooks that to open the shop (or skip-shop, in dev mode).

signal continue_requested

const SPECIES_DISPLAY := {
	"sardine": "Sardine",
	"pufferfish": "Pufferfish",
	"mahimahi": "Mahi-mahi",
	"squid": "Squid",
	"lanternfish": "Lanternfish",
	"anglerfish": "Anglerfish",
	"marlin": "Marlin",
	"grouper": "Grouper",
	"tuna": "Tuna",
	"whitewhale": "White Whale",
	"bonito": "Bonito",
	"blockfish": "Blockfish",
	"triggerfish": "Triggerfish",
}

var _root: Control
var _summary_panel: PanelContainer
var _history_panel: PanelContainer
var _is_visible: bool = false


func _ready() -> void:
	# Above shop (layer 10), below pause menu (layer 60) so ESC still works.
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Dim backdrop.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	_summary_panel = _build_summary_panel()
	_root.add_child(_summary_panel)

	_history_panel = _build_history_panel()
	_root.add_child(_history_panel)
	_history_panel.visible = false


func _make_panel(min_size: Vector2) -> PanelContainer:
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.custom_minimum_size = min_size
	card.position = -min_size * 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.10, 0.16, 0.96)
	sb.border_color = Color(0.45, 0.65, 0.85, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", sb)
	return card


func _build_summary_panel() -> PanelContainer:
	var card := _make_panel(Vector2(560, 520))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.name = "SummaryVBox"
	card.add_child(v)
	return card


func _build_history_panel() -> PanelContainer:
	var card := _make_panel(Vector2(620, 560))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.name = "HistoryVBox"
	card.add_child(v)
	return card


# --- Public entry point ---

func show_summary() -> void:
	if _is_visible:
		return
	# Sanity: finish_dive() must have run before the summary opens — that is
	# what populates last_dive_*. If a future refactor swaps the call order, the
	# screen would show the previous dive's totals (or empty defaults). Catch
	# that during development.
	assert(GameData.dive_state == GameData.DiveState.SURFACE,
		"DiveSummary.show_summary called before finish_dive transitioned to SURFACE")
	_is_visible = true
	_populate_summary()
	_summary_panel.visible = true
	_history_panel.visible = false
	_root.visible = true
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _hide() -> void:
	if not _is_visible:
		return
	_is_visible = false
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): _root.visible = false)


# --- Summary content ---

func _populate_summary() -> void:
	var v: VBoxContainer = _summary_panel.get_node("SummaryVBox")
	for c in v.get_children():
		c.queue_free()

	var zone_name := _zone_display_name(GameData.last_dive_zone_id)
	var title := Label.new()
	title.text = "Dive %d · %s" % [GameData.dive_number, zone_name]
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var totals := Label.new()
	var dur_s := int(round(GameData.last_dive_duration))
	totals.text = "%d fish · $%d earned · %ds underwater" % [
		GameData.last_dive_fish, GameData.last_dive_cash, dur_s
	]
	totals.add_theme_font_size_override("font_size", 13)
	totals.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
	totals.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(totals)

	v.add_child(HSeparator.new())

	# Spear stats
	var spears_lbl := Label.new()
	spears_lbl.text = "Spears"
	spears_lbl.add_theme_font_size_override("font_size", 14)
	spears_lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	v.add_child(spears_lbl)

	v.add_child(_build_spear_table(GameData.last_dive_shots_by_spear, GameData.last_dive_hits_by_spear))

	v.add_child(HSeparator.new())

	# Fish catches
	var fish_lbl := Label.new()
	fish_lbl.text = "Catches"
	fish_lbl.add_theme_font_size_override("font_size", 14)
	fish_lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	v.add_child(fish_lbl)

	v.add_child(_build_fish_table(GameData.last_dive_catches_by_fish))

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	v.add_child(btn_row)

	var history_btn := Button.new()
	history_btn.text = "History (%d)" % GameData.run_history.size()
	history_btn.custom_minimum_size = Vector2(140, 38)
	history_btn.pressed.connect(_show_history)
	btn_row.add_child(history_btn)

	var continue_btn := Button.new()
	continue_btn.text = "Continue"
	continue_btn.custom_minimum_size = Vector2(180, 38)
	continue_btn.pressed.connect(_on_continue_pressed)
	btn_row.add_child(continue_btn)


func _build_spear_table(shots: Dictionary, hits: Dictionary) -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)

	# Header
	for header in ["Spear", "Shots", "Hits", "Accuracy"]:
		grid.add_child(_make_cell(header, true))

	# Iterate spear types in canonical order so layout is stable.
	var any_row := false
	for t in GameData.spear_types:
		var key := str(t.id)
		var s_count: int = int(shots.get(key, 0))
		var h_count: int = int(hits.get(key, 0))
		if s_count == 0 and h_count == 0:
			continue
		any_row = true
		grid.add_child(_make_cell(t.display_name if t.display_name != "" else key, false))
		grid.add_child(_make_cell(str(s_count), false))
		grid.add_child(_make_cell(str(h_count), false))
		var acc_str := "—"
		if s_count > 0:
			acc_str = "%d%%" % int(round(100.0 * h_count / s_count))
		grid.add_child(_make_cell(acc_str, false))
	if not any_row:
		var none := Label.new()
		none.text = "No shots fired."
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
		return none
	return grid


func _build_fish_table(catches: Dictionary) -> Control:
	if catches.is_empty():
		var none := Label.new()
		none.text = "No catches this dive — the fish got lucky."
		none.add_theme_font_size_override("font_size", 13)
		none.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Italic via theme is awkward in pure script; the centered + slightly
		# softer color carries the "this is a flavour line, not data" feel.
		return none

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)

	for header in ["Fish", "Count", "Earned"]:
		grid.add_child(_make_cell(header, true))

	# Sort by total value desc so the most lucrative catch is on top.
	var keys: Array = catches.keys()
	keys.sort_custom(func(a, b):
		return int(catches[a].get("value", 0)) > int(catches[b].get("value", 0)))

	for key in keys:
		var entry: Dictionary = catches[key]
		grid.add_child(_make_cell(_species_display(key), false))
		grid.add_child(_make_cell(str(int(entry.get("count", 0))), false))
		grid.add_child(_make_cell("$%d" % int(entry.get("value", 0)), false))
	return grid


func _make_cell(text: String, header: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12 if not header else 11)
	if header:
		lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	else:
		lbl.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	return lbl


# --- History view ---

func _show_history() -> void:
	_populate_history()
	_summary_panel.visible = false
	_history_panel.visible = true


func _hide_history() -> void:
	_history_panel.visible = false
	_summary_panel.visible = true


func _populate_history() -> void:
	var v: VBoxContainer = _history_panel.get_node("HistoryVBox")
	for c in v.get_children():
		c.queue_free()

	var title := Label.new()
	title.text = "Run History"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var subtitle := Label.new()
	var total_cash := 0
	var total_fish := 0
	for e in GameData.run_history:
		total_cash += int(e.get("cash", 0))
		total_fish += int(e.get("fish", 0))
	subtitle.text = "%d dives · %d fish · $%d total" % [GameData.run_history.size(), total_fish, total_cash]
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(subtitle)

	v.add_child(HSeparator.new())

	# Scrollable list — most recent first.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 380)
	v.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	if GameData.run_history.is_empty():
		var none := Label.new()
		none.text = "No dives logged yet."
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
		list.add_child(none)
	else:
		var entries := GameData.run_history.duplicate()
		entries.reverse()
		for e in entries:
			list.add_child(_build_history_row(e))

	# Back button
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(back_row)
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(140, 36)
	back_btn.pressed.connect(_hide_history)
	back_row.add_child(back_btn)


func _build_history_row(entry: Dictionary) -> Control:
	# Click anywhere on the row to expand details. Implemented as a Button so we
	# get free hover feedback and keyboard focus.
	var btn := Button.new()
	btn.toggle_mode = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 28)
	btn.add_theme_font_size_override("font_size", 12)
	var dive_n := int(entry.get("dive_n", 0))
	var zone_id := str(entry.get("zone_id", ""))
	var cash := int(entry.get("cash", 0))
	var fish := int(entry.get("fish", 0))
	var shots := int(entry.get("shots", 0))
	var hits := 0
	for k in (entry.get("hits_by_spear", {}) as Dictionary).keys():
		hits += int(entry["hits_by_spear"][k])
	var acc_str := "—"
	if shots > 0:
		acc_str = "%d%%" % int(round(100.0 * hits / shots))
	btn.text = "Dive %d · %s · $%d · %d fish · %s acc" % [
		dive_n, _zone_display_name(zone_id), cash, fish, acc_str
	]

	var holder := VBoxContainer.new()
	holder.add_child(btn)
	holder.add_theme_constant_override("separation", 2)

	var detail := PanelContainer.new()
	detail.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.11, 0.6)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	detail.add_theme_stylebox_override("panel", sb)
	holder.add_child(detail)

	var detail_v := VBoxContainer.new()
	detail_v.add_theme_constant_override("separation", 6)
	detail.add_child(detail_v)

	detail_v.add_child(_build_spear_table(
		entry.get("shots_by_spear", {}),
		entry.get("hits_by_spear", {})))
	detail_v.add_child(HSeparator.new())
	detail_v.add_child(_build_fish_table(entry.get("catches_by_fish", {})))

	btn.toggled.connect(func(pressed): detail.visible = pressed)
	return holder


# --- Helpers ---

func _zone_display_name(zone_id: String) -> String:
	for z in GameData.zones:
		if str(z.id) == zone_id:
			return z.display_name if z.display_name != "" else zone_id
	if zone_id == "":
		return "—"
	return zone_id


func _species_display(species_id: String) -> String:
	return SPECIES_DISPLAY.get(species_id, species_id.capitalize())


func _on_continue_pressed() -> void:
	# Press feedback: panel slides up 8px and desaturates while fading out, so
	# the transition reads as intentional rather than instant. Total ~200ms.
	var panel := _summary_panel
	if panel:
		var start_y := panel.position.y
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(panel, "position:y", start_y - 8, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "modulate", Color(0.7, 0.7, 0.7, 1.0), 0.18)
	_hide()
	# Defer the signal one frame so the slide reads visually before the next
	# scene takes over.
	await get_tree().create_timer(0.2).timeout
	continue_requested.emit()
