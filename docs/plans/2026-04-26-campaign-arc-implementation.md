# Campaign Arc Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restructure Harpoony's spear identities, upgrade trees, fish size classes, and zone arc per the validated design at [docs/plans/2026-04-26-campaign-arc-design.md](2026-04-26-campaign-arc-design.md).

**Architecture:** Data-driven changes to `.tres` files (spears + zones), additive fields on `Fish` (size_class), filter-rule on Net catch in `spear.gd`, new species behavior, win-condition signal from `GameData`.

**Tech Stack:** Godot 4.6 GDScript, custom `Resource` classes, signal-driven HUD/shop refresh.

**Verification model:** No unit-test framework in this project. Each task ends with a manual run via `godot --headless --quit-after 3000 --debug` to verify clean parse, plus an editor smoke-test for behavioral tasks.

---

## Task Ordering

Tasks are ordered so the game stays runnable after each commit. Data structures first, behavior second, content third, finale last.

1. Fish size_class field
2. Net catch filter (size-gated, defense-non-bypass)
3. Move pierce from Normal to Heavy
4. Rebuild Normal upgrade tree
5. Rebuild Net upgrade tree
6. Rebuild Heavy upgrade tree
7. Consolidate to 4 zones
8. Z3 Open Blue content (marlin, jellyfish)
9. Z4 Abyss content + White Whale legendary
10. Win condition + ending screen
11. Final balance pass

---

### Task 1: Fish size_class field

Add a discrete size class to every fish so Net catch and Heavy trophy logic can filter cleanly.

**Files:**
- Modify: `scripts/fish.gd` (add `size_class` field, set per species in `setup`)

**Step 1: Add the field and constants**

In `scripts/fish.gd`, near the top of the script (after the `species` field):

```gdscript
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
```

**Step 2: Assign size_class in each species' `setup` branch**

In `scripts/fish.gd::setup`, append the assignment to each `match` branch:

| Species | size_class |
|---|---|
| sardine | small |
| lanternfish | small |
| grouper | medium |
| pufferfish | medium |
| mahimahi | medium |
| tuna | large |
| triggerfish | large |
| squid | medium |

(marlin, jellyfish, whitewhale come in later tasks.)

**Step 3: Verify clean parse**

Run: `godot --headless --quit-after 3000 --debug`
Expected: no parse errors, game runs as before.

**Step 4: Commit**

```bash
git add scripts/fish.gd
git commit -m "feat: add size_class to Fish for Net catch gating"
```

---

### Task 2: Net catch filter — size-gated, no defense bypass

Net should only catch fish whose size class is permitted by current upgrades. No more bypassing defenses.

**Files:**
- Modify: `data/spears/net.tres` (remove `bypasses_defenses`, add `catch_size_classes` field)
- Modify: `scripts/spear_type.gd` (add `catch_size_classes` field)
- Modify: `scripts/spear.gd` (filter caught fish by size class; restore defense honoring)

**Step 1: Add `catch_size_classes` to SpearType**

In `scripts/spear_type.gd`, add:

```gdscript
@export var catch_size_classes: Array[StringName] = [&"small", &"medium", &"large", &"trophy"]
```

Default for Normal/Heavy stays inclusive (they target one fish anyway). Net will narrow it.

**Step 2: Edit `data/spears/net.tres`**

- Remove the line `bypasses_defenses = true`.
- Add: `catch_size_classes = Array[StringName]([&"small"])`
- Replace the `net_radius` and `net_max_catch` upgrades with the new tree (Task 5 will do this in full — for now just remove `bypasses_defenses` and add the size-class field with default `[&"small"]`).

**Step 3: Filter in `spear.gd` net catch logic**

Locate the Net catch loop in `scripts/spear.gd` (search for `net_radius` or `net_max_catch`). Inside the per-fish check, before adding a fish to the catch list, add:

```gdscript
if not _spear_type.catch_size_classes.has(fish.size_class):
    continue
```

**Step 4: Restore defense check for Net**

Find any `if _spear_type.bypasses_defenses:` short-circuit that lets Net skip `fish.deflects_spear()`. Net must now respect defenses. After this change, Net hitting an inflated puffer or a triggerfish front should bounce.

**Step 5: Verify**

Run: `godot --headless --quit-after 3000 --debug`. In editor: cast Net at a sardine school → catches. Cast Net at an inflated puffer → bounces. Cast Net at a grouper → no catch (grouper is medium, Net only allows small).

**Step 6: Commit**

```bash
git add scripts/spear_type.gd scripts/spear.gd data/spears/net.tres
git commit -m "feat: net is size-gated, no longer bypasses defenses"
```

---

### Task 3: Move pierce from Normal to Heavy

Pierce belongs on the heavy weapon. Strip Razor Edge from Normal, add Drill Tip to Heavy.

**Files:**
- Modify: `data/spears/normal.tres` (remove `pierce_count` upgrade)
- Modify: `data/spears/heavy.tres` (add `pierce_count` upgrade tree node)
- Verify: `scripts/spear.gd` pierce code still functions when driven by Heavy

**Step 1: Remove pierce upgrade from normal.tres**

Delete the entire `"pierce_count": { ... }` block from the `upgrades` dict in `data/spears/normal.tres`. Keep `pierce_count = 1` at the top (default) — that's the field, not the upgrade.

**Step 2: Add pierce upgrade to heavy.tres**

Add to `data/spears/heavy.tres` upgrades dict:

```gdscript
"pierce_count": {
    "name": "Drill Tip",
    "description": "+1 fish pierced per shot. Plows a line through stacked targets.",
    "icon": "✦",
    "max_level": 2,
    "costs": [400, 1200],
    "field": "pierce_count",
    "step": 1
}
```

**Step 3: Verify**

Run game. Buy a Heavy + Drill Tip. Fire into a line of fish — first two should pierce, third reels.

**Step 4: Commit**

```bash
git add data/spears/normal.tres data/spears/heavy.tres
git commit -m "feat: move pierce upgrade from Normal to Heavy"
```

---

### Task 4: Rebuild Normal upgrade tree (Speed / Power branches)

Final shape per the design.

**Files:**
- Modify: `data/spears/normal.tres`

**Step 1: Replace the `upgrades` dict**

Final upgrade tree for Normal:

```gdscript
upgrades = {
"speed_mult": {
    "name": "Aerodynamic Shaft",
    "description": "+10% travel speed.",
    "icon": "➤",
    "max_level": 1,
    "costs": [40],
    "field": "speed_mult",
    "step": 0.15
},
"reel_speed_mult": {
    "name": "Rapid Reel",
    "description": "Speed branch — +25% reel return.",
    "icon": "≣",
    "max_level": 1,
    "costs": [120],
    "field": "reel_speed_mult",
    "step": 0.25
},
"twin_shot": {
    "name": "Twin Shot",
    "description": "Speed branch — fire two spears per click.",
    "icon": "❙❙",
    "max_level": 1,
    "costs": [450],
    "field": "twin_shot",
    "step": 1
},
"hit_radius_bonus": {
    "name": "Wider Tip",
    "description": "Power branch — +12 hit radius.",
    "icon": "◎",
    "max_level": 1,
    "costs": [80],
    "field": "hit_radius_bonus",
    "step": 12.0
},
"value_bonus": {
    "name": "Polished Tip",
    "description": "Power branch — +50% cash per hit.",
    "icon": "✱",
    "max_level": 1,
    "costs": [350],
    "field": "value_bonus",
    "step": 0.5
}
}
```

Note: `twin_shot` is a new field. Add `@export var twin_shot: int = 0` to `scripts/spear_type.gd`. Twin Shot implementation defers to a follow-up task (mark TODO in `diver.gd::_try_fire`).

**Step 2: Add `twin_shot` field to SpearType**

In `scripts/spear_type.gd`, add: `@export var twin_shot: int = 0`.

**Step 3: TODO marker in diver.gd**

In `scripts/diver.gd::_try_fire`, after the spear instantiation, add a comment:

```gdscript
# TODO: if normal.twin_shot > 0, fire a second spear at aim_angle ± small offset.
```

(Wire actual twin-fire after the initial pass — keeps this task small.)

**Step 4: Verify**

Run game. Open shop. Normal card should show 5 upgrade tiles (Aerodynamic, Rapid Reel, Twin Shot, Wider Tip, Polished Tip). Costs visible. No parse errors.

**Step 5: Commit**

```bash
git add data/spears/normal.tres scripts/spear_type.gd scripts/diver.gd
git commit -m "feat: rebuild Normal upgrade tree (Speed/Power branches)"
```

---

### Task 5: Rebuild Net upgrade tree (Wide / Smart branches)

**Files:**
- Modify: `data/spears/net.tres`

**Step 1: Replace upgrades dict**

```gdscript
upgrades = {
"net_radius": {
    "name": "Mesh Quality",
    "description": "+25 catch radius (baseline).",
    "icon": "◯",
    "max_level": 1,
    "costs": [120],
    "field": "net_radius",
    "step": 25.0
},
"cast_wide": {
    "name": "Cast Wide",
    "description": "Wide branch — +50% net radius.",
    "icon": "⊙",
    "max_level": 1,
    "costs": [400],
    "field": "net_radius",
    "step": 30.0
},
"bigger_hoop": {
    "name": "Bigger Hoop",
    "description": "Wide branch — also catches MEDIUM fish.",
    "icon": "⊞",
    "max_level": 1,
    "costs": [800],
    "field": "catches_medium",
    "step": 1
},
"reel_speed_mult": {
    "name": "Weighted Net",
    "description": "Smart branch — +30% reel-in speed.",
    "icon": "≣",
    "max_level": 1,
    "costs": [200],
    "field": "reel_speed_mult",
    "step": 0.3
},
"lure_net": {
    "name": "Lure Net",
    "description": "Smart branch — fish drift toward center before snap.",
    "icon": "✺",
    "max_level": 1,
    "costs": [600],
    "field": "lure_net",
    "step": 1
}
}
```

**Step 2: Add `catches_medium` and `lure_net` to SpearType**

In `scripts/spear_type.gd`:

```gdscript
@export var catches_medium: int = 0   # 0/1 — when 1, medium fish appended to catch_size_classes
@export var lure_net: int = 0         # 0/1 — pulls fish toward center
```

**Step 3: Wire `catches_medium` into Net catch logic**

In `scripts/spear.gd` Net catch loop, before the `catch_size_classes.has(...)` check, build the effective set:

```gdscript
var allowed := _spear_type.catch_size_classes.duplicate()
if _spear_type.catches_medium == 1 and not allowed.has(&"medium"):
    allowed.append(&"medium")
# ...
if not allowed.has(fish.size_class):
    continue
```

**Step 4: TODO for Lure Net**

Add `# TODO: if lure_net == 1, tween fish toward net center over ~0.2s before catch resolution.` in the Net catch block. Wire after initial pass.

**Step 5: Verify**

Run. Buy Net + Bigger Hoop. Cast at a grouper → catches now. Without Bigger Hoop → does not.

**Step 6: Commit**

```bash
git add data/spears/net.tres scripts/spear_type.gd scripts/spear.gd
git commit -m "feat: rebuild Net upgrade tree (Wide/Smart branches)"
```

---

### Task 6: Rebuild Heavy upgrade tree (Crit / Penetrate branches)

**Files:**
- Modify: `data/spears/heavy.tres`

**Step 1: Replace upgrades dict**

```gdscript
upgrades = {
"speed_mult": {
    "name": "Reinforced Shaft",
    "description": "+15% travel speed (baseline).",
    "icon": "➤",
    "max_level": 1,
    "costs": [200],
    "field": "speed_mult",
    "step": 0.15
},
"sharp_tip": {
    "name": "Sharp Tip",
    "description": "Crit branch — 25% chance for 2x value.",
    "icon": "◆",
    "max_level": 1,
    "costs": [500],
    "field": "crit_chance",
    "step": 0.25
},
"perfect_strike": {
    "name": "Perfect Strike",
    "description": "Crit branch — direct-center hits crit at 3x.",
    "icon": "★",
    "max_level": 1,
    "costs": [1200],
    "field": "perfect_strike",
    "step": 1
},
"pierce_count": {
    "name": "Drill Tip",
    "description": "Penetrate branch — pierces up to 3 fish in a line.",
    "icon": "✦",
    "max_level": 1,
    "costs": [600],
    "field": "pierce_count",
    "step": 2
},
"sonic_boom": {
    "name": "Sonic Boom",
    "description": "Penetrate branch — impact stuns nearby fish briefly.",
    "icon": "◊",
    "max_level": 1,
    "costs": [1100],
    "field": "sonic_boom",
    "step": 1
}
}
```

(Note Drill Tip step=2 brings pierce from 1 → 3 in one purchase, since this design uses single-level upgrades.)

**Step 2: Add new fields to SpearType**

```gdscript
@export var crit_chance: float = 0.0
@export var perfect_strike: int = 0
@export var sonic_boom: int = 0
```

**Step 3: Wire crit into hit value**

In `scripts/spear.gd` at hit resolution (where base value is computed), after value calculation:

```gdscript
var crit_mult := 1.0
if _spear_type.perfect_strike == 1 and _is_dead_center_hit(fish):
    crit_mult = 3.0
elif _spear_type.crit_chance > 0.0 and randf() < _spear_type.crit_chance:
    crit_mult = 2.0
final_value = int(round(final_value * crit_mult))
```

`_is_dead_center_hit(fish)` is a helper: returns true when the spear's hit position is within 25% of the fish's hit_radius from center. Add as private helper at bottom of `spear.gd`.

**Step 4: TODOs for Sonic Boom**

In `_arrive` / `_apply_hit`, add `# TODO: if sonic_boom == 1, mark nearby fish stunned for 0.6s.`

**Step 5: Verify**

Buy Heavy + Sharp Tip. Hit a grouper repeatedly — occasional 2x payouts.

**Step 6: Commit**

```bash
git add data/spears/heavy.tres scripts/spear_type.gd scripts/spear.gd
git commit -m "feat: rebuild Heavy upgrade tree (Crit/Penetrate branches)"
```

---

### Task 7: Consolidate to 4 zones

Delete extras, finalize the four-zone arc.

**Files:**
- Delete: `data/zones/04_midnight.tres`, `data/zones/06_trench.tres`
- Rename: `data/zones/03_twilight.tres` → `data/zones/03_open_blue.tres`
- Rename: `data/zones/05_abyss.tres` → `data/zones/04_abyss.tres`
- Modify: `scripts/game_data.gd` zone-loading code (paths and order)

**Step 1: Inspect current zone load order**

Open `scripts/game_data.gd`. Find where `zones` array is populated. Confirm zones are loaded by explicit path or by directory scan. Adjust accordingly.

**Step 2: Delete extra zone files**

```bash
git rm data/zones/04_midnight.tres data/zones/06_trench.tres
```

**Step 3: Rename**

```bash
git mv data/zones/03_twilight.tres data/zones/03_open_blue.tres
git mv data/zones/05_abyss.tres data/zones/04_abyss.tres
```

**Step 4: Update zone load list in game_data.gd**

Set the explicit path list to the 4 surviving files in the order: reef, kelp, open_blue, abyss.

**Step 5: Update `display_name` and prices**

Edit `data/zones/03_open_blue.tres`: `display_name = "Open Blue"`, `unlock_cost` = $750.
Edit `data/zones/04_abyss.tres`: `display_name = "The Abyss"`, `unlock_cost` = $2200.

**Step 6: Verify**

Run. Boat lever should show 4 zones. Each unlock cost matches design.

**Step 7: Commit**

```bash
git add data/zones/ scripts/game_data.gd
git commit -m "feat: consolidate to 4-zone campaign (Reef/Kelp/Open Blue/Abyss)"
```

---

### Task 8: Z3 Open Blue content — marlin and jellyfish

Add two new species. Marlin = fast, large, valuable. Jellyfish = slow, defended (bounce), medium.

**Files:**
- Modify: `scripts/fish.gd` (add `marlin` and `jellyfish` species branches)
- Modify: `data/zones/03_open_blue.tres` (spawn weights)
- Modify: `scripts/fish_spawner.gd` if any species hardcoding exists

**Step 1: Add marlin to Fish.setup**

```gdscript
"marlin":
    base_value = 60
    hit_radius = 22.0
    speed = 220.0
    color = Color(0.25, 0.4, 0.65)
    wave_frequency = 4.0
    size_class = SIZE_LARGE
```

**Step 2: Add jellyfish to Fish.setup**

```gdscript
"jellyfish":
    base_value = 18
    hit_radius = 16.0
    speed = 30.0
    color = Color(0.85, 0.7, 0.95, 0.85)
    wave_frequency = 1.0
    wave_amplitude = 8.0
    size_class = SIZE_MEDIUM
    # Jellyfish always deflects Normal/Net — only Heavy can land.
```

**Step 3: Add jellyfish defense in `deflects_spear`**

```gdscript
if species == "jellyfish":
    return not spear.spear_type_breaks_defenses()
```

(Add `spear_type_breaks_defenses()` helper on `Spear` returning `_spear_type.id == &"heavy"`. Sub-step.)

**Step 4: Custom draws**

Add `_draw_marlin()` and `_draw_jellyfish()` helpers in `fish.gd::_draw`. Marlin: long sleek body with bill. Jellyfish: dome + dangling tendrils.

**Step 5: Set spawn weights**

In `data/zones/03_open_blue.tres`:

```
spawn_weights = { "tuna": 0.3, "marlin": 0.15, "jellyfish": 0.25, "mahimahi": 0.2, "pufferfish": 0.1 }
```

**Step 6: Verify**

Buy Z3, dive. Marlin streaks across. Jellyfish drifts. Normal bounces off jellyfish. Heavy lands.

**Step 7: Commit**

```bash
git add scripts/fish.gd scripts/spear.gd data/zones/03_open_blue.tres
git commit -m "feat: add marlin + jellyfish to Z3 Open Blue"
```

---

### Task 9: Z4 Abyss + White Whale legendary

The trophy fish. Rare spawn, very high value, only Heavy lands it.

**Files:**
- Modify: `scripts/fish.gd` (add `whitewhale` species)
- Modify: `data/zones/04_abyss.tres`
- Modify: `scripts/fish_spawner.gd` (rare-spawn cap: max 1 whitewhale on screen at once, low spawn weight)
- Modify: `scripts/game_data.gd` (track `whitewhale_caught` flag)

**Step 1: Add whitewhale species**

```gdscript
"whitewhale":
    base_value = 800
    hit_radius = 40.0
    speed = 60.0
    color = Color(0.92, 0.94, 0.96)
    wave_frequency = 0.6
    wave_amplitude = 30.0
    size_class = SIZE_TROPHY
```

**Step 2: Defense — only Heavy lands trophies**

In `deflects_spear`:

```gdscript
if size_class == SIZE_TROPHY:
    return not spear.spear_type_breaks_defenses()
```

**Step 3: Spawn cap in fish_spawner.gd**

Add a check before spawning whitewhale: count existing whitewhales in scene; if ≥ 1, skip. Spawn weight in `04_abyss.tres`:

```
spawn_weights = { "tuna": 0.25, "marlin": 0.25, "jellyfish": 0.2, "triggerfish": 0.15, "pufferfish": 0.1, "whitewhale": 0.05 }
```

**Step 4: Custom draw**

Large pale silhouette with subtle gradient. Distinct from other fish at a glance.

**Step 5: Track catch in GameData**

```gdscript
var whitewhale_caught: bool = false
signal whitewhale_caught_signal
```

In `register_hit` (or wherever value is added), if `species == "whitewhale"` and not yet caught, set flag and emit signal.

**Step 6: Verify**

Buy Z4, dive repeatedly. White whale appears occasionally. Only Heavy lands it. Catch triggers signal.

**Step 7: Commit**

```bash
git add scripts/fish.gd scripts/fish_spawner.gd scripts/game_data.gd data/zones/04_abyss.tres
git commit -m "feat: White Whale legendary in Z4 Abyss"
```

---

### Task 10: Win condition + ending screen

Catching the white whale ends the campaign (player can keep diving after).

**Files:**
- Create: `scripts/ending_screen.gd` (CanvasLayer, fade-in, "You caught the legend." card)
- Modify: `scripts/main.gd` (listen to `whitewhale_caught_signal`, show ending)

**Step 1: Create ending screen**

`scripts/ending_screen.gd` — minimal CanvasLayer with a centered Panel:

```gdscript
extends CanvasLayer

func _ready() -> void:
    layer = 100
    process_mode = Node.PROCESS_MODE_ALWAYS

func show_ending() -> void:
    # full-screen dim + centered text card with fade-in
    # Buttons: "Continue Diving" (closes), "Reset Campaign" (calls main reset)
    ...
```

(Stub it — can iterate visuals later. Goal is the credits-trigger moment exists.)

**Step 2: Wire signal in main.gd**

In `main.gd::_ready`, connect:

```gdscript
GameData.whitewhale_caught_signal.connect(_on_whitewhale_caught)

func _on_whitewhale_caught() -> void:
    # let the cash popup play first, then show ending
    await get_tree().create_timer(1.5).timeout
    _ending_screen.show_ending()
```

**Step 3: Verify**

Use cheat mode, force-spawn whitewhale, catch with Heavy. Ending screen appears.

**Step 4: Commit**

```bash
git add scripts/ending_screen.gd scripts/main.gd
git commit -m "feat: ending screen on White Whale catch"
```

---

### Task 11: Final balance pass

Adjust upgrade costs, fish values, and zone unlock prices so the campaign clocks ~2-3 hours and each zone *demands* its associated upgrades.

**Files:**
- Modify: `data/spears/*.tres`, `data/zones/*.tres`, `scripts/fish.gd` base values

**Step 1: Playtest target — 5-min Z1**

Time a Z1-only run with 0 upgrades. Adjust sardine ($4) / grouper ($15) / puffer ($12) base values until a competent player pulls $300 in 5 min and unlocks Z2.

**Step 2: Playtest target — 30-min Z2**

Confirm Net unlock at $500 lands ~10 min into Z2. If too early, raise unlock cost.

**Step 3: Playtest target — 30-min Z3**

Heavy unlock at $1500. Confirm Z3 cash flow allows it within the zone.

**Step 4: Playtest target — 45-min Z4**

White whale catch should require Heavy + at least one crit upgrade. Tune whitewhale_caught probability + value so it feels earned, not random.

**Step 5: Commit**

```bash
git add data/
git commit -m "balance: tune campaign pacing for 2-3hr completion"
```

---

## Out of Scope (Defer)

- Twin Shot actual implementation (TODO marker placed in Task 4)
- Lure Net actual implementation (TODO marker in Task 5)
- Sonic Boom actual implementation (TODO marker in Task 6)
- Real sprite art (sprites > procedural shapes)
- Trophy log UI
- "Continue Diving" post-credits state polish

These ride after the structural work lands and playtest confirms the loop.
