extends CanvasLayer

signal next_day_pressed

var root_control: Control
var day_label: Label
var earnings_label: Label
var next_day_button: Button


func _ready() -> void:
	_build_ui()
	hide_summary()


func _build_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	var overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.92)
	root_control.add_child(overlay)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	center.add_child(vbox)

	day_label = Label.new()
	day_label.add_theme_font_size_override("font_size", 48)
	day_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(day_label)

	earnings_label = Label.new()
	earnings_label.add_theme_font_size_override("font_size", 28)
	earnings_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	earnings_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(earnings_label)

	var tagline = Label.new()
	tagline.text = "Sleep well. The sea awaits."
	tagline.add_theme_font_size_override("font_size", 14)
	tagline.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tagline)

	next_day_button = Button.new()
	next_day_button.text = "⇢  NEXT DAY"
	next_day_button.custom_minimum_size = Vector2(260, 52)
	next_day_button.add_theme_font_size_override("font_size", 20)
	next_day_button.pressed.connect(_on_next_day_pressed)
	var btn_s = StyleBoxFlat.new()
	btn_s.bg_color = Color(0.12, 0.35, 0.75)
	btn_s.set_corner_radius_all(10)
	btn_s.set_content_margin_all(10)
	next_day_button.add_theme_stylebox_override("normal", btn_s)
	var btn_wrap = CenterContainer.new()
	btn_wrap.add_child(next_day_button)
	vbox.add_child(btn_wrap)


func show_summary() -> void:
	day_label.text = "Day %d complete" % GameData.day_number
	earnings_label.text = "$%d earned" % int(GameData.day_cash)
	root_control.visible = true


func hide_summary() -> void:
	root_control.visible = false


func _on_next_day_pressed() -> void:
	next_day_pressed.emit()
