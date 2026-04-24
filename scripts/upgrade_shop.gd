extends CanvasLayer

signal next_dive_pressed

var root_control: Control
var cash_label: Label
var depth_buttons: Dictionary = {}  # tier -> Button
var upgrade_buttons: Dictionary = {}
var tier_buttons: Dictionary = {}  # "mid" | "deep" -> Button
var dive_button: Button
var cheat_button: Button


func _ready() -> void:
	_build_ui()
	hide_shop()
	GameData.cash_changed.connect(_on_cash_changed)
	GameData.tanks_changed.connect(func(_r, _t): _refresh_all())
	GameData.depth_changed.connect(func(_d): _refresh_depth_buttons())


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
	panel_margin.add_theme_constant_override("margin_left", 100)
	panel_margin.add_theme_constant_override("margin_right", 100)
	panel_margin.add_theme_constant_override("margin_top", 40)
	panel_margin.add_theme_constant_override("margin_bottom", 40)
	root_control.add_child(panel_margin)

	var scroll = ScrollContainer.new()
	panel_margin.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

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

	# Depth selector
	var depth_header = Label.new()
	depth_header.text = "— NEXT DIVE DEPTH —"
	depth_header.add_theme_font_size_override("font_size", 14)
	depth_header.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9))
	depth_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(depth_header)

	var depth_hbox = HBoxContainer.new()
	depth_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	depth_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(depth_hbox)

	for tier in ["shallow", "mid", "deep"]:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(140, 40)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_depth_pressed.bind(tier))
		depth_hbox.add_child(btn)
		depth_buttons[tier] = btn

	# Upgrade list
	var upg_header = Label.new()
	upg_header.text = "— UPGRADES —"
	upg_header.add_theme_font_size_override("font_size", 14)
	upg_header.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9))
	upg_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(upg_header)

	for key in GameData.upgrades.keys():
		var btn = _build_upgrade_row(key)
		vbox.add_child(btn)
		upgrade_buttons[key] = btn

	# Tier unlocks
	var tier_header = Label.new()
	tier_header.text = "— DEPTH TIER UNLOCKS —"
	tier_header.add_theme_font_size_override("font_size", 14)
	tier_header.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9))
	tier_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tier_header)

	for tier in ["mid", "deep"]:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(0, 44)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_tier_pressed.bind(tier))
		vbox.add_child(btn)
		tier_buttons[tier] = btn

	# Dev / cheat
	var dev_header = Label.new()
	dev_header.text = "— DEV —"
	dev_header.add_theme_font_size_override("font_size", 14)
	dev_header.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9))
	dev_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(dev_header)

	cheat_button = Button.new()
	cheat_button.custom_minimum_size = Vector2(200, 36)
	cheat_button.pressed.connect(_on_cheat_toggle)
	var cheat_wrap = CenterContainer.new()
	cheat_wrap.add_child(cheat_button)
	vbox.add_child(cheat_wrap)

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
	btn.custom_minimum_size = Vector2(0, 44)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(_on_upgrade_pressed.bind(key))
	return btn


func _refresh_all() -> void:
	_update_cash()
	_refresh_upgrade_rows()
	_refresh_tier_rows()
	_refresh_depth_buttons()
	_refresh_cheat_button()
	_refresh_dive_button()


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


func _refresh_tier_rows() -> void:
	for tier in tier_buttons.keys():
		var btn: Button = tier_buttons[tier]
		var owned = (tier == "mid" and GameData.mid_tier_unlocked) or (tier == "deep" and GameData.deep_tier_unlocked)
		var cost = GameData.TIER_COSTS[tier]
		var name = "%s Tier Access" % tier.capitalize()
		if owned:
			btn.text = "%s   —   OWNED" % name
			btn.disabled = true
		else:
			btn.text = "%s   —   $%d" % [name, cost]
			btn.disabled = not GameData.can_buy_tier(tier)


func _refresh_depth_buttons() -> void:
	for tier in depth_buttons.keys():
		var btn: Button = depth_buttons[tier]
		var unlocked = GameData.can_select_depth(tier)
		var selected = tier == GameData.selected_depth
		var label = tier.capitalize()
		if not unlocked:
			btn.text = "🔒 %s" % label
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5)
		else:
			btn.disabled = false
			btn.modulate = Color(1, 1, 1)
			if selected:
				btn.text = "● %s" % label
				var s = StyleBoxFlat.new()
				s.bg_color = Color(0.2, 0.55, 0.35)
				s.set_corner_radius_all(6)
				btn.add_theme_stylebox_override("normal", s)
			else:
				btn.text = "○ %s" % label
				var s = StyleBoxFlat.new()
				s.bg_color = Color(0.15, 0.2, 0.3)
				s.set_corner_radius_all(6)
				btn.add_theme_stylebox_override("normal", s)


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


func _on_tier_pressed(tier: String) -> void:
	if GameData.buy_tier(tier):
		_refresh_all()


func _on_depth_pressed(tier: String) -> void:
	GameData.set_depth(tier)
	_refresh_depth_buttons()


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
	_refresh_tier_rows()


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
