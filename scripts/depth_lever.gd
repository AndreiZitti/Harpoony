class_name DepthLever
extends Control

const TITLE_H: float = 28.0
const TRACK_TOP: float = 40.0
const TRACK_BOTTOM_PAD: float = 16.0
const TRACK_WIDTH: float = 14.0
const HANDLE_SIZE: Vector2 = Vector2(64.0, 22.0)
const NOTCH_LABEL_X: float = 80.0

var _dragging: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(220, 380)
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameData.zone_changed.connect(func(_z): queue_redraw())
	GameData.zone_unlocked.connect(func(_i): queue_redraw())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_select_at_y(mb.position.y)
			else:
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_select_at_y(mm.position.y)


func _select_at_y(y: float) -> void:
	var n := GameData.zones.size()
	if n == 0:
		return
	var best_idx := 0
	var best_d := INF
	for i in n:
		var ny := _notch_y(i)
		var d = absf(y - ny)
		if d < best_d:
			best_d = d
			best_idx = i
	if GameData.can_select_zone(best_idx):
		GameData.select_zone(best_idx)


func _notch_y(idx: int) -> float:
	var n: int = GameData.zones.size()
	if n <= 1:
		return TRACK_TOP
	var track_h := size.y - TRACK_TOP - TRACK_BOTTOM_PAD
	return TRACK_TOP + track_h * float(idx) / float(n - 1)


func _draw() -> void:
	if GameData.zones.is_empty():
		return

	# Background plate
	var plate_bg := Color(0.12, 0.1, 0.08, 0.85)
	var plate_border := Color(0.55, 0.4, 0.2, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), plate_bg)
	draw_rect(Rect2(Vector2.ZERO, size), plate_border, false, 2.0)

	# Title
	var font := ThemeDB.fallback_font
	var title := "DEPTH"
	draw_string(font, Vector2(14, 22), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.95, 0.85, 0.55))

	# Track
	var track_x: float = 32.0
	var track_top := TRACK_TOP
	var track_bot := size.y - TRACK_BOTTOM_PAD
	draw_rect(Rect2(track_x - TRACK_WIDTH * 0.5, track_top, TRACK_WIDTH, track_bot - track_top), Color(0.06, 0.06, 0.08))
	draw_rect(Rect2(track_x - TRACK_WIDTH * 0.5, track_top, TRACK_WIDTH, track_bot - track_top), Color(0.4, 0.3, 0.15), false, 1.5)

	# Notches and labels
	var n: int = GameData.zones.size()
	for i in n:
		var y := _notch_y(i)
		var unlocked: bool = GameData.can_select_zone(i)
		var selected: bool = (i == GameData.selected_zone_index)
		var notch_color := Color(0.85, 0.7, 0.4) if unlocked else Color(0.35, 0.3, 0.25)
		# Tick on the track
		draw_line(Vector2(track_x - 14, y), Vector2(track_x + 14, y), notch_color, 2.0)

		var zone: ZoneConfig = GameData.zones[i]
		var label_color: Color
		if not unlocked:
			label_color = Color(0.45, 0.4, 0.35)
		elif selected:
			label_color = Color(1.0, 0.95, 0.5)
		else:
			label_color = Color(0.85, 0.85, 0.9)

		var line1 := zone.display_name
		if not unlocked:
			line1 = "🔒 " + line1
		var line2 := "%dm" % zone.depth_meters
		draw_string(font, Vector2(NOTCH_LABEL_X, y - 2), line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, label_color)
		draw_string(font, Vector2(NOTCH_LABEL_X, y + 13), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, label_color * Color(0.85, 0.85, 0.85, 1))

	# Handle on selected notch
	var handle_y := _notch_y(GameData.selected_zone_index)
	var handle_rect := Rect2(Vector2(track_x - HANDLE_SIZE.x * 0.5, handle_y - HANDLE_SIZE.y * 0.5), HANDLE_SIZE)
	draw_rect(handle_rect, Color(0.9, 0.75, 0.3))
	draw_rect(handle_rect, Color(0.4, 0.25, 0.1), false, 2.0)
	# Grip lines
	for i in 3:
		var gx := handle_rect.position.x + 14 + i * 12
		draw_line(Vector2(gx, handle_y - 6), Vector2(gx, handle_y + 6), Color(0.3, 0.2, 0.1), 1.5)
