extends CanvasLayer

var oxygen_bar: ProgressBar
var oxygen_label: Label
var dive_cash_label: Label
var total_cash_label: Label
var phase_label: Label
var spear_row: HBoxContainer
var resurface_button: Button
var zone_name_label: Label
var zone_depth_label: Label
var popups: Control

const SPECIES_COLOR = {
	"sardine": Color(0.85, 0.92, 1.0),
	"grouper": Color(1.0, 0.75, 0.4),
	"tuna": Color(0.6, 0.8, 1.0),
	"pufferfish": Color(1.0, 0.95, 0.55),
	"mahimahi": Color(1.0, 0.8, 0.3),
	"squid": Color(0.85, 0.5, 0.95),
	"lanternfish": Color(0.7, 0.85, 1.0),
	"anglerfish": Color(1.0, 0.85, 0.4),
	"marlin": Color(0.55, 0.7, 1.0),
}


func _ready() -> void:
	_build_ui()
	GameData.cash_changed.connect(_on_cash_changed)
	GameData.oxygen_changed.connect(_on_oxygen_changed)
	GameData.dive_state_changed.connect(_on_dive_state_changed)
	GameData.day_changed.connect(func(_d): _refresh_phase())
	GameData.tanks_changed.connect(func(_r, _t): _refresh_phase())
	GameData.zone_changed.connect(func(_z): _refresh_depth())
	GameData.zone_unlocked.connect(func(_i): _refresh_depth())
	_refresh()


func _build_ui() -> void:
	# Top bar
	var top = MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 90
	top.add_theme_constant_override("margin_left", 20)
	top.add_theme_constant_override("margin_right", 20)
	top.add_theme_constant_override("margin_top", 12)
	add_child(top)

	var top_hbox = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 30)
	top.add_child(top_hbox)

	# Left: total cash + phase label
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(left_vbox)

	total_cash_label = Label.new()
	total_cash_label.text = "$0"
	total_cash_label.add_theme_font_size_override("font_size", 22)
	total_cash_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	left_vbox.add_child(total_cash_label)

	phase_label = Label.new()
	phase_label.text = "Day 1 · Morning"
	phase_label.add_theme_font_size_override("font_size", 12)
	phase_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	left_vbox.add_child(phase_label)

	# Center: oxygen
	var oxy_vbox = VBoxContainer.new()
	oxy_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oxy_vbox.custom_minimum_size = Vector2(300, 0)
	top_hbox.add_child(oxy_vbox)

	oxygen_label = Label.new()
	oxygen_label.text = "OXYGEN"
	oxygen_label.add_theme_font_size_override("font_size", 12)
	oxygen_label.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0))
	oxygen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	oxy_vbox.add_child(oxygen_label)

	oxygen_bar = ProgressBar.new()
	oxygen_bar.min_value = 0.0
	oxygen_bar.max_value = GameData.get_oxygen_capacity()
	oxygen_bar.value = GameData.oxygen
	oxygen_bar.show_percentage = false
	oxygen_bar.custom_minimum_size = Vector2(300, 18)
	var bar_bg = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.12, 0.2)
	bar_bg.set_corner_radius_all(6)
	oxygen_bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fg = StyleBoxFlat.new()
	bar_fg.bg_color = Color(0.3, 0.7, 1.0)
	bar_fg.set_corner_radius_all(6)
	oxygen_bar.add_theme_stylebox_override("fill", bar_fg)
	oxy_vbox.add_child(oxygen_bar)

	# Right: dive cash
	dive_cash_label = Label.new()
	dive_cash_label.text = ""
	dive_cash_label.add_theme_font_size_override("font_size", 22)
	dive_cash_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	dive_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dive_cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(dive_cash_label)

	# Depth indicator (left edge, below top bar)
	var depth_margin = MarginContainer.new()
	depth_margin.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	depth_margin.offset_top = 100
	depth_margin.offset_right = 140
	depth_margin.add_theme_constant_override("margin_left", 18)
	add_child(depth_margin)

	var depth_vbox = VBoxContainer.new()
	depth_vbox.add_theme_constant_override("separation", 4)
	depth_margin.add_child(depth_vbox)

	var depth_header = Label.new()
	depth_header.text = "DEPTH"
	depth_header.add_theme_font_size_override("font_size", 10)
	depth_header.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
	depth_vbox.add_child(depth_header)

	zone_name_label = Label.new()
	zone_name_label.add_theme_font_size_override("font_size", 16)
	zone_name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	depth_vbox.add_child(zone_name_label)

	zone_depth_label = Label.new()
	zone_depth_label.add_theme_font_size_override("font_size", 12)
	zone_depth_label.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	depth_vbox.add_child(zone_depth_label)

	# Spear inventory (bottom-center)
	var bottom = MarginContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -70
	bottom.add_theme_constant_override("margin_bottom", 16)
	add_child(bottom)

	spear_row = HBoxContainer.new()
	spear_row.alignment = BoxContainer.ALIGNMENT_CENTER
	spear_row.add_theme_constant_override("separation", 8)
	bottom.add_child(spear_row)

	# Resurface button (bottom-right)
	var btn_margin = MarginContainer.new()
	btn_margin.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn_margin.offset_left = -200
	btn_margin.offset_top = -70
	btn_margin.add_theme_constant_override("margin_right", 30)
	btn_margin.add_theme_constant_override("margin_bottom", 16)
	add_child(btn_margin)

	resurface_button = Button.new()
	resurface_button.text = "RESURFACE"
	resurface_button.custom_minimum_size = Vector2(160, 40)
	resurface_button.pressed.connect(_on_resurface_pressed)
	btn_margin.add_child(resurface_button)

	# Popup layer (cash floats, etc.)
	popups = Control.new()
	popups.set_anchors_preset(Control.PRESET_FULL_RECT)
	popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(popups)


func spawn_cash_popup(value: int, world_pos: Vector2, species: String) -> void:
	var label := Label.new()
	label.text = "+$%d" % value
	label.add_theme_font_size_override("font_size", 18)
	var tint: Color = SPECIES_COLOR.get(species, Color.WHITE)
	label.add_theme_color_override("font_color", tint)
	# HUD has no Camera2D in this project — world == screen coords
	label.position = world_pos - Vector2(20, 0)
	label.z_index = 100
	popups.add_child(label)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(label, "position:y", label.position.y - 60.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.3)
	t.chain().tween_callback(label.queue_free)


func _refresh() -> void:
	_on_cash_changed(GameData.cash)
	_on_oxygen_changed(GameData.oxygen)
	_on_dive_state_changed(GameData.dive_state)
	_refresh_phase()
	_refresh_depth()
	_rebuild_spear_row()


func _on_cash_changed(_amount: float) -> void:
	total_cash_label.text = "$%d" % int(GameData.cash)
	if GameData.dive_state == GameData.DiveState.UNDERWATER:
		dive_cash_label.text = "+$%d" % int(GameData.dive_cash)
	else:
		dive_cash_label.text = ""


func _on_oxygen_changed(value: float) -> void:
	oxygen_bar.max_value = GameData.get_oxygen_capacity()
	oxygen_bar.value = value
	oxygen_label.text = "OXYGEN %.0fs" % value
	var ratio = value / max(0.001, GameData.get_oxygen_capacity())
	var bar_fg = StyleBoxFlat.new()
	bar_fg.bg_color = Color(1.0, 0.3, 0.3).lerp(Color(0.3, 0.7, 1.0), ratio)
	bar_fg.set_corner_radius_all(6)
	oxygen_bar.add_theme_stylebox_override("fill", bar_fg)


func _on_dive_state_changed(state: int) -> void:
	var underwater = state == GameData.DiveState.UNDERWATER
	resurface_button.visible = underwater
	spear_row.visible = state != GameData.DiveState.SURFACE
	if underwater:
		_rebuild_spear_row()
	_refresh_phase()
	_on_cash_changed(0.0)


func _refresh_phase() -> void:
	if phase_label == null:
		return
	var phase = GameData.get_current_phase().capitalize()
	var dive_num = GameData.dive_number_today
	if GameData.dive_state == GameData.DiveState.SURFACE:
		dive_num = GameData.dive_number_today + 1
	var tank_total = GameData.get_tank_count()
	phase_label.text = "Day %d · %s · Dive %d of %d" % [GameData.day_number, phase, dive_num, tank_total]


func _refresh_depth() -> void:
	if zone_name_label == null:
		return
	var zone := GameData.get_current_zone()
	if zone == null:
		return
	zone_name_label.text = zone.display_name
	zone_depth_label.text = "%dm  ·  Zone %d/%d" % [zone.depth_meters, GameData.selected_zone_index + 1, GameData.zones.size()]


func _rebuild_spear_row() -> void:
	for child in spear_row.get_children():
		child.queue_free()
	var count = GameData.get_spear_count()
	for i in count:
		var dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.color = Color(0.7, 0.85, 1.0)
		dot.name = "Spear%d" % i
		spear_row.add_child(dot)


func update_spear_state(index: int, state: String) -> void:
	if spear_row == null:
		return
	if index < 0 or index >= spear_row.get_child_count():
		return
	var dot = spear_row.get_child(index) as ColorRect
	if dot == null:
		return
	match state:
		"ready":
			dot.color = Color(0.7, 0.85, 1.0)
		"flying":
			dot.color = Color(1.0, 0.85, 0.3)
		"reeling":
			dot.color = Color(0.4, 0.6, 1.0)


func _on_resurface_pressed() -> void:
	var main = get_tree().current_scene
	if main and main.has_method("begin_manual_resurface"):
		main.begin_manual_resurface()
