extends Node2D

var species: String = "sardine"
var base_value: int = 2
var hit_radius: float = 10.0
var speed: float = 120.0
var velocity: Vector2 = Vector2.ZERO
var wave_amplitude: float = 20.0
var wave_frequency: float = 2.0
var wave_phase: float = 0.0
var age: float = 0.0
var speared: bool = false
var color: Color = Color(0.7, 0.8, 0.9)


func setup(s: String, start_pos: Vector2, direction_right: bool) -> void:
	species = s
	match species:
		"sardine":
			base_value = 2
			hit_radius = 10.0
			speed = 160.0
			color = Color(0.75, 0.85, 0.95)
		"grouper":
			base_value = 10
			hit_radius = 18.0
			speed = 80.0
			color = Color(0.8, 0.6, 0.3)
		"tuna":
			base_value = 40
			hit_radius = 24.0
			speed = 120.0
			color = Color(0.4, 0.5, 0.7)
	velocity = Vector2(speed if direction_right else -speed, 0)
	global_position = start_pos
	wave_phase = randf() * TAU


func _process(delta: float) -> void:
	if speared:
		return
	age += delta
	var wave_y = sin(age * wave_frequency + wave_phase) * wave_amplitude * delta
	global_position += velocity * delta + Vector2(0, wave_y)
	# Despawn when fully off-screen
	var viewport = get_viewport_rect().size
	var margin = 60.0
	if global_position.x < -margin or global_position.x > viewport.x + margin:
		queue_free()
		return
	queue_redraw()


func on_speared(_spear: Node2D) -> void:
	speared = true


func get_cash_value() -> int:
	return int(base_value * GameData.get_fish_value_multiplier())


func get_effective_hit_radius() -> float:
	return hit_radius + GameData.get_hit_radius_bonus()


func _draw() -> void:
	var facing_right = velocity.x >= 0
	var dir = 1.0 if facing_right else -1.0
	# Body ellipse (approximate via scaled circle)
	var body_len = hit_radius * 1.8
	var body_h = hit_radius * 1.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Body
	var pts = PackedVector2Array()
	var n = 16
	for i in n:
		var a = float(i) / n * TAU
		pts.append(Vector2(cos(a) * body_len * 0.5, sin(a) * body_h * 0.5))
	draw_colored_polygon(pts, color)
	# Tail triangle
	var tx = -body_len * 0.5 * dir
	draw_polygon(
		PackedVector2Array([
			Vector2(tx, 0),
			Vector2(tx - 8 * dir, -6),
			Vector2(tx - 8 * dir, 6),
		]),
		PackedColorArray([color.darkened(0.15)])
	)
	# Eye
	draw_circle(Vector2(body_len * 0.3 * dir, -body_h * 0.2), 1.6, Color.BLACK)
