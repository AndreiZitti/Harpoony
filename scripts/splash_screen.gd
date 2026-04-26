extends CanvasLayer

# Narrative beat shown after Normal mode is picked, before the shop opens.
# Sits over the live boat scene with a soft vignette so the world stays visible
# behind the prompt — continuous with the title screen treatment.
# 0.5s fade-in + 1.0s hold + 0.5s fade-out, then `finished` is emitted.

signal finished

const PROMPT := "Can you reach the treasure\non the bottom in 100 dives?"

var _root: Control


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_play()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Soft vignette — partial darkening so the boat reads as the backdrop, not lost.
	var vignette := ColorRect.new()
	vignette.color = Color(0.02, 0.04, 0.08, 0.7)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(vignette)

	# Drop-shadow pass for the prompt — same trick as the title screen.
	var shadow := Label.new()
	shadow.text = PROMPT
	shadow.add_theme_font_size_override("font_size", 30)
	shadow.add_theme_color_override("font_color", Color(0.02, 0.04, 0.10, 0.7))
	shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shadow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shadow.anchor_left = 0.5
	shadow.anchor_right = 0.5
	shadow.anchor_top = 0.5
	shadow.anchor_bottom = 0.5
	shadow.offset_left = -320 + 3
	shadow.offset_right = 320 + 3
	shadow.offset_top = -100 + 3
	shadow.offset_bottom = 100 + 3
	_root.add_child(shadow)

	var label := Label.new()
	label.text = PROMPT
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.6))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.14))
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 0.5
	label.anchor_bottom = 0.5
	label.offset_left = -320
	label.offset_right = 320
	label.offset_top = -100
	label.offset_bottom = 100
	_root.add_child(label)


func _play() -> void:
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.0)
	tw.tween_property(_root, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		finished.emit()
		queue_free()
	)
