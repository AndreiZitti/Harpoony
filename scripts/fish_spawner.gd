extends Node2D

const FishScene = preload("res://scenes/fish.tscn")
const FishSchoolScript = preload("res://scripts/fish_school.gd")

var spawn_timer: float = 0.0
var active: bool = false

const BASE_SPAWN_INTERVAL = 1.2


func start_spawning() -> void:
	active = true
	spawn_timer = 0.5


func stop_spawning() -> void:
	active = false
	for child in get_tree().get_nodes_in_group("fish"):
		if is_instance_valid(child) and not child.speared:
			child.queue_free()


func _process(delta: float) -> void:
	if not active:
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = BASE_SPAWN_INTERVAL * randf_range(0.7, 1.3)
		_spawn_one()


func _spawn_one() -> void:
	var species = _pick_species()
	_spawn_at_random_edge(species)


func dev_spawn(species: String) -> void:
	_spawn_at_random_edge(species)


func _spawn_at_random_edge(species: String) -> void:
	var viewport = get_viewport_rect().size
	var from_right = randf() < 0.5
	var x = viewport.x + 40.0 if from_right else -40.0
	var y = randf_range(viewport.y * 0.25, viewport.y * 0.85)
	_spawn_species(species, Vector2(x, y), not from_right)


func _spawn_species(species: String, pos: Vector2, direction_right: bool) -> void:
	if species == "sardine" or species == "lanternfish":
		var school = FishSchoolScript.new()
		get_tree().current_scene.add_child(school)
		var count = randi_range(4, 10) if species == "sardine" else randi_range(3, 6)
		school.setup(species, pos, direction_right, count)
	else:
		var fish: Fish = FishScene.instantiate()
		fish.add_to_group("fish")
		get_tree().current_scene.add_child(fish)
		fish.setup(species, pos, direction_right)


func _pick_species() -> String:
	var weights = GameData.get_zone_spawn_weights()
	var total = 0.0
	for w in weights.values():
		total += w
	var r = randf() * total
	var acc = 0.0
	for key in weights.keys():
		acc += weights[key]
		if r <= acc:
			return key
	return "sardine"
