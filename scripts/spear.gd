class_name Spear
extends Area2D

const HitBurstScene = preload("res://scenes/hit_burst.tscn")
const NormalSpearTexture = preload("res://assets/spears/normal.png")
const NetSpearTexture = preload("res://assets/spears/net.png")
const HeavySpearTexture = preload("res://assets/spears/heavy.png")
const SPEAR_DRAW_LENGTH = 64.0  # screen length — tweak if too big/small in playtest

@onready var _shape: CollisionShape2D = $CollisionShape2D

enum State { READY, FLYING, REELING_MISS, REELING_HIT, NET_REELING, NET_STANDING_WAVE }

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
const STANDING_WAVE_DURATION := 3.0
# Net unfurls over its first ~0.4s of flight: visual + collision sweep both use
# the interpolated radius, so a too-early hit catches a smaller area. Rewards
# letting the net fly toward the school instead of point-blank casting.
const NET_GROW_TIME := 0.4
var _flight_time: float = 0.0
var _standing_wave_remaining: float = 0.0
var _standing_wave_max_catch: int = 1
var _standing_wave_allowed: Array = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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


func spear_type_breaks_defenses() -> bool:
	return current_type != null and current_type.bypasses_defenses


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
	# Heavy spear: small/medium fish are destroyed on impact (no catch, no
	# normal cash). Penetration Depth ramp lets Heavy plough through extra
	# small/medium fish on its way to a large target — Heavy's identity is the
	# trophy/defense-cracker, so this sacrifice is baked in.
	if current_type_id == &"heavy" and (f.size_class == Fish.SIZE_SMALL or f.size_class == Fish.SIZE_MEDIUM):
		_heavy_destroy_small(f)
		return
	# Defense check — fish may deflect non-bypassing spears.
	var bypass: bool = current_type and current_type.bypasses_defenses
	if not bypass and f.has_method("deflects_spear") and f.deflects_spear(self):
		_handle_bounce(f)
		return
	# Net is AoE: route through standing-wave trap if keystone owned, else
	# the regular instant-resolve sweep.
	if current_type_id == &"net":
		if int(GameData.get_effective_spear_stat(&"net", "standing_wave")) >= 1:
			_net_start_standing_wave(f)
		else:
			_net_capture(f)
		return
	# Heavy keystones fire on the impact frame (large/trophy fish only — the
	# small/med destroy branch above already returned). Black Hole Tip pulls
	# everything else in; Seismic Roar disables defenses screen-wide.
	if current_type_id == &"heavy":
		var bh: int = int(GameData.get_effective_spear_stat(&"heavy", "black_hole_tip"))
		if bh >= 1:
			_trigger_black_hole(global_position)
		var sr: int = int(GameData.get_effective_spear_stat(&"heavy", "seismic_roar"))
		if sr >= 1:
			GameData.trigger_seismic_roar()
	# Normal/Heavy: use pierce-through path when pierce_count > 1, else attach.
	var pierce_cap: int = int(GameData.get_effective_spear_stat(current_type_id, "pierce_count"))
	if pierce_cap > 1:
		_pierce_through(f)
	else:
		attach_to_fish(f)


# Heavy + Black Hole Tip: tween every small/medium fish on screen to the impact
# point over ~0.4s and pay them out as free catches when they arrive. Spear is
# not consumed for these — they're a free bonus on top of the regular catch.
func _trigger_black_hole(at: Vector2) -> void:
	var fish_nodes := get_tree().get_nodes_in_group("fish")
	var pulled: Array = []
	for n in fish_nodes:
		var f := n as Fish
		if f == null or not is_instance_valid(f) or f.speared:
			continue
		if f.size_class != Fish.SIZE_SMALL and f.size_class != Fish.SIZE_MEDIUM:
			continue
		f.speared = true  # locks out other interactions during the pull
		pulled.append(f)
	if pulled.is_empty():
		return
	var tween := get_tree().create_tween().set_parallel(true)
	for f in pulled:
		tween.tween_property(f, "global_position", at, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_finish_black_hole.bind(pulled, at))


func _finish_black_hole(pulled: Array, at: Vector2) -> void:
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	for f in pulled:
		if not is_instance_valid(f):
			continue
		var cash := int(round(f.get_cash_value()))
		var tag_mult: float = GameData.consume_fish_tag(f.get_instance_id())
		if tag_mult > 0.0:
			cash = int(round(cash * tag_mult))
		var result := GameData.register_hit(cash)
		GameData.add_dive_cash(result["value"])
		GameData.note_fish_caught(current_type_id, StringName(f.species), int(result["value"]))
		if hud and hud.has_method("spawn_cash_popup"):
			hud.spawn_cash_popup(result["value"], at, f.species)
		_spawn_hit_burst(at, f.color)
		f.queue_free()


# Heavy + small/medium target: destroy the fish, drop a small consolation
# cash popup, and keep the spear flying as long as the penetration cap allows.
# Penetration cap = penetration_depth + 1 (Lv 0 = 1 fish then reel; Lv 3 = 4).
func _heavy_destroy_small(f: Fish) -> void:
	var pen_levels: int = int(GameData.get_effective_spear_stat(current_type_id, "penetration_depth"))
	var pen_cap: int = pen_levels + 1
	var mini := int(round(f.get_cash_value() * 0.25))
	# Drop any tag the fish might have had — it's gone now, no future catch will
	# pay the bonus.
	GameData.consume_fish_tag(f.get_instance_id())
	if mini > 0:
		var result := GameData.register_hit(mini)
		GameData.add_dive_cash(result["value"])
		var hud = get_tree().current_scene.get_node_or_null("HUD")
		if hud and hud.has_method("spawn_cash_popup"):
			hud.spawn_cash_popup(result["value"], f.global_position, f.species)
	_spawn_hit_burst(f.global_position, f.color)
	f.queue_free()
	_hits_this_flight += 1
	if _hits_this_flight >= pen_cap:
		state = State.REELING_MISS
		monitoring = false
		_sync_hud()


func _handle_bounce(fish: Fish) -> void:
	# Bounce VFX — reuse hit_burst with a metallic tint so it reads differently.
	_spawn_hit_burst(global_position, Color(0.9, 0.95, 1.0))
	Sfx.bounce()
	if fish.has_method("on_bounce"):
		fish.on_bounce(self)
	# If the spear already had pierced catches on the line, don't drop them on
	# the bounce — reel everything home as a multi-catch instead.
	if not attached_fish_array.is_empty():
		state = State.NET_REELING
	else:
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
	_flight_time = 0.0
	attached_fish_array.clear()
	GameData.note_spear_fired(current_type_id)
	Sfx.fire()
	_sync_hud()
	queue_redraw()
	return true


func _effective_speed() -> float:
	return GameData.get_effective_spear_speed(current_type_id)


func _effective_reel_speed() -> float:
	return GameData.get_effective_reel_speed(current_type_id)


func _pierce_through(fish: Fish) -> void:
	# Pierce now hooks the fish onto the spear and drags it forward — when the
	# pierce cap is reached (or the spear runs out of distance), every speared
	# fish reels back together via the NET_REELING path. Earlier behaviour was
	# instant kills along the line, which felt like the fish disappeared.
	fish.on_speared(self)
	attached_fish_array.append(fish)
	_spawn_hit_burst(fish.global_position, fish.color)
	Sfx.hit()
	_hits_this_flight += 1
	var cap: int = int(GameData.get_effective_spear_stat(current_type_id, "pierce_count"))
	if _hits_this_flight >= cap:
		state = State.NET_REELING
		monitoring = false
		var main = get_tree().current_scene
		if main and main.has_method("hit_stop"):
			main.hit_stop()
		_sync_hud()


# Capacity slots a fish takes inside the net. Net is tuned around small schools
# — bigger fish "fill" the net much faster, so a single medium catch leaves
# little room for additional small companions. Big/defender targets use the
# whole net almost on their own.
#   SMALL  → 1 slot   (sardine, lanternfish, bonito)
#   MEDIUM → 5 slots  (grouper, jelly, squid, anglerfish, mahi, puffer)
#   LARGE / TROPHY → 10 slots ("defender type" — triggerfish, blockfish, etc.)
func _net_slot_cost(f: Fish) -> int:
	if f == null or not is_instance_valid(f):
		return 1
	match f.size_class:
		Fish.SIZE_MEDIUM:
			return 5
		Fish.SIZE_LARGE, Fish.SIZE_TROPHY:
			return 10
		_:
			return 1


# Effective net radius right now. While flying, the net unfurls from 0 to full
# over NET_GROW_TIME so close-range hits use a smaller catch zone.
func _net_current_radius() -> float:
	var full: float = GameData.get_effective_spear_stat(current_type_id, "net_radius")
	if current_type_id != &"net":
		return full
	if state != State.FLYING:
		return full
	var grow: float = clampf(_flight_time / NET_GROW_TIME, 0.0, 1.0)
	return full * grow


# Per-frame check while a Net spear is flying — finds the first fish inside
# the unfurled mesh radius and triggers a capture. Without this the player
# only catches fish that physically touch the tip's tiny collision shape;
# with it, anything the visible web touches gets netted.
func _net_zone_sweep() -> void:
	if state != State.FLYING:
		return
	var r: float = _net_current_radius()
	if r <= 4.0:
		return  # net hasn't unfurled yet — fall back to tip collision
	var r2: float = r * r
	var closest_fish: Fish = null
	var closest_d: float = INF
	for n in get_tree().get_nodes_in_group("fish"):
		var f := n as Fish
		if f == null or not is_instance_valid(f) or f.speared:
			continue
		var d: float = global_position.distance_squared_to(f.global_position)
		if d > r2:
			continue
		if d < closest_d:
			closest_d = d
			closest_fish = f
	if closest_fish == null:
		return
	# Defended fish still bounce on the trigger contact — Net respects defenses.
	if not (current_type and current_type.bypasses_defenses) \
			and closest_fish.has_method("deflects_spear") and closest_fish.deflects_spear(self):
		_handle_bounce(closest_fish)
		return
	if int(GameData.get_effective_spear_stat(&"net", "standing_wave")) >= 1:
		_net_start_standing_wave(closest_fish)
	else:
		_net_capture(closest_fish)


func _net_capture(first_fish: Fish) -> void:
	var radius: float = _net_current_radius()
	var max_catch: int = int(GameData.get_effective_spear_stat(current_type_id, "net_max_catch"))
	var allowed := current_type.catch_size_classes.duplicate()
	if int(GameData.get_effective_spear_stat(current_type_id, "catches_medium")) == 1 and not allowed.has(&"medium"):
		allowed.append(&"medium")
	var has_tagging: bool = int(GameData.get_effective_spear_stat(&"net", "tagging_net")) >= 1
	attached_fish_array.clear()
	var capacity_used: int = 0
	# Track every fish that was inside the radius — used by Tagging Net to mark
	# escapees (those skipped due to cap or size mismatch).
	var in_radius: Array = []
	if allowed.has(first_fish.size_class) and capacity_used + _net_slot_cost(first_fish) <= max_catch:
		first_fish.on_speared(self)
		attached_fish_array.append(first_fish)
		capacity_used += _net_slot_cost(first_fish)
		_spawn_hit_burst(first_fish.global_position, first_fish.color)
	in_radius.append(first_fish)
	var center := global_position
	var r2 := radius * radius
	var nearby = get_tree().get_nodes_in_group("fish")
	for n in nearby:
		if n == first_fish:
			continue
		var f := n as Fish
		if f == null or not is_instance_valid(f) or f.speared:
			continue
		if f.global_position.distance_squared_to(center) > r2:
			continue
		in_radius.append(f)
		if not allowed.has(f.size_class):
			continue
		var cost: int = _net_slot_cost(f)
		if capacity_used + cost > max_catch:
			continue  # not enough room — counts as escape for Tagging Net
		f.on_speared(self)
		attached_fish_array.append(f)
		capacity_used += cost
		_spawn_hit_burst(f.global_position, f.color)
	# Tag any in-radius fish we didn't actually capture. The award path consumes
	# the tag for a 2× payout when any spear catches them later in the dive.
	if has_tagging:
		for f in in_radius:
			if not is_instance_valid(f):
				continue
			if attached_fish_array.has(f):
				continue
			GameData.tag_fish(f.get_instance_id())
	state = State.NET_REELING
	monitoring = false
	_hits_this_flight = attached_fish_array.size()
	Sfx.net_catch()
	var main = get_tree().current_scene
	if main and main.has_method("hit_stop"):
		main.hit_stop()
	_sync_hud()


# Standing Wave (Net keystone): instead of instant-resolving the cast, the net
# hangs at the impact point for STANDING_WAVE_DURATION seconds. Per-frame sweep
# in _process_standing_wave captures any fish that drifts into the radius
# (subject to net_max_catch). When the timer expires or the cap is reached the
# spear transitions to NET_REELING and pays out normally.
func _net_start_standing_wave(first_fish: Fish) -> void:
	var max_catch: int = int(GameData.get_effective_spear_stat(current_type_id, "net_max_catch"))
	var allowed := current_type.catch_size_classes.duplicate()
	if int(GameData.get_effective_spear_stat(current_type_id, "catches_medium")) == 1 and not allowed.has(&"medium"):
		allowed.append(&"medium")
	attached_fish_array.clear()
	if allowed.has(first_fish.size_class) and _net_slot_cost(first_fish) <= max_catch:
		first_fish.on_speared(self)
		attached_fish_array.append(first_fish)
		_spawn_hit_burst(first_fish.global_position, first_fish.color)
	state = State.NET_STANDING_WAVE
	monitoring = false
	_standing_wave_remaining = STANDING_WAVE_DURATION
	_standing_wave_max_catch = max_catch
	_standing_wave_allowed = allowed
	flight_dir = Vector2.ZERO
	Sfx.net_catch()
	_sync_hud()


func _process_standing_wave(delta: float) -> void:
	_standing_wave_remaining -= delta
	var capacity_used: int = 0
	for f0 in attached_fish_array:
		capacity_used += _net_slot_cost(f0)
	if capacity_used < _standing_wave_max_catch:
		var radius: float = GameData.get_effective_spear_stat(current_type_id, "net_radius")
		var r2 := radius * radius
		for n in get_tree().get_nodes_in_group("fish"):
			if capacity_used >= _standing_wave_max_catch:
				break
			var f := n as Fish
			if f == null or not is_instance_valid(f) or f.speared:
				continue
			if not _standing_wave_allowed.has(f.size_class):
				continue
			if f.global_position.distance_squared_to(global_position) > r2:
				continue
			var cost: int = _net_slot_cost(f)
			if capacity_used + cost > _standing_wave_max_catch:
				continue
			f.on_speared(self)
			attached_fish_array.append(f)
			capacity_used += cost
			_spawn_hit_burst(f.global_position, f.color)
	if _standing_wave_remaining <= 0.0 or capacity_used >= _standing_wave_max_catch:
		state = State.NET_REELING
		_hits_this_flight = attached_fish_array.size()
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
	if state == State.FLYING or state == State.REELING_HIT or state == State.REELING_MISS or state == State.NET_REELING or state == State.NET_STANDING_WAVE:
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
			_flight_time += delta
			# Pierce-attached fish ride along on the spear tip while flying.
			if not attached_fish_array.is_empty():
				_position_net_fish(delta)
			# Net catch-zone sweep — any fish inside the *visible* mesh radius
			# triggers a capture, not just one touched by the spear tip. Keeps
			# the catch area honest with the drawn web.
			if current_type_id == &"net":
				_net_zone_sweep()
			if flight_distance_remaining <= 0.0 or _is_out_of_bounds():
				if not attached_fish_array.is_empty():
					# Out of distance with pierce-caught fish on the line —
					# reel them home as a multi-catch.
					state = State.NET_REELING
				else:
					state = State.REELING_MISS
					if _hits_this_flight == 0:
						GameData.register_miss()
						Sfx.miss()
				monitoring = false
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
		State.NET_STANDING_WAVE:
			# Trap hovers in place — no movement, just per-frame fish sweep.
			_line_time += delta
			_process_standing_wave(delta)
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


func _award_fish(fish: Fish, extra_mult: float = 1.0) -> void:
	var base := fish.get_cash_value()
	# Apply per-type value bonus (universal stat ramp on every spear).
	var bonus: float = 1.0
	if current_type:
		bonus = GameData.get_effective_spear_stat(current_type_id, "value_bonus")
	base = int(round(base * bonus))
	# Bullseye (Normal): center-of-radius hits add a multiplier.
	base = int(round(base * _value_multiplier(fish)))
	# Tagging Net (Net keystone): a previously-tagged fish caught by any spear
	# pays its tag bonus on top of everything else. Consume the tag on award.
	var tag_mult: float = GameData.consume_fish_tag(fish.get_instance_id())
	if tag_mult > 0.0:
		base = int(round(base * tag_mult))
	# Schooling Bonus (Net keystone): caller passes 2.0 when ≥5 fish landed in a single net cast.
	if extra_mult != 1.0:
		base = int(round(base * extra_mult))
	var result := GameData.register_hit(base)
	var arrive_pos := fish.global_position
	var species := fish.species
	# Trophy hook — emits whitewhale_caught_signal on first catch (consumed by ending screen).
	if fish.size_class == Fish.SIZE_TROPHY:
		GameData.note_trophy_caught(StringName(species))
	GameData.add_dive_cash(result["value"])
	GameData.note_fish_caught(current_type_id, StringName(species), int(result["value"]))
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
		# Schooling Bonus (Net keystone): 5+ fish in one cast → each pays 2×.
		var sb: int = int(GameData.get_effective_spear_stat(&"net", "schooling_bonus"))
		var school_mult: float = 2.0 if (sb >= 1 and attached_fish_array.size() >= 5) else 1.0
		for f in attached_fish_array:
			if is_instance_valid(f):
				_award_fish(f, school_mult)
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
	# Pixel-art silhouette per spear type — texture rect anchored centered for
	# now so the asset extends evenly fore/aft of the pivot. If rotation reads
	# poorly in playtest, shift the rect's x offset to weight the pivot toward
	# the back of the spear.
	var tex: Texture2D = null
	match current_type_id:
		&"net":
			tex = NetSpearTexture
		&"heavy":
			tex = HeavySpearTexture
		&"normal":
			tex = NormalSpearTexture
		_:
			tex = null
	if tex != null:
		var tex_size := tex.get_size()
		var aspect: float = tex_size.y / tex_size.x
		var draw_w: float = SPEAR_DRAW_LENGTH
		var draw_h: float = draw_w * aspect
		var rect := Rect2(-draw_w * 0.5, -draw_h * 0.5, draw_w, draw_h)
		draw_texture_rect(tex, rect, false)
	# Net mesh — polar grid with concentric rings + radial spokes so the AoE
	# reads as a "web" rather than a thin hoop. While flying, the radius
	# unfurls from 0 to the upgraded full size over NET_GROW_TIME.
	if current_type_id == &"net" and (state == State.FLYING or state == State.NET_STANDING_WAVE):
		var hoop_color := current_type.color if current_type else Color(0.5, 0.85, 1.0)
		var r: float = _net_current_radius()
		var hoop_center := Vector2(SPEAR_DRAW_LENGTH * 0.5, 0.0)
		if r > 1.0:
			var col_rim := Color(hoop_color.r, hoop_color.g, hoop_color.b, 0.55)
			var col_inner := Color(hoop_color.r, hoop_color.g, hoop_color.b, 0.28)
			var col_thread := Color(hoop_color.r, hoop_color.g, hoop_color.b, 0.22)
			# Inner mesh rings (3 concentric).
			for k in 3:
				var rr: float = r * (0.35 + 0.27 * k)
				draw_arc(hoop_center, rr, 0.0, TAU, 24, col_inner, 1.0, true)
			# Outer rim — thicker, brighter so the catch boundary is unambiguous.
			draw_arc(hoop_center, r, 0.0, TAU, 36, col_rim, 2.0, true)
			# 12 radial threads from center to rim.
			for i in 12:
				var a := float(i) / 12.0 * TAU
				var p := Vector2(cos(a), sin(a)) * r
				draw_line(hoop_center, hoop_center + p, col_thread, 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _value_multiplier(fish: Node2D) -> float:
	# Bullseye (Normal): center-of-radius hits add `bullseye_bonus` to the value
	# multiplier — base property is 0.0; each upgrade level adds 0.5, so Lv 1
	# pays 1.5×, Lv 2 pays 2×, Lv 3 pays 2.5×.
	if current_type_id == &"":
		return 1.0
	var bullseye_eff: float = GameData.get_effective_spear_stat(current_type_id, "bullseye_bonus")
	if bullseye_eff > 0.0 and _is_dead_center_hit(fish):
		return 1.0 + bullseye_eff
	return 1.0


func _is_dead_center_hit(fish: Node2D) -> bool:
	if fish == null or not is_instance_valid(fish):
		return false
	var d := global_position.distance_to(fish.global_position)
	return d <= fish.hit_radius * 0.25
