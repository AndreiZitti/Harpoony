class_name FishSchool
extends Node2D

const FishScene = preload("res://scenes/fish.tscn")

var SCHOOL_RADIUS = 40.0
const PANIC_DURATION = 0.6
const REGROUP_DURATION = 0.4
const PANIC_SPEED = 320.0
const PANIC_STEER = 8.0
const STEER_GAIN = 2.5
const STEER_SMOOTH = 6.0
const MAX_SCHOOL_SPEED = 220.0
const OFFSET_JITTER_INTERVAL = 2.0

# Wave amplitude is a var (not const) so sardine archetypes can override it.
var wave_amplitude: float = 20.0

enum State { NORMAL, PANIC, REGROUP }

# Sardine archetypes — each school rolls one at spawn so two schools never feel
# identical. Tight/Loose/Wavy diverge on radius, speed, and undulation depth.
enum Archetype { TIGHT, LOOSE, WAVY }
var archetype: int = Archetype.TIGHT

var state: int = State.NORMAL
var state_timer: float = 0.0
var panic_origin: Vector2 = Vector2.ZERO

var leader_pos: Vector2 = Vector2.ZERO
var direction_right: bool = true
var wave_phase: float = 0.0
var base_y: float = 0.0
var age: float = 0.0
var leader_speed: float = 160.0
var wave_frequency: float = 5.5

var followers: Array[Fish] = []


func setup(species_name: String, start_pos: Vector2, direction_right_: bool, count: int) -> void:
	direction_right = direction_right_
	leader_pos = start_pos
	base_y = start_pos.y
	wave_phase = randf() * TAU

	match species_name:
		"lanternfish":
			leader_speed = 130.0
			wave_frequency = 4.5
			SCHOOL_RADIUS = 24.0   # tighter cluster — net-prime
		"mahimahi":
			leader_speed = 90.0
			wave_frequency = 4.0
			SCHOOL_RADIUS = 28.0   # small pod
		"sardine":
			_apply_sardine_archetype()
		_:
			leader_speed = 160.0
			wave_frequency = 5.5
			SCHOOL_RADIUS = 40.0

	for i in count:
		var fish: Fish = FishScene.instantiate()
		fish.add_to_group("fish")
		var offset = _random_in_disc(SCHOOL_RADIUS)
		var fish_pos = start_pos + offset
		get_tree().current_scene.add_child(fish)
		fish.setup(species_name, fish_pos, direction_right)
		fish.school = self
		fish.slot_offset = offset
		fish._offset_jitter_timer = randf() * OFFSET_JITTER_INTERVAL
		fish.tree_exited.connect(_on_follower_exited.bind(fish))
		followers.append(fish)


func _process(delta: float) -> void:
	age += delta
	_update_state(delta)
	_advance_leader(delta)
	if followers.is_empty():
		queue_free()


func _update_state(delta: float) -> void:
	if state == State.NORMAL:
		return
	state_timer -= delta
	if state_timer <= 0.0:
		if state == State.PANIC:
			state = State.REGROUP
			state_timer = REGROUP_DURATION
		else:
			state = State.NORMAL


func _apply_sardine_archetype() -> void:
	# Roll an archetype + small per-school speed jitter so even same-archetype
	# schools feel distinct. Wavy reads as the "current zone has an undertow"
	# moment; Loose reads as "lazy big group"; Tight is the net-prime default.
	archetype = randi() % 3
	var jitter := randf_range(0.85, 1.15)
	match archetype:
		Archetype.TIGHT:
			SCHOOL_RADIUS = 32.0
			leader_speed = 160.0 * jitter
			wave_frequency = 5.5
			wave_amplitude = 20.0
		Archetype.LOOSE:
			SCHOOL_RADIUS = 60.0
			leader_speed = 130.0 * jitter
			wave_frequency = 4.0
			wave_amplitude = 24.0
		Archetype.WAVY:
			SCHOOL_RADIUS = 36.0
			leader_speed = 150.0 * jitter
			wave_frequency = 3.0
			wave_amplitude = 50.0


func _advance_leader(delta: float) -> void:
	var dir = 1.0 if direction_right else -1.0
	leader_pos.x += dir * leader_speed * delta
	leader_pos.y = base_y + sin(age * wave_frequency + wave_phase) * wave_amplitude
	# Diver avoidance: drift the whole school's path to curve around. Only the
	# y-component nudges base_y so the school re-centers after passing.
	var avoid := Fish.diver_avoidance_for(self, leader_pos, "sardine")
	if avoid != Vector2.ZERO:
		leader_pos += avoid * delta * 0.7
		base_y = lerpf(base_y, leader_pos.y, clampf(delta * 2.0, 0.0, 1.0))


func _on_member_speared(hit_pos: Vector2) -> void:
	panic_origin = hit_pos
	state = State.PANIC
	state_timer = PANIC_DURATION


func _on_follower_exited(fish: Fish) -> void:
	followers.erase(fish)


func _random_in_disc(r: float) -> Vector2:
	var theta = randf() * TAU
	var rho = sqrt(randf()) * r
	return Vector2(cos(theta) * rho, sin(theta) * rho)
