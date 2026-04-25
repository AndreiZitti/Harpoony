class_name Fish
extends Area2D

@onready var _shape: CollisionShape2D = $CollisionShape2D

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
var school = null
var slot_offset: Vector2 = Vector2.ZERO
var _offset_jitter_timer: float = 0.0
var forward_sign: float = 1.0
# Per-species behavior fields
var puffer_inflated_until: float = -1.0
var mahi_burst_until: float = -1.0
var mahi_burst_dir: Vector2 = Vector2.ZERO
var mahi_prev_seen_spear: bool = false
var squid_phase: int = 0  # 0 = STILL, 1 = BURST
var squid_phase_timer: float = 0.0
var spear_check_timer: float = 0.0
var _flash_tween: Tween = null
var _squash_tween: Tween = null


func setup(s: String, start_pos: Vector2, direction_right: bool) -> void:
	species = s
	match species:
		"sardine":
			base_value = 2
			hit_radius = 10.0
			speed = 160.0
			color = Color(0.75, 0.85, 0.95)
			wave_frequency = 5.5
		"grouper":
			base_value = 10
			hit_radius = 18.0
			speed = 80.0
			color = Color(0.8, 0.6, 0.3)
			wave_frequency = 2.8
		"tuna":
			base_value = 40
			hit_radius = 24.0
			speed = 120.0
			color = Color(0.4, 0.5, 0.7)
			wave_frequency = 3.6
		"pufferfish":
			base_value = 8
			hit_radius = 13.0
			speed = 50.0
			color = Color(0.95, 0.9, 0.45)
			wave_frequency = 1.5
		"mahimahi":
			base_value = 25
			hit_radius = 16.0
			speed = 90.0
			color = Color(0.95, 0.7, 0.2)
			wave_frequency = 4.0
		"squid":
			base_value = 18
			hit_radius = 13.0
			speed = 0.0
			color = Color(0.7, 0.35, 0.75)
			wave_frequency = 1.0
			squid_phase_timer = randf_range(0.4, 1.6)
		"lanternfish":
			base_value = 5
			hit_radius = 9.0
			speed = 130.0
			color = Color(0.4, 0.5, 0.75)
			wave_frequency = 4.5
		"anglerfish":
			base_value = 50
			hit_radius = 16.0
			speed = 30.0
			color = Color(0.13, 0.08, 0.18)
			wave_frequency = 0.9
		"marlin":
			base_value = 60
			hit_radius = 22.0
			speed = 280.0
			color = Color(0.2, 0.3, 0.55)
			wave_frequency = 1.0
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
	if global_position.x < -margin or global_position.x > viewport.x + margin:
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
		_:
			_process_default(delta)


func _process_default(delta: float) -> void:
	var wave_y = sin(age * wave_frequency + wave_phase) * wave_amplitude * delta
	global_position += velocity * delta + Vector2(0, wave_y)


func _process_pufferfish(delta: float) -> void:
	spear_check_timer -= delta
	if spear_check_timer <= 0.0:
		spear_check_timer = 0.05
		var sp = _find_flying_spear()
		if sp and global_position.distance_to(sp.global_position) < 80.0:
			puffer_inflated_until = age + 0.4
			_update_collision_radius()
		elif age > puffer_inflated_until and _shape and _shape.shape is CircleShape2D:
			# Restore deflated radius if expired
			if absf((_shape.shape as CircleShape2D).radius - get_effective_hit_radius()) > 0.5:
				_update_collision_radius()
	# Slow drift, sluggish
	var wave_y = sin(age * wave_frequency + wave_phase) * wave_amplitude * delta
	global_position += velocity * delta * 0.6 + Vector2(0, wave_y)


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
		var burst_speed = 320.0
		velocity = velocity.lerp(mahi_burst_dir * burst_speed, 9.0 * delta)
		global_position += velocity * delta
	else:
		# Restore cruise velocity if recovering from burst
		if velocity.length() > speed * 1.2:
			velocity = Vector2(speed * forward_sign, 0)
		var wave_y = sin(age * wave_frequency + wave_phase) * wave_amplitude * delta
		global_position += velocity * delta + Vector2(0, wave_y)


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
	global_position += velocity * delta
	if squid_phase == 0:
		# Subtle bob
		global_position.y += sin(age * 1.2 + wave_phase) * 8.0 * delta


func _is_inflated() -> bool:
	return species == "pufferfish" and age < puffer_inflated_until


func _update_collision_radius() -> void:
	if _shape and _shape.shape is CircleShape2D:
		(_shape.shape as CircleShape2D).radius = get_effective_hit_radius()


func _find_flying_spear() -> Node2D:
	var diver = get_tree().current_scene.get_node_or_null("Diver")
	if diver == null:
		return null
	for child in diver.get_children():
		if child is Spear and (child as Spear).state == Spear.State.FLYING:
			return child
	return null


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
	return int(base_value * GameData.get_fish_value_multiplier() * bonus)


func get_effective_hit_radius() -> float:
	var r = hit_radius
	if _is_inflated():
		r = 32.0
	return r + GameData.get_hit_radius_bonus()


func _draw() -> void:
	if species == "squid":
		_draw_squid()
		return
	if species == "anglerfish":
		_draw_anglerfish()
		return
	var tint = GameData.get_fish_tint()
	var body_color = color * tint
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


func _draw_squid() -> void:
	var tint = GameData.get_fish_tint()
	var body_color = color * tint
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


func _draw_anglerfish() -> void:
	var tint = GameData.get_fish_tint()
	var body_color = color * tint
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
