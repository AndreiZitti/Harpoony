# Spear Types & Bag System — Design

Date: 2026-04-25

## Overview

Adds a multi-type spear system with per-type ammo stocks, per-type upgrades, and a pre-dive bag loadout that shuffles into a firing queue.

Three initial types: **Normal**, **Piercing**, **Net**.

## Data Model

### `SpearType` Resource (`scripts/spear_type.gd`)

One `.tres` per type in `data/spears/`:

- `id: StringName` — `&"normal"`, `&"pierce"`, `&"net"`
- `display_name: String`, `description: String`
- `color: Color`
- `unlock_cost: int` (0 for normal)
- `ammo_buy_cost: int` — per-spear ammo price
- Behavior knobs (typed fields, used per kind):
  - `pierce_count: int` (pierce only)
  - `net_radius: float`, `net_max_catch: int` (net only)
  - `value_bonus: float` (normal)
  - `speed_mult: float` (all)
  - `hit_radius_bonus: float` (all)
- `upgrades: Dictionary` — same shape as `GameData.upgrades`, but the keys are the field names being leveled (e.g. `"pierce_count"`, `"net_radius"`).

### `GameData` additions

```
spear_types: Array[SpearType]
unlocked_spear_types: Array[StringName]   # [&"normal"] initially
spear_ammo: Dictionary                    # { id: int }
spear_upgrade_levels: Dictionary          # { id: { upgrade_key: level } }
bag_loadout: Dictionary                   # { id: int_in_bag }
bag_queue: Array[StringName]              # built at dive start
bag_index: int
```

Existing change:

- Rename `upgrade_levels["spears"]` → `upgrade_levels["spear_slots"]`. Same 1→3 progression. Renames the upgrade UI label too.
- New upgrade key `"spear_bag"` — capacity 5 → 20 (5 levels).

### Pierce ability migration

`pierce` ability stops being read by `spear.gd`. Behavior moves into the pierce SpearType. Keep the ability resource on disk (no save migration needed) but remove its UI affordance from the abilities row, or leave equippable but inert. Simplest: remove it from `ABILITY_PATHS`.

## Bag Mechanics

### Pre-dive

`BagLoadoutPanel` (new) on the boat scene next to the depth lever. For each unlocked type:
- Icon (color square), name
- Owned ammo count
- `−` / `+` selector for "in bag" amount, capped by `min(owned, capacity_remaining)`
- Live readout: `loaded / capacity`

Persists in `GameData.bag_loadout` between dives. "Fill" button auto-fills greedily.

### Dive start

`GameData.start_dive()`:

1. Build `bag_queue` by expanding `bag_loadout` to a flat `Array[StringName]`.
2. `bag_queue.shuffle()`.
3. `bag_index = 0`.
4. If `bag_queue.is_empty()`, fall back to a single `&"normal"` so the dive isn't bricked.

### During dive

Each `Spear` slot is type-agnostic. When it transitions to `READY` (initial spawn or post-recall), it calls `GameData.draw_next_spear_type()`:

- Returns `bag_queue[bag_index]`.
- Increments `bag_index`. If past end: shuffle, reset to 0.

The slot then sets `current_type` and updates its visuals/behavior.

### Dive end

`finish_dive()` clears `bag_queue` and `bag_index`. `bag_loadout` persists.

## Spear Type Behaviors

All share fly → reel state machine. Branch at hit time on `current_type`.

### Normal
Unchanged from current `attach_to_fish` flow. `value_bonus` applied via a multiplier in `register_hit` if the hit came from a normal-type spear.

### Piercing
Replaces `pierce` ability. On `_on_area_entered`:
- Award cash inline (current `_pierce_through` logic).
- Stay in `FLYING`.
- Stop when `_hits_this_flight >= effective_pierce_count` or distance exhausted.

`effective_pierce_count = base_pierce_count + level_bonus`.

### Net
New state `State.NET_REELING`. New field `attached_fish_array: Array[Fish]`.

On first `_on_area_entered` with a fish:
1. Build a temporary `Area2D` query at hit position with `CircleShape2D(net_radius)`. Use `get_tree().get_nodes_in_group("fish")` and a distance check (simpler than spinning up a transient Area2D and waiting a physics frame).
2. Take up to `net_max_catch` not-already-speared fish, mark each with `on_speared(self)` and add to array.
3. Transition to `NET_REELING`.

During `NET_REELING`:
- Reel position toward diver at `reel_speed`.
- Each caught fish positions in a small fan around the spear tip (e.g. `Vector2.from_angle(i * TAU / N) * 12`).

On arrive:
- For each caught fish, `register_hit(fish.get_cash_value())`, spawn cash popup, free.

### Drawing
Per-type tint from `SpearType.color`. Net additionally draws a hoop (circle outline) at the tip during flight.

## Shop UI

`upgrade_shop.gd` gets a new "Spears" section split into per-type cards:

For each unlocked type:
- Header: icon, name, "Owned: N"
- "Buy 5 ammo — $X" button
- Per-type stat upgrade rows (read from `SpearType.upgrades`)

Locked types render as a single "Unlock <name> — $X" row.

A "Bag" sub-section above per-type cards:
- `Spear Slots` upgrade (renamed from `spears`)
- `Bag Capacity` upgrade (new)

## Signals

New on `GameData`:
- `spear_type_unlocked(id: StringName)`
- `spear_ammo_changed(id: StringName, amount: int)`
- `bag_loadout_changed`
- `spear_upgrade_changed(id: StringName, key: String, level: int)`

## Build Sequence

1. `SpearType` resource class + three `.tres` files.
2. `GameData` data fields, signals, helper methods (`get_effective_speed`, `get_effective_hit_radius`, `draw_next_spear_type`, ammo/upgrade buy methods, `unlock_spear_type`).
3. Rename `spears` → `spear_slots`. Add `spear_bag` upgrade.
4. `Spear` script: per-type branching for normal/pierce/net, color/tint, drawing.
5. `BagLoadoutPanel` scene + script on the boat.
6. Shop UI: per-type cards.
7. Remove pierce ability wiring (drop from `ABILITY_PATHS`).
8. Manual test: each type fires, reshuffle works, bag fills correctly.
