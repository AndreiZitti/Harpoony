extends CanvasLayer

# Bestiary / codex screen. Reads species data from GameData.species_list and
# the discovery state from GameData.discovered_species. Locked species render
# as dark silhouettes with a zone hint. Click a card to open a detail panel.
#
# Entry points (all call show_bestiary): MainMenu button, UpgradeShop button,
# GameMenu (pause) button.

signal closed

const COLS := 5
const CARD_SIZE := Vector2(170, 180)
const SIZE_LABELS := {
	&"small": "Small",
	&"medium": "Medium",
	&"large": "Large",
	&"trophy": "Trophy",
}
const SPEAR_LABELS := {
	&"normal": "Normal Spear",
	&"net": "Net",
	&"heavy": "Heavy Spear",
}

var _root: Control = null
var _detail_panel: Control = null


func _ready() -> void:
	layer = 85  # above MainMenu (80) so it covers + consumes input from any caller
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	GameData.species_discovered.connect(_on_species_discovered)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide_bestiary()
		get_viewport().set_input_as_handled()


func show_bestiary() -> void:
	_refresh()
	visible = true
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.2)


func hide_bestiary() -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func():
		visible = false
		closed.emit()
	)


func _on_species_discovered(_id: StringName) -> void:
	if visible:
		_refresh()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)


func _refresh() -> void:
	# Tear down previous content (header + grid) and rebuild from current state.
	for c in _root.get_children():
		if c is ColorRect:
			continue  # keep dim
		c.queue_free()

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	_root.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	margin.add_child(v)

	v.add_child(_build_header())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for s in GameData.get_all_species():
		grid.add_child(_build_card(s))


func _build_header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)

	var title := Label.new()
	title.text = "Bestiary"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(1.0, 0.93, 0.6))
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.14))
	title.add_theme_constant_override("outline_size", 6)
	h.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	var counter := Label.new()
	var total: int = GameData.get_all_species().size()
	var found: int = GameData.discovered_species.size()
	counter.text = "%d / %d discovered" % [found, total]
	counter.add_theme_font_size_override("font_size", 18)
	counter.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(counter)

	var close_btn := Button.new()
	close_btn.text = "Close (Esc)"
	close_btn.custom_minimum_size = Vector2(120, 36)
	close_btn.focus_mode = Control.FOCUS_NONE
	_style_button(close_btn, false)
	close_btn.pressed.connect(hide_bestiary)
	h.add_child(close_btn)

	return h


func _build_card(s: SpeciesData) -> Control:
	var discovered := GameData.is_species_discovered(s.id)

	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.14, 0.20, 0.95) if discovered else Color(0.06, 0.08, 0.12, 0.95)
	sb.border_color = Color(0.85, 0.78, 0.45, 0.7) if discovered else Color(0.30, 0.34, 0.42, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)

	# Thumbnail (procedural fish silhouette).
	var thumb := _make_thumbnail(s, discovered)
	v.add_child(thumb)

	# Name (or ???).
	var name_label := Label.new()
	name_label.text = s.display_name if discovered else "???"
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color",
		Color(1.0, 0.93, 0.6) if discovered else Color(0.55, 0.6, 0.7))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_label)

	# Zone hint (always shown — the locked-state nudge toward where to find it).
	var zone_label := Label.new()
	zone_label.text = _zone_display_name(s.found_in_zone)
	zone_label.add_theme_font_size_override("font_size", 11)
	zone_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(zone_label)

	# Click → detail panel (only meaningful for discovered species; locked cards
	# are inert beyond the zone hint).
	if discovered:
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_open_detail(s)
		)
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return card


# Procedural fish silhouette: ellipse body + tail triangle, tinted by species
# color (or solid dark for locked). Replace with a real Sprite2D + texture per
# species when art lands — the SpeciesData resource has room for a texture
# field whenever you want to extend it.
func _make_thumbnail(s: SpeciesData, discovered: bool) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(CARD_SIZE.x - 20, 90)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var draw := _ThumbnailDraw.new()
	draw.species_color = s.color if discovered else Color(0.10, 0.13, 0.18)
	draw.size_class = s.size_class
	draw.discovered = discovered
	draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(draw)
	return box


func _zone_display_name(zone_id: StringName) -> String:
	for z in GameData.zones:
		if z.id == zone_id:
			return z.display_name
	return "Unknown waters"


func _open_detail(s: SpeciesData) -> void:
	if _detail_panel and is_instance_valid(_detail_panel):
		_detail_panel.queue_free()
		_detail_panel = null

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = -240
	panel.offset_bottom = 240
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.17, 0.98)
	sb.border_color = Color(0.85, 0.78, 0.45, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)
	_detail_panel = panel

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	# Header row — name + close.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	v.add_child(header)

	var name_label := Label.new()
	name_label.text = s.display_name
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.6))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(96, 32)
	close.focus_mode = Control.FOCUS_NONE
	_style_button(close, false)
	close.pressed.connect(func():
		panel.queue_free()
		_detail_panel = null
	)
	header.add_child(close)

	# Big thumbnail row.
	var big_thumb_box := Control.new()
	big_thumb_box.custom_minimum_size = Vector2(0, 140)
	big_thumb_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(big_thumb_box)

	var big_draw := _ThumbnailDraw.new()
	big_draw.species_color = s.color
	big_draw.size_class = s.size_class
	big_draw.discovered = true
	big_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	big_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_thumb_box.add_child(big_draw)

	# Description.
	var desc := Label.new()
	desc.text = s.description
	desc.add_theme_font_size_override("font_size", 15)
	desc.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)

	# Stats row: zone, value, size, recommended spear.
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 18)
	stats.add_theme_constant_override("v_separation", 4)
	v.add_child(stats)

	_add_stat(stats, "Found in:", _zone_display_name(s.found_in_zone))
	_add_stat(stats, "Cash value:", "$%d" % s.base_value)
	_add_stat(stats, "Size:", SIZE_LABELS.get(s.size_class, str(s.size_class)))
	_add_stat(stats, "Best spear:", SPEAR_LABELS.get(s.recommended_spear, str(s.recommended_spear)))

	# Behavior notes.
	if s.behavior_notes != "":
		var notes := Label.new()
		notes.text = s.behavior_notes
		notes.add_theme_font_size_override("font_size", 13)
		notes.add_theme_color_override("font_color", Color(0.78, 0.85, 0.95))
		notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(notes)


func _add_stat(grid: GridContainer, label_text: String, value_text: String) -> void:
	var l := Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
	grid.add_child(l)

	var v := Label.new()
	v.text = value_text
	v.add_theme_font_size_override("font_size", 13)
	v.add_theme_color_override("font_color", Color(1.0, 0.93, 0.6))
	grid.add_child(v)


func _style_button(btn: Button, primary: bool) -> void:
	btn.add_theme_font_size_override("font_size", 14)
	var normal_sb := StyleBoxFlat.new()
	var hover_sb := StyleBoxFlat.new()
	var pressed_sb := StyleBoxFlat.new()
	if primary:
		normal_sb.bg_color = Color(1.0, 0.88, 0.45, 0.95)
		hover_sb.bg_color = Color(1.0, 0.95, 0.6, 1.0)
		pressed_sb.bg_color = Color(0.85, 0.72, 0.32, 1.0)
		btn.add_theme_color_override("font_color", Color(0.08, 0.10, 0.18))
	else:
		normal_sb.bg_color = Color(0.05, 0.08, 0.14, 0.6)
		hover_sb.bg_color = Color(0.08, 0.14, 0.22, 0.85)
		pressed_sb.bg_color = Color(0.04, 0.06, 0.10, 0.95)
		btn.add_theme_color_override("font_color", Color(1.0, 0.93, 0.6))
	for sb in [normal_sb, hover_sb, pressed_sb]:
		sb.set_corner_radius_all(5)
		sb.set_border_width_all(1)
		sb.border_color = Color(1.0, 0.93, 0.6, 0.7)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	btn.add_theme_stylebox_override("focus", normal_sb)


# Procedural fish silhouette: oval body + tail triangle. Width scales with
# size_class so a Trophy reads bigger than a Small even in the same card.
class _ThumbnailDraw extends Control:
	var species_color: Color = Color.WHITE
	var size_class: StringName = &"medium"
	var discovered: bool = true

	func _draw() -> void:
		var center := size * 0.5
		var scale_factor: float = 1.0
		match size_class:
			&"small": scale_factor = 0.7
			&"medium": scale_factor = 0.9
			&"large": scale_factor = 1.1
			&"trophy": scale_factor = 1.3
		var body_w: float = min(size.x, size.y * 1.6) * 0.55 * scale_factor
		var body_h: float = body_w * 0.45
		var body_color: Color = species_color
		var outline_color := Color(0.05, 0.07, 0.14, 0.9)
		# Body — filled ellipse (approx via polygon ring).
		_draw_ellipse(center, body_w * 0.5, body_h * 0.5, body_color)
		_draw_ellipse_outline(center, body_w * 0.5, body_h * 0.5, outline_color)
		# Tail — triangle off the right side.
		var tail_pts := PackedVector2Array([
			Vector2(center.x - body_w * 0.4, center.y),
			Vector2(center.x - body_w * 0.6, center.y - body_h * 0.55),
			Vector2(center.x - body_w * 0.6, center.y + body_h * 0.55),
		])
		draw_colored_polygon(tail_pts, body_color)
		draw_polyline(PackedVector2Array([tail_pts[0], tail_pts[1], tail_pts[2], tail_pts[0]]), outline_color, 1.5)
		# Eye — small white dot, only when discovered (locked = pure silhouette).
		if discovered:
			var eye_pos := Vector2(center.x + body_w * 0.25, center.y - body_h * 0.1)
			draw_circle(eye_pos, 2.0, Color(1, 1, 1, 0.95))
			draw_circle(eye_pos, 1.0, Color(0.05, 0.07, 0.14))
		# Locked indicator — a small lighter dot near the body so the silhouette
		# reads as deliberately obscured rather than just an empty fish shape.
		if not discovered:
			var glyph_pos := Vector2(center.x, center.y - body_h * 0.2)
			draw_circle(glyph_pos, 5.0, Color(0.55, 0.6, 0.7, 0.6))

	func _draw_ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		var segs := 32
		for i in segs:
			var a := TAU * float(i) / float(segs)
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, col)

	func _draw_ellipse_outline(c: Vector2, rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		var segs := 32
		for i in segs + 1:
			var a := TAU * float(i) / float(segs)
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_polyline(pts, col, 1.5)
