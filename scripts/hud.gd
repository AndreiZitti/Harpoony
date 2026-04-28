extends CanvasLayer

signal dev_panel_button_pressed

var oxygen_bar: ProgressBar
var oxygen_label: Label
var dive_cash_label: Label
var total_cash_label: Label
var queue_preview: HBoxContainer
var queue_chips: Array[PanelContainer] = []
const QUEUE_PREVIEW_LEN := 3
var summary_toast: PanelContainer
var summary_label: Label
var resurface_button: Button
var zone_name_label: Label
var zone_depth_label: Label
var popups: Control
var session_timer_label: Label
var session_reset_button: Button
var session_time: float = 0.0
var dive_counter_label: Label
var dev_button: Button = null
var trophy_target: Node2D = null
var trophy_marker: Label = null
var reload_label: Label = null
var reload_bar: ProgressBar = null

const SPEAR_TEXTURES := {
	&"normal": preload("res://assets/spears/normal.png"),
	&"net": preload("res://assets/spears/net.png"),
	&"heavy": preload("res://assets/spears/heavy.png"),
}

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
	GameData.zone_changed.connect(func(_z): _refresh_depth())
	GameData.zone_unlocked.connect(func(_i): _refresh_depth())
	GameData.dive_number_changed.connect(_on_dive_number_changed)
	GameData.reload_state_changed.connect(_on_reload_state_changed)
	_refresh()


func _on_reload_state_changed(active: bool) -> void:
	if reload_label:
		reload_label.visible = active
	if reload_bar:
		reload_bar.visible = active
		if not active:
			reload_bar.value = 1.0


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

	# Left: total cash + session timer
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 2)
	top_hbox.add_child(left_vbox)

	total_cash_label = Label.new()
	total_cash_label.text = "$0"
	total_cash_label.add_theme_font_size_override("font_size", 22)
	total_cash_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	left_vbox.add_child(total_cash_label)

	# Dive counter — soft campaign target is 100 dives. Hidden before first dive.
	dive_counter_label = Label.new()
	dive_counter_label.text = ""
	dive_counter_label.add_theme_font_size_override("font_size", 13)
	dive_counter_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92))
	dive_counter_label.visible = false
	left_vbox.add_child(dive_counter_label)

	session_timer_label = Label.new()
	session_timer_label.text = "0:00"
	session_timer_label.add_theme_font_size_override("font_size", 13)
	session_timer_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	left_vbox.add_child(session_timer_label)

	session_reset_button = Button.new()
	session_reset_button.text = "Reset"
	session_reset_button.custom_minimum_size = Vector2(72, 22)
	session_reset_button.add_theme_font_size_override("font_size", 10)
	session_reset_button.pressed.connect(_on_session_reset)
	left_vbox.add_child(session_reset_button)

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

	# Queue preview — bottom-center, shows the next N shots from the shuffled bag.
	var bottom = MarginContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -90
	bottom.add_theme_constant_override("margin_bottom", 16)
	add_child(bottom)

	var queue_vbox = VBoxContainer.new()
	queue_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	queue_vbox.add_theme_constant_override("separation", 4)
	bottom.add_child(queue_vbox)

	var queue_label = Label.new()
	queue_label.text = "NEXT SHOTS"
	queue_label.add_theme_font_size_override("font_size", 10)
	queue_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	queue_vbox.add_child(queue_label)

	queue_preview = HBoxContainer.new()
	queue_preview.alignment = BoxContainer.ALIGNMENT_CENTER
	queue_preview.add_theme_constant_override("separation", 8)
	queue_vbox.add_child(queue_preview)

	queue_chips.clear()
	for i in QUEUE_PREVIEW_LEN:
		queue_chips.append(_build_queue_chip(i))
		queue_preview.add_child(queue_chips[i])

	# Reload indicator — tucked under the queue preview. The label fades while
	# active so the player can see "the spears are being reshuffled" without it
	# competing with the cash popups for attention.
	reload_label = Label.new()
	reload_label.text = "RELOADING…"
	reload_label.add_theme_font_size_override("font_size", 11)
	reload_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.30))
	reload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reload_label.visible = false
	queue_vbox.add_child(reload_label)

	reload_bar = ProgressBar.new()
	reload_bar.show_percentage = false
	reload_bar.custom_minimum_size = Vector2(160, 4)
	reload_bar.min_value = 0.0
	reload_bar.max_value = 1.0
	reload_bar.value = 0.0
	reload_bar.visible = false
	queue_vbox.add_child(reload_bar)


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

	summary_toast = _build_summary_toast()
	add_child(summary_toast)

	# Floating "DEV" button — top-right corner, only when cheat_mode is on.
	# Click toggles the dev panel without going through the ESC menu.
	dev_button = Button.new()
	dev_button.text = "DEV"
	dev_button.custom_minimum_size = Vector2(54, 28)
	dev_button.add_theme_font_size_override("font_size", 12)
	dev_button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	var dev_sb := StyleBoxFlat.new()
	dev_sb.bg_color = Color(0.1, 0.13, 0.18, 0.85)
	dev_sb.border_color = Color(0.85, 0.78, 0.45, 0.7)
	dev_sb.set_border_width_all(1)
	dev_sb.set_corner_radius_all(4)
	dev_button.add_theme_stylebox_override("normal", dev_sb)
	# Anchor top-right corner of the viewport.
	dev_button.anchor_left = 1.0
	dev_button.anchor_right = 1.0
	dev_button.anchor_top = 0.0
	dev_button.anchor_bottom = 0.0
	dev_button.offset_left = -64
	dev_button.offset_right = -10
	dev_button.offset_top = 10
	dev_button.offset_bottom = 38
	dev_button.visible = GameData.cheat_mode
	dev_button.pressed.connect(func(): dev_panel_button_pressed.emit())
	add_child(dev_button)


func spawn_cash_popup(value: int, world_pos: Vector2, species: String) -> void:
	# Font size + travel distance scale with the catch value so big hauls feel big.
	var size: int = clampi(14 + int(value * 0.6), 14, 38)
	var rise: float = 50.0 + clampf(value * 1.4, 0.0, 60.0)
	var hold: float = 0.35 + clampf(value * 0.005, 0.0, 0.4)
	var label := Label.new()
	label.text = "+$%d" % value
	label.add_theme_font_size_override("font_size", size)
	var tint: Color = SPECIES_COLOR.get(species, Color.WHITE)
	label.add_theme_color_override("font_color", tint)
	# Subtle outline so it stays readable on busy backgrounds.
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.pivot_offset = Vector2(40, size * 0.6)
	label.position = world_pos - label.pivot_offset
	label.z_index = 100
	label.scale = Vector2(0.6, 0.6)
	popups.add_child(label)
	var t := create_tween()
	t.set_parallel(true)
	# Pop in with a slight overshoot so it reads as a hit.
	t.tween_property(label, "scale", Vector2(1.15, 1.15), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "scale", Vector2(1.0, 1.0), 0.18).set_delay(0.10)
	t.tween_property(label, "position:y", label.position.y - rise, hold + 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(hold)
	t.chain().tween_callback(label.queue_free)


func _refresh() -> void:
	_on_cash_changed(GameData.cash)
	_on_oxygen_changed(GameData.oxygen)
	_on_dive_state_changed(GameData.dive_state)
	_on_dive_number_changed(GameData.dive_number)
	_refresh_depth()
	_refresh_queue_preview()


func _on_dive_number_changed(n: int) -> void:
	if dive_counter_label == null:
		return
	if n <= 0:
		dive_counter_label.visible = false
		dive_counter_label.text = ""
		return
	dive_counter_label.visible = true
	dive_counter_label.text = "Dive %d / 100" % n


func _on_cash_changed(_amount: float) -> void:
	total_cash_label.text = "$%d" % int(GameData.cash)
	if GameData.dive_state == GameData.DiveState.UNDERWATER:
		dive_cash_label.text = "+$%d" % int(GameData.dive_cash)
	else:
		dive_cash_label.text = ""


const OXYGEN_COL_FULL := Color(0.30, 0.85, 0.65)   # calm green
const OXYGEN_COL_WARN := Color(1.00, 0.78, 0.30)   # amber
const OXYGEN_COL_CRIT := Color(1.00, 0.30, 0.30)   # red
const OXYGEN_FLASH_THRESHOLD := 5.0                # seconds — pulse the bar


func _on_oxygen_changed(value: float) -> void:
	oxygen_bar.max_value = GameData.get_oxygen_capacity()
	oxygen_bar.value = value
	oxygen_label.text = "OXYGEN %.1fs" % value
	# Three bands keyed off remaining *seconds*, not ratio — feel is consistent
	# even after Tank Capacity upgrades push the cap higher.
	var color := OXYGEN_COL_FULL
	if value <= OXYGEN_FLASH_THRESHOLD:
		color = OXYGEN_COL_CRIT
	elif value <= OXYGEN_FLASH_THRESHOLD * 2.0:
		color = OXYGEN_COL_WARN
	var bar_fg = StyleBoxFlat.new()
	bar_fg.bg_color = color
	bar_fg.set_corner_radius_all(6)
	oxygen_bar.add_theme_stylebox_override("fill", bar_fg)
	oxygen_label.add_theme_color_override("font_color", color.lightened(0.15))


func _on_dive_state_changed(state: int) -> void:
	var underwater = state == GameData.DiveState.UNDERWATER
	resurface_button.visible = underwater
	_refresh_queue_preview()
	_on_cash_changed(0.0)


func _refresh_depth() -> void:
	if zone_name_label == null:
		return
	var zone := GameData.get_current_zone()
	if zone == null:
		return
	zone_name_label.text = zone.display_name
	zone_depth_label.text = "%dm  ·  Zone %d/%d" % [zone.depth_meters, GameData.selected_zone_index + 1, GameData.zones.size()]


func _build_queue_chip(idx: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(56, 56) if idx == 0 else Vector2(40, 40)
	# First chip is bigger — that's the imminent shot.
	var box = StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.08, 0.12, 0.9)
	box.set_corner_radius_all(8)
	box.set_border_width_all(2)
	box.border_color = Color(0.5, 0.6, 0.8, 0.5)
	box.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", box)
	# Spear sprite — pixel art, NEAREST filtering, fits the chip with margin.
	var sprite := TextureRect.new()
	sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.name = "Sprite"
	panel.add_child(sprite)
	# Empty-slot fallback glyph — only visible when there's no spear queued at
	# this index (round drained, waiting for reshuffle).
	var lbl = Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24 if idx == 0 else 18)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.name = "Glyph"
	lbl.visible = false
	panel.add_child(lbl)
	return panel


func _refresh_queue_preview() -> void:
	if queue_preview == null:
		return
	var underwater := GameData.dive_state == GameData.DiveState.UNDERWATER \
			or GameData.dive_state == GameData.DiveState.DIVING \
			or GameData.dive_state == GameData.DiveState.RESURFACING
	queue_preview.get_parent().visible = underwater
	if not underwater:
		return
	var ids := GameData.peek_bag_queue(QUEUE_PREVIEW_LEN)
	for i in queue_chips.size():
		var chip := queue_chips[i]
		var glyph := chip.get_node("Glyph") as Label
		var sprite := chip.get_node("Sprite") as TextureRect
		var sb = StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(2)
		sb.set_content_margin_all(4)
		if i < ids.size():
			var id: StringName = ids[i]
			var t := GameData.get_spear_type(id)
			var c: Color = t.color if t else Color(0.6, 0.6, 0.7)
			sprite.texture = SPEAR_TEXTURES.get(id, null)
			sprite.visible = sprite.texture != null
			glyph.visible = sprite.texture == null
			if not sprite.visible:
				glyph.text = t.icon_glyph if t else "?"
				glyph.add_theme_color_override("font_color", c)
			sb.bg_color = Color(c.r * 0.18, c.g * 0.18, c.b * 0.18, 0.95)
			sb.border_color = c
			# First chip pops with full intensity.
			if i == 0:
				sb.bg_color = Color(c.r * 0.28, c.g * 0.28, c.b * 0.28, 0.95)
		else:
			# Empty slot — round drained, waiting for reload to finish.
			sprite.texture = null
			sprite.visible = false
			glyph.visible = true
			glyph.text = "·"
			glyph.add_theme_color_override("font_color", Color(0.4, 0.45, 0.55))
			sb.bg_color = Color(0.06, 0.07, 0.10, 0.6)
			sb.border_color = Color(0.3, 0.35, 0.45, 0.4)
		chip.add_theme_stylebox_override("panel", sb)


func notify_bag_changed() -> void:
	_refresh_queue_preview()


func _build_summary_toast() -> PanelContainer:
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.position = Vector2(0, 110)
	panel.custom_minimum_size = Vector2(0, 40)
	panel.size_flags_horizontal = Control.SIZE_FILL
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.10, 0.16, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.4, 1.0, 0.5, 0.6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)

	summary_label = Label.new()
	summary_label.add_theme_font_size_override("font_size", 16)
	summary_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(summary_label)

	# Center horizontally with a fixed width.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -200
	panel.offset_right = 200
	panel.offset_top = 110
	panel.offset_bottom = 160
	panel.modulate.a = 0.0
	return panel


func show_dive_summary(cash_earned: int, fish: int, shots: int) -> void:
	if summary_toast == null or summary_label == null:
		return
	var hit_rate := 0
	if shots > 0:
		hit_rate = int(round(100.0 * float(fish) / float(shots)))
	summary_label.text = "+$%d  ·  %d fish  ·  %d / %d shots (%d%%)" % [cash_earned, fish, fish, shots, hit_rate]
	summary_toast.modulate.a = 0.0
	summary_toast.visible = true
	var t := create_tween()
	t.tween_property(summary_toast, "modulate:a", 1.0, 0.20)
	t.tween_interval(2.4)
	t.tween_property(summary_toast, "modulate:a", 0.0, 0.50)


func _on_resurface_pressed() -> void:
	var main = get_tree().current_scene
	if main and main.has_method("begin_manual_resurface"):
		main.begin_manual_resurface()


func mark_trophy_target(node: Node2D) -> void:
	# Whale Sonar (Heavy keystone) calls this with the force-spawned trophy.
	# A small floating beacon tracks the fish's position until it despawns.
	trophy_target = node
	if trophy_marker == null:
		trophy_marker = Label.new()
		trophy_marker.text = "▼ TROPHY"
		trophy_marker.add_theme_font_size_override("font_size", 14)
		trophy_marker.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
		trophy_marker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		trophy_marker.add_theme_constant_override("outline_size", 4)
		trophy_marker.z_index = 100
		add_child(trophy_marker)
	trophy_marker.visible = true


func _process(delta: float) -> void:
	# Stopwatch ticks regardless of dive state — measures real wall-clock playtime.
	session_time += delta
	if session_timer_label:
		var total: int = int(session_time)
		@warning_ignore("integer_division")
		var mins: int = total / 60
		var secs: int = total % 60
		session_timer_label.text = "%d:%02d" % [mins, secs]
	# Cheat mode can be toggled at runtime — keep the DEV button in sync.
	if dev_button and dev_button.visible != GameData.cheat_mode:
		dev_button.visible = GameData.cheat_mode
	# Reload progress bar — drives off GameData each frame while reloading.
	if reload_bar and reload_bar.visible:
		reload_bar.value = GameData.reload_progress()
	if reload_label and reload_label.visible:
		# Subtle pulse so the eye picks it up without it being distracting.
		var pulse := 0.65 + 0.35 * sin(session_time * 8.0)
		reload_label.modulate.a = pulse
	# Oxygen flash — last few seconds the bar pulses brightness so the player
	# notices in peripheral vision. Frequency ramps up the lower it gets.
	if oxygen_bar and GameData.dive_state == GameData.DiveState.UNDERWATER:
		if GameData.oxygen <= OXYGEN_FLASH_THRESHOLD and GameData.oxygen > 0.0:
			var freq: float = 6.0 + (OXYGEN_FLASH_THRESHOLD - GameData.oxygen) * 1.5
			var alpha: float = 0.55 + 0.45 * absf(sin(session_time * freq))
			oxygen_bar.modulate.a = alpha
			oxygen_label.modulate.a = alpha
		else:
			oxygen_bar.modulate.a = 1.0
			oxygen_label.modulate.a = 1.0
	# Trophy sonar marker — bob above the marked fish until it despawns.
	if trophy_marker:
		if trophy_target != null and is_instance_valid(trophy_target) and not (trophy_target is Fish and (trophy_target as Fish).speared):
			var bob := sin(session_time * 4.0) * 4.0
			trophy_marker.position = trophy_target.global_position + Vector2(-trophy_marker.size.x * 0.5, -36.0 + bob)
			trophy_marker.visible = true
		else:
			trophy_marker.visible = false
			trophy_target = null


func _on_session_reset() -> void:
	session_time = 0.0
	if session_timer_label:
		session_timer_label.text = "0:00"
