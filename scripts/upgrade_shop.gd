extends CanvasLayer

signal next_dive_pressed

const COL_BOAT := Color(0.45, 0.7, 1.0)
const COL_SPEARS := Color(1.0, 0.55, 0.55)
const COL_DEPTH := Color(0.85, 0.7, 0.35)
const COL_DIM := Color(0.55, 0.6, 0.7)
const COL_TEXT := Color(0.92, 0.94, 1.0)
const COL_TEXT_MUTED := Color(0.65, 0.7, 0.82)
const COL_PIP_FILLED := Color(1.0, 0.85, 0.3)
const COL_PIP_HOLLOW := Color(0.4, 0.45, 0.55)

# Spear cards become visible as zones unlock. Index matches GameData.unlocked_zone_index.
const MIN_ZONE_FOR_SPEAR := {
	&"normal": 0,
	&"net": 1,
	&"heavy": 2,
}

# Projectile sprite preview at the top of each spear card. Pixel-art is rendered
# with NEAREST filtering and stretched to fit the card width as a banner.
const SPEAR_SPRITE_PATHS := {
	&"normal": "res://assets/spears/normal.png",
	&"net": "res://assets/spears/net.png",
	&"heavy": "res://assets/spears/heavy.png",
}

var root_control: Control

var cash_label: Label

# Zone selector strip
var zone_buttons: Array[Button] = []
var unlock_zone_button: Button

# Global upgrade chips (boat-side: oxygen, spear_bag)
var upgrade_chips: Dictionary = {}  # key -> { chip, name_label, dots_label, buy_button }

# Spear column UI
var bag_capacity_label: Label = null
var spear_card_widgets: Dictionary = {}  # id -> { card, unlock_btn, status_lbl, upgrade_rows, bag_minus, bag_count, bag_plus, bag_caption }
var fill_bag_button: Button = null

var dive_button: Button
var cheat_button: Button


func _ready() -> void:
	_build_ui()
	hide_shop()
	GameData.cash_changed.connect(_on_cash_changed)
	GameData.zone_changed.connect(func(_z): _refresh_all())
	GameData.zone_unlocked.connect(func(_i): _refresh_all())
	GameData.spear_type_unlocked.connect(func(_id): _refresh_all())
	GameData.spear_upgrade_changed.connect(func(_id, _k, _l): _refresh_all())
	GameData.bag_loadout_changed.connect(_refresh_all)


# --- Build ---

func _build_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	var overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.02, 0.04, 0.08, 0.92)
	root_control.add_child(overlay)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	root_control.add_child(margin)

	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)

	outer.add_child(_build_header())
	outer.add_child(_build_loadout_strip())

	var spears = _build_spears_column()
	spears.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(spears)

	outer.add_child(_build_footer())


func _build_header() -> Control:
	var header = HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 48)

	var title = Label.new()
	title.text = "⛵ ABOARD THE BOAT"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", COL_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)

	cash_label = Label.new()
	cash_label.add_theme_font_size_override("font_size", 28)
	cash_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(cash_label)

	return header


# Top strip: zone selector | global upgrade chips | DIVE button.
func _build_loadout_strip() -> Control:
	var panel = PanelContainer.new()
	var box = StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.1, 0.16, 0.9)
	box.set_corner_radius_all(8)
	box.set_border_width_all(2)
	box.border_color = Color(0.4, 0.5, 0.7, 0.55)
	box.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", box)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	panel.add_child(hbox)

	# Depth selector (zone buttons + unlock-next)
	hbox.add_child(_build_depth_block())

	# Vertical separator
	var sep = VSeparator.new()
	sep.custom_minimum_size = Vector2(2, 0)
	hbox.add_child(sep)

	# Global upgrade chips
	hbox.add_child(_build_global_upgrades_block())

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# Dive button (right)
	dive_button = Button.new()
	dive_button.text = "🐟  DIVE"
	dive_button.custom_minimum_size = Vector2(220, 64)
	dive_button.add_theme_font_size_override("font_size", 22)
	dive_button.pressed.connect(_on_dive_pressed)
	var dive_s = StyleBoxFlat.new()
	dive_s.bg_color = Color(0.12, 0.45, 0.85)
	dive_s.set_corner_radius_all(10)
	dive_s.set_content_margin_all(10)
	dive_s.set_border_width_all(2)
	dive_s.border_color = Color(0.5, 0.8, 1.0, 0.6)
	dive_button.add_theme_stylebox_override("normal", dive_s)
	hbox.add_child(dive_button)

	return panel


func _build_depth_block() -> Control:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var label = Label.new()
	label.text = "DEPTH"
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COL_DEPTH)
	vbox.add_child(label)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	vbox.add_child(row)

	zone_buttons.clear()
	for i in GameData.zones.size():
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(48, 40)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_zone_button_pressed.bind(i))
		row.add_child(btn)
		zone_buttons.append(btn)

	unlock_zone_button = Button.new()
	unlock_zone_button.custom_minimum_size = Vector2(160, 40)
	unlock_zone_button.add_theme_font_size_override("font_size", 11)
	unlock_zone_button.pressed.connect(_on_unlock_zone_pressed)
	row.add_child(unlock_zone_button)

	return vbox


func _build_global_upgrades_block() -> Control:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var label = Label.new()
	label.text = "BOAT UPGRADES"
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COL_BOAT)
	vbox.add_child(label)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	for key in GameData.upgrades.keys():
		row.add_child(_build_upgrade_chip(key))

	return vbox


func _build_upgrade_chip(key: String) -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(190, 40)
	var box = StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	box.set_corner_radius_all(6)
	box.set_border_width_all(1)
	box.border_color = Color(COL_BOAT.r, COL_BOAT.g, COL_BOAT.b, 0.45)
	box.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", box)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	hbox.add_child(info)

	var name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", COL_TEXT)
	info.add_child(name_label)

	var dots_label = Label.new()
	dots_label.add_theme_font_size_override("font_size", 10)
	dots_label.add_theme_color_override("font_color", COL_TEXT_MUTED)
	info.add_child(dots_label)

	var buy = Button.new()
	buy.custom_minimum_size = Vector2(64, 28)
	buy.add_theme_font_size_override("font_size", 10)
	buy.pressed.connect(_on_upgrade_pressed.bind(key))
	hbox.add_child(buy)

	upgrade_chips[key] = {
		"chip": panel,
		"name_label": name_label,
		"dots_label": dots_label,
		"buy_button": buy,
	}
	return panel


# Spears column: custom header with inline capacity + auto-fill, then per-type cards.
# Bag controls live on each card so there's no separate bag list.
func _build_spears_column() -> Control:
	var wrap_box = VBoxContainer.new()
	wrap_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap_box.add_theme_constant_override("separation", 4)

	# Custom header — title + capacity readout + Auto-Fill inline.
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	wrap_box.add_child(header)

	var title = Label.new()
	title.text = "SPEARS"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", COL_SPEARS)
	header.add_child(title)

	var dot = Label.new()
	dot.text = "·"
	dot.add_theme_font_size_override("font_size", 14)
	dot.add_theme_color_override("font_color", COL_TEXT_MUTED)
	header.add_child(dot)

	bag_capacity_label = Label.new()
	bag_capacity_label.add_theme_font_size_override("font_size", 12)
	bag_capacity_label.add_theme_color_override("font_color", COL_TEXT_MUTED)
	header.add_child(bag_capacity_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	fill_bag_button = Button.new()
	fill_bag_button.text = "Auto-Fill Bag"
	fill_bag_button.custom_minimum_size = Vector2(120, 26)
	fill_bag_button.add_theme_font_size_override("font_size", 11)
	fill_bag_button.pressed.connect(_on_fill_bag_pressed)
	header.add_child(fill_bag_button)

	# Card panel — full body for the cards.
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pbox = StyleBoxFlat.new()
	pbox.bg_color = Color(0.08, 0.1, 0.16, 0.9)
	pbox.set_corner_radius_all(8)
	pbox.set_border_width_all(2)
	pbox.border_color = Color(COL_SPEARS.r, COL_SPEARS.g, COL_SPEARS.b, 0.55)
	pbox.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", pbox)
	wrap_box.add_child(panel)

	var card_hbox = HBoxContainer.new()
	card_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_hbox.add_theme_constant_override("separation", 12)
	panel.add_child(card_hbox)

	for t in GameData.spear_types:
		var card_data = _build_spear_card(t)
		card_data["card"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_hbox.add_child(card_data["card"])
		spear_card_widgets[t.id] = card_data

	_apply_zone_gating()
	return wrap_box


# Hide spear cards whose zone gate hasn't been met yet. Called on build and on zone unlocks.
func _apply_zone_gating() -> void:
	for id in spear_card_widgets.keys():
		var w: Dictionary = spear_card_widgets[id]
		var card: Control = w["card"]
		var min_zone: int = int(MIN_ZONE_FOR_SPEAR.get(id, 0))
		card.visible = GameData.unlocked_zone_index >= min_zone


func _build_spear_card(t: SpearType) -> Dictionary:
	var card = PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box = StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.09, 0.13, 0.95)
	box.set_corner_radius_all(6)
	box.set_border_width_all(2)
	box.border_color = Color(t.color.r, t.color.g, t.color.b, 0.4)
	box.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", box)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	# Banner-style projectile preview across the top of the card. Shows even when
	# the spear is locked so players see what they're saving up for. NEAREST
	# filtering keeps the pixel-art crisp at any scale.
	var sprite_path: String = SPEAR_SPRITE_PATHS.get(t.id, "")
	if sprite_path != "":
		var preview := TextureRect.new()
		preview.texture = load(sprite_path)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.custom_minimum_size = Vector2(0, 56)
		preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(preview)

	var header = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header)

	var swatch = ColorRect.new()
	swatch.custom_minimum_size = Vector2(8, 24)
	swatch.color = t.color
	header.add_child(swatch)

	var name_lbl = Label.new()
	name_lbl.text = t.display_name
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", COL_TEXT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_lbl)

	var status_lbl = Label.new()
	status_lbl.add_theme_font_size_override("font_size", 11)
	status_lbl.add_theme_color_override("font_color", COL_TEXT_MUTED)
	header.add_child(status_lbl)

	var desc = Label.new()
	desc.text = t.description
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", COL_TEXT_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	# In-card bag controls: − [ count ] +. Centered, prominent.
	var bag_row = HBoxContainer.new()
	bag_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bag_row.add_theme_constant_override("separation", 8)
	vbox.add_child(bag_row)

	var minus = Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(36, 32)
	minus.add_theme_font_size_override("font_size", 18)
	minus.pressed.connect(_on_bag_minus.bind(t.id))
	bag_row.add_child(minus)

	var count_lbl = Label.new()
	count_lbl.custom_minimum_size = Vector2(80, 0)
	count_lbl.add_theme_font_size_override("font_size", 22)
	count_lbl.add_theme_color_override("font_color", COL_TEXT)
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bag_row.add_child(count_lbl)

	var plus = Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(36, 32)
	plus.add_theme_font_size_override("font_size", 18)
	plus.pressed.connect(_on_bag_plus.bind(t.id))
	bag_row.add_child(plus)

	var bag_caption = Label.new()
	bag_caption.text = "in bag"
	bag_caption.add_theme_font_size_override("font_size", 10)
	bag_caption.add_theme_color_override("font_color", COL_TEXT_MUTED)
	bag_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(bag_caption)

	var unlock_btn = Button.new()
	unlock_btn.custom_minimum_size = Vector2(0, 32)
	unlock_btn.add_theme_font_size_override("font_size", 12)
	unlock_btn.pressed.connect(_on_unlock_spear_pressed.bind(t.id))
	vbox.add_child(unlock_btn)

	# Spacer pushes the icon strip toward the bottom of the card.
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Horizontal icon-tile strip — each upgrade is a single button with icon + price.
	var tile_row = HBoxContainer.new()
	tile_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tile_row.add_theme_constant_override("separation", 6)
	vbox.add_child(tile_row)

	var upgrade_rows_local: Dictionary = {}
	for key in t.upgrades.keys():
		var def: Dictionary = t.upgrades[key]
		var tile = _build_upgrade_tile(t.id, key, def)
		tile_row.add_child(tile["button"])
		upgrade_rows_local[key] = tile

	return {
		"card": card,
		"unlock_btn": unlock_btn,
		"status_lbl": status_lbl,
		"upgrade_rows": upgrade_rows_local,
		"bag_row": bag_row,
		"bag_minus": minus,
		"bag_count": count_lbl,
		"bag_plus": plus,
		"bag_caption": bag_caption,
	}


# Single icon tile for a per-spear upgrade. Button contains icon + tiny pip row;
# tooltip surfaces full name + description on hover. Razor Edge gets a goal accent.
func _build_upgrade_tile(spear_id: StringName, key: String, def: Dictionary) -> Dictionary:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(82, 72)
	btn.add_theme_font_size_override("font_size", 18)
	btn.clip_text = false
	btn.pressed.connect(_on_spear_upgrade_pressed.bind(spear_id, key))
	# Tooltip: name + description + cost.
	btn.tooltip_text = "%s\n%s" % [def.get("name", key), def.get("description", "")]
	# Stack icon glyph on top of pip + price using a custom child layout.
	var content = VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 2)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(content)

	var icon_lbl = Label.new()
	icon_lbl.text = def.get("icon", "?")
	icon_lbl.add_theme_font_size_override("font_size", 18)
	icon_lbl.add_theme_color_override("font_color", COL_TEXT)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(icon_lbl)

	var pips_lbl = RichTextLabel.new()
	pips_lbl.bbcode_enabled = true
	pips_lbl.fit_content = true
	pips_lbl.scroll_active = false
	pips_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	pips_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips_lbl.add_theme_font_size_override("normal_font_size", 13)
	pips_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(pips_lbl)

	var price_lbl = Label.new()
	price_lbl.add_theme_font_size_override("font_size", 10)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(price_lbl)

	# Highlight Razor Edge (the L1 milestone goal) with a warm accent border.
	var is_goal := key == "pierce_count"
	return {
		"button": btn,
		"icon_lbl": icon_lbl,
		"pips_lbl": pips_lbl,
		"price_lbl": price_lbl,
		"is_goal": is_goal,
	}


func _style_tile(button: Button, is_goal: bool, state: String) -> void:
	var sb = StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	match state:
		"buyable":
			sb.bg_color = Color(0.10, 0.14, 0.20)
			sb.border_color = Color(0.55, 0.95, 0.65, 0.7) if is_goal else Color(0.55, 0.7, 0.95, 0.5)
		"goal":  # buyable + Razor-Edge highlight at low level
			sb.bg_color = Color(0.16, 0.16, 0.08)
			sb.border_color = Color(1.0, 0.85, 0.35)
			sb.set_border_width_all(2)
		"max":
			sb.bg_color = Color(0.06, 0.10, 0.06)
			sb.border_color = Color(0.4, 0.7, 0.5, 0.5)
		"locked":
			sb.bg_color = Color(0.05, 0.06, 0.08)
			sb.border_color = Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.3)
		_:  # "unaffordable"
			sb.bg_color = Color(0.08, 0.10, 0.13)
			sb.border_color = Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.4)
	button.add_theme_stylebox_override("normal", sb)
	button.add_theme_stylebox_override("hover", sb)
	button.add_theme_stylebox_override("pressed", sb)
	button.add_theme_stylebox_override("disabled", sb)


func _build_footer() -> Control:
	var footer = HBoxContainer.new()
	footer.custom_minimum_size = Vector2(0, 32)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	cheat_button = Button.new()
	cheat_button.custom_minimum_size = Vector2(140, 28)
	cheat_button.add_theme_font_size_override("font_size", 11)
	cheat_button.pressed.connect(_on_cheat_toggle)
	footer.add_child(cheat_button)

	return footer


func _build_section_panel(title: String, accent: Color) -> Control:
	var wrap_box = VBoxContainer.new()
	wrap_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap_box.add_theme_constant_override("separation", 4)

	var header = Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", accent)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap_box.add_child(header)

	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box = StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.1, 0.16, 0.9)
	box.set_corner_radius_all(8)
	box.set_border_width_all(2)
	box.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	box.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", box)
	wrap_box.add_child(panel)

	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)

	wrap_box.set_meta("content", content)
	return wrap_box


# --- Refresh ---

func _refresh_all() -> void:
	_update_cash()
	_refresh_upgrade_chips()
	_refresh_zone_buttons()
	_refresh_unlock_zone_button()
	_refresh_cheat_button()
	_refresh_dive_button()
	_apply_zone_gating()
	_refresh_spear_column()


func _refresh_upgrade_chips() -> void:
	for key in upgrade_chips.keys():
		var d: Dictionary = upgrade_chips[key]
		var name_label: Label = d["name_label"]
		var dots_label: Label = d["dots_label"]
		var buy: Button = d["buy_button"]
		var upgrade = GameData.upgrades[key]
		var level: int = GameData.upgrade_levels[key]
		var max_level: int = upgrade["max_level"]
		name_label.text = upgrade["name"]
		dots_label.text = _level_dots(level, max_level)
		if level >= max_level:
			buy.text = "MAX"
			buy.disabled = true
		else:
			var cost: int = upgrade["costs"][level]
			buy.text = "$%d" % cost
			buy.disabled = not GameData.cheat_mode and GameData.cash < cost


func _refresh_zone_buttons() -> void:
	for i in zone_buttons.size():
		var btn: Button = zone_buttons[i]
		var zone: ZoneConfig = GameData.zones[i]
		var unlocked: bool = GameData.can_select_zone(i)
		var selected: bool = (i == GameData.selected_zone_index)
		btn.text = "%d\n%dm" % [i + 1, zone.depth_meters]
		btn.disabled = not unlocked
		btn.tooltip_text = zone.display_name
		var sb = StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(2)
		sb.set_content_margin_all(4)
		if selected:
			sb.bg_color = Color(0.25, 0.18, 0.05)
			sb.border_color = COL_DEPTH
		elif unlocked:
			sb.bg_color = Color(0.08, 0.1, 0.15)
			sb.border_color = Color(COL_DEPTH.r, COL_DEPTH.g, COL_DEPTH.b, 0.4)
		else:
			sb.bg_color = Color(0.05, 0.06, 0.08)
			sb.border_color = Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.3)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_stylebox_override("disabled", sb)


func _refresh_spear_column() -> void:
	if bag_capacity_label == null:
		return
	var cap := GameData.get_bag_capacity()
	var loaded := GameData.get_bag_loaded_count()
	bag_capacity_label.text = "Bag %d / %d" % [loaded, cap]

	if fill_bag_button:
		fill_bag_button.disabled = loaded >= cap

	for id in spear_card_widgets.keys():
		var w: Dictionary = spear_card_widgets[id]
		var t := GameData.get_spear_type(id)
		var status_lbl: Label = w["status_lbl"]
		var unlock_btn: Button = w["unlock_btn"]
		var bag_minus: Button = w["bag_minus"]
		var bag_plus: Button = w["bag_plus"]
		var bag_count: Label = w["bag_count"]
		var bag_caption: Label = w["bag_caption"]
		var unlocked := GameData.is_spear_type_unlocked(id)
		var in_bag := int(GameData.bag_loadout.get(id, 0))
		if unlocked:
			status_lbl.text = "UNLOCKED"
			status_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
			unlock_btn.visible = false
		else:
			status_lbl.text = "LOCKED"
			status_lbl.add_theme_color_override("font_color", COL_TEXT_MUTED)
			unlock_btn.visible = true
			unlock_btn.text = "UNLOCK — $%d" % t.unlock_cost
			unlock_btn.disabled = not GameData.cheat_mode and GameData.cash < t.unlock_cost
		# Bag controls
		bag_count.text = "%d" % in_bag
		bag_minus.disabled = in_bag <= 0 or not unlocked
		bag_plus.disabled = not GameData.can_increment_bag(id)
		var bag_color: Color = COL_TEXT if unlocked else COL_TEXT_MUTED
		bag_count.add_theme_color_override("font_color", bag_color)
		bag_caption.add_theme_color_override("font_color", COL_TEXT_MUTED if unlocked else Color(COL_TEXT_MUTED.r, COL_TEXT_MUTED.g, COL_TEXT_MUTED.b, 0.4))

		var upg_rows: Dictionary = w["upgrade_rows"]
		for key in upg_rows.keys():
			var def: Dictionary = t.upgrades[key]
			var ud: Dictionary = upg_rows[key]
			var btn: Button = ud["button"]
			var pips: RichTextLabel = ud["pips_lbl"]
			var price: Label = ud["price_lbl"]
			var is_goal: bool = ud["is_goal"]
			var level := GameData.get_spear_upgrade_level(id, key)
			var max_level: int = int(def["max_level"])
			pips.text = _pip_string(level, max_level)
			var state := "locked"
			if not unlocked:
				price.text = "—"
				price.add_theme_color_override("font_color", COL_TEXT_MUTED)
				btn.disabled = true
				state = "locked"
			elif level >= max_level:
				price.text = "MAX"
				price.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
				btn.disabled = true
				state = "max"
			else:
				var cost: int = int((def["costs"] as Array)[level])
				price.text = "$%d" % cost
				if GameData.cheat_mode or GameData.cash >= cost:
					price.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
					btn.disabled = false
					state = "goal" if (is_goal and level == 0) else "buyable"
				else:
					price.add_theme_color_override("font_color", COL_TEXT_MUTED)
					btn.disabled = true
					state = "unaffordable"
			# Tooltip stays static — just keep the cost in the tile.
			btn.tooltip_text = "%s\n%s" % [def.get("name", key), def.get("description", "")]
			_style_tile(btn, is_goal, state)


func _pip_string(level: int, max_level: int) -> String:
	# BBCode-colored dots for prominence on the tile (filled = warm yellow, hollow = dim gray).
	var filled_hex := COL_PIP_FILLED.to_html(false)
	var hollow_hex := COL_PIP_HOLLOW.to_html(false)
	var s := "[center]"
	for i in max_level:
		if i < level:
			s += "[color=#%s]●[/color]" % filled_hex
		else:
			s += "[color=#%s]○[/color]" % hollow_hex
	s += "[/center]"
	return s


func _level_dots(level: int, max_level: int) -> String:
	var visual_max: int = mini(max_level, 10)
	var ratio := float(level) / float(max(1, max_level))
	var filled: int = roundi(ratio * visual_max)
	if level > 0 and filled == 0:
		filled = 1
	if level >= max_level:
		filled = visual_max
	var s := ""
	for i in visual_max:
		s += "●" if i < filled else "○"
	s += "  Lv %d/%d" % [level, max_level]
	return s


func _refresh_unlock_zone_button() -> void:
	var next_idx = GameData.unlocked_zone_index + 1
	if next_idx >= GameData.zones.size():
		unlock_zone_button.text = "All zones unlocked"
		unlock_zone_button.disabled = true
		return
	var next_zone: ZoneConfig = GameData.zones[next_idx]
	unlock_zone_button.text = "Unlock %s — $%d" % [next_zone.display_name, next_zone.unlock_cost]
	unlock_zone_button.disabled = not GameData.can_unlock_next_zone()


func _refresh_cheat_button() -> void:
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(4)
	if GameData.cheat_mode:
		cheat_button.text = "Cheat: ON"
		s.bg_color = Color(0.6, 0.2, 0.2)
	else:
		cheat_button.text = "Cheat: OFF"
		s.bg_color = Color(0.18, 0.18, 0.22)
	cheat_button.add_theme_stylebox_override("normal", s)


func _refresh_dive_button() -> void:
	dive_button.text = "🐟  DIVE"
	dive_button.disabled = false


# --- Handlers ---

func _on_upgrade_pressed(key: String) -> void:
	if GameData.buy_upgrade(key):
		Sfx.cash(8)
		_refresh_all()


func _on_zone_button_pressed(idx: int) -> void:
	GameData.select_zone(idx)
	_refresh_zone_buttons()


func _on_unlock_zone_pressed() -> void:
	if GameData.unlock_next_zone():
		Sfx.unlock()
		_refresh_all()


func _on_cheat_toggle() -> void:
	GameData.toggle_cheat_mode()
	_refresh_all()


func _on_dive_pressed() -> void:
	hide_shop()
	next_dive_pressed.emit()


func _on_bag_plus(id: StringName) -> void:
	GameData.increment_bag(id)


func _on_bag_minus(id: StringName) -> void:
	GameData.decrement_bag(id)


func _on_fill_bag_pressed() -> void:
	GameData.auto_fill_bag()


func _on_unlock_spear_pressed(id: StringName) -> void:
	if GameData.unlock_spear_type(id):
		Sfx.unlock()


func _on_spear_upgrade_pressed(id: StringName, key: String) -> void:
	if GameData.buy_spear_upgrade(id, key):
		Sfx.cash(8)


func _on_cash_changed(_amount: float) -> void:
	_update_cash()
	_refresh_upgrade_chips()
	_refresh_unlock_zone_button()
	_refresh_zone_buttons()
	_refresh_spear_column()


func _update_cash() -> void:
	if GameData.cheat_mode:
		cash_label.text = "💰  ∞  (CHEAT)"
	else:
		cash_label.text = "💰  $%d" % int(GameData.cash)


func show_shop() -> void:
	root_control.visible = true
	_refresh_all()


func hide_shop() -> void:
	root_control.visible = false
