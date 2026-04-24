extends CanvasLayer

var oxygen_bar: ProgressBar
var oxygen_label: Label
var dive_cash_label: Label
var total_cash_label: Label
var spear_row: HBoxContainer
var resurface_button: Button
var _spear_count_cache: int = -1


func _ready() -> void:
	_build_ui()
	GameData.cash_changed.connect(_on_cash_changed)
	GameData.oxygen_changed.connect(_on_oxygen_changed)
	GameData.dive_state_changed.connect(_on_dive_state_changed)
	_refresh()


func _build_ui() -> void:
	# Top bar
	var top = MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 80
	top.add_theme_constant_override("margin_left", 20)
	top.add_theme_constant_override("margin_right", 20)
	top.add_theme_constant_override("margin_top", 15)
	add_child(top)

	var top_hbox = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 30)
	top.add_child(top_hbox)

	# Total cash (left)
	total_cash_label = Label.new()
	total_cash_label.text = "$0"
	total_cash_label.add_theme_font_size_override("font_size", 22)
	total_cash_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	total_cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(total_cash_label)

	# Oxygen bar (center)
	var oxy_vbox = VBoxContainer.new()
	oxy_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oxy_vbox.custom_minimum_size = Vector2(300, 0)
	top_hbox.add_child(oxy_vbox)

	oxygen_label = Label.new()
	oxygen_label.text = "OXYGEN 45s"
	oxygen_label.add_theme_font_size_override("font_size", 12)
	oxygen_label.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0))
	oxygen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	oxy_vbox.add_child(oxygen_label)

	oxygen_bar = ProgressBar.new()
	oxygen_bar.min_value = 0.0
	oxygen_bar.max_value = 45.0
	oxygen_bar.value = 45.0
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

	# Dive cash (right)
	dive_cash_label = Label.new()
	dive_cash_label.text = ""
	dive_cash_label.add_theme_font_size_override("font_size", 22)
	dive_cash_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	dive_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dive_cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(dive_cash_label)

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


func _refresh() -> void:
	_on_cash_changed(GameData.cash)
	_on_oxygen_changed(GameData.oxygen)
	_on_dive_state_changed(GameData.dive_state)
	_rebuild_spear_row()


func _on_cash_changed(_amount: float) -> void:
	total_cash_label.text = "$%d" % int(GameData.cash)
	if GameData.dive_state == "underwater":
		dive_cash_label.text = "+$%d" % int(GameData.dive_cash)
	else:
		dive_cash_label.text = ""


func _on_oxygen_changed(value: float) -> void:
	oxygen_bar.max_value = GameData.get_oxygen_capacity()
	oxygen_bar.value = value
	oxygen_label.text = "OXYGEN %.0fs" % value
	# Color shifts as oxygen empties
	var ratio = value / GameData.get_oxygen_capacity()
	var bar_fg = StyleBoxFlat.new()
	bar_fg.bg_color = Color(1.0, 0.3, 0.3).lerp(Color(0.3, 0.7, 1.0), ratio)
	bar_fg.set_corner_radius_all(6)
	oxygen_bar.add_theme_stylebox_override("fill", bar_fg)


func _on_dive_state_changed(state: String) -> void:
	var underwater = state == "underwater"
	resurface_button.visible = underwater
	spear_row.visible = underwater or state == "diving" or state == "resurfacing"
	if state == "underwater":
		_rebuild_spear_row()
	_on_cash_changed(0.0)


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
	# state: "ready" | "flying" | "reeling"
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
