extends CanvasLayer

signal next_epoch_pressed

var root_control: Control
var tree_canvas: Control
var compute_display: Label
var tooltip_panel: PanelContainer
var tooltip_name: Label
var tooltip_desc: Label
var tooltip_stats: Label
var tooltip_effect: Label

var hovered_node: String = ""

# Visual config — circular nodes
const NODE_RADIUS = 25.0

# Node icons displayed inside circles
var node_icons: Dictionary = {
	"nodes": "⬡",
	"layers": "≡",
	"dataset_size": "▦",
	"data_quality": "◆",
	"cursor_size": "◎",
	"label_speed": "⚡",
	"activation_func": "ƒ",
	"learning_rate": "α",
	"aug_chance": "⊕",
	"aug_quality": "✦",
	"batch_label": "⊞",
	"training_time": "⏱",
	"transfer_learning": "⟳",
}

var current_layout: Dictionary = {"positions": {}, "edges": []}

var node_appear_timers: Dictionary = {}
const NODE_APPEAR_DURATION = 0.8

var cheats_enabled: bool = false


func _ready() -> void:
	_build_ui()
	_refresh_layout()
	hide_shop()
	GameData.stage_changed.connect(_on_stage_changed)


func _build_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	# Dark overlay
	var overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.8)
	root_control.add_child(overlay)

	# Tree canvas — custom draw
	tree_canvas = Control.new()
	tree_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree_canvas.draw.connect(_draw_tree)
	tree_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	tree_canvas.gui_input.connect(_on_tree_input)
	root_control.add_child(tree_canvas)

	# Header
	var header_margin = MarginContainer.new()
	header_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header_margin.offset_bottom = 80
	header_margin.add_theme_constant_override("margin_top", 20)
	root_control.add_child(header_margin)

	var header_vbox = VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 2)
	header_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	header_margin.add_child(header_vbox)

	compute_display = Label.new()
	compute_display.add_theme_font_size_override("font_size", 22)
	compute_display.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	compute_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_vbox.add_child(compute_display)

	var round_label = Label.new()
	round_label.name = "RoundLabel"
	round_label.add_theme_font_size_override("font_size", 13)
	round_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55))
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_vbox.add_child(round_label)

	# Tooltip
	_build_tooltip()

	# Bottom bar
	var bottom_margin = MarginContainer.new()
	bottom_margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_margin.offset_top = -70
	bottom_margin.add_theme_constant_override("margin_left", 30)
	bottom_margin.add_theme_constant_override("margin_right", 30)
	bottom_margin.add_theme_constant_override("margin_bottom", 16)
	root_control.add_child(bottom_margin)

	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 20)
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_margin.add_child(bottom_hbox)

	var cheat_btn = CheckButton.new()
	cheat_btn.text = "CHEATS"
	cheat_btn.add_theme_font_size_override("font_size", 12)
	cheat_btn.add_theme_color_override("font_color", Color(0.45, 0.3, 0.3))
	cheat_btn.toggled.connect(_on_cheat_toggled)
	cheat_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_hbox.add_child(cheat_btn)

	var next_btn = Button.new()
	next_btn.text = "START TRAINING  >"
	next_btn.custom_minimum_size = Vector2(220, 48)
	next_btn.add_theme_font_size_override("font_size", 18)
	next_btn.add_theme_color_override("font_color", Color.WHITE)
	next_btn.pressed.connect(_on_next_epoch)

	var btn_s = StyleBoxFlat.new()
	btn_s.bg_color = Color(0.12, 0.35, 0.75)
	btn_s.set_corner_radius_all(10)
	btn_s.set_content_margin_all(10)
	next_btn.add_theme_stylebox_override("normal", btn_s)

	var btn_h = StyleBoxFlat.new()
	btn_h.bg_color = Color(0.18, 0.45, 0.88)
	btn_h.set_corner_radius_all(10)
	btn_h.set_content_margin_all(10)
	next_btn.add_theme_stylebox_override("hover", btn_h)

	var btn_p = StyleBoxFlat.new()
	btn_p.bg_color = Color(0.08, 0.25, 0.6)
	btn_p.set_corner_radius_all(10)
	btn_p.set_content_margin_all(10)
	next_btn.add_theme_stylebox_override("pressed", btn_p)

	bottom_hbox.add_child(next_btn)


func _build_tooltip() -> void:
	tooltip_panel = PanelContainer.new()
	tooltip_panel.visible = false
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.custom_minimum_size = Vector2(220, 0)
	tooltip_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tooltip_panel.size = Vector2(220, 0)
	tooltip_panel.reset_size()

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	style.border_color = Color(0.3, 0.6, 1.0, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	tooltip_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.add_child(vbox)

	tooltip_name = Label.new()
	tooltip_name.add_theme_font_size_override("font_size", 15)
	tooltip_name.add_theme_color_override("font_color", Color.WHITE)
	tooltip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(tooltip_name)

	tooltip_desc = Label.new()
	tooltip_desc.add_theme_font_size_override("font_size", 11)
	tooltip_desc.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(tooltip_desc)

	tooltip_effect = Label.new()
	tooltip_effect.add_theme_font_size_override("font_size", 11)
	tooltip_effect.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))
	tooltip_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(tooltip_effect)

	tooltip_stats = Label.new()
	tooltip_stats.add_theme_font_size_override("font_size", 12)
	tooltip_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(tooltip_stats)

	root_control.add_child(tooltip_panel)


# --- State helpers ---

func _get_upgrade_state(key: String) -> String:
	var level = GameData.upgrade_levels[key]
	var max_level = GameData.upgrades[key]["max_level"]

	if not GameData.is_upgrade_unlocked(key):
		return "locked"
	if level >= max_level:
		return "maxed"
	if level > 0:
		if GameData.can_buy_upgrade(key):
			return "owned_affordable"
		return "owned"
	if GameData.can_buy_upgrade(key):
		return "affordable"
	return "available"


func _get_screen_center() -> Vector2:
	return tree_canvas.size / 2.0


func _get_node_screen_pos(key: String) -> Vector2:
	return _get_screen_center() + current_layout["positions"][key]


# --- Process ---

func _process(_delta: float) -> void:
	if not root_control.visible:
		return

	var mouse_pos = tree_canvas.get_local_mouse_position()
	var new_hover = ""

	for key in current_layout["positions"]:
		if key == "root":
			continue
		if key not in GameData.upgrades:
			continue
		var pos = _get_node_screen_pos(key)
		if mouse_pos.distance_to(pos) <= NODE_RADIUS:
			new_hover = key

	if new_hover != hovered_node:
		hovered_node = new_hover
		_update_tooltip()

	for key in node_appear_timers.keys():
		node_appear_timers[key] += _delta
		if node_appear_timers[key] >= NODE_APPEAR_DURATION:
			node_appear_timers.erase(key)

	tree_canvas.queue_redraw()


# --- Tooltip ---

func _update_tooltip() -> void:
	if hovered_node == "":
		tooltip_panel.visible = false
		return

	var upgrade = GameData.upgrades[hovered_node]
	var level = GameData.upgrade_levels[hovered_node]
	var max_level = upgrade["max_level"]
	var state = _get_upgrade_state(hovered_node)

	tooltip_name.text = "%s   Lv %d/%d" % [upgrade["name"], level, max_level]
	tooltip_desc.text = upgrade["description"]

	# Effect preview
	if state == "locked":
		tooltip_effect.text = ""
		tooltip_effect.visible = false
	else:
		var previews = GameData.get_effect_preview(hovered_node)
		tooltip_effect.text = "\n".join(previews)
		tooltip_effect.visible = true
		if state == "maxed":
			tooltip_effect.add_theme_color_override("font_color", Color(0.5, 0.85, 0.3))
		else:
			tooltip_effect.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))

	# Stats line (cost or status)
	if state == "locked":
		var prereq = GameData.upgrade_prerequisites[hovered_node]
		if prereq != "":
			var prereq_name = GameData.upgrades[prereq]["name"]
			tooltip_stats.text = "Requires: " + prereq_name
		else:
			tooltip_stats.text = "Locked"
		tooltip_stats.add_theme_color_override("font_color", Color(0.6, 0.4, 0.3))
	elif state == "maxed":
		tooltip_stats.text = "MAXED"
		tooltip_stats.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	else:
		var cost = upgrade["costs"][level]
		tooltip_stats.text = "Cost: %d CP" % cost
		if GameData.can_buy_upgrade(hovered_node):
			tooltip_stats.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		else:
			tooltip_stats.add_theme_color_override("font_color", Color(0.7, 0.35, 0.3))

	tooltip_panel.visible = true
	tooltip_panel.reset_size()

	# Position tooltip near hovered node
	var node_pos = _get_node_screen_pos(hovered_node)
	var tip_pos = node_pos + Vector2(NODE_RADIUS + 14, -20)

	var tip_size = tooltip_panel.size
	if tip_pos.x + tip_size.x > tree_canvas.size.x - 20:
		tip_pos.x = node_pos.x - NODE_RADIUS - tip_size.x - 14
	if tip_pos.y < 80:
		tip_pos.y = 80
	if tip_pos.y + tip_size.y > tree_canvas.size.y - 80:
		tip_pos.y = tree_canvas.size.y - 80 - tip_size.y

	tooltip_panel.position = tip_pos


# --- Input ---

func _on_tree_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if hovered_node != "":
				_try_buy(hovered_node)


func _try_buy(key: String) -> void:
	if GameData.buy_upgrade(key):
		if cheats_enabled:
			GameData.cash = 999999999
			GameData.cash_changed.emit(GameData.cash)
		_update_ui()


# --- Drawing ---

func _draw_tree() -> void:
	var font = ThemeDB.fallback_font
	var time = Time.get_ticks_msec() / 1000.0

	# 1. Draw edges
	for edge in current_layout["edges"]:
		_draw_edge(edge[0], edge[1], time)

	# 2. Draw root node (small decorative circle)
	if "root" in current_layout["positions"]:
		var root_pos = _get_node_screen_pos("root")
		tree_canvas.draw_circle(root_pos, 12.0, Color(0.15, 0.2, 0.35, 0.9))
		tree_canvas.draw_arc(root_pos, 12.0, 0, TAU, 32, Color(0.3, 0.5, 0.8, 0.6), 1.5)
		var r_text = "R"
		var r_size = font.get_string_size(r_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		tree_canvas.draw_string(font, root_pos - Vector2(r_size.x / 2.0, -4), r_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.7, 1.0, 0.8))

	# 3. Draw upgrade nodes
	for key in current_layout["positions"]:
		if key != "root":
			_draw_node_circle(key, font, time)


func _draw_edge(from_key: String, to_key: String, time: float) -> void:
	var from_pos = _get_node_screen_pos(from_key)
	var to_pos = _get_node_screen_pos(to_key)

	var line_alpha = 0.15
	var line_width = 1.5
	var is_dashed = false

	if to_key in GameData.upgrades:
		var state = _get_upgrade_state(to_key)
		match state:
			"locked":
				line_alpha = 0.1
				line_width = 1.0
				is_dashed = true
			"available":
				line_alpha = 0.25
				line_width = 1.5
			"affordable":
				line_alpha = 0.5
				line_width = 2.0
			"owned", "owned_affordable":
				line_alpha = 0.6
				line_width = 2.0
			"maxed":
				line_alpha = 0.7
				line_width = 2.5
	else:
		line_alpha = 0.3

	var line_color = Color(0.3, 0.5, 0.8, line_alpha)

	# Fade edge during node appearance
	if to_key in node_appear_timers:
		var edge_progress = clampf(node_appear_timers[to_key] / NODE_APPEAR_DURATION, 0.0, 1.0)
		line_color.a *= edge_progress

	if is_dashed:
		var direction = (to_pos - from_pos)
		var length = direction.length()
		var norm = direction / length
		var dash_len = 6.0
		var gap_len = 4.0
		var d = 0.0
		while d < length:
			var seg_start = from_pos + norm * d
			var seg_end = from_pos + norm * minf(d + dash_len, length)
			tree_canvas.draw_line(seg_start, seg_end, line_color, line_width)
			d += dash_len + gap_len
	else:
		tree_canvas.draw_line(from_pos, to_pos, line_color, line_width)

	# Glow on bright edges
	if line_alpha > 0.4:
		var glow = 0.03 + sin(time * 1.5) * 0.02
		tree_canvas.draw_line(from_pos, to_pos, Color(0.4, 0.6, 1.0, glow), 5.0)


func _draw_node_circle(key: String, font: Font, time: float) -> void:
	if key not in GameData.upgrades:
		return
	var pos = _get_node_screen_pos(key)
	var upgrade = GameData.upgrades[key]
	var level = GameData.upgrade_levels[key]
	var max_level = upgrade["max_level"]
	var state = _get_upgrade_state(key)
	var is_hover = key == hovered_node

	# Appear animation
	var appear_progress = 1.0
	if key in node_appear_timers:
		appear_progress = clampf(node_appear_timers[key] / NODE_APPEAR_DURATION, 0.0, 1.0)

	var draw_radius = NODE_RADIUS * (0.5 + 0.5 * appear_progress)

	# Colors based on state
	var fill_color: Color
	var ring_color: Color
	var name_color: Color
	var cost_color: Color

	match state:
		"locked":
			fill_color = Color(0.08, 0.08, 0.1, 0.5)
			ring_color = Color(0.15, 0.15, 0.2, 0.0)
			name_color = Color(0.3, 0.3, 0.38)
			cost_color = Color(0.0, 0.0, 0.0, 0.0)
		"available":
			fill_color = Color(0.1, 0.12, 0.2, 0.9)
			ring_color = Color(0.25, 0.3, 0.5, 0.4)
			name_color = Color(0.5, 0.5, 0.6)
			cost_color = Color(0.6, 0.3, 0.3)
		"affordable":
			fill_color = Color(0.12, 0.15, 0.28, 0.95)
			ring_color = Color(0.3, 0.5, 0.9, 0.7)
			name_color = Color(0.8, 0.85, 1.0)
			cost_color = Color(0.3, 1.0, 0.4)
		"owned":
			fill_color = Color(0.15, 0.2, 0.35, 0.95)
			ring_color = Color(0.3, 0.55, 1.0, 0.6)
			name_color = Color.WHITE
			cost_color = Color(0.6, 0.3, 0.3)
		"owned_affordable":
			fill_color = Color(0.15, 0.2, 0.35, 0.95)
			ring_color = Color(0.3, 0.55, 1.0, 0.6)
			name_color = Color.WHITE
			cost_color = Color(0.3, 1.0, 0.4)
		"maxed":
			fill_color = Color(0.2, 0.35, 0.25, 0.95)
			ring_color = Color(0.3, 0.9, 0.7, 0.7)
			name_color = Color(0.7, 1.0, 0.6)
			cost_color = Color(0.5, 0.85, 0.3)

	# Hover effect
	if is_hover and state != "locked":
		fill_color = fill_color.lightened(0.12)
		ring_color.a = minf(ring_color.a + 0.25, 1.0)

	# Appear fade
	if appear_progress < 1.0:
		fill_color.a *= appear_progress
		ring_color.a *= appear_progress
		name_color.a *= appear_progress
		cost_color.a *= appear_progress

	# Pulsing glow for affordable nodes
	if state in ["affordable", "owned_affordable"]:
		var pulse = (sin(time * 3.0) + 1.0) / 2.0
		var glow_r = draw_radius + 4 + pulse * 4
		tree_canvas.draw_circle(pos, glow_r, Color(0.3, 0.6, 1.0, 0.06 + pulse * 0.05))

	# Fill circle
	tree_canvas.draw_circle(pos, draw_radius, fill_color)

	# Outer ring (thin border)
	if ring_color.a > 0.01:
		tree_canvas.draw_arc(pos, draw_radius, 0, TAU, 32, ring_color, 1.5)

	# Radial level arc — progress ring
	if level > 0 and state != "locked":
		var arc_angle = (float(level) / float(max_level)) * TAU
		var start_angle = -PI / 2.0  # start from top
		var arc_color = ring_color.lightened(0.2)
		if state == "maxed":
			arc_color = Color(0.3, 0.9, 0.7, 0.8)
		tree_canvas.draw_arc(pos, draw_radius + 3, start_angle, start_angle + arc_angle, 32, arc_color, 2.5)

	# Abbreviation inside circle
	var abbr = node_icons.get(key, "?")
	var abbr_fs = 16
	var abbr_size = font.get_string_size(abbr, HORIZONTAL_ALIGNMENT_LEFT, -1, abbr_fs)
	var abbr_pos = Vector2(pos.x - abbr_size.x / 2.0, pos.y + 5)
	tree_canvas.draw_string(font, abbr_pos, abbr, HORIZONTAL_ALIGNMENT_LEFT, -1, abbr_fs, name_color)

	# Name below circle
	var name_text = upgrade["name"]
	var name_fs = 11
	var name_size = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs)
	var name_pos = Vector2(pos.x - name_size.x / 2.0, pos.y + draw_radius + 14)
	tree_canvas.draw_string(font, name_pos, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs, name_color)

	# Cost below name
	var cost_text = ""
	if state == "maxed":
		cost_text = "MAX"
		cost_color = Color(0.5, 0.85, 0.3)
	elif state != "locked":
		var cost = GameData.get_upgrade_cost(key)
		if cost > 0:
			cost_text = "%d CP" % cost
	if cost_text != "":
		var cost_fs = 10
		var cost_size = font.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, cost_fs)
		var cost_pos = Vector2(pos.x - cost_size.x / 2.0, pos.y + draw_radius + 26)
		tree_canvas.draw_string(font, cost_pos, cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, cost_fs, cost_color)


# --- Layout ---

func _get_tree_layout() -> Dictionary:
	var positions: Dictionary = {}
	var edges: Array = []

	# Root at center
	positions["root"] = Vector2(0, 0)

	# Ring 1 — Stage 1 upgrades, ~130px from center
	var ring1_r = 130.0
	positions["nodes"] = Vector2(ring1_r, 0).rotated(deg_to_rad(250))
	positions["layers"] = Vector2(ring1_r, 0).rotated(deg_to_rad(290))
	positions["dataset_size"] = Vector2(ring1_r, 0).rotated(deg_to_rad(345))
	positions["data_quality"] = Vector2(ring1_r, 0).rotated(deg_to_rad(25))
	positions["cursor_size"] = Vector2(ring1_r, 0).rotated(deg_to_rad(110))
	positions["label_speed"] = Vector2(ring1_r, 0).rotated(deg_to_rad(150))

	# Root connects to all Ring 1
	for key in ["nodes", "layers", "dataset_size", "data_quality", "cursor_size", "label_speed"]:
		edges.append(["root", key])

	# Ring 2 — Stage 2 upgrades, ~250px from center
	if GameData.current_stage >= 1:
		var ring2_r = 250.0
		positions["activation_func"] = Vector2(ring2_r, 0).rotated(deg_to_rad(240))
		positions["learning_rate"] = Vector2(ring2_r, 0).rotated(deg_to_rad(280))
		positions["aug_chance"] = Vector2(ring2_r, 0).rotated(deg_to_rad(5))
		positions["batch_label"] = Vector2(ring2_r, 0).rotated(deg_to_rad(130))

		positions["training_time"] = Vector2(ring2_r, 0).rotated(deg_to_rad(345))

		edges.append(["nodes", "activation_func"])
		edges.append(["layers", "learning_rate"])
		edges.append(["data_quality", "aug_chance"])
		edges.append(["dataset_size", "training_time"])
		edges.append(["label_speed", "batch_label"])

		# Ring 3 — deep chains, ~350px
		var ring3_r = 350.0
		positions["aug_quality"] = Vector2(ring3_r, 0).rotated(deg_to_rad(5))
		positions["transfer_learning"] = Vector2(ring3_r, 0).rotated(deg_to_rad(280))
		edges.append(["aug_chance", "aug_quality"])
		edges.append(["learning_rate", "transfer_learning"])

	return {"positions": positions, "edges": edges}


func _refresh_layout() -> void:
	var old_keys = current_layout.get("positions", {}).keys()
	current_layout = _get_tree_layout()
	var new_keys = current_layout["positions"].keys()
	for key in new_keys:
		if key not in old_keys:
			node_appear_timers[key] = 0.0


# --- Shop visibility ---

func show_shop() -> void:
	_refresh_layout()
	_update_ui()
	root_control.visible = true
	tree_canvas.queue_redraw()


func hide_shop() -> void:
	root_control.visible = false
	tooltip_panel.visible = false
	hovered_node = ""


func _update_ui() -> void:
	compute_display.text = "$%d" % int(GameData.cash)

	var round_label = root_control.find_child("RoundLabel") as Label
	if round_label:
		if GameData.training_round == 0:
			round_label.text = "Prepare for training"
		else:
			round_label.text = "Round %d complete" % GameData.training_round


func _on_cheat_toggled(enabled: bool) -> void:
	cheats_enabled = enabled
	if cheats_enabled:
		GameData.cash = 999999999
		GameData.cash_changed.emit(GameData.cash)
	_update_ui()


func _on_stage_changed(_stage_index: int) -> void:
	_refresh_layout()


func _on_next_epoch() -> void:
	hide_shop()
	next_epoch_pressed.emit()
