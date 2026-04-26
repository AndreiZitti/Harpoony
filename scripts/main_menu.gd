extends CanvasLayer

# Opening menu shown on launch. Player picks Normal (splash → shop) or Dev
# (cheat_mode + dev spawn panel, skip splash). main.gd routes on mode_selected.

signal mode_selected(mode: StringName)  # &"normal" or &"dev"

const TITLE := "FEED THE NETWORK"
const SUBTITLE := "An arcade spearfishing campaign"

var _root: Control


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Background dim — slightly less than the pause menu so the boat peeks through.
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.10, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.custom_minimum_size = Vector2(420, 260)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.14, 0.20, 0.98)
	sb.border_color = Color(0.85, 0.78, 0.45, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	card.add_theme_stylebox_override("panel", sb)
	_root.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)

	var title := Label.new()
	title.text = TITLE
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var subtitle := Label.new()
	subtitle.text = SUBTITLE
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	v.add_child(spacer)

	var normal_btn := Button.new()
	normal_btn.text = "Normal Mode"
	normal_btn.custom_minimum_size = Vector2(0, 44)
	normal_btn.pressed.connect(func(): _select(&"normal"))
	v.add_child(normal_btn)

	var dev_btn := Button.new()
	dev_btn.text = "Dev Mode"
	dev_btn.custom_minimum_size = Vector2(0, 36)
	dev_btn.pressed.connect(func(): _select(&"dev"))
	v.add_child(dev_btn)

	var hint := Label.new()
	hint.text = "Dev mode: infinite cash, dev spawn panel, skip splash."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)

	# Fade in.
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _select(mode: StringName) -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		mode_selected.emit(mode)
		queue_free()
	)
