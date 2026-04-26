class_name Fish
extends Area2D

@onready var _shape: CollisionShape2D = $CollisionShape2D

var species: String = "sardine"
# Size class drives Net catch eligibility and trophy lane.
# small  → Net catches by default
# medium → Net catches only after Bigger Hoop upgrade
# large  → Net never catches; Heavy can pierce
# trophy → Net never catches; only Heavy lands them
const SIZE_SMALL := &"small"
const SIZE_MEDIUM := &"medium"
const SIZE_LARGE := &"large"
const SIZE_TROPHY := &"trophy"

var size_class: StringName = SIZE_MEDIUM
var base_value: int = 2
var hit_radius: float = 10.0
var speed: float = 120.0
var velocity: Vector2 = Vector2.ZERO
var wave_amplitude: float = 20.0
var wave_frequency: float = 2.0
var wave_phase: float = 0.0
var age: float = 0.0
var speared: bool = false
# Spawn-cull guard: don't free a fish for being off-screen until it's been
# visible at least once. Bonito streaks spawn beyond the cull margin so they
# can stream in as a dense formation; without this flag, most of the pack
# would queue_free on the first frame.
var _was_on_screen: bool = false
var color: Color = Color(0.7, 0.8, 0.9)
var school = null
var slot_offset: Vector2 = Vector2.ZERO
var _offset_jitter_timer: float = 0.0
var forward_sign: float = 1.0
# Per-species behavior fields
# Pufferfish — predictable inflate cycle.
enum PufferPhase { DEFLATED, INFLATING, INFLATED, DEFLATING }
var puffer_phase: int = PufferPhase.DEFLATED
var puffer_phase_timer: float = 0.0
const PUFFER_DEFLATED_DURATION := 3.0
const PUFFER_INFLATING_DURATION := 0.4
const PUFFER_INFLATED_DURATION := 2.0
const PUFFER_DEFLATING_DURATION := 0.4
const PUFFER_THREAT_RADIUS := 80.0
# Mahimahi
var mahi_burst_until: float = -1.0
var mahi_burst_dir: Vector2 = Vector2.ZERO
var mahi_prev_seen_spear: bool = false
# Squid
var squid_phase: int = 0  # 0 = STILL, 1 = BURST
var squid_phase_timer: float = 0.0
var spear_check_timer: float = 0.0
# Triggerfish — directional shield, alarm-on-bounce.
var trigger_alarm_until: float = -1.0
const TRIGGER_SHIELD_HALF_ANGLE := deg_to_rad(60.0)  # 120° front cone total
const TRIGGER_ALARM_DURATION := 1.2
# Blockfish — same defense mechanic, but the shield can spawn on the BACK
# instead of the front. Player has to read which side is shielded before firing.
var blockfish_shield_back: bool = false
const BLOCKFISH_SHIELD_HALF_ANGLE := deg_to_rad(55.0)  # 110° cone, slightly tighter
const BLOCKFISH_ALARM_DURATION := 1.2
var blockfish_alarm_until: float = -1.0
var _flash_tween: Tween = null
var _squash_tween: Tween = null

# --- Diver avoidance ---
# Most fish steer gently away from the diver inside this radius. Trophy + apex
# predators (whitewhale, anglerfish) ignore it so they stay menacing.
const DIVER_AVOID_RADIUS := 90.0
const DIVER_AVOID_STRENGTH := 220.0
static var _diver_cache: Node2D = null


static func _get_diver(node: Node) -> Node2D:
	if _diver_cache != null and is_instance_valid(_diver_cache):
		return _diver_cache
	var scene := node.get_tree().current_scene
	if scene == null:
		return null
	var d := scene.get_node_or_null("Diver")
	if d is Node2D:
		_diver_cache = d
		return _diver_cache
	return null


# Avoidance velocity vector for the given world position. Returns ZERO when
# outside the radius, when the fish is an apex/trophy species, or while diver
# is hidden (e.g. on the surface). Strength falls off linearly with distance.
static func diver_avoidance_for(node: Node, pos: Vector2, species_id: String) -> Vector2:
	if species_id == "whitewhale" or species_id == "anglerfish":
		return Vector2.ZERO
	var diver := _get_diver(node)
	if diver == null or not diver.visible:
		return Vector2.ZERO
	var to_fish := pos - diver.global_position
	var dist := to_fish.length()
	if dist >= DIVER_AVOID_RADIUS or dist < 0.001:
		return Vector2.ZERO
	var falloff := 1.0 - (dist / DIVER_AVOID_RADIUS)
	return to_fish.normalized() * DIVER_AVOID_STRENGTH * falloff


func setup(s: String, start_pos: Vector2, direction_right: bool) -> void:
	species = s
	match species:
		"sardine":
			base_value = 4
			hit_radius = 10.0
			speed = 160.0
			color = Color(0.75, 0.85, 0.95)
			wave_frequency = 5.5
			size_class = SIZE_SMALL
		"grouper":
			base_value = 15
			hit_radius = 18.0
			speed = 80.0
			color = Color(0.8, 0.6, 0.3)
			wave_frequency = 2.8
			size_class = SIZE_MEDIUM
		"tuna":
			base_value = 40
			hit_radius = 24.0
			speed = 120.0
			color = Color(0.4, 0.5, 0.7)
			wave_frequency = 3.6
			size_class = SIZE_LARGE
		"pufferfish":
			base_value = 12
			hit_radius = 13.0
			speed = 50.0
			color = Color(0.95, 0.9, 0.45)
			wave_frequency = 1.5
			puffer_phase = PufferPhase.DEFLATED
			puffer_phase_timer = randf_range(1.5, PUFFER_DEFLATED_DURATION)  # stagger spawns
			size_class = SIZE_MEDIUM
		"mahimahi":
			base_value = 25
			hit_radius = 16.0
			speed = 90.0
			color = Color(0.95, 0.7, 0.2)
			wave_frequency = 4.0
			size_class = SIZE_MEDIUM
		"squid":
			base_value = 18
			hit_radius = 13.0
			speed = 0.0
			color = Color(0.7, 0.35, 0.75)
			wave_frequency = 1.0
			squid_phase_timer = randf_range(0.4, 1.6)
			size_class = SIZE_MEDIUM
		"lanternfish":
			base_value = 5
			hit_radius = 9.0
			speed = 130.0
			color = Color(0.4, 0.5, 0.75)
			wave_frequency = 4.5
			size_class = SIZE_SMALL
		"anglerfish":
			base_value = 50
			hit_radius = 16.0
			speed = 30.0
			color = Color(0.13, 0.08, 0.18)
			wave_frequency = 0.9
		"triggerfish":
			base_value = 30
			hit_radius = 16.0
			speed = 70.0
			color = Color(0.55, 0.65, 0.85)
			wave_frequency = 1.6
			wave_amplitude = 8.0
			size_class = SIZE_LARGE
		"marlin":
			base_value = 60
			hit_radius = 22.0
			speed = 280.0
			color = Color(0.2, 0.3, 0.55)
			wave_frequency = 1.0
			size_class = SIZE_LARGE
		"whitewhale":
			base_value = 800
			hit_radius = 40.0
			speed = 60.0
			color = Color(0.92, 0.94, 0.96)
			wave_frequency = 0.6
			wave_amplitude = 30.0
			size_class = SIZE_TROPHY
		"jellyfish":
			base_value = 18
			hit_radius = 16.0
			speed = 30.0
			color = Color(0.85, 0.7, 0.95, 0.85)
			wave_frequency = 1.0
			wave_amplitude = 8.0
			size_class = SIZE_MEDIUM
		"bonito":
			# Fast, telegraphed streaker — committed lane, no avoidance, no wave.
			# Net catches it (size_small) but only if you fire ahead of the streak.
			base_value = 8
			hit_radius = 11.0
			speed = 280.0
			color = Color(0.78, 0.88, 1.0)
			wave_frequency = 0.0
			wave_amplitude = 0.0
			size_class = SIZE_SMALL
		"blockfish":
			# Directional shield — spawns with the plate on FRONT or BACK at random.
			# Net never catches (size_large), only catchable on the unshielded side.
			# Bigger hit_radius than triggerfish so the unshielded half is a
			# generous target — player's reward for reading the plate correctly.
			base_value = 35
			hit_radius = 22.0
			speed = 70.0
			color = Color(0.7, 0.6, 0.35)
			wave_frequency = 1.6
			wave_amplitude = 8.0
			size_class = SIZE_LARGE
			blockfish_shield_back = randf() < 0.5
	# Apply dev-panel runtime overrides last so they win over the species defaults.
	if GameData.fish_stat_overrides.has(species):
		var ov: Dictionary = GameData.fish_stat_overrides[species]
		if ov.has("base_value"): base_value = int(ov["base_value"])
		if ov.has("speed"): speed = float(ov["speed"])
		if ov.has("hit_radius"): hit_radius = float(ov["hit_radius"])
		if ov.has("wave_amplitude"): wave_amplitude = float(ov["wave_amplitude"])
		if ov.has("wave_frequency"): wave_frequency = float(ov["wave_frequency"])
	forward_sign = 1.0 if direction_right else -1.0
	velocity = Vector2(speed * forward_sign, 0)
	global_position = start_pos
	wave_phase = randf() * TAU
	if _shape:
		var circle := CircleShape2D.new()
		circle.radius = get_effective_hit_radius()
		_shape.shape = circle


func _process(delta: float) -> void:
	if speared:
		return
	age += delta
	if school != null and is_instance_valid(school):
		_process_schooling(delta)
	else:
		_process_species_movement(delta)
	var viewport = get_viewport_rect().size
	var margin = 60.0
	var off_x: bool = global_position.x < -margin or global_position.x > viewport.x + margin
	if not off_x:
		_was_on_screen = true
	if _was_on_screen and off_x:
		queue_free()
		return
	queue_redraw()


func _process_species_movement(delta: float) -> void:
	match species:
		"pufferfish":
			_process_pufferfish(delta)
		"mahimahi":
			_process_mahimahi(delta)
		"squid":
			_process_squid(delta)
		"triggerfish":
			_process_triggerfish(delta)
		"blockfish":
			_process_blockfish(delta)
		"bonito":
			_process_bonito(delta)
		_:
			_process_default(delta)


const BONITO_DIVER_RADIUS := 130.0
const BONITO_DIVER_STRENGTH := 480.0


func _process_bonito(delta: float) -> void:
	# Bonito commits to the lane (no wave, no spear-reaction) but still curves
	# around the diver — wider radius + stronger force than other fish so the
	# streak bends cleanly at 280 px/s instead of looking erratic or clipping
	# through the diver.
	var avoid := Vector2.ZERO
	var diver := _get_diver(self)
	if diver != null and diver.visible:
		var to_fish := global_position - diver.global_position
		var dist := to_fish.length()
		if dist > 0.001 and dist < BONITO_DIVER_RADIUS:
			var falloff := 1.0 - (dist / BONITO_DIVER_RADIUS)
			avoid = to_fish.normalized() * BONITO_DIVER_STRENGTH * falloff
	global_position += (velocity + avoid) * delta


# Returns the blockfish's shielded direction in world space (1.0 = right shield, etc).
func _blockfish_shield_dir() -> float:
	return forward_sign * (-1.0 if blockfish_shield_back else 1.0)


func _process_blockfish(delta: float) -> void:
	# Edge bounce so it patrols the lane.
	var viewport = get_viewport_rect().size
	if global_position.x < 40.0 and forward_sign < 0:
		forward_sign = 1.0
	elif global_position.x > viewport.x - 40.0 and forward_sign > 0:
		forward_sign = -1.0
	# Alarmed = full speed, otherwise gentle patrol.
	var s := speed if age < blockfish_alarm_until else speed * 0.85
	velocity = Vector2(s * forward_sign, 0)
	var wave_y = sin(age * wave_frequency + wave_phase) * wave_amplitude * delta
	var avoid = diver_avoidance_for(self, global_position, species)
	global_position += (velocity + avoid) * delta + Vector2(0, wave_y)


func _process_default(delta: float) -> void:
	var wave_y = sin(age * wave_frequency + wave_phase) * wave_amplitude * delta
	var avoid = diver_avoidance_for(self, global_position, species)
	global_position += (velocity + avoid) * delta + Vector2(0, wave_y)


func _process_pufferfish(delta: float) -> void:
	# Pure timed cycle — DEFLATED is the catch window. We deliberately do NOT
	# react to nearby spears; the player learns the rhythm and times the shot.
	puffer_phase_timer -= delta
	if puffer_phase == PufferPhase.DEFLATED and puffer_phase_timer <= 0.0:
		_set_puffer_phase(PufferPhase.INFLATING)
	elif puffer_phase == PufferPhase.INFLATING and puffer_phase_timer <= 0.0:
		_set_puffer_phase(PufferPhase.INFLATED)
	elif puffer_phase == PufferPhase.INFLATED and puffer_phase_timer <= 0.0:
		_set_puffer_phase(PufferPhase.DEFLATING)
	elif puffer_phase == PufferPhase.DEFLATING and puffer_phase_timer <= 0.0:
		_set_puffer_phase(PufferPhase.DEFLATED)
	# Slow drift, sluggish — only avoid the diver while deflated (inflated is committed defense pose).
	var wave_y = sin(age * wave_frequency + wave_phase) * wave_amplitude * delta
	var avoid = Vector2.ZERO
	if puffer_phase == PufferPhase.DEFLATED:
		avoid = diver_avoidance_for(self, global_position, species) * 0.6
	global_position += (velocity * 0.6 + avoid) * delta + Vector2(0, wave_y)


func _set_puffer_phase(phase: int) -> void:
	puffer_phase = phase
	match phase:
		PufferPhase.DEFLATED:
			puffer_phase_timer = PUFFER_DEFLATED_DURATION
		PufferPhase.INFLATING:
			puffer_phase_timer = PUFFER_INFLATING_DURATION
		PufferPhase.INFLATED:
			puffer_phase_timer = PUFFER_INFLATED_DURATION
		PufferPhase.DEFLATING:
			puffer_phase_timer = PUFFER_DEFLATING_DURATION
	_update_collision_radius()


func _process_mahimahi(delta: float) -> void:
	var sp = _find_flying_spear()
	var seen = sp != null
	if seen and not mahi_prev_seen_spear:
		mahi_burst_until = age + 0.6
		var away = global_position - sp.global_position
		if away.length_squared() < 0.01:
			away = Vector2.RIGHT * -forward_sign
		mahi_burst_dir = away.normalized()
	mahi_prev_seen_spear = seen

	if age < mahi_burst_until:
		# Mid-burst: committed move, ignore diver avoidance.
		var burst_speed = 320.0
		velocity = velocity.lerp(mahi_burst_dir * burst_speed, 9.0 * delta)
		global_position += velocity * delta
	else:
		# Restore cruise velocity if recovering from burst
		if velocity.length() > speed * 1.2:
			velocity = Vector2(speed * forward_sign, 0)
		var wave_y = sin(age * wave_frequency + wave_phase) * wave_amplitude * delta
		var avoid = diver_avoidance_for(self, global_position, species)
		global_position += (velocity + avoid) * delta + Vector2(0, wave_y)


func _process_squid(delta: float) -> void:
	squid_phase_timer -= delta
	if squid_phase_timer <= 0.0:
		if squid_phase == 0:
			squid_phase = 1
			squid_phase_timer = 0.4
			var theta = randf_range(-0.6, 0.6)
			var dir = Vector2(forward_sign, 0).rotated(theta)
			velocity = dir.normalized() * 220.0
		else:
			squid_phase = 0
			squid_phase_timer = randf_range(1.2, 1.8)
			velocity = Vector2.ZERO
	# Squid in STILL phase nudges away from the diver; in BURST it commits.
	var avoid = Vector2.ZERO
	if squid_phase == 0:
		avoid = diver_avoidance_for(self, global_position, species) * 0.7
	global_position += (velocity + avoid) * delta
	if squid_phase == 0:
		# Subtle bob
		global_position.y += sin(age * 1.2 + wave_phase) * 8.0 * delta


func _is_inflated() -> bool:
	return species == "pufferfish" and (puffer_phase == PufferPhase.INFLATED or puffer_phase == PufferPhase.INFLATING)


# Returns true if this fish should deflect the given spear (defense like puffer
# inflation or triggerfish front-cone). Spears with bypasses_defenses skip the call.
func deflects_spear(spear: Node2D) -> bool:
	# Trophy-class fish (e.g. White Whale) bounce anything that doesn't break defenses.
	# Generic so future trophy species inherit the rule automatically.
	if size_class == SIZE_TROPHY:
		return not spear.spear_type_breaks_defenses()
	if species == "jellyfish":
		return not spear.spear_type_breaks_defenses()
	if species == "pufferfish":
		# Only the fully-inflated phase bounces; the inflating transition is just a tell.
		return puffer_phase == PufferPhase.INFLATED
	if species == "triggerfish":
		var facing := Vector2(forward_sign, 0.0)
		var to_spear := spear.global_position - global_position
		if to_spear.length_squared() < 0.0001:
			return false
		# True if spear approaches inside the front cone (i.e. dot is positive enough).
		var cos_threshold := cos(TRIGGER_SHIELD_HALF_ANGLE)
		return facing.dot(to_spear.normalized()) >= cos_threshold
	if species == "blockfish":
		# Shield direction is randomized per fish — could be front or back.
		var shield := Vector2(_blockfish_shield_dir(), 0.0)
		var to_spear_b := spear.global_position - global_position
		if to_spear_b.length_squared() < 0.0001:
			return false
		var cos_thr_b := cos(BLOCKFISH_SHIELD_HALF_ANGLE)
		return shield.dot(to_spear_b.normalized()) >= cos_thr_b
	return false


# Called by Spear after a bounce. Triggerfish flips facing toward threat + alarm.
func on_bounce(spear: Node2D) -> void:
	if species == "triggerfish":
		var to_spear := spear.global_position - global_position
		if to_spear.x != 0:
			forward_sign = 1.0 if to_spear.x > 0 else -1.0
			velocity = Vector2(speed * forward_sign, 0)
		trigger_alarm_until = age + TRIGGER_ALARM_DURATION
	elif species == "blockfish":
		# Same alarm tell as triggerfish, but it doesn't flip to face the threat —
		# the shield direction is fixed, so the player has to read it and reposition.
		blockfish_alarm_until = age + BLOCKFISH_ALARM_DURATION


func _process_triggerfish(delta: float) -> void:
	# Edge bounce: turn around when reaching screen margins so it patrols.
	var viewport = get_viewport_rect().size
	if global_position.x < 40.0 and forward_sign < 0:
		forward_sign = 1.0
		velocity = Vector2(speed * forward_sign, 0)
	elif global_position.x > viewport.x - 40.0 and forward_sign > 0:
		forward_sign = -1.0
		velocity = Vector2(speed * forward_sign, 0)
	# While alarmed it moves at full speed; otherwise gentle patrol.
	var s := speed if age < trigger_alarm_until else speed * 0.85
	velocity = Vector2(s * forward_sign, 0)
	var wave_y = sin(age * wave_frequency + wave_phase) * wave_amplitude * delta
	var avoid = diver_avoidance_for(self, global_position, species)
	global_position += (velocity + avoid) * delta + Vector2(0, wave_y)


func _update_collision_radius() -> void:
	if _shape and _shape.shape is CircleShape2D:
		(_shape.shape as CircleShape2D).radius = get_effective_hit_radius()


func _find_flying_spear() -> Node2D:
	# Spears spawn under the main scene now (not under the diver). Pick the
	# closest one in flight so puffer/triggerfish detection feels responsive.
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var closest: Node2D = null
	var min_d_sq := INF
	for child in scene.get_children():
		if child is Spear and (child as Spear).state == Spear.State.FLYING:
			var d := global_position.distance_squared_to(child.global_position)
			if d < min_d_sq:
				min_d_sq = d
				closest = child
	return closest


func _process_schooling(delta: float) -> void:
	_offset_jitter_timer -= delta
	if _offset_jitter_timer <= 0.0:
		_offset_jitter_timer = school.OFFSET_JITTER_INTERVAL
		var theta = randf() * TAU
		var rho = sqrt(randf()) * school.SCHOOL_RADIUS
		slot_offset = Vector2(cos(theta) * rho, sin(theta) * rho)

	if school.state == school.State.PANIC:
		var flee_dir = global_position - school.panic_origin
		if flee_dir.length_squared() < 0.01:
			flee_dir = Vector2.RIGHT.rotated(randf() * TAU)
		else:
			flee_dir = flee_dir.normalized()
		var desired = flee_dir * school.PANIC_SPEED
		velocity = velocity.lerp(desired, school.PANIC_STEER * delta)
		global_position += velocity * delta
		return

	var gain = school.STEER_GAIN
	if school.state == school.State.REGROUP:
		gain *= 1.5
	var target = school.leader_pos + slot_offset
	var to_target = target - global_position
	var desired_velocity = (to_target * gain).limit_length(school.MAX_SCHOOL_SPEED)
	velocity = velocity.lerp(desired_velocity, school.STEER_SMOOTH * delta)
	global_position += velocity * delta


func on_speared(_spear: Node2D) -> void:
	speared = true
	if school != null and is_instance_valid(school):
		school._on_member_speared(global_position)
	if species == "squid":
		_spawn_ink_cloud()
	play_hit_feedback()


func _spawn_ink_cloud() -> void:
	var ink_scene: PackedScene = load("res://scenes/ink_cloud.tscn") as PackedScene
	if ink_scene == null:
		return
	var cloud = ink_scene.instantiate()
	cloud.global_position = global_position
	get_tree().current_scene.add_child(cloud)


func play_hit_feedback() -> void:
	# Overbright flash, then fade back to normal modulate
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = Color(4.0, 4.0, 4.0)
	_flash_tween = create_tween()
	_flash_tween.set_ignore_time_scale(true)
	_flash_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Squash-stretch
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	scale = Vector2.ONE
	_squash_tween = create_tween()
	_squash_tween.set_ignore_time_scale(true)
	_squash_tween.tween_property(self, "scale", Vector2(1.35, 0.7), 0.06)
	_squash_tween.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func get_cash_value() -> int:
	var bonus = 1.5 if _is_inflated() else 1.0
	return int(base_value * bonus)


func get_effective_hit_radius() -> float:
	var r = hit_radius
	if _is_inflated():
		r = 32.0
	return r


func _draw() -> void:
	if species == "squid":
		_draw_squid()
		return
	if species == "anglerfish":
		_draw_anglerfish()
		return
	if species == "jellyfish":
		_draw_jellyfish()
		return
	if species == "whitewhale":
		_draw_whitewhale()
		return
	var body_color = color
	# Lock facing once speared so external rotation orients the fish
	var facing_right = true if speared else velocity.x >= 0
	var dir = 1.0 if facing_right else -1.0
	var radius_for_draw = 32.0 if _is_inflated() else hit_radius
	var body_len = radius_for_draw * 1.8
	var body_h = radius_for_draw * 1.0
	if species == "marlin":
		body_len = hit_radius * 2.6  # long sleek body + bill
		body_h = hit_radius * 0.7
	var half_len = body_len * 0.5
	# Tail beat — back half flexes, tail kicks
	var bend = sin(age * wave_frequency + wave_phase)
	var bend_amp = body_h * 0.25
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Body — vertices toward the tail side get a vertical offset
	var pts = PackedVector2Array()
	var n = 18
	for i in n:
		var a = float(i) / n * TAU
		var x = cos(a) * half_len
		var y = sin(a) * body_h * 0.5
		var tail_factor = clampf(-dir * x / half_len, 0.0, 1.0)
		y += bend * bend_amp * tail_factor
		pts.append(Vector2(x, y))
	draw_colored_polygon(pts, body_color)
	# Tail triangle — rotates around its anchor by bend
	var tx = -half_len * dir
	var tail_kick = bend * 0.5  # radians
	var ca = cos(tail_kick)
	var sa = sin(tail_kick)
	var p_a = Vector2(0, 0)
	var p_b = Vector2(-8 * dir, -6)
	var p_c = Vector2(-8 * dir, 6)
	p_b = Vector2(p_b.x * ca - p_b.y * sa, p_b.x * sa + p_b.y * ca)
	p_c = Vector2(p_c.x * ca - p_c.y * sa, p_c.x * sa + p_c.y * ca)
	draw_polygon(
		PackedVector2Array([
			Vector2(tx, 0) + p_a,
			Vector2(tx, 0) + p_b,
			Vector2(tx, 0) + p_c,
		]),
		PackedColorArray([body_color.darkened(0.15)])
	)
	draw_circle(Vector2(half_len * 0.6 * dir, -body_h * 0.2), 1.6, Color.BLACK)
	# Marlin bill — long pointy nose
	if species == "marlin":
		var bill_tip = Vector2(half_len * dir + 18 * dir, 0)
		var bill_base_top = Vector2(half_len * dir, -2)
		var bill_base_bot = Vector2(half_len * dir, 2)
		draw_polygon(
			PackedVector2Array([bill_base_top, bill_tip, bill_base_bot]),
			PackedColorArray([body_color.darkened(0.3)])
		)
	# Pufferfish spikes when inflated
	if species == "pufferfish" and _is_inflated():
		for i in 12:
			var a = float(i) / 12 * TAU
			var inner = Vector2(cos(a), sin(a)) * radius_for_draw * 0.95
			var outer = Vector2(cos(a), sin(a)) * radius_for_draw * 1.18
			draw_line(inner, outer, body_color.darkened(0.3), 1.5)
	# Lanternfish glow
	if species == "lanternfish":
		var glow_color = Color(0.55, 0.75, 1.0, 0.35)
		draw_circle(Vector2.ZERO, hit_radius * 1.6, glow_color)
		draw_circle(Vector2(half_len * 0.7 * dir, 0), 2.0, Color(0.7, 0.9, 1.0))
	# Triggerfish shield plate — darker plate on the front half, brighter when alarmed.
	if species == "triggerfish":
		var alarmed := age < trigger_alarm_until
		var plate_color = Color(0.85, 0.9, 1.0) if alarmed else Color(0.35, 0.4, 0.55)
		var plate_pts = PackedVector2Array()
		var segs := 12
		for i in segs + 1:
			var t := float(i) / segs  # 0..1
			# Sweep across the front cone (60° each side of facing).
			var a := lerpf(-TRIGGER_SHIELD_HALF_ANGLE, TRIGGER_SHIELD_HALF_ANGLE, t)
			var local_dir := Vector2(cos(a) * dir, sin(a))
			plate_pts.append(local_dir * (hit_radius * 0.95))
		# Close the polygon back through center for a fan look.
		plate_pts.append(Vector2.ZERO)
		draw_colored_polygon(plate_pts, Color(plate_color.r, plate_color.g, plate_color.b, 0.55))
	# Blockfish shield plate — extends OUT past the body so the armored side
	# reads instantly. Larger fan + thicker rim than triggerfish.
	if species == "blockfish":
		var alarmed_b := age < blockfish_alarm_until
		var plate_color_b = Color(1.0, 0.85, 0.3) if alarmed_b else Color(0.55, 0.4, 0.18)
		var plate_dir: float = _blockfish_shield_dir()
		# Draw flips with `dir` for sprite-facing, but the SHIELD position depends
		# on world-space direction (forward_sign × shield_back). Convert to local.
		var draw_shield_dir: float = plate_dir / dir if dir != 0 else plate_dir
		# Outer plate (bigger than body to read clearly).
		var plate_outer: float = hit_radius * 1.25
		var pts_b := PackedVector2Array()
		var segs_b := 14
		for i in segs_b + 1:
			var t := float(i) / segs_b
			var a := lerpf(-BLOCKFISH_SHIELD_HALF_ANGLE, BLOCKFISH_SHIELD_HALF_ANGLE, t)
			var local_dir_b := Vector2(cos(a) * draw_shield_dir, sin(a))
			pts_b.append(local_dir_b * plate_outer)
		pts_b.append(Vector2.ZERO)
		draw_colored_polygon(pts_b, Color(plate_color_b.r, plate_color_b.g, plate_color_b.b, 0.78))
		# Inner darker layer for depth.
		var inner_pts := PackedVector2Array()
		for i in segs_b + 1:
			var t := float(i) / segs_b
			var a := lerpf(-BLOCKFISH_SHIELD_HALF_ANGLE * 0.85, BLOCKFISH_SHIELD_HALF_ANGLE * 0.85, t)
			inner_pts.append(Vector2(cos(a) * draw_shield_dir, sin(a)) * (plate_outer * 0.7))
		inner_pts.append(Vector2.ZERO)
		draw_colored_polygon(inner_pts, Color(plate_color_b.r * 0.6, plate_color_b.g * 0.6, plate_color_b.b * 0.6, 0.6))
		# Studded rim — bigger dots on the outer arc make it read as armor.
		var rim_color := Color(plate_color_b.r * 1.3, plate_color_b.g * 1.3, plate_color_b.b * 1.3, 0.95)
		var studs := 7
		for j in studs:
			var t2: float = (float(j) + 0.5) / float(studs)
			var a2: float = lerpf(-BLOCKFISH_SHIELD_HALF_ANGLE * 0.92, BLOCKFISH_SHIELD_HALF_ANGLE * 0.92, t2)
			var stud_pos := Vector2(cos(a2) * draw_shield_dir, sin(a2)) * (plate_outer * 0.95)
			draw_circle(stud_pos, 2.4, rim_color)


func _draw_squid() -> void:
	var body_color = color
	# Squid body (triangular mantle pointing in burst direction).
	# When speared, spear sets node rotation externally — keep local draw flat.
	var ang = 0.0
	if not speared:
		var dir_vec = velocity.normalized() if velocity.length() > 1.0 else Vector2(forward_sign, 0)
		ang = dir_vec.angle()
	draw_set_transform(Vector2.ZERO, ang, Vector2.ONE)
	var body_len = hit_radius * 1.6
	var body_h = hit_radius * 1.1
	# Mantle (teardrop pointing forward)
	draw_polygon(
		PackedVector2Array([
			Vector2(body_len * 0.6, 0),
			Vector2(0, -body_h * 0.5),
			Vector2(-body_len * 0.4, 0),
			Vector2(0, body_h * 0.5),
		]),
		PackedColorArray([body_color])
	)
	# Tentacles trailing behind
	var tentacle_base = Vector2(-body_len * 0.4, 0)
	var bend = sin(age * 6.0 + wave_phase) * 0.4
	for i in 5:
		var t_off = (float(i) - 2) * 2.5
		var bend_i = bend + (float(i) - 2) * 0.15
		var p1 = tentacle_base + Vector2(0, t_off)
		var p2 = p1 + Vector2(-6, t_off + bend_i * 4)
		var p3 = p2 + Vector2(-6, t_off + bend_i * 7)
		draw_line(p1, p2, body_color.darkened(0.25), 1.5)
		draw_line(p2, p3, body_color.darkened(0.4), 1.2)
	# Eye
	draw_circle(Vector2(body_len * 0.25, -body_h * 0.18), 1.6, Color.BLACK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_jellyfish() -> void:
	# Translucent dome with wavy tendrils — drifts gently regardless of facing.
	var body_color = color
	var r = hit_radius
	# Dome (semi-circle, opening downward).
	var dome_pts = PackedVector2Array()
	var segs: int = 14
	for i in segs + 1:
		var t: float = float(i) / float(segs)
		var a: float = lerpf(PI, TAU, t)  # PI..TAU = upper half
		dome_pts.append(Vector2(cos(a) * r, sin(a) * r * 0.9))
	# Close the polygon along the bottom.
	dome_pts.append(Vector2(r, 0))
	dome_pts.append(Vector2(-r, 0))
	draw_colored_polygon(dome_pts, body_color)
	# Inner highlight rim across the top.
	draw_arc(Vector2.ZERO, r * 0.8, PI + 0.3, TAU - 0.3, 12, body_color.lightened(0.3), 1.2)
	# Tendrils — 4 wavy lines dangling below.
	var tendril_color := Color(body_color.r, body_color.g, body_color.b, 0.7)
	var n_tendrils: int = 4
	for i in n_tendrils:
		var x_off: float = lerpf(-r * 0.7, r * 0.7, float(i) / float(n_tendrils - 1))
		var prev := Vector2(x_off, 0)
		var pieces: int = 5
		for j in pieces:
			var t: float = float(j + 1) / float(pieces)
			var y: float = t * r * 1.4
			var sway: float = sin(age * 2.0 + wave_phase + t * 3.0 + float(i) * 0.5) * 3.0
			var next := Vector2(x_off + sway, y)
			draw_line(prev, next, tendril_color, 1.3)
			prev = next


func _draw_anglerfish() -> void:
	var body_color = color
	body_color.a = 0.55  # body is faint — almost invisible in dark zones
	var facing_right = true if speared else velocity.x >= 0
	var dir = 1.0 if facing_right else -1.0
	var body_len = hit_radius * 2.0
	var body_h = hit_radius * 1.2
	var half_len = body_len * 0.5
	# Faint body silhouette
	var pts = PackedVector2Array()
	var n = 16
	for i in n:
		var a = float(i) / n * TAU
		var x = cos(a) * half_len
		var y = sin(a) * body_h * 0.5
		pts.append(Vector2(x, y))
	draw_colored_polygon(pts, body_color)
	# Tail
	var tx = -half_len * dir
	draw_polygon(
		PackedVector2Array([
			Vector2(tx, 0),
			Vector2(tx - 7 * dir, -5),
			Vector2(tx - 7 * dir, 5),
		]),
		PackedColorArray([body_color.darkened(0.2)])
	)
	# Lure — bright glowing dot dangling from a thin stalk above the body
	# Lure is offset 22px above and 4px forward of head
	var lure_pos = Vector2(half_len * 0.6 * dir, -22)
	var head_pos = Vector2(half_len * 0.55 * dir, -body_h * 0.3)
	# Stalk
	draw_line(head_pos, lure_pos, Color(0.4, 0.4, 0.5, 0.5), 1.0)
	# Lure halo
	var halo = Color(1.0, 0.85, 0.4, 0.35)
	draw_circle(lure_pos, 9, halo)
	draw_circle(lure_pos, 5, Color(1.0, 0.95, 0.6, 0.7))
	draw_circle(lure_pos, 2.5, Color(1.0, 1.0, 0.85))
	# Mouth — sharp teeth hint
	var mouth_x = half_len * 0.85 * dir
	draw_line(Vector2(mouth_x - 4 * dir, 2), Vector2(mouth_x, 0), Color(0.6, 0.55, 0.5, 0.7), 1.2)
	draw_line(Vector2(mouth_x - 4 * dir, -2), Vector2(mouth_x, 0), Color(0.6, 0.55, 0.5, 0.7), 1.2)


func _draw_whitewhale() -> void:
	# Massive pale silhouette: elongated body, dorsal fin, broad tail flare.
	# Strict typing because Godot 4.6 sometimes balks at inferred Vector2/float in draw helpers.
	var dir: float = forward_sign if not speared else 1.0
	var body_len: float = hit_radius * 3.0
	var body_h: float = hit_radius * 1.0
	var half_len: float = body_len * 0.5
	var bend: float = sin(age * wave_frequency + wave_phase)
	var bend_amp: float = body_h * 0.18
	# Body: elongated ellipse with subtle tail flex.
	var pts: PackedVector2Array = PackedVector2Array()
	var n: int = 22
	for i in n:
		var a: float = float(i) / float(n) * TAU
		var x: float = cos(a) * half_len
		var y: float = sin(a) * body_h * 0.5
		var tail_factor: float = clampf(-dir * x / half_len, 0.0, 1.0)
		y += bend * bend_amp * tail_factor
		pts.append(Vector2(x, y))
	draw_colored_polygon(pts, color)
	# Belly shading — slightly darker band on the lower half for depth.
	var belly_pts: PackedVector2Array = PackedVector2Array()
	for i in n:
		var a2: float = float(i) / float(n) * PI  # 0..PI lower half
		var x2: float = cos(a2) * half_len * 0.95
		var y2: float = sin(a2) * body_h * 0.45
		belly_pts.append(Vector2(x2, y2))
	draw_colored_polygon(belly_pts, color.darkened(0.18))
	# Dorsal fin — small triangle near mid-back.
	var fin_x: float = -half_len * 0.1 * dir
	var fin_w: float = body_h * 0.3
	draw_polygon(
		PackedVector2Array([
			Vector2(fin_x, -body_h * 0.5),
			Vector2(fin_x - fin_w * dir, -body_h * 0.85),
			Vector2(fin_x + fin_w * dir, -body_h * 0.55),
		]),
		PackedColorArray([color.darkened(0.25)])
	)
	# Tail fluke — wide horizontal flare at the back.
	var tx: float = -half_len * dir
	var fluke_kick: float = bend * 0.35
	var ca: float = cos(fluke_kick)
	var sa: float = sin(fluke_kick)
	var p_top: Vector2 = Vector2(-14.0 * dir, -16.0)
	var p_bot: Vector2 = Vector2(-14.0 * dir, 16.0)
	var p_mid: Vector2 = Vector2(-4.0 * dir, 0.0)
	p_top = Vector2(p_top.x * ca - p_top.y * sa, p_top.x * sa + p_top.y * ca)
	p_bot = Vector2(p_bot.x * ca - p_bot.y * sa, p_bot.x * sa + p_bot.y * ca)
	p_mid = Vector2(p_mid.x * ca - p_mid.y * sa, p_mid.x * sa + p_mid.y * ca)
	draw_polygon(
		PackedVector2Array([
			Vector2(tx, 0) + p_mid,
			Vector2(tx, 0) + p_top,
			Vector2(tx - 4.0 * dir, 0),
			Vector2(tx, 0) + p_bot,
		]),
		PackedColorArray([color.darkened(0.22)])
	)
	# Eye — small dark dot near the head.
	draw_circle(Vector2(half_len * 0.7 * dir, -body_h * 0.18), 2.2, Color.BLACK)
