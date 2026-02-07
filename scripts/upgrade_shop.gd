extends CanvasLayer

signal next_epoch_pressed

var root_control: Control
var tree_canvas: Control
var compute_display: Label
var tooltip_panel: PanelContainer
var tooltip_name: Label
var tooltip_desc: Label
var tooltip_stats: Label

var hovered_node: String = ""

# Visual config
const NODE_SIZE = Vector2(120, 58)
const CAT_SIZE = Vector2(86, 28)

# Category nodes (non-interactive visual anchors)
var category_keys: Array = ["root", "cat_network", "cat_data", "cat_player"]
var category_labels: Dictionary = {
	"root": "RESEARCH",
	"cat_network": "NETWORK",
	"cat_data": "DATA",
	"cat_player": "PLAYER",
}

var current_layout: Dictionary = {"positions": {}, "edges": []}

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
	compute_display.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
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
	tooltip_panel.custom_minimum_size = Vector2(190, 0)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	style.border_color = Color(0.3, 0.6, 1.0, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	tooltip_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	tooltip_panel.add_child(vbox)

	tooltip_name = Label.new()
	tooltip_name.add_theme_font_size_override("font_size", 15)
	tooltip_name.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(tooltip_name)

	tooltip_desc = Label.new()
	tooltip_desc.add_theme_font_size_override("font_size", 11)
	tooltip_desc.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(tooltip_desc)

	tooltip_stats = Label.new()
	tooltip_stats.add_theme_font_size_override("font_size", 12)
	vbox.add_child(tooltip_stats)

	root_control.add_child(tooltip_panel)


# --- State helpers ---

func _is_category(key: String) -> bool:
	return key in category_keys


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
		if _is_category(key):
			continue
		if key not in GameData.upgrades:
			continue
		var pos = _get_node_screen_pos(key)
		var rect = Rect2(pos - NODE_SIZE / 2.0, NODE_SIZE)
		if rect.has_point(mouse_pos):
			new_hover = key

	if new_hover != hovered_node:
		hovered_node = new_hover
		_update_tooltip()

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

	tooltip_name.text = upgrade["name"]
	tooltip_desc.text = upgrade["description"]

	if state == "locked":
		var prereq_name = GameData.upgrades[GameData.upgrade_prerequisites[hovered_node]]["name"]
		tooltip_stats.text = "Requires: " + prereq_name
		tooltip_stats.add_theme_color_override("font_color", Color(0.6, 0.4, 0.3))
	elif state == "maxed":
		tooltip_stats.text = "Level %d/%d  (MAX)" % [level, max_level]
		tooltip_stats.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	else:
		var cost = upgrade["costs"][level]
		tooltip_stats.text = "Level %d/%d  |  Cost: %d CP" % [level, max_level, cost]
		if GameData.can_buy_upgrade(hovered_node):
			tooltip_stats.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		else:
			tooltip_stats.add_theme_color_override("font_color", Color(0.7, 0.35, 0.3))

	tooltip_panel.visible = true

	var node_pos = _get_node_screen_pos(hovered_node)
	var tip_pos = node_pos + Vector2(NODE_SIZE.x / 2.0 + 14, -20)

	var tip_size = tooltip_panel.size
	if tip_pos.x + tip_size.x > tree_canvas.size.x - 20:
		tip_pos.x = node_pos.x - NODE_SIZE.x / 2.0 - tip_size.x - 14
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
			GameData.compute = 999999999
			GameData.compute_changed.emit(GameData.compute)
		_update_ui()


# --- Drawing ---

func _draw_tree() -> void:
	var font = ThemeDB.fallback_font
	var time = Time.get_ticks_msec() / 1000.0

	# 1. Draw edges
	for edge in current_layout["edges"]:
		_draw_edge(edge[0], edge[1], time)

	# 2. Draw category nodes
	for key in category_keys:
		if key in current_layout["positions"]:
			_draw_category_node(key, font, time)

	# 3. Draw upgrade nodes
	for key in current_layout["positions"]:
		if not _is_category(key):
			_draw_upgrade_node(key, font, time)


func _draw_edge(from_key: String, to_key: String, time: float) -> void:
	var from_pos = _get_node_screen_pos(from_key)
	var to_pos = _get_node_screen_pos(to_key)

	# Determine brightness from node states
	var to_bright = 0.15
	if _is_category(to_key):
		to_bright = 0.5
	else:
		var state = _get_upgrade_state(to_key)
		match state:
			"locked":
				to_bright = 0.1
			"available":
				to_bright = 0.25
			"affordable":
				to_bright = 0.5
			"owned", "owned_affordable":
				to_bright = 0.6
			"maxed":
				to_bright = 0.7

	var line_color = Color(0.3, 0.5, 0.8, to_bright)
	tree_canvas.draw_line(from_pos, to_pos, line_color, 2.0)

	# Subtle glow on bright edges
	if to_bright > 0.4:
		var glow = 0.03 + sin(time * 1.5) * 0.02
		tree_canvas.draw_line(from_pos, to_pos, Color(0.4, 0.6, 1.0, glow), 5.0)


func _draw_category_node(key: String, font: Font, _time: float) -> void:
	var pos = _get_node_screen_pos(key)
	var label_text = category_labels[key]

	# Small subtle background
	var rect = Rect2(pos - CAT_SIZE / 2.0, CAT_SIZE)
	tree_canvas.draw_rect(rect, Color(0.1, 0.12, 0.2, 0.6), true)
	tree_canvas.draw_rect(rect, Color(0.3, 0.45, 0.7, 0.35), false, 1.0)

	# Label text centered
	var text_size = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var text_pos = Vector2(pos.x - text_size.x / 2.0, pos.y + 4)
	tree_canvas.draw_string(font, text_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.65, 0.9, 0.8))


func _draw_upgrade_node(key: String, font: Font, time: float) -> void:
	var pos = _get_node_screen_pos(key)
	var upgrade = GameData.upgrades[key]
	var level = GameData.upgrade_levels[key]
	var max_level = upgrade["max_level"]
	var state = _get_upgrade_state(key)
	var is_hover = key == hovered_node

	var rect = Rect2(pos - NODE_SIZE / 2.0, NODE_SIZE)

	# Colors based on state
	var bg_color: Color
	var border_color: Color
	var name_color: Color
	var detail_color: Color

	match state:
		"locked":
			bg_color = Color(0.05, 0.05, 0.08, 0.8)
			border_color = Color(0.15, 0.15, 0.2, 0.4)
			name_color = Color(0.3, 0.3, 0.38)
			detail_color = Color(0.25, 0.2, 0.2)
		"available":
			bg_color = Color(0.06, 0.07, 0.12, 0.9)
			border_color = Color(0.2, 0.25, 0.4, 0.5)
			name_color = Color(0.5, 0.5, 0.6)
			detail_color = Color(0.6, 0.3, 0.3)
		"affordable":
			bg_color = Color(0.07, 0.09, 0.16, 0.95)
			border_color = Color(0.3, 0.5, 0.9, 0.65)
			name_color = Color(0.8, 0.85, 1.0)
			detail_color = Color(0.3, 1.0, 0.4)
		"owned":
			bg_color = Color(0.08, 0.1, 0.18, 0.95)
			border_color = Color(0.3, 0.55, 1.0, 0.6)
			name_color = Color.WHITE
			detail_color = Color(0.6, 0.3, 0.3)
		"owned_affordable":
			bg_color = Color(0.08, 0.1, 0.18, 0.95)
			border_color = Color(0.3, 0.55, 1.0, 0.6)
			name_color = Color.WHITE
			detail_color = Color(0.3, 1.0, 0.4)
		"maxed":
			bg_color = Color(0.1, 0.16, 0.1, 0.95)
			border_color = Color(0.35, 0.8, 0.3, 0.65)
			name_color = Color(0.7, 1.0, 0.6)
			detail_color = Color(0.5, 0.85, 0.3)

	# Hover effect
	if is_hover and state != "locked":
		bg_color = bg_color.lightened(0.12)
		border_color.a = minf(border_color.a + 0.25, 1.0)

	# Pulsing glow for affordable nodes
	if state in ["affordable", "owned_affordable"]:
		var pulse = (sin(time * 3.0) + 1.0) / 2.0
		var glow_rect = rect.grow(3 + pulse * 3)
		var glow_color = Color(0.3, 0.6, 1.0, 0.06 + pulse * 0.05)
		tree_canvas.draw_rect(glow_rect, glow_color, true)

	# Background
	tree_canvas.draw_rect(rect, bg_color, true)

	# Border
	var border_width = 1.5
	if is_hover and state != "locked":
		border_width = 2.0
	tree_canvas.draw_rect(rect, border_color, false, border_width)

	# Level pips at top of node
	if state != "locked":
		var pip_y = pos.y - NODE_SIZE.y / 2.0 + 9
		var pip_spacing = 8.0
		if max_level > 6:
			pip_spacing = 6.0
		var pip_total = (max_level - 1) * pip_spacing
		var pip_start = pos.x - pip_total / 2.0
		for i in range(max_level):
			var pip_x = pip_start + i * pip_spacing
			if i < level:
				var pip_color = detail_color if state != "maxed" else Color(0.4, 0.85, 0.3)
				tree_canvas.draw_circle(Vector2(pip_x, pip_y), 2.5, pip_color)
			else:
				tree_canvas.draw_circle(Vector2(pip_x, pip_y), 1.5, Color(0.2, 0.2, 0.3, 0.5))

	# Name
	var name_text = upgrade["name"]
	if state == "locked":
		name_text = upgrade["name"]  # show name even when locked
	var name_fs = 13
	var name_size = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs)
	var name_pos = Vector2(pos.x - name_size.x / 2.0, pos.y + 3)
	tree_canvas.draw_string(font, name_pos, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs, name_color)

	# Bottom detail line
	var bottom_text = ""
	var bottom_color = detail_color
	var bottom_fs = 10

	match state:
		"locked":
			bottom_text = "LOCKED"
			bottom_color = Color(0.35, 0.25, 0.25)
		"maxed":
			bottom_text = "MAX"
		_:
			if level > 0:
				var cost = GameData.get_upgrade_cost(key)
				if cost > 0:
					bottom_text = "Lv.%d | %d CP" % [level, cost]
				else:
					bottom_text = "Lv.%d" % level
			else:
				var cost = GameData.get_upgrade_cost(key)
				if cost > 0:
					bottom_text = "%d CP" % cost

	if bottom_text != "":
		var bt_size = font.get_string_size(bottom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, bottom_fs)
		var bt_pos = Vector2(pos.x - bt_size.x / 2.0, pos.y + 20)
		tree_canvas.draw_string(font, bt_pos, bottom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, bottom_fs, bottom_color)


# --- Layout ---

func _get_tree_layout() -> Dictionary:
	var positions: Dictionary = {}
	var edges: Array = []

	# Always present: root + 3 categories
	positions["root"] = Vector2(0, -195)
	positions["cat_network"] = Vector2(-220, -105)
	positions["cat_data"] = Vector2(0, -105)
	positions["cat_player"] = Vector2(220, -105)

	edges.append(["root", "cat_network"])
	edges.append(["root", "cat_data"])
	edges.append(["root", "cat_player"])

	# Stage 1 nodes — always visible
	positions["nodes"] = Vector2(-280, 0)
	positions["layers"] = Vector2(-160, 0)
	positions["dataset_size"] = Vector2(-60, 0)
	positions["data_quality"] = Vector2(60, 0)
	positions["cursor_size"] = Vector2(160, 0)
	positions["label_speed"] = Vector2(280, 0)

	edges.append(["cat_network", "nodes"])
	edges.append(["cat_network", "layers"])
	edges.append(["cat_data", "dataset_size"])
	edges.append(["cat_data", "data_quality"])
	edges.append(["cat_player", "cursor_size"])
	edges.append(["cat_player", "label_speed"])

	# Stage 2 nodes — only visible from stage 1+
	if GameData.current_stage >= 1:
		positions["activation_func"] = Vector2(-280, 95)
		positions["learning_rate"] = Vector2(-220, 95)
		positions["aug_chance"] = Vector2(-10, 95)
		positions["aug_quality"] = Vector2(-10, 180)
		positions["batch_label"] = Vector2(220, 95)

		edges.append(["nodes", "activation_func"])
		edges.append(["cat_network", "learning_rate"])
		edges.append(["cat_data", "aug_chance"])
		edges.append(["aug_chance", "aug_quality"])
		edges.append(["cat_player", "batch_label"])

	return {"positions": positions, "edges": edges}


func _refresh_layout() -> void:
	current_layout = _get_tree_layout()


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
	compute_display.text = "%d Compute" % int(GameData.compute)

	var round_label = root_control.find_child("RoundLabel") as Label
	if round_label:
		if GameData.training_round == 0:
			round_label.text = "Prepare for training"
		else:
			round_label.text = "Round %d complete" % GameData.training_round


func _on_cheat_toggled(enabled: bool) -> void:
	cheats_enabled = enabled
	if cheats_enabled:
		GameData.compute = 999999999
		GameData.compute_changed.emit(GameData.compute)
	_update_ui()


func _on_stage_changed(_stage_index: int) -> void:
	_refresh_layout()


func _on_next_epoch() -> void:
	hide_shop()
	next_epoch_pressed.emit()
