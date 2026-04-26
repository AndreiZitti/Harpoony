extends Node2D

const FishScene = preload("res://scenes/fish.tscn")
const FishSchoolScript = preload("res://scripts/fish_school.gd")
const BonitoHeraldScript = preload("res://scripts/bonito_herald.gd")

var spawn_timer: float = 0.0
var active: bool = false

# Slower default than v1 — schools are bigger, so fewer spawn events still
# fills the screen comfortably. Effective interval = BASE / spawn_rate_multiplier
# so the future "Reef Density" upgrade just bumps the multiplier above 1.0.
const BASE_SPAWN_INTERVAL = 2.2
# Bonito streaks pack a dense formation — matches the reference jack-school
# imagery. Pack length is along travel direction, height is lateral spread.
const BONITO_STREAK_MIN := 30
const BONITO_STREAK_MAX := 80
const BONITO_PACK_LENGTH := 240.0
const BONITO_PACK_HEIGHT := 80.0


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
		var mult: float = max(0.05, GameData.spawn_rate_multiplier)
		spawn_timer = (BASE_SPAWN_INTERVAL / mult) * randf_range(0.7, 1.3)
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
	# Trophy cap — only one White Whale on screen at a time.
	if species == "whitewhale":
		for n in get_tree().get_nodes_in_group("fish"):
			if n is Fish and (n as Fish).species == "whitewhale" and not (n as Fish).speared:
				return  # cap reached, skip this spawn
	# Bonito uses a heralded streak: bubble plume telegraphs the lane for 2s,
	# then a tight chain enters from off-screen at the heralded y.
	if species == "bonito":
		_spawn_bonito_with_herald(pos, direction_right)
		return
	# Schooling species: tight clusters built via FishSchool. Sizes per species.
	var school_count := 0
	match species:
		"sardine":
			school_count = randi_range(4, 10)
		"lanternfish":
			school_count = randi_range(5, 8)  # tighter, denser cluster than before
		"mahimahi":
			school_count = randi_range(2, 3)  # small pod
	if school_count > 0:
		var school = FishSchoolScript.new()
		get_tree().current_scene.add_child(school)
		school.setup(species, pos, direction_right, school_count)
	else:
		var fish: Fish = FishScene.instantiate()
		fish.add_to_group("fish")
		get_tree().current_scene.add_child(fish)
		fish.setup(species, pos, direction_right)


func _spawn_bonito_with_herald(pos: Vector2, direction_right: bool) -> void:
	var herald := BonitoHeraldScript.new()
	get_tree().current_scene.add_child(herald)
	herald.setup(pos, direction_right)
	herald.streak_ready.connect(_spawn_bonito_streak)


func _spawn_bonito_streak(direction_right: bool, y: float) -> void:
	# Dense pack streaming in from off-screen at the heralded y. Each fish gets
	# a random position inside a rectangle behind the entry edge so the school
	# enters as a thick formation rather than a rule-straight line.
	var viewport := get_viewport_rect().size
	var dir: float = 1.0 if direction_right else -1.0
	var entry_x: float = -40.0 if direction_right else viewport.x + 40.0
	var count := randi_range(BONITO_STREAK_MIN, BONITO_STREAK_MAX)
	for i in count:
		var fish: Fish = FishScene.instantiate()
		fish.add_to_group("fish")
		var local_x: float = -randf_range(0.0, BONITO_PACK_LENGTH) * dir
		var local_y: float = randf_range(-BONITO_PACK_HEIGHT * 0.5, BONITO_PACK_HEIGHT * 0.5)
		var fish_pos := Vector2(entry_x + local_x, y + local_y)
		get_tree().current_scene.add_child(fish)
		fish.setup("bonito", fish_pos, direction_right)


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
