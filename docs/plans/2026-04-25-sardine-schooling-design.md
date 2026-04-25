# Sardine Schooling AI — Design

**Date:** 2026-04-25
**Scope:** Replace lone-sardine spawns with cohesive schools (4–10 fish) that swim together, panic when one is speared, and regroup.
**Affected species:** Sardine only. Grouper and tuna behavior unchanged.

## Goal

Sardines today share the same AI as every other fish: constant horizontal velocity + sine wiggle, no reaction to the player. Give them a unique behavior that plays into their stats (low value, fast, plentiful): they swim in **schools**, and when the player spears one, the rest **panic-scatter** before **regrouping**.

## Design decisions (locked)

| Question | Decision |
|---|---|
| School size | Variable per spawn, random in **4–10** |
| Spawn rule | **All** sardine spawns become schools — no more lone sardines |
| Panic trigger | **Confirmed hit only** (not spear-in-water, not proximity) |
| Scatter response | **Burst outward, then regroup** after ~1s |
| Formation | **Loose blob** — random offsets within a school radius |
| Leader | **Virtual point** (math-only) — all visible sardines are equal followers |

## Architecture

A new `FishSchool` node acts as a lightweight conductor. It owns no rendering and is not itself speared. It holds:

- `leader_pos: Vector2` — virtual point advancing along a sine path (the same math today's solo sardine uses)
- `followers: Array[Fish]` — the actual sardine nodes (4–10 of them)
- `state: NORMAL | PANIC | REGROUP` + `state_timer: float`
- `panic_origin: Vector2` — recorded at the moment of a confirmed hit

Each follower has two new fields: `school: FishSchool` (back-reference) and `slot_offset: Vector2` (a random point in a disc of radius `SCHOOL_RADIUS`). When `school != null`, the fish bypasses its standalone wave-swim and instead steers toward `school.leader_pos + slot_offset`.

The school despawns when its follower list is empty (all speared or all walked off-screen). Followers despawn individually on the existing screen-margin check; they notify the school via `tree_exited` so it can erase them from its list.

The leader is virtual on purpose. The "leader gets killed" problem disappears — there's nothing to kill. The school as a whole swims like one big invisible sardine, with members orbiting that path.

## Per-fish steering

When `school != null`, the fish runs:

```
target = school.leader_pos + slot_offset
to_target = target - global_position
velocity = velocity.lerp(to_target * STEER_GAIN, STEER_SMOOTH * delta)
global_position += velocity * delta
```

- `STEER_GAIN ≈ 2.5`, `STEER_SMOOTH ≈ 6.0` → loose, breathing blob (not a rigid formation)
- Existing tail-beat wiggle in `_draw()` (driven by `age * wave_frequency`) keeps each sardine flickering individually
- Every `OFFSET_JITTER_INTERVAL` seconds (~2s), each follower re-rolls its `slot_offset` within the school radius. The blob shape evolves over time instead of looking stamped.

The school's leader advances using the existing solo-sardine path math:

```
leader_pos.x += direction * speed * delta
leader_pos.y = base_y + sin(age * wave_frequency + wave_phase) * wave_amplitude
```

Speed is the existing sardine speed (160 px/s).

## States: NORMAL → PANIC → REGROUP → NORMAL

**Trigger.** `Fish.on_speared()` notifies its school via `school._on_member_speared(hit_pos)`. The school:

1. Records `panic_origin = hit_pos`
2. Sets `state = PANIC`, `state_timer = PANIC_DURATION` (~0.6s)
3. Removes the speared fish from `followers`

**PANIC.** Followers ignore the leader. Each follower:

```
flee_dir = (self.position - panic_origin).normalized()
velocity = velocity.lerp(flee_dir * PANIC_SPEED, PANIC_STEER * delta)
```

`PANIC_SPEED ≈ 320` (2× normal), `PANIC_STEER ≈ 8.0` → sharp radial fan-out.

**REGROUP.** When `state_timer` hits 0, switch to `REGROUP` with `state_timer = REGROUP_DURATION` (~0.4s). Followers steer toward `leader_pos + slot_offset` with stronger gain (`STEER_GAIN * 1.5`) so they pull back into formation quickly without snapping.

**Back to NORMAL.** Total disruption window ~1s.

**Chained hits.** If a sardine is speared during PANIC or REGROUP, reset `state = PANIC`, refresh `panic_origin` and `state_timer`. The school stays jittery as long as the player keeps shooting.

**Leader continuity.** During PANIC and REGROUP, the leader's path keeps advancing in the background. The school regroups onto a position reflecting time spent panicking — natural, no rubber-band back.

## Files

**New:** `scripts/fish_school.gd` (~80–100 lines)

- `class_name FishSchool extends Node2D`
- Methods: `setup(start_pos, direction_right, count)`, `_process(delta)`, `_on_member_speared(hit_pos)`, `_advance_leader(delta)`, `_update_state(delta)`
- On `setup()`, spawns N `Fish` instances as siblings under `current_scene` (so spear group queries find them) and sets each fish's `school` and `slot_offset`.

**Modified:** `scripts/fish.gd`

- Add: `school: FishSchool = null`, `slot_offset: Vector2 = Vector2.ZERO`, `_offset_jitter_timer: float`
- `_process(delta)`: if `school != null`, run schooling steering and skip the existing wave-swim block. Otherwise, current behavior unchanged (preserves the option to revert any species to solo).
- Connect `tree_exited` so school auto-removes despawned/speared followers from its list.
- `on_speared()` calls `school._on_member_speared(global_position)` if school is set.

**Modified:** `scripts/fish_spawner.gd` (around [scripts/fish_spawner.gd:32](scripts/fish_spawner.gd#L32))

- Preload the school script (or scene)
- In `_spawn_one()`: if rolled species is `"sardine"`, instantiate a `FishSchool` and call `school.setup(spawn_pos, !from_right, randi_range(4, 10))`. Otherwise unchanged.

**Untouched:** `spear.gd`, `hud.gd`, zone configs, `GameData`. The school is invisible to all of them — only individual `Fish` interact with the spear.

## Constants (top of `fish_school.gd`)

```gdscript
const SCHOOL_RADIUS = 40.0
const PANIC_DURATION = 0.6
const REGROUP_DURATION = 0.4
const PANIC_SPEED = 320.0
const PANIC_STEER = 8.0
const STEER_GAIN = 2.5
const STEER_SMOOTH = 6.0
const OFFSET_JITTER_INTERVAL = 2.0
```

These are starting values — expect to tune `STEER_GAIN`, `STEER_SMOOTH`, and `SCHOOL_RADIUS` once playing.

## Out of scope (intentional)

- **Boid steering** (separation/alignment forces between followers). The loose-blob model with random offsets is enough for the visual; full boid math can come later if needed.
- **Inter-school avoidance.** Two schools overlapping is fine for now.
- **Other species schooling.** Grouper and tuna stay solo.
- **Predator/prey** between sardine schools and tuna. Could be a follow-up.
- **Spear changes.** The existing `pierce` ability already rewards tight schools — no spear work needed.

## Open tuning questions

- Does 4–10 with `SCHOOL_RADIUS = 40` feel crowded or sparse on screen?
- Is 0.6s panic + 0.4s regroup the right total window, or should it be longer to let the player follow up?
- Should the school's `wave_amplitude` be larger than a solo sardine's so the school visibly arcs across the screen?

These are best answered by playing the implemented version, not by argument.
