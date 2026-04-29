extends CanvasLayer

# Title screen. Sits on top of the live boat-on-water scene as a transparent
# overlay — no dimmer, no panel — so the boot frame is the actual game world.
# Title text floats in the sky band with an idle bob; buttons sit below the
# waterline. Replace TITLE_LOGO_SLOT with a sprite when the logo asset lands.

signal mode_selected(mode: StringName)  # &"continue", &"new_game", or &"dev"
signal bestiary_pressed

const TITLE := "HARPOONY"
const SUBTITLE := "An arcade spearfishing campaign"

var _root: Control
var _title_box: Label = null
var _title_anchor_y: float = 0.0
var _bob_time: float = 0.0
# When the player taps New Game with a save present, the button cluster is
# replaced in-place by a confirm overlay. _btn_box holds the original cluster
# so we can fade it back in if they cancel.
var _btn_box: VBoxContainer = null
var _confirm_box: VBoxContainer = null


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _process(delta: float) -> void:
	if _title_box == null:
		return
	_bob_time += delta
	# Gentle vertical bob — sells the "floating over water" feel without distracting.
	_title_box.position.y = _title_anchor_y + sin(_bob_time * 1.6) * 4.0


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)

	# Title block — anchored top-center, sits in the sky band above the boat.
	# Sky band in main.gd is 0..140 px so we keep the text in 8..96 to leave a
	# breathing strip above the waterline and avoid clipping into the hull.
	# Single Label with built-in shadow + outline themes so the bob can't desync
	# a separate shadow node — earlier two-Label approach produced render ghosts.
	_title_box = Label.new()
	_title_box.text = TITLE
	_title_box.add_theme_font_size_override("font_size", 72)
	_title_box.add_theme_color_override("font_color", Color(1.0, 0.93, 0.6))
	_title_box.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.14))
	_title_box.add_theme_constant_override("outline_size", 8)
	_title_box.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.10, 0.7))
	_title_box.add_theme_constant_override("shadow_offset_x", 4)
	_title_box.add_theme_constant_override("shadow_offset_y", 4)
	_title_box.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_box.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_title_box.anchor_left = 0.5
	_title_box.anchor_right = 0.5
	_title_box.anchor_top = 0.0
	_title_box.anchor_bottom = 0.0
	_title_box.offset_left = -380
	_title_box.offset_right = 380
	_title_box.offset_top = 8
	_title_box.offset_bottom = 100
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_anchor_y = _title_box.position.y
	_root.add_child(_title_box)

	# Subtitle — anchored just below the title block, still in the sky band.
	var subtitle := Label.new()
	subtitle.text = SUBTITLE
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98, 0.85))
	subtitle.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.14))
	subtitle.add_theme_constant_override("outline_size", 4)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.anchor_left = 0.0
	subtitle.anchor_right = 1.0
	subtitle.anchor_top = 0.0
	subtitle.anchor_bottom = 0.0
	subtitle.offset_top = 108
	subtitle.offset_bottom = 130
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(subtitle)

	# Button cluster — anchored bottom-center over the deeper water band so it
	# never overlaps the boat hull. Vertical stack with comfortable hit boxes.
	_btn_box = VBoxContainer.new()
	_btn_box.anchor_left = 0.5
	_btn_box.anchor_right = 0.5
	_btn_box.anchor_top = 1.0
	_btn_box.anchor_bottom = 1.0
	_btn_box.offset_left = -160
	_btn_box.offset_right = 160
	_btn_box.offset_top = -240
	_btn_box.offset_bottom = -60
	_btn_box.add_theme_constant_override("separation", 12)
	_root.add_child(_btn_box)

	# Continue is the primary action when a save exists; otherwise New Game is
	# primary and Continue is hidden.
	var has_save := GameData.progress_exists()

	if has_save:
		var continue_btn := _make_button("Continue", true)
		continue_btn.pressed.connect(func(): _select(&"continue"))
		_btn_box.add_child(continue_btn)

		var new_game_btn := _make_button("New Game", false)
		new_game_btn.pressed.connect(_on_new_game_pressed)
		_btn_box.add_child(new_game_btn)
	else:
		var new_game_btn := _make_button("New Game", true)
		new_game_btn.pressed.connect(func(): _select(&"new_game"))
		_btn_box.add_child(new_game_btn)

	var bestiary_btn := _make_button("Bestiary", false)
	bestiary_btn.pressed.connect(func(): bestiary_pressed.emit())
	_btn_box.add_child(bestiary_btn)

	var dev_btn := _make_button("Dev Mode", false)
	dev_btn.pressed.connect(func(): _select(&"dev"))
	_btn_box.add_child(dev_btn)

	var hint := Label.new()
	hint.text = "Dev Mode is a sandbox — your saved game won't be touched."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98, 0.7))
	hint.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.14))
	hint.add_theme_constant_override("outline_size", 3)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_btn_box.add_child(hint)

	# Fade in the whole overlay.
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# Pixel-art friendly button: cream fill for primary, transparent + cream border
# for secondary. Hover/press handled by stylebox swaps.
func _make_button(text: String, primary: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 48 if primary else 40)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 18 if primary else 15)

	var normal_sb := StyleBoxFlat.new()
	var hover_sb := StyleBoxFlat.new()
	var pressed_sb := StyleBoxFlat.new()

	if primary:
		normal_sb.bg_color = Color(1.0, 0.88, 0.45, 0.95)
		hover_sb.bg_color = Color(1.0, 0.95, 0.6, 1.0)
		pressed_sb.bg_color = Color(0.85, 0.72, 0.32, 1.0)
		btn.add_theme_color_override("font_color", Color(0.08, 0.10, 0.18))
		btn.add_theme_color_override("font_hover_color", Color(0.05, 0.07, 0.14))
		btn.add_theme_color_override("font_pressed_color", Color(0.05, 0.07, 0.14))
	else:
		normal_sb.bg_color = Color(0.05, 0.08, 0.14, 0.55)
		hover_sb.bg_color = Color(0.08, 0.14, 0.22, 0.7)
		pressed_sb.bg_color = Color(0.04, 0.06, 0.10, 0.85)
		btn.add_theme_color_override("font_color", Color(1.0, 0.93, 0.6))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.75))
		btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.78, 0.5))

	for sb in [normal_sb, hover_sb, pressed_sb]:
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.05, 0.07, 0.14, 0.9) if primary else Color(1.0, 0.93, 0.6, 0.85)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8

	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	btn.add_theme_stylebox_override("focus", normal_sb)
	return btn


func _select(mode: StringName) -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		mode_selected.emit(mode)
		queue_free()
	)


# New Game with a save present: replace the button cluster with an inline
# confirm. Skip the prompt entirely on a fresh-launch (no save exists).
func _on_new_game_pressed() -> void:
	if not GameData.progress_exists():
		_select(&"new_game")
		return
	_show_wipe_confirm()


func _show_wipe_confirm() -> void:
	if _btn_box == null:
		return
	# Fade buttons out, swap in confirm, fade confirm in.
	_btn_box.modulate.a = 1.0
	var fade_out := create_tween()
	fade_out.tween_property(_btn_box, "modulate:a", 0.0, 0.15)
	fade_out.tween_callback(func():
		_btn_box.visible = false
		_build_confirm_overlay()
	)


func _build_confirm_overlay() -> void:
	_confirm_box = VBoxContainer.new()
	_confirm_box.anchor_left = 0.5
	_confirm_box.anchor_right = 0.5
	_confirm_box.anchor_top = 1.0
	_confirm_box.anchor_bottom = 1.0
	_confirm_box.offset_left = -200
	_confirm_box.offset_right = 200
	_confirm_box.offset_top = -200
	_confirm_box.offset_bottom = -60
	_confirm_box.add_theme_constant_override("separation", 10)
	_root.add_child(_confirm_box)

	var prompt := Label.new()
	prompt.text = "Wipe your saved progress?\nThis can't be undone."
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", Color(1.0, 0.93, 0.6))
	prompt.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.14))
	prompt.add_theme_constant_override("outline_size", 4)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_box.add_child(prompt)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_confirm_box.add_child(spacer)

	var wipe_btn := _make_button("Wipe & start", true)
	wipe_btn.pressed.connect(func(): _select(&"new_game"))
	_confirm_box.add_child(wipe_btn)

	var cancel_btn := _make_button("Cancel", false)
	cancel_btn.pressed.connect(_on_cancel_wipe)
	_confirm_box.add_child(cancel_btn)

	_confirm_box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_confirm_box, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_cancel_wipe() -> void:
	if _confirm_box == null:
		return
	var tw := create_tween()
	tw.tween_property(_confirm_box, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func():
		_confirm_box.queue_free()
		_confirm_box = null
		if _btn_box:
			_btn_box.visible = true
			_btn_box.modulate.a = 0.0
			var fade_in := create_tween()
			fade_in.tween_property(_btn_box, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	)
