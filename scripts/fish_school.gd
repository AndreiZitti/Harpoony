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
const WAVE_AMPLITUDE = 20.0

enum State { NORMAL, PANIC, REGROUP }

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


func _advance_leader(delta: float) -> void:
	var dir = 1.0 if direction_right else -1.0
	leader_pos.x += dir * leader_speed * delta
	leader_pos.y = base_y + sin(age * wave_frequency + wave_phase) * WAVE_AMPLITUDE


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
