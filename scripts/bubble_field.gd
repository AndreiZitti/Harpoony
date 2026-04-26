class_name BubbleField
extends Node2D

# Drifting bubble particles for underwater ambience. Spawns from below the
# viewport, rises with a slight horizontal wobble, fades as it nears the surface.

const SPAWN_INTERVAL := 0.16
const MAX_BUBBLES := 80
const WATER_SURFACE_Y := 140.0

var _spawn_timer: float = 0.0
var _bubbles: Array = []  # of Dictionaries to keep it light


func _process(delta: float) -> void:
	var underwater := GameData.dive_state == GameData.DiveState.UNDERWATER \
			or GameData.dive_state == GameData.DiveState.DIVING \
			or GameData.dive_state == GameData.DiveState.RESURFACING
	if underwater:
		_spawn_timer -= delta
		while _spawn_timer <= 0.0 and _bubbles.size() < MAX_BUBBLES:
			_spawn_timer += SPAWN_INTERVAL * randf_range(0.6, 1.4)
			_spawn_bubble()
	# Update + cull. Iterate backward so removals are safe.
	var i := _bubbles.size() - 1
	while i >= 0:
		var b: Dictionary = _bubbles[i]
		b["pos"].y -= b["rise_speed"] * delta
		b["wobble_phase"] += delta * 2.0
		b["pos"].x += sin(b["wobble_phase"]) * b["wobble_amp"] * delta
		if b["pos"].y < WATER_SURFACE_Y - 10:
			_bubbles.remove_at(i)
		i -= 1
	queue_redraw()


func _spawn_bubble() -> void:
	var viewport := get_viewport_rect().size
	var b := {
		"pos": Vector2(randf_range(0, viewport.x), viewport.y + randf_range(0, 30)),
		"radius": randf_range(1.5, 3.5),
		"rise_speed": randf_range(20, 55),
		"wobble_phase": randf() * TAU,
		"wobble_amp": randf_range(3, 12),
	}
	_bubbles.append(b)


func _draw() -> void:
	var viewport := get_viewport_rect().size
	var col_height := viewport.y - WATER_SURFACE_Y
	for b in _bubbles:
		var pos: Vector2 = b["pos"]
		# Fade out as it approaches the surface so they vanish naturally.
		var height_ratio := clampf((pos.y - WATER_SURFACE_Y) / col_height, 0.0, 1.0)
		var alpha := clampf(0.10 + height_ratio * 0.45, 0.0, 0.55)
		var radius: float = b["radius"]
		draw_circle(pos, radius, Color(0.85, 0.95, 1.0, alpha))
		# Top-left highlight.
		draw_circle(pos + Vector2(-radius * 0.25, -radius * 0.25), radius * 0.35, Color(1, 1, 1, alpha * 0.7))
