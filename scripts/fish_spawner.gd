extends Node2D

const Fish = preload("res://scenes/fish.tscn")

var spawn_timer: float = 0.0
var active: bool = false

const BASE_SPAWN_INTERVAL = 1.2
const SPECIES_WEIGHTS = {
	"sardine": 0.6,
	"grouper": 0.3,
	"tuna": 0.1,
}


func start_spawning() -> void:
	active = true
	spawn_timer = 0.5  # First spawn quickly


func stop_spawning() -> void:
	active = false
	# Clear any still-swimming fish (speared ones are owned by spears — leave them)
	for child in get_tree().get_nodes_in_group("fish"):
		if is_instance_valid(child) and not child.speared:
			child.queue_free()


func _process(delta: float) -> void:
	if not active:
		return
	spawn_timer -= delta * GameData.get_spawn_rate_multiplier()
	if spawn_timer <= 0.0:
		spawn_timer = BASE_SPAWN_INTERVAL * randf_range(0.7, 1.3)
		_spawn_one()


func _spawn_one() -> void:
	var species = _pick_species()
	var viewport = get_viewport_rect().size
	var from_right = randf() < 0.5
	var x = viewport.x + 40.0 if from_right else -40.0
	var y = randf_range(viewport.y * 0.25, viewport.y * 0.85)
	var fish = Fish.instantiate()
	fish.add_to_group("fish")
	get_tree().current_scene.add_child(fish)
	fish.setup(species, Vector2(x, y), not from_right)


func _pick_species() -> String:
	var total = 0.0
	for w in SPECIES_WEIGHTS.values():
		total += w
	var r = randf() * total
	var acc = 0.0
	for key in SPECIES_WEIGHTS.keys():
		acc += SPECIES_WEIGHTS[key]
		if r <= acc:
			return key
	return "sardine"
