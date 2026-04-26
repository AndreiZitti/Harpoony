class_name Spear
extends Area2D

const HitBurstScene = preload("res://scenes/hit_burst.tscn")

@onready var _shape: CollisionShape2D = $CollisionShape2D

enum State { READY, FLYING, REELING_MISS, REELING_HIT, NET_REELING }

var state: int = State.READY
var diver_node: Node2D = null
var attached_fish: Fish = null
var attached_fish_array: Array = []  # net catches

# Type
var current_type_id: StringName = &"normal"
var current_type: SpearType = null

# Movement
var flight_dir: Vector2 = Vector2.ZERO
var flight_distance_remaining: float = 0.0
var _line_time: float = 0.0
var _hits_this_flight: int = 0
const MAX_FLIGHT_DISTANCE = 600.0


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	# Type is pulled at fire time so the bag stays a discrete round — see throw_in_direction.
	_clear_type()
	_sync_hud()


func _clear_type() -> void:
	current_type_id = &""
	current_type = null
	_apply_type_visuals()


# Tries to pull the next type from the bag for an imminent throw. Returns false
# if the round is exhausted — caller should not fire.
func _pull_type_for_fire() -> bool:
	var id := GameData.draw_next_spear_type()
	if id == &"":
		return false
	current_type_id = id
	current_type = GameData.get_spear_type(id)
	_apply_type_visuals()
	return true


func _apply_type_visuals() -> void:
	# Per-instance shape so hit-radius upgrades don't share radius globally.
	var circle := CircleShape2D.new()
	var bonus := 0.0
	if current_type:
		bonus = GameData.get_effective_spear_stat(current_type_id, "hit_radius_bonus")
	circle.radius = 4.0 + bonus
	if _shape:
		_shape.shape = circle


func _on_area_entered(area: Area2D) -> void:
	if state != State.FLYING:
		return
	if not (area is Fish):
		return
	var f := area as Fish
	if f.speared:
		return
	# Defense check first — fish may deflect non-bypassing spears.
	var bypass: bool = current_type and current_type.bypasses_defenses
	if not bypass and f.has_method("deflects_spear") and f.deflects_spear(self):
		_handle_bounce(f)
		return
	# Net is AoE: always go through net path even with no special pierce.
	if current_type_id == &"net":
		_net_capture(f)
		return
	# Normal/Heavy: use pierce-through path when pierce_count > 1, else attach.
	var pierce_cap: int = int(GameData.get_effective_spear_stat(current_type_id, "pierce_count"))
	if pierce_cap > 1:
		_pierce_through(f)
	else:
		attach_to_fish(f)


func _handle_bounce(fish: Fish) -> void:
	# Bounce VFX — reuse hit_burst with a metallic tint so it reads differently.
	_spawn_hit_burst(global_position, Color(0.9, 0.95, 1.0))
	Sfx.bounce()
	if fish.has_method("on_bounce"):
		fish.on_bounce(self)
	state = State.REELING_MISS
	monitoring = false
	_sync_hud()


func throw_in_direction(dir: Vector2) -> void:
	# Legacy entry point. Prefer fire(dir), which signals failure to the caller.
	fire(dir)


# Pulls a type from the bag, transitions to FLYING. Returns false if the bag
# can't yield a type (e.g. round exhausted) so the caller can drop the instance.
func fire(dir: Vector2) -> bool:
	if state != State.READY:
		return false
	if dir.length() < 0.001:
		return false
	if not _pull_type_for_fire():
		return false
	flight_dir = dir.normalized()
	flight_distance_remaining = MAX_FLIGHT_DISTANCE
	state = State.FLYING
	monitoring = true
	_hits_this_flight = 0
	GameData.note_spear_fired()
	Sfx.fire()
	_sync_hud()
	queue_redraw()
	return true


func _effective_speed() -> float:
	return GameData.get_effective_spear_speed(current_type_id)


func _effective_reel_speed() -> float:
	return GameData.get_effective_reel_speed(current_type_id)


func _pierce_through(fish: Fish) -> void:
	fish.on_speared(self)
	var base := fish.get_cash_value()
	base = int(round(base * _crit_multiplier(fish)))
	# TODO: if get_effective_spear_stat(current_type_id, "sonic_boom") >= 1, stun nearby fish for ~0.6s.
	var result := GameData.register_hit(base)
	var arrive_pos := fish.global_position
	var species := fish.species
	GameData.add_dive_cash(result["value"])
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud and hud.has_method("spawn_cash_popup"):
		hud.spawn_cash_popup(result["value"], arrive_pos, species)
	_spawn_hit_burst(arrive_pos, fish.color)
	fish.queue_free()
	_hits_this_flight += 1
	# Stop piercing after the cap.
	var cap: int = int(GameData.get_effective_spear_stat(current_type_id, "pierce_count"))
	if _hits_this_flight >= cap:
		state = State.REELING_MISS
		monitoring = false
		_sync_hud()


func _net_capture(first_fish: Fish) -> void:
	var radius: float = GameData.get_effective_spear_stat(current_type_id, "net_radius")
	var max_catch: int = int(GameData.get_effective_spear_stat(current_type_id, "net_max_catch"))
	# Effective allowed size set: defaults from SpearType, widened by Bigger Hoop upgrade.
	var allowed := current_type.catch_size_classes.duplicate()
	if int(GameData.get_effective_spear_stat(current_type_id, "catches_medium")) == 1 and not allowed.has(&"medium"):
		allowed.append(&"medium")
	attached_fish_array.clear()
	# TODO: if current_type.lure_net == 1 (or effective stat == 1), tween caught fish toward net center over ~0.2s before resolution.
	# Include the first fish that triggered the net only if it matches the size gate.
	if allowed.has(first_fish.size_class):
		first_fish.on_speared(self)
		attached_fish_array.append(first_fish)
		_spawn_hit_burst(first_fish.global_position, first_fish.color)
	# Sweep nearby fish.
	var center := global_position
	var r2 := radius * radius
	var nearby = get_tree().get_nodes_in_group("fish")
	for n in nearby:
		if attached_fish_array.size() >= max_catch:
			break
		if n == first_fish:
			continue
		var f := n as Fish
		if f == null or not is_instance_valid(f) or f.speared:
			continue
		if not allowed.has(f.size_class):
			continue
		if f.global_position.distance_squared_to(center) <= r2:
			f.on_speared(self)
			attached_fish_array.append(f)
			_spawn_hit_burst(f.global_position, f.color)
	state = State.NET_REELING
	monitoring = false
	_hits_this_flight = attached_fish_array.size()
	Sfx.net_catch()
	var main = get_tree().current_scene
	if main and main.has_method("hit_stop"):
		main.hit_stop()
	_sync_hud()


func attach_to_fish(fish: Fish) -> void:
	if state != State.FLYING:
		return
	attached_fish = fish
	fish.on_speared(self)
	state = State.REELING_HIT
	monitoring = false
	_hits_this_flight += 1
	_spawn_hit_burst(fish.global_position, fish.color)
	Sfx.hit()
	var main = get_tree().current_scene
	if main and main.has_method("hit_stop"):
		main.hit_stop()
	_sync_hud()


func _spawn_hit_burst(at: Vector2, tint: Color) -> void:
	var burst: GPUParticles2D = HitBurstScene.instantiate()
	burst.global_position = at
	burst.modulate = tint.lightened(0.3)
	get_tree().current_scene.add_child(burst)
	var t := burst.get_tree().create_timer(burst.lifetime + 0.1)
	t.timeout.connect(burst.queue_free)


func recall_instant() -> void:
	# Used when the dive ends mid-flight. Drop the spear and tell the bag we're done.
	if state == State.FLYING or state == State.REELING_HIT or state == State.REELING_MISS or state == State.NET_REELING:
		GameData.note_spear_returned()
	attached_fish = null
	attached_fish_array.clear()
	monitoring = false
	state = State.READY
	_clear_type()
	_sync_hud()
	queue_free()


func _process(delta: float) -> void:
	match state:
		State.READY:
			if diver_node:
				global_position = diver_node.global_position
		State.FLYING:
			var speed = _effective_speed()
			var step = speed * delta
			global_position += flight_dir * step
			flight_distance_remaining -= step
			if flight_distance_remaining <= 0.0 or _is_out_of_bounds():
				state = State.REELING_MISS
				monitoring = false
				if _hits_this_flight == 0:
					GameData.register_miss()
					Sfx.miss()
				_sync_hud()
		State.REELING_MISS:
			var speed = _effective_speed()
			_reel_toward_diver(speed, delta)
		State.REELING_HIT:
			var speed = _effective_reel_speed()
			_reel_toward_diver(speed, delta)
			_line_time += delta
			if attached_fish and is_instance_valid(attached_fish):
				attached_fish.global_position = global_position
				var away_from_diver = global_position - diver_node.global_position
				if away_from_diver.length_squared() > 0.01:
					var target_angle = away_from_diver.angle()
					attached_fish.rotation = lerp_angle(attached_fish.rotation, target_angle, clampf(delta * 10.0, 0.0, 1.0))
		State.NET_REELING:
			var speed = _effective_reel_speed()
			_reel_toward_diver(speed, delta)
			_line_time += delta
			_position_net_fish(delta)
	queue_redraw()


func _position_net_fish(delta: float) -> void:
	# Fan caught fish in a small ring around the spear tip.
	var n := attached_fish_array.size()
	if n == 0:
		return
	for i in n:
		var f = attached_fish_array[i]
		if not is_instance_valid(f):
			continue
		var angle := TAU * float(i) / float(n)
		var offset := Vector2(cos(angle), sin(angle)) * 14.0
		f.global_position = global_position + offset
		var away = global_position - diver_node.global_position
		if away.length_squared() > 0.01:
			f.rotation = lerp_angle(f.rotation, away.angle(), clampf(delta * 10.0, 0.0, 1.0))


func _is_out_of_bounds() -> bool:
	# Once the tip leaves the play area, treat as a miss and reel back in.
	var viewport = get_viewport_rect().size
	const MARGIN := 8.0
	return global_position.x < -MARGIN \
			or global_position.x > viewport.x + MARGIN \
			or global_position.y < -MARGIN \
			or global_position.y > viewport.y + MARGIN


func _reel_toward_diver(speed: float, delta: float) -> void:
	if not diver_node:
		return
	var to_diver = diver_node.global_position - global_position
	var dist = to_diver.length()
	if dist < 8.0:
		_arrive()
		return
	global_position += to_diver.normalized() * speed * delta


func _award_fish(fish: Fish) -> void:
	var base := fish.get_cash_value()
	# Apply per-type value bonus (normal spears mostly).
	var bonus: float = 1.0
	if current_type:
		bonus = GameData.get_effective_spear_stat(current_type_id, "value_bonus")
	base = int(round(base * bonus))
	# Heavy crit branch: Sharp Tip rolls a chance for 2x; Perfect Strike auto-3x on dead-center.
	# TODO: if get_effective_spear_stat(current_type_id, "sonic_boom") >= 1, stun nearby fish for ~0.6s on impact.
	base = int(round(base * _crit_multiplier(fish)))
	var result := GameData.register_hit(base)
	var arrive_pos := fish.global_position
	var species := fish.species
	GameData.add_dive_cash(result["value"])
	GameData.note_fish_caught()
	Sfx.cash(result["value"])
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud and hud.has_method("spawn_cash_popup"):
		hud.spawn_cash_popup(result["value"], arrive_pos, species)


func _arrive() -> void:
	if state == State.REELING_HIT and attached_fish and is_instance_valid(attached_fish):
		_award_fish(attached_fish)
		attached_fish.queue_free()
		attached_fish = null
	elif state == State.NET_REELING:
		for f in attached_fish_array:
			if is_instance_valid(f):
				_award_fish(f)
				f.queue_free()
		attached_fish_array.clear()
	# Notify the bag so the round can reshuffle once the last spear lands.
	GameData.note_spear_returned()
	# Notify HUD before we go away so the queue chip refreshes.
	state = State.READY
	_clear_type()
	_sync_hud()
	queue_free()


func _sync_hud() -> void:
	# Single hook — HUD reads the bag queue itself for the preview.
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud == null:
		return
	if hud.has_method("notify_bag_changed"):
		hud.notify_bag_changed()


func _draw() -> void:
	if state == State.READY:
		return
	if diver_node:
		var local_diver = to_local(diver_node.global_position)
		var line_color = Color(0.9, 0.9, 0.95, 0.6)
		var has_catch := (state == State.REELING_HIT and attached_fish) or (state == State.NET_REELING and not attached_fish_array.is_empty())
		if has_catch:
			var segs = 8
			var amp = 4.0
			if state == State.REELING_HIT and attached_fish:
				amp += attached_fish.get_effective_hit_radius() * 0.25
			elif state == State.NET_REELING:
				amp += 2.0 * float(attached_fish_array.size())
			var perp = (local_diver - Vector2.ZERO).normalized().orthogonal()
			var pts = PackedVector2Array()
			for i in range(segs + 1):
				var t = float(i) / segs
				var base = Vector2.ZERO.lerp(local_diver, t)
				var env = sin(t * PI)
				var offset = sin(_line_time * 9.0 + t * 6.0) * amp * env
				pts.append(base + perp * offset)
			for i in range(segs):
				draw_line(pts[i], pts[i + 1], line_color, 1.5)
		else:
			draw_line(Vector2.ZERO, local_diver, line_color, 1.5)
	var angle = flight_dir.angle()
	if state != State.FLYING:
		var reel_vec = diver_node.global_position - global_position if diver_node else Vector2.RIGHT
		if reel_vec.length() > 0.001:
			angle = reel_vec.angle() + PI
	draw_set_transform(Vector2.ZERO, angle, Vector2.ONE)
	# Per-type silhouette so each spear reads at a glance.
	match current_type_id:
		&"net":
			_draw_net_spear()
		&"heavy":
			_draw_heavy_spear()
		_:
			_draw_normal_spear()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_normal_spear() -> void:
	# Slim, cream-colored — quick & precise.
	var length = 22.0
	var width = 3.0
	var shaft_color = current_type.color.darkened(0.15) if current_type else Color(0.8, 0.8, 0.85)
	var tip_color = current_type.color if current_type else Color(0.95, 0.9, 0.6)
	draw_rect(Rect2(-length / 2, -width / 2, length, width), shaft_color)
	# Sharp, narrow arrowhead.
	var tip = length / 2
	draw_polygon(
		PackedVector2Array([Vector2(tip + 3, 0), Vector2(tip - 5, -4), Vector2(tip - 5, 4)]),
		PackedColorArray([tip_color])
	)
	# Fletching — small back fins.
	var back = -length / 2
	draw_polygon(
		PackedVector2Array([Vector2(back, 0), Vector2(back + 5, -3), Vector2(back + 5, 3)]),
		PackedColorArray([shaft_color.lightened(0.1)])
	)


func _draw_heavy_spear() -> void:
	# Thick, dark shaft with a chunky head — reads as "weight".
	var length = 28.0
	var width = 6.0
	var shaft_color = current_type.color.darkened(0.4) if current_type else Color(0.4, 0.3, 0.2)
	var tip_color = current_type.color if current_type else Color(0.85, 0.65, 0.45)
	# Shaft with two darker stripes for grip texture.
	draw_rect(Rect2(-length / 2, -width / 2, length, width), shaft_color)
	draw_line(Vector2(-length / 2 + 3, -width / 2 + 1), Vector2(length / 2 - 8, -width / 2 + 1), shaft_color.darkened(0.3), 1.0)
	draw_line(Vector2(-length / 2 + 3, width / 2 - 1), Vector2(length / 2 - 8, width / 2 - 1), shaft_color.darkened(0.3), 1.0)
	# Heavy bladed head — wider triangular plate.
	var tip_x = length / 2 + 4
	var head_back = length / 2 - 8
	draw_polygon(
		PackedVector2Array([
			Vector2(tip_x, 0),
			Vector2(head_back, -7),
			Vector2(head_back + 3, 0),
			Vector2(head_back, 7),
		]),
		PackedColorArray([tip_color])
	)
	# Center ridge highlight.
	draw_line(Vector2(head_back, 0), Vector2(tip_x, 0), tip_color.lightened(0.3), 1.2)


func _draw_net_spear() -> void:
	# Compact bolt with a translucent hoop hauling the net.
	var length = 18.0
	var width = 4.0
	var shaft_color = current_type.color.darkened(0.2) if current_type else Color(0.4, 0.7, 0.85)
	var tip_color = current_type.color if current_type else Color(0.5, 0.85, 1.0)
	draw_rect(Rect2(-length / 2, -width / 2, length, width), shaft_color)
	# Knot/anchor at the back where the net trails from.
	draw_circle(Vector2(-length / 2, 0), 3, shaft_color.lightened(0.15))
	# Wider, blunter head — net launcher, not piercer.
	var tip_x = length / 2
	draw_polygon(
		PackedVector2Array([
			Vector2(tip_x + 2, 0),
			Vector2(tip_x - 3, -5),
			Vector2(tip_x - 3, 5),
		]),
		PackedColorArray([tip_color])
	)
	# Net hoop preview during flight, scaled to current radius upgrade.
	if state == State.FLYING:
		var r: float = GameData.get_effective_spear_stat(current_type_id, "net_radius")
		draw_arc(Vector2(tip_x, 0), r, 0.0, TAU, 32, Color(tip_color.r, tip_color.g, tip_color.b, 0.25), 1.5)
		# Mesh hint — radial spokes.
		for i in 8:
			var a := float(i) / 8.0 * TAU
			var p := Vector2(cos(a), sin(a)) * r
			draw_line(Vector2(tip_x, 0), Vector2(tip_x, 0) + p, Color(tip_color.r, tip_color.g, tip_color.b, 0.12), 1.0)


func _crit_multiplier(fish: Node2D) -> float:
	# Heavy-only Crit branch: Perfect Strike (auto-3x on dead-center) takes precedence
	# over Sharp Tip's probabilistic 2x. Both upgrades read via get_effective_spear_stat
	# so future stacking sources Just Work.
	if current_type_id == &"":
		return 1.0
	var perfect_strike_eff: int = int(GameData.get_effective_spear_stat(current_type_id, "perfect_strike"))
	if perfect_strike_eff >= 1 and _is_dead_center_hit(fish):
		return 3.0
	var crit_chance_eff: float = GameData.get_effective_spear_stat(current_type_id, "crit_chance")
	if crit_chance_eff > 0.0 and randf() < crit_chance_eff:
		return 2.0
	return 1.0


func _is_dead_center_hit(fish: Node2D) -> bool:
	if fish == null or not is_instance_valid(fish):
		return false
	var d := global_position.distance_to(fish.global_position)
	return d <= fish.hit_radius * 0.25
