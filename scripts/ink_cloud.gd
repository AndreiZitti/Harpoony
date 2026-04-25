extends Node2D

const LIFETIME = 1.5
const MAX_RADIUS = 60.0

var time: float = 0.0


func _process(delta: float) -> void:
	time += delta
	if time >= LIFETIME:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var t = clampf(time / LIFETIME, 0.0, 1.0)
	var radius = MAX_RADIUS * sqrt(t)
	var alpha = (1.0 - t) * 0.85
	var core = Color(0.04, 0.02, 0.1, alpha)
	for i in 6:
		var angle = float(i) / 6 * TAU + time * 0.6
		var off = Vector2(cos(angle), sin(angle)) * radius * 0.45
		draw_circle(off, radius * 0.55, core)
	draw_circle(Vector2.ZERO, radius * 0.85, Color(core.r, core.g, core.b, alpha * 0.7))
