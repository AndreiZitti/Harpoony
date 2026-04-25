extends CanvasLayer

signal next_dive_pressed

var root_control: Control
var cash_label: Label
var upgrade_buttons: Dictionary = {}
var unlock_zone_button: Button
var dive_button: Button
var cheat_button: Button
var depth_lever: DepthLever


func _ready() -> void:
	_build_ui()
	hide_shop()
	GameData.cash_changed.connect(_on_cash_changed)
	GameData.tanks_changed.connect(func(_r, _t): _refresh_all())
	GameData.zone_changed.connect(func(_z): _refresh_all())
	GameData.zone_unlocked.connect(func(_i): _refresh_all())


func _build_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	var overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.85)
	root_control.add_child(overlay)

	var panel_margin = MarginContainer.new()
	panel_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_margin.add_theme_constant_override("margin_left", 80)
	panel_margin.add_theme_constant_override("margin_right", 80)
	panel_margin.add_theme_constant_override("margin_top", 32)
	panel_margin.add_theme_constant_override("margin_bottom", 32)
	root_control.add_child(panel_margin)

	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 12)
	panel_margin.add_child(outer_vbox)

	# Header
	var header = Label.new()
	header.text = "⛵ ABOARD THE BOAT"
	header.add_theme_font_size_override("font_size", 28)
	header.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(header)

	cash_label = Label.new()
	cash_label.add_theme_font_size_override("font_size", 20)
	cash_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(cash_label)

	# Two-column body: lever on the left, upgrades on the right
	var body_hbox = HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 24)
	outer_vbox.add_child(body_hbox)

	depth_lever = DepthLever.new()
	depth_lever.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body_hbox.add_child(depth_lever)

	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 8)
	body_hbox.add_child(right_vbox)

	# Unlock-next-zone button
	unlock_zone_button = Button.new()
	unlock_zone_button.custom_minimum_size = Vector2(0, 44)
	unlock_zone_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	unlock_zone_button.add_theme_font_size_override("font_size", 14)
	unlock_zone_button.pressed.connect(_on_unlock_zone_pressed)
	right_vbox.add_child(unlock_zone_button)

	# Upgrade list
	var upg_header = Label.new()
	upg_header.text = "— UPGRADES —"
	upg_header.add_theme_font_size_override("font_size", 14)
	upg_header.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9))
	upg_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vbox.add_child(upg_header)

	var upg_scroll = ScrollContainer.new()
	upg_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upg_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upg_scroll.custom_minimum_size = Vector2(0, 220)
	right_vbox.add_child(upg_scroll)

	var upg_vbox = VBoxContainer.new()
	upg_vbox.add_theme_constant_override("separation", 6)
	upg_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upg_scroll.add_child(upg_vbox)

	for key in GameData.upgrades.keys():
		var btn = _build_upgrade_row(key)
		upg_vbox.add_child(btn)
		upgrade_buttons[key] = btn

	# Dev / cheat
	cheat_button = Button.new()
	cheat_button.custom_minimum_size = Vector2(200, 32)
	cheat_button.pressed.connect(_on_cheat_toggle)
	var cheat_wrap = CenterContainer.new()
	cheat_wrap.add_child(cheat_button)
	right_vbox.add_child(cheat_wrap)

	# Dive button (full width at the bottom)
	dive_button = Button.new()
	dive_button.text = "🐟  DIVE"
	dive_button.custom_minimum_size = Vector2(280, 56)
	dive_button.add_theme_font_size_override("font_size", 22)
	dive_button.pressed.connect(_on_dive_pressed)
	var dive_s = StyleBoxFlat.new()
	dive_s.bg_color = Color(0.12, 0.35, 0.75)
	dive_s.set_corner_radius_all(10)
	dive_s.set_content_margin_all(10)
	dive_button.add_theme_stylebox_override("normal", dive_s)
	var dive_wrap = CenterContainer.new()
	dive_wrap.add_child(dive_button)
	outer_vbox.add_child(dive_wrap)


func _build_upgrade_row(key: String) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 40)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(_on_upgrade_pressed.bind(key))
	return btn


func _refresh_all() -> void:
	_update_cash()
	_refresh_upgrade_rows()
	_refresh_unlock_zone_button()
	_refresh_cheat_button()
	_refresh_dive_button()
	if depth_lever:
		depth_lever.queue_redraw()


func _refresh_upgrade_rows() -> void:
	for key in upgrade_buttons.keys():
		var btn: Button = upgrade_buttons[key]
		var upgrade = GameData.upgrades[key]
		var level = GameData.upgrade_levels[key]
		var max_level = upgrade["max_level"]
		var maxed = level >= max_level
		var cost_str = "MAX" if maxed else "$%d" % upgrade["costs"][level]
		btn.text = "%s  (Lv %d/%d)   %s   —   %s" % [
			upgrade["name"], level, max_level, upgrade["description"], cost_str
		]
		btn.disabled = maxed or not GameData.can_buy_upgrade(key)


func _refresh_unlock_zone_button() -> void:
	var next_idx = GameData.unlocked_zone_index + 1
	if next_idx >= GameData.zones.size():
		unlock_zone_button.text = "All zones unlocked"
		unlock_zone_button.disabled = true
		return
	var next_zone: ZoneConfig = GameData.zones[next_idx]
	unlock_zone_button.text = "Unlock %s (%dm)   —   $%d" % [next_zone.display_name, next_zone.depth_meters, next_zone.unlock_cost]
	unlock_zone_button.disabled = not GameData.can_unlock_next_zone()


func _refresh_cheat_button() -> void:
	if GameData.cheat_mode:
		cheat_button.text = "Cheat: ON"
		var s = StyleBoxFlat.new()
		s.bg_color = Color(0.8, 0.3, 0.3)
		s.set_corner_radius_all(6)
		cheat_button.add_theme_stylebox_override("normal", s)
	else:
		cheat_button.text = "Cheat: OFF"
		var s = StyleBoxFlat.new()
		s.bg_color = Color(0.25, 0.25, 0.3)
		s.set_corner_radius_all(6)
		cheat_button.add_theme_stylebox_override("normal", s)


func _refresh_dive_button() -> void:
	if GameData.tanks_remaining <= 0:
		dive_button.text = "NO TANKS LEFT"
		dive_button.disabled = true
	else:
		dive_button.text = "🐟  DIVE  (tanks left: %d)" % GameData.tanks_remaining
		dive_button.disabled = false


func _on_upgrade_pressed(key: String) -> void:
	if GameData.buy_upgrade(key):
		_refresh_all()


func _on_unlock_zone_pressed() -> void:
	if GameData.unlock_next_zone():
		_refresh_all()


func _on_cheat_toggle() -> void:
	GameData.toggle_cheat_mode()
	_refresh_all()


func _on_dive_pressed() -> void:
	if GameData.tanks_remaining <= 0:
		return
	hide_shop()
	next_dive_pressed.emit()


func _on_cash_changed(_amount: float) -> void:
	_update_cash()
	_refresh_upgrade_rows()
	_refresh_unlock_zone_button()


func _update_cash() -> void:
	if GameData.cheat_mode:
		cash_label.text = "Wallet: ∞ (CHEAT)"
	else:
		cash_label.text = "Wallet: $%d" % int(GameData.cash)


func show_shop() -> void:
	root_control.visible = true
	_refresh_all()


func hide_shop() -> void:
	root_control.visible = false
