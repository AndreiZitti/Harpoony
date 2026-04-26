extends CanvasLayer

# 2-second narrative splash shown after Normal mode is picked, before the shop.
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

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var label := Label.new()
	label.text = PROMPT
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Anchor a fixed-size box centered on the viewport so multi-line text reads cleanly.
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
