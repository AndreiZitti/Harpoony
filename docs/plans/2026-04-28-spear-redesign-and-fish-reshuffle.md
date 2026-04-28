# Spear Upgrade Redesign + Fish Roster Reshuffle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current flat per-spear stat ramps with the locked 3-layer design (base behavior → stat ramps → keystones), implement Heavy/Net keystones as new code paths, and reshuffle zone rosters to activate the 3 orphaned species.

**Architecture:** Each spear gets a layered upgrade pool: cheap multi-level "ramp" upgrades for the long tail, plus binary "keystone" upgrades that flip game rules. Keystones are stored as level-1 upgrades with a `keystone: true` flag so existing `buy_spear_upgrade()` / `get_spear_upgrade_level()` flow handles them unchanged. Heavy gains an always-on defense-bypass (the `bypasses_defenses` field on its `SpearType` resource is already true) and a new "destroys small/medium" base behavior on impact. Three new keystone-driven runtime systems are added: a screen-wide pull (Black Hole Tip), a 10s defense-disable flag on `GameData` consulted by `Fish.deflects_spear()` (Seismic Roar), a guaranteed-trophy hint on `FishSpawner` + a HUD marker (Whale-Finder Sonar), a timed trap area for nets (Standing Wave), an escape-tag system that survives across spears (Tagging Net), and a per-cast bonus for ≥5-fish hauls (Schooling Bonus). Zone `.tres` files are updated to reshuffle species (3 orphans activated, Pufferfish trimmed from Reef + Kelp). Old branched-ladder UI scaffolding (`scripts/skill_tree_view.gd`, `TREE_NODE_SIZE` constants in `upgrade_shop.gd`) is removed and replaced with a flat-but-grouped layout: ramps stacked on the card, keystones below as bigger tiles.

**Tech Stack:** Godot 4.x · GDScript (no C#) · `.tres` resources for data · existing `GameData` autoload for state · existing `Fish` / `Spear` / `FishSpawner` scenes.

---

## Pre-flight

Current uncommitted state on `main`:
- `data/spears/{normal,heavy,net}.tres` — partially updated with old `tier:`/`parents:` fields from the aborted branched-ladder design. We will rewrite cleanly, dropping `tier`/`parents`, adding `keystone: true` flag.
- `scripts/skill_tree_view.gd` (+ `.uid`) — old connector drawer for branched-ladder. Will be deleted.
- `scripts/upgrade_shop.gd` — has `TREE_NODE_SIZE` / `TREE_SLOT_POS` / `TREE_EDGES` constants for the aborted shape. Will be cleaned in Phase 5.
- `docs/plans/2026-04-26-loadout-skill-tree-design.md` — leave in place; this new plan supersedes it but the historical context stays.

We will commit phase by phase. Phase 1 (pure data) lands a coherent first commit so a partial implementation always boots.

---

## Phase 1: Data foundation (safe, no behavior change)

Goal: Lock the upgrade catalog and zone rosters in `.tres` files. After this phase the *data* is correct but new behaviors haven't been wired up yet — the existing engine consumes the new entries gracefully because each one uses an existing `field:` that already feeds `get_effective_spear_stat()` (or a new field that just defaults to 0 until Phase 2-4).

### Task 1.1: Rewrite `data/spears/normal.tres`

**Files:**
- Modify: `data/spears/normal.tres`

**Final upgrades dict (no `tier`, no `parents`, add `keystone: false` to all — Normal has no keystones):**

```gdscript
upgrades = {
"speed_mult": {
    "name": "Quick Reel",
    "description": "+10% cast & reel speed per level.",
    "icon": "≣",
    "max_level": 5,
    "costs": [30, 80, 200, 500, 1200],
    "field": "speed_mult",
    "step": 0.1,
    "keystone": false
},
"hit_radius_bonus": {
    "name": "Wider Tip",
    "description": "+6 hit radius per level.",
    "icon": "◎",
    "max_level": 5,
    "costs": [40, 120, 300, 800, 1800],
    "field": "hit_radius_bonus",
    "step": 6.0,
    "keystone": false
},
"value_bonus": {
    "name": "Polished Tip",
    "description": "+15% cash per hit, per level.",
    "icon": "✱",
    "max_level": 5,
    "costs": [60, 180, 450, 1100, 2500],
    "field": "value_bonus",
    "step": 0.15,
    "keystone": false
},
"pierce_count": {
    "name": "Piercing Tip",
    "description": "+1 fish pierced per shot, per level (1 → 4).",
    "icon": "✦",
    "max_level": 3,
    "costs": [200, 600, 1500],
    "field": "pierce_count",
    "step": 1,
    "keystone": false
},
"bullseye_bonus": {
    "name": "Bullseye",
    "description": "Center-of-radius hit bonus 1.5× → 2× → 2.5×.",
    "icon": "◉",
    "max_level": 3,
    "costs": [250, 700, 1800],
    "field": "bullseye_bonus",
    "step": 0.5,
    "keystone": false
}
}
```

Also drop `reel_speed_mult` from the upgrades dict (folded into `speed_mult` per the locked design — speed unification). The `reel_speed_mult` *property* on `SpearType` will be left set to 1.0 in the resource (no upgrade points at it any more). The existing reel reading paths still use `speed_mult` separately to compute actual reel speed in code — see Phase 2.

**Verification:** Open the project in Godot; the resource should still load with no parser errors. Existing playthroughs may have stored levels for `reel_speed_mult` in `spear_upgrade_levels`; those become inert (no upgrade key references the field) — acceptable for in-development saves. No tests yet; defer manual play to Phase 2.

**Commit:** `feat(data): rewrite normal spear upgrade catalog (ramps + bullseye)`

### Task 1.2: Rewrite `data/spears/heavy.tres`

**Files:**
- Modify: `data/spears/heavy.tres`

**Heavy stays defense-ignoring (`bypasses_defenses = true` is already set on the resource — verify). Dropping the standalone `crit_chance` upgrade (defense-bypass made it redundant). Adding `penetration_depth` ramp:**

```gdscript
upgrades = {
"speed_mult": {
    "name": "Quick Reel",
    "description": "+10% cast & reel speed per level.",
    "icon": "≣",
    "max_level": 5,
    "costs": [80, 200, 500, 1200, 2800],
    "field": "speed_mult",
    "step": 0.1,
    "keystone": false
},
"hit_radius_bonus": {
    "name": "Sharper Head",
    "description": "+5 hit radius per level.",
    "icon": "◎",
    "max_level": 5,
    "costs": [70, 180, 450, 1000, 2400],
    "field": "hit_radius_bonus",
    "step": 5.0,
    "keystone": false
},
"value_bonus": {
    "name": "Trophy Bonus",
    "description": "+15% cash per catch, per level.",
    "icon": "✱",
    "max_level": 5,
    "costs": [200, 500, 1200, 2800, 6000],
    "field": "value_bonus",
    "step": 0.15,
    "keystone": false
},
"penetration_depth": {
    "name": "Penetration",
    "description": "Pass through 2 → 3 → 4 small/medium fish to reach a large target. Each destroyed fish drops mini-cash.",
    "icon": "↠",
    "max_level": 3,
    "costs": [400, 1000, 2400],
    "field": "penetration_depth",
    "step": 1,
    "keystone": false
},
"black_hole_tip": {
    "name": "Black Hole Tip",
    "description": "Impact pulls all small/medium fish toward the hit point and insta-catches them.",
    "icon": "●",
    "max_level": 1,
    "costs": [3500],
    "field": "black_hole_tip",
    "step": 1,
    "keystone": true
},
"seismic_roar": {
    "name": "Seismic Roar",
    "description": "Hit disables all defended fish defenses for 10 seconds.",
    "icon": "≋",
    "max_level": 1,
    "costs": [3000],
    "field": "seismic_roar",
    "step": 1,
    "keystone": true
},
"whale_sonar": {
    "name": "Whale Sonar",
    "description": "Each dive spawns a guaranteed trophy fish marked on the HUD.",
    "icon": "✺",
    "max_level": 1,
    "costs": [4500],
    "field": "whale_sonar",
    "step": 1,
    "keystone": true
}
}
```

Also remove `pierce_count`, `crit_chance`, `sonic_boom` upgrade entries from the dict — Heavy doesn't use them in the new design. Leave the `pierce_count: 1` *property* on the resource so `spear.gd` doesn't divide by zero or break the pierce-through path; `_pierce_through` only triggers when effective pierce > 1, which won't happen for Heavy now.

Also extend `scripts/spear_type.gd`'s `@export_group("Behavior — Pierce")` to include `penetration_depth: int = 0`, `black_hole_tip: int = 0`, `seismic_roar: int = 0`, `whale_sonar: int = 0` — these need to exist as properties for `get_effective_spear_stat()` to find them.

**Verification:** Resource loads, project runs, Heavy spear still fires (because in Phase 1 the behavior code is unchanged — Heavy is still using the *old* `crit_chance` path, which has been removed from the upgrades dict so it just always returns 0 → no crits any more, no regression).

**Commit:** `feat(data): rewrite heavy spear upgrade catalog (ramps + 3 keystones)`

### Task 1.3: Rewrite `data/spears/net.tres`

**Files:**
- Modify: `data/spears/net.tres`
- Modify: `scripts/spear_type.gd` (add new field properties: `lure_pulse: int = 0`, `standing_wave: int = 0`, `tagging_net: int = 0`, `schooling_bonus: int = 0`)

**Final upgrades dict:**

```gdscript
upgrades = {
"speed_mult": {
    "name": "Quick Cast",
    "description": "+10% cast & reel speed per level.",
    "icon": "≣",
    "max_level": 5,
    "costs": [60, 160, 400, 1000, 2400],
    "field": "speed_mult",
    "step": 0.1,
    "keystone": false
},
"net_radius": {
    "name": "Wider Hoop",
    "description": "+12 net radius per level.",
    "icon": "○",
    "max_level": 5,
    "costs": [80, 200, 500, 1200, 2500],
    "field": "net_radius",
    "step": 12.0,
    "keystone": false
},
"value_bonus": {
    "name": "Trophy Bonus",
    "description": "+15% cash per net cast, per level.",
    "icon": "✱",
    "max_level": 5,
    "costs": [180, 450, 1100, 2400, 5200],
    "field": "value_bonus",
    "step": 0.15,
    "keystone": false
},
"net_max_catch": {
    "name": "Wider Mesh",
    "description": "+1 fish caught per cast, per level.",
    "icon": "⊞",
    "max_level": 5,
    "costs": [150, 400, 1000, 2200, 4800],
    "field": "net_max_catch",
    "step": 1,
    "keystone": false
},
"lure_pulse": {
    "name": "Lure Pulse",
    "description": "After cast, the net pulls small fish toward center for 1s. Each level extends pull radius.",
    "icon": "❀",
    "max_level": 3,
    "costs": [300, 800, 2000],
    "field": "lure_pulse",
    "step": 1,
    "keystone": false
},
"standing_wave": {
    "name": "Standing Wave",
    "description": "Net stays open for 3 seconds. Anything passing through is caught (subject to max-catch).",
    "icon": "≈",
    "max_level": 1,
    "costs": [3000],
    "field": "standing_wave",
    "step": 1,
    "keystone": true
},
"tagging_net": {
    "name": "Tagging Net",
    "description": "Fish that escape the net are marked. Any spear that catches a marked fish later earns 2× cash.",
    "icon": "⌖",
    "max_level": 1,
    "costs": [2500],
    "field": "tagging_net",
    "step": 1,
    "keystone": true
},
"schooling_bonus": {
    "name": "Schooling Bonus",
    "description": "If 5+ fish are caught in a single cast, each is worth 2× cash.",
    "icon": "❉",
    "max_level": 1,
    "costs": [3500],
    "field": "schooling_bonus",
    "step": 1,
    "keystone": true
}
}
```

Drop `catches_medium` (replaced by Schooling Bonus / Standing Wave as Net's late-game) and `lure_net` (replaced by Lure Pulse, which has level steps).

**Verification:** Game loads, Net still casts and catches at base.

**Commit:** `feat(data): rewrite net spear upgrade catalog (ramps + 3 keystones)`

### Task 1.4: Activate orphan species, reshuffle zones

**Files:**
- Modify: `data/zones/01_reef.tres` — add `squid: 0.15`; reduce `pufferfish: 0.10`; resulting weights: `sardine: 0.50, grouper: 0.25, pufferfish: 0.10, squid: 0.15`
- Modify: `data/zones/02_kelp.tres` — drop `pufferfish`; rebalance to `sardine: 0.25, bonito: 0.20, blockfish: 0.25, grouper: 0.30`
- Modify: `data/zones/03_open_blue.tres` — keep current 5 species, drop nothing. (Heavy's natural zone — Pufferfish stays here.)
- Modify: `data/zones/04_abyss.tres` — drop `tuna`, `jellyfish`, `pufferfish`; add `anglerfish: 0.20, lanternfish: 0.30`; resulting `lanternfish: 0.30, anglerfish: 0.20, triggerfish: 0.20, marlin: 0.20, whitewhale: 0.10`

**Verification:** Dive into each zone in dev mode; confirm new species spawn and old ones don't appear in Reef/Kelp/Abyss as expected. (Spawn weighting is probabilistic; a few dives may need more than one attempt to see all species.)

**Commit:** `feat(data): reshuffle zones — activate squid/anglerfish/lanternfish, trim pufferfish`

---

## Phase 2: Spear base behavior (foundation for keystones)

Goal: Lock in the new "always-on" behaviors that don't require keystone purchases — Heavy destroys small/medium on impact (with Penetration Depth ramp); Normal applies bullseye bonus on center hits.

### Task 2.1: Heavy "destroys small/medium" base behavior

**Files:**
- Modify: `scripts/spear.gd` — at the top of `_on_area_entered`, before the deflection branch, add a Heavy-specific filter.

**Code (insert after the `var f := area as Fish; if f.speared: return` block, around line 78):**

```gdscript
# Heavy spear: destroys small/medium on impact (no catch, no cash, fish despawns).
# Heavy's role is the trophy/large/defended-fish specialist — sacrifice baked in.
if current_type_id == &"heavy" and (f.size_class == Fish.SIZE_SMALL or f.size_class == Fish.SIZE_MEDIUM):
    _heavy_destroy_small(f)
    return
```

**New helper function (anywhere in `spear.gd`):**

```gdscript
func _heavy_destroy_small(f: Fish) -> void:
    # Mini-cash consolation: 25% of the fish's base value, capped at the
    # remaining penetration count. Penetration ramp lets Heavy plough through
    # 2 → 3 → 4 small/medium fish before returning to reel.
    var pen_cap: int = int(GameData.get_effective_spear_stat(current_type_id, "penetration_depth")) + 1
    # +1 because penetration_depth=0 means "destroy 1 then reel" (the natural
    # heavy-vs-small case). Each level adds one extra pass-through.
    var cash := int(round(f.get_cash_value() * 0.25))
    var result := GameData.register_hit(cash)
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
```

**Verification:**
- Open Godot, dive in Reef
- Fire Heavy at a Sardine — it should despawn, you get a small cash popup, the spear continues forward
- Fire Heavy at a Grouper (medium) — same
- Fire Heavy at a Pufferfish (medium, defended) — destroys (medium-class wins over the defense check; defended just means deflect, but Heavy's destroy filter runs first)
- Fire Heavy at the White Whale — passes the size filter, attaches normally
- Buy Penetration Lv1 — Heavy now plows through 2 small fish in one shot before reeling

**Commit:** `feat(heavy): always-destroy small/medium with penetration depth ramp`

### Task 2.2: Bullseye bonus on Normal

**Files:**
- Modify: `scripts/spear.gd` — `_award_fish` (around line 325) and `_pierce_through` (around line 142)

**Replace the `_crit_multiplier` body (line 445) with a more general `_value_multiplier`** that incorporates Bullseye for Normal and keeps the dead-center detection:

```gdscript
func _value_multiplier(fish: Node2D) -> float:
    if current_type_id == &"":
        return 1.0
    # Bullseye (Normal): center-of-radius hit pays bonus_per_level (cumulative).
    var bullseye_levels: float = GameData.get_effective_spear_stat(current_type_id, "bullseye_bonus")
    if bullseye_levels > 0.0 and _is_dead_center_hit(fish):
        # bullseye_bonus property starts at 1.0; each level adds 0.5 → 1.5×, 2×, 2.5×.
        return 1.0 + bullseye_levels
    return 1.0
```

Update both call sites (`_pierce_through` and `_award_fish`) to call `_value_multiplier` instead of `_crit_multiplier`. Delete the old `_crit_multiplier` and `_is_dead_center_hit` stays.

**Set base `bullseye_bonus = 0.0`** on `SpearType` so unupgraded Normal gets no bonus. Already declared in Task 1.3's spear_type.gd extension.

**Verification:**
- Fire a Normal spear directly through the dead-center of a Grouper — should pay normal cash (no bullseye yet)
- Buy Bullseye Lv1 — same shot now pays 1.5× (cash popup shows higher number)
- Buy Lv2 — 2× ; Lv3 — 2.5×
- Off-center hits still pay 1×

**Commit:** `feat(normal): bullseye center-hit cash multiplier`

### Task 2.3: Verify Heavy bypass remains correct

**Files:** `scripts/spear.gd` — already does `current_type.bypasses_defenses` check. Ensure `data/spears/heavy.tres` has `bypasses_defenses = true` set on the resource itself (check the file). If not, set it.

**Verification:** Heavy fired into an inflated Pufferfish goes through and destroys it (small-medium destroy path). Heavy into a Triggerfish from the front: the destroy path runs because Triggerfish is `large`-class — wait, Triggerfish is large per its species data, so destroy doesn't fire. The bypass check fires next, and Heavy bypasses → attach. Confirm. (If Triggerfish is medium, the destroy branch wins, meaning Heavy can't catch armored medium fish — undesirable. We want Heavy to KEEP catching Triggerfish/Blockfish/etc. Let me check.)

Looking at the species: `triggerfish.size_class = "large"`, `blockfish.size_class = "large"`, `pufferfish = "medium"`. Pufferfish defended + medium → Heavy destroys it (no catch). That's actually fine — Heavy isn't meant to catch Pufferfish, that's Net (after Bigger Hoop) or Normal's job. Let me confirm with the user this is the intended outcome — Heavy can't catch Pufferfish.

If we want Heavy to ALSO catch defended-mediums (Pufferfish), we add a second branch: defended-medium fish escape the destroy filter. But that complicates the rule. For v1, simplest: Heavy destroys all small/medium regardless of defense; player uses Normal/Net for those.

**No commit if no change.**

---

## Phase 3: Heavy keystones

### Task 3.1: Black Hole Tip

**Files:**
- Modify: `scripts/spear.gd` — at the top of `attach_to_fish` (large/trophy hit, after the destroy filter), check the keystone and trigger the pull.

**New helper:**

```gdscript
func _trigger_black_hole(at: Vector2) -> void:
    # On Heavy impact with a large/trophy target, all small/medium fish on
    # screen are pulled toward the impact point and insta-caught for free.
    # Implementation: tween each fish over 0.4s to `at`, then resolve as if
    # they were speared (cash + popup). No spear consumed for these catches.
    var fish_nodes := get_tree().get_nodes_in_group("fish")
    var tween := get_tree().create_tween().set_parallel(true)
    for n in fish_nodes:
        var f := n as Fish
        if f == null or not is_instance_valid(f) or f.speared:
            continue
        if f.size_class != Fish.SIZE_SMALL and f.size_class != Fish.SIZE_MEDIUM:
            continue
        f.speared = true  # prevent further interaction
        tween.tween_property(f, "global_position", at, 0.4)
    tween.tween_callback(func():
        for n in fish_nodes:
            var f := n as Fish
            if f == null or not is_instance_valid(f):
                continue
            if not f.speared:
                continue
            if f.size_class != Fish.SIZE_SMALL and f.size_class != Fish.SIZE_MEDIUM:
                continue
            var cash := int(round(f.get_cash_value()))
            var result := GameData.register_hit(cash)
            GameData.add_dive_cash(result["value"])
            GameData.note_fish_caught(current_type_id, StringName(f.species), int(result["value"]))
            var hud = get_tree().current_scene.get_node_or_null("HUD")
            if hud and hud.has_method("spawn_cash_popup"):
                hud.spawn_cash_popup(result["value"], at, f.species)
            _spawn_hit_burst(at, f.color)
            f.queue_free()
    ).set_delay(0.4)
```

In `attach_to_fish` (top, before doing anything else):

```gdscript
if current_type_id == &"heavy":
    var bh: int = int(GameData.get_effective_spear_stat(&"heavy", "black_hole_tip"))
    if bh >= 1:
        _trigger_black_hole(global_position)
```

**Verification:** Buy Black Hole Tip ($3500), fire Heavy at a White Whale or Tuna — all on-screen small/medium fish pull toward the impact and pay out as free catches.

**Commit:** `feat(heavy): black hole tip keystone — pulls small/med to impact`

### Task 3.2: Seismic Roar

**Files:**
- Modify: `scripts/game_data.gd` — add `var seismic_roar_until: float = 0.0` (timestamp; while `Time.get_ticks_msec() / 1000.0 < seismic_roar_until`, defenses are disabled). Add `func trigger_seismic_roar() -> void` that sets `seismic_roar_until = now + 10.0`.
- Modify: `scripts/fish.gd` — at the top of `deflects_spear`, add `if GameData.is_seismic_active(): return false`
- Modify: `scripts/game_data.gd` — `func is_seismic_active() -> bool: return Time.get_ticks_msec() / 1000.0 < seismic_roar_until`
- Modify: `scripts/spear.gd` — in `_on_area_entered`, after the bypass check on Heavy hits, call `GameData.trigger_seismic_roar()` if the keystone is owned

**Code (in `spear.gd` `_on_area_entered`, before `attach_to_fish` for Heavy hits):**

```gdscript
if current_type_id == &"heavy":
    var sr: int = int(GameData.get_effective_spear_stat(&"heavy", "seismic_roar"))
    if sr >= 1:
        GameData.trigger_seismic_roar()
```

**Reset on dive end:** in `GameData`, when a dive starts, `seismic_roar_until = 0.0`. Hook into the existing dive-start signal.

**HUD pulse (optional v1.1):** flash a brief screen-edge tint while seismic is active. Defer.

**Verification:** Buy Seismic Roar, dive into Abyss, hit Whale → for 10 seconds, every Pufferfish/Triggerfish/Blockfish takes spears normally (no bounce). Wait it out → defenses re-engage.

**Commit:** `feat(heavy): seismic roar keystone — 10s defense disable`

### Task 3.3: Whale-Finder Sonar

**Files:**
- Modify: `scripts/fish_spawner.gd` — at dive start, if the player owns the keystone and the current zone has a trophy in its weights, force-spawn one trophy at a known point and tell the HUD to mark it.
- Modify: `scripts/hud.gd` — add a `mark_trophy_target(node: Node2D)` method that draws a beacon arrow above the marked fish until it's despawned.

**Pseudo-implementation in `fish_spawner.gd::_ready` (or wherever dive starts spawning):**

```gdscript
func try_spawn_sonar_trophy() -> void:
    var sr: int = int(GameData.get_effective_spear_stat(&"heavy", "whale_sonar"))
    if sr < 1:
        return
    var zone := GameData.current_zone_config()
    if zone == null:
        return
    var trophy_id := _pick_trophy_in_weights(zone.spawn_weights)
    if trophy_id == StringName(""):
        return
    var fish := _spawn_fish(trophy_id, _random_spawn_position())
    var hud = get_tree().current_scene.get_node_or_null("HUD")
    if hud and hud.has_method("mark_trophy_target"):
        hud.mark_trophy_target(fish)
```

`_pick_trophy_in_weights` returns the first key whose species has `size_class == &"trophy"`, or `&""` if none.

**Verification:** Buy Whale Sonar, dive into Abyss → on dive start, a White Whale appears with a HUD marker pointing at it. Catch it normally.

**Commit:** `feat(heavy): whale sonar keystone — guaranteed trophy + HUD marker`

---

## Phase 4: Net keystones

### Task 4.1: Standing Wave

**Files:**
- Modify: `scripts/spear.gd` — when Net hits, if `standing_wave` is owned, instead of immediately resolving the catch, enter a new state `NET_STANDING_WAVE` for 3 seconds. During that window, any fish that crosses the net's position is captured (capped by `net_max_catch`).

**State:** add `NET_STANDING_WAVE` to the enum. In `_process`, when in this state, sweep `get_tree().get_nodes_in_group("fish")` each tick and capture eligible ones (apply same size/escape rules as `_net_capture`). After 3s of duration OR `attached_fish_array.size() >= max_catch`, transition to `NET_REELING`.

**Verification:** Buy Standing Wave, fire Net into an empty area → net hangs there 3s; if a school passes through, they're caught. Reels back to diver after.

**Commit:** `feat(net): standing wave keystone — 3s trap`

### Task 4.2: Tagging Net

**Files:**
- Modify: `scripts/game_data.gd` — add `var tagged_fish: Dictionary = {}` (instance_id → bonus multiplier). On dive end clear it. Add `func tag_fish(fish_id: int, mult: float)` and `func consume_fish_tag(fish_id: int) -> float`.
- Modify: `scripts/spear.gd` — in `_net_capture` after calling `f.on_speared`, if a fish *escapes* (i.e. the cast was over capacity and skipped this fish, AND `tagging_net` keystone owned), call `GameData.tag_fish(f.get_instance_id(), 2.0)`. (Realistically: track which fish were *touched* but rejected by the cap.)
- Modify: `scripts/spear.gd` — in `_award_fish`, after value bonus calc, multiply by `GameData.consume_fish_tag(fish.get_instance_id())` if returned > 0.

**Verification:** Buy Tagging Net + Wider Mesh (max_catch=1, so plenty of escapees). Cast Net on a Sardine school → 1 caught, others "tagged". Switch to Normal, harpoon a tagged Sardine → cash popup shows 2× value.

**Commit:** `feat(net): tagging net keystone — escape-marker for cross-spear bonus`

### Task 4.3: Schooling Bonus

**Files:**
- Modify: `scripts/spear.gd::_arrive` (in the `NET_REELING` branch, around line 354) — if `schooling_bonus` keystone owned and `attached_fish_array.size() >= 5`, multiply each `_award_fish` by 2× before payout.

**Code:**

```gdscript
elif state == State.NET_REELING:
    var sb: int = int(GameData.get_effective_spear_stat(&"net", "schooling_bonus"))
    var bonus_mult := 2.0 if (sb >= 1 and attached_fish_array.size() >= 5) else 1.0
    for f in attached_fish_array:
        if is_instance_valid(f):
            _award_fish_with_mult(f, bonus_mult)
            f.queue_free()
    attached_fish_array.clear()
```

Refactor `_award_fish` to take an optional multiplier param.

**Verification:** Buy Schooling Bonus + max-out Wider Hoop and Wider Mesh, dive in Reef, cast Net into a thick Sardine school → if ≥5 catch, payout label flashes 2× per fish.

**Commit:** `feat(net): schooling bonus keystone — 2x payout on 5+ catch`

---

## Phase 5: Upgrade shop UI cleanup

Goal: Drop the abandoned branched-ladder scaffolding, render ramps + keystones in two clean visual sections per spear card (no fancy tree shape).

### Task 5.1: Delete `skill_tree_view.gd` and remove tree constants

**Files:**
- Delete: `scripts/skill_tree_view.gd`, `scripts/skill_tree_view.gd.uid`
- Modify: `scripts/upgrade_shop.gd` — remove `TREE_NODE_SIZE`, `TREE_AREA_SIZE`, `TREE_SLOT_POS`, `TREE_EDGES` constants and any code paths that consume them

**Verification:** `grep -r 'SkillTreeView\|TREE_NODE_SIZE\|TREE_SLOT_POS' scripts/` returns no hits. Game still boots and the upgrade shop opens.

**Commit:** `refactor(shop): drop branched-ladder scaffolding`

### Task 5.2: Render ramps + keystones as two grouped rows

**Files:**
- Modify: `scripts/upgrade_shop.gd` — in `_build_spear_card` (or equivalent), after the spear sprite + bag stepper, lay out:
  - **Section 1 — RAMPS:** a flow-container row of upgrade buttons for every upgrade where `def.keystone == false`, sorted by entry order (the `.tres` ordering already matches the locked design).
  - **Section 2 — KEYSTONES:** a row of larger (~96×96) tiles for upgrades where `def.keystone == true`. Different visual treatment: gold border, glyph centered, name + price stacked below.
  - For Normal (no keystones) the keystone section is omitted.
- Reuse existing `_style_tile()`, drop the `tier`/`parents` lookups (parents-gating is unused in this design — `are_spear_upgrade_parents_satisfied` always returns true since `parents=[]`).

**Verification:** Open the shop, see Normal with 5 ramp tiles + no keystone row; Heavy with 4 ramp tiles + 3 keystone tiles; Net with 5 ramp tiles + 3 keystone tiles. Each tile shows level pips, price, buyable highlight.

**Commit:** `feat(shop): render ramps + keystones in two grouped sections`

---

## Phase 6: Verification & cleanup

### Task 6.1: Manual playtest checklist

Run through:
- [ ] Start a fresh save — only Normal spear available, $0 cash
- [ ] Reef dives — verify Squid spawns
- [ ] Buy Bullseye Lv1, hit a fish dead-center — 1.5× payout
- [ ] Unlock Net spear — Net works, Schooling Bonus eligible after dives 5+ cash
- [ ] Unlock Heavy — Heavy destroys small fish, ignores Pufferfish defenses
- [ ] Buy Penetration Lv1 — Heavy plows 2 small fish per shot
- [ ] Buy Black Hole Tip — Heavy hits Tuna → all small/medium pulled in
- [ ] Buy Seismic Roar — Heavy hit → 10s defense window observed on screen
- [ ] Buy Whale Sonar — dive in Abyss → Whale auto-spawns with HUD marker
- [ ] Buy Standing Wave — Net cast hangs 3s
- [ ] Buy Tagging Net — Net + Normal combo: tagged fish pays 2×
- [ ] Buy Schooling Bonus — Net cast on dense school of 5+ → 2× payout per fish
- [ ] Kelp dive — Pufferfish absent, Blockfish/Bonito/Grouper present
- [ ] Abyss dive — Anglerfish + Lanternfish spawn

### Task 6.2: Cost calibration pass

After playing 30-40 dives, sanity-check:
- Are cheap ramps too expensive? (Player should afford one purchase per 1-2 dives early.)
- Are keystones too cheap? (Should take 20-30 dives to save up.)
- Adjust costs in `.tres` files in a single sweep commit.

**Commit:** `tune(spears): cost calibration after playtest`

### Task 6.3: Update Notion

After all phases are merged, update the Notion Upgrades page's status from "Locked design" to "Implemented". Add a "v1 known-issues" section if any rough edges remain.

---

## Out of scope (deferred — track in Notion open questions)

- Cross-spear gating ("spend 5 upgrades on Normal to unlock Heavy" — alt to cash unlock)
- Fusion keystones (Vampire Survivors style)
- Cosmetic shop (hats)
- Research-gated keystones (only revealed after sighting relevant fish)
- Adding more trophy species (post-v1, after Sonar feels played-out)
- Fish density tuning for 40s dives (separate plan — affects `fish_spawner.gd` scaling)
- Tree shape redesign (deferred until content is play-tested)
