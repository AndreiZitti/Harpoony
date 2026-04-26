extends Node2D

# Bubble plume that telegraphs an incoming bonito streak. Lives 2 seconds at
# the entry edge, then emits `streak_ready(direction_right, y)` and frees
# itself. fish_spawner connects the signal and spawns the actual fish chain.

signal streak_ready(direction_right: bool, y: float)

const HERALD_DURATION := 2.0
const BUBBLE_SPAWN_INTERVAL := 0.04  # dense plume — much heavier than ambient
const BUBBLE_RISE_HEIGHT := 80.0     # column height before bubbles fade out

var _direction_right: bool = true
var _entry_y: float = 0.0
var _age: float = 0.0
var _spawn_timer: float = 0.0
var _bubbles: Array = []  # of Dictionaries: { pos, radius, rise_speed, wobble_phase, age, life }
var _fired: bool = false


func setup(entry_pos: Vector2, direction_right: bool) -> void:
	_direction_right = direction_right
	_entry_y = entry_pos.y
	# Place the plume just inside the entry edge so the player sees it on-screen.
	var viewport := get_viewport_rect().size
	var x: float = 24.0 if direction_right else viewport.x - 24.0
	global_position = Vector2(x, _entry_y)


func _process(delta: float) -> void:
	_age += delta
	# Spawn new bubbles until just before the streak fires (last 0.2s the column
	# stops feeding so it visually breaks before the fish appear).
	if _age < HERALD_DURATION - 0.2:
		_spawn_timer -= delta
		while _spawn_timer <= 0.0:
			_spawn_timer += BUBBLE_SPAWN_INTERVAL
			_spawn_bubble()
	# Update existing bubbles.
	var i := _bubbles.size() - 1
	while i >= 0:
		var b: Dictionary = _bubbles[i]
		b["age"] += delta
		b["pos"].y -= b["rise_speed"] * delta
		b["wobble_phase"] += delta * 3.0
		b["pos"].x += sin(b["wobble_phase"]) * 8.0 * delta
		if b["age"] >= b["life"]:
			_bubbles.remove_at(i)
		i -= 1
	# Fire the streak signal at the end of the duration, then linger briefly so
	# trailing bubbles can finish rising before we free.
	if not _fired and _age >= HERALD_DURATION:
		_fired = true
		streak_ready.emit(_direction_right, _entry_y)
	if _fired and _bubbles.is_empty():
		queue_free()
	queue_redraw()


func _spawn_bubble() -> void:
	# Cluster bubbles around the herald origin with horizontal jitter so the
	# plume reads as a column rather than a point source.
	var b := {
		"pos": Vector2(randf_range(-12.0, 12.0), randf_range(-4.0, 4.0)),
		"radius": randf_range(2.0, 4.5),
		"rise_speed": randf_range(40.0, 80.0),
		"wobble_phase": randf() * TAU,
		"age": 0.0,
		"life": randf_range(1.0, 1.6),
	}
	_bubbles.append(b)


func _draw() -> void:
	for b in _bubbles:
		var pos: Vector2 = b["pos"]
		var life: float = b["life"]
		var age_b: float = b["age"]
		# Fade in fast, fade out as it nears end of life.
		var fade_in: float = clampf(age_b / 0.15, 0.0, 1.0)
		var fade_out: float = clampf((life - age_b) / 0.4, 0.0, 1.0)
		var alpha: float = clampf(0.45 * fade_in * fade_out, 0.0, 0.55)
		var radius: float = b["radius"]
		draw_circle(pos, radius, Color(0.85, 0.95, 1.0, alpha))
		draw_circle(pos + Vector2(-radius * 0.3, -radius * 0.3), radius * 0.35, Color(1, 1, 1, alpha * 0.7))
