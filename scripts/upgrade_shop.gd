extends CanvasLayer

signal next_dive_pressed

var root_control: Control
var cash_label: Label
var list_vbox: VBoxContainer
var dive_button: Button
var upgrade_buttons: Dictionary = {}


func _ready() -> void:
	_build_ui()
	hide_shop()
	GameData.cash_changed.connect(_on_cash_changed)


func _build_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	var overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.85)
	root_control.add_child(overlay)

	# Centered panel
	var panel_margin = MarginContainer.new()
	panel_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_margin.add_theme_constant_override("margin_left", 120)
	panel_margin.add_theme_constant_override("margin_right", 120)
	panel_margin.add_theme_constant_override("margin_top", 60)
	panel_margin.add_theme_constant_override("margin_bottom", 60)
	root_control.add_child(panel_margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel_margin.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "⛵ ABOARD THE BOAT"
	header.add_theme_font_size_override("font_size", 28)
	header.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	cash_label = Label.new()
	cash_label.add_theme_font_size_override("font_size", 20)
	cash_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(cash_label)

	# Upgrade list
	list_vbox = VBoxContainer.new()
	list_vbox.add_theme_constant_override("separation", 6)
	vbox.add_child(list_vbox)

	for key in GameData.upgrades.keys():
		var btn = _build_upgrade_row(key)
		list_vbox.add_child(btn)
		upgrade_buttons[key] = btn

	# Dive button
	dive_button = Button.new()
	dive_button.text = "🐟  DIVE"
	dive_button.custom_minimum_size = Vector2(260, 52)
	dive_button.add_theme_font_size_override("font_size", 20)
	dive_button.pressed.connect(_on_dive_pressed)
	var dive_s = StyleBoxFlat.new()
	dive_s.bg_color = Color(0.12, 0.35, 0.75)
	dive_s.set_corner_radius_all(10)
	dive_s.set_content_margin_all(10)
	dive_button.add_theme_stylebox_override("normal", dive_s)
	var dive_wrap = CenterContainer.new()
	dive_wrap.add_child(dive_button)
	vbox.add_child(dive_wrap)


func _build_upgrade_row(key: String) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 48)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(_on_upgrade_pressed.bind(key))
	return btn


func _refresh_rows() -> void:
	for key in upgrade_buttons.keys():
		var btn: Button = upgrade_buttons[key]
		var upgrade = GameData.upgrades[key]
		var level = GameData.upgrade_levels[key]
		var max_level = upgrade["max_level"]
		var maxed = level >= max_level
		var cost_str = "MAX" if maxed else "$%d" % upgrade["costs"][level]
		btn.text = "%s  (Lv %d/%d)   %s   —   %s" % [upgrade["name"], level, max_level, upgrade["description"], cost_str]
		btn.disabled = maxed or not GameData.can_buy_upgrade(key)


func _on_upgrade_pressed(key: String) -> void:
	if GameData.buy_upgrade(key):
		_refresh_rows()
		_update_cash()


func _on_dive_pressed() -> void:
	hide_shop()
	next_dive_pressed.emit()


func _on_cash_changed(_amount: float) -> void:
	_update_cash()
	_refresh_rows()


func _update_cash() -> void:
	cash_label.text = "Wallet: $%d" % int(GameData.cash)


func show_shop() -> void:
	root_control.visible = true
	_update_cash()
	_refresh_rows()


func hide_shop() -> void:
	root_control.visible = false
