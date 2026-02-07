# Stage 3: Math Operations — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the Stage 2 math operations mechanic where numbers and signs spawn together, and simultaneously labeling 2 numbers + 1 sign creates a purple combo equation worth 2× points.

**Architecture:** Extend the existing stage system in `GameData` with a 3-output Math stage. Add `point_type` and `digit_value` fields to data points for number/sign distinction. Combo detection lives in `data_spawner.gd` using a recently-labeled buffer, triggering merge animations in `data_point.gd` that produce purple equation points routed to a shiny output node.

**Tech Stack:** Godot 4.6, GDScript, custom 2D draw calls

---

## Summary of Changes

| Area | Current | Target |
|------|---------|--------|
| Stage 2 definition | "Images", 10 outputs, yellow | "Math", 3 outputs, purple |
| Data point types | All same type | `point_type` = "number" or "sign" |
| Spawn logic (Stage 2) | All same class | 75% numbers (0-9), 25% signs (+, −, ×) |
| Output routing (Stage 2) | 10 class-based outputs | 3 outputs: Numbers(0), Signs(1), Equations(2) |
| Combo system | N/A | 2 nums + 1 sign simultaneous → purple merge, 2× cash |
| Equations output node | N/A | Shiny/glow effect |
| Stage transition 1→2 | Output expands 2→10 | Output collapses 10→3 with animation |

---

### Task 1: GameData — Stage 2 Definition & Helpers

**Files:**
- Modify: `scripts/game_data.gd`

**Step 1: Update the Stage 2 entry in the `stages` array**

Change the stage at index 2 from "Images" to "Math" with purple color and 3 output nodes:

```gdscript
{
    "name": "Math",
    "label_time": 1.0,
    "cash_per_point": 25,
    "accuracy_needed": 300,
    "output_nodes": 3,
    "color": Color(0.7, 0.3, 1.0),
},
```

**Step 2: Add combo multiplier constant**

Add a constant near the top of the file:

```gdscript
const COMBO_MULTIPLIER: float = 2.0
```

**Step 3: Add `get_combo_cash(individual_count: int)` helper**

```gdscript
func get_combo_cash(individual_count: int) -> int:
    var per_point = get_cash_per_point()
    return int(per_point * individual_count * COMBO_MULTIPLIER)
```

**Step 4: Run the game. Verify the stage definition loads without errors (game should start normally).**

**Step 5: Commit**

```bash
git add scripts/game_data.gd
git commit -m "feat: update Stage 2 definition — Math with purple color and 3 outputs"
```

---

### Task 2: Data Point — point_type & Sign Display

**Files:**
- Modify: `scripts/data_point.gd`

**Step 1: Add new fields**

Add these fields after the existing `data_class` declaration (line 18):

```gdscript
var point_type: String = "number"  # "number" or "sign"
var digit_value: int = 0           # 0-9 for numbers, 0/1/2 for signs (+/-/×)
```

**Step 2: Update `_discover()` — Stage 2 display logic**

Replace the `match GameData.current_stage` block in `_discover()` (lines 140-151) with:

```gdscript
match GameData.current_stage:
    0:
        display_value = str(data_class)
    1:
        display_value = str(data_class)
    2:  # Math
        if point_type == "sign":
            var signs = ["+", "−", "×"]
            display_value = signs[digit_value % signs.size()]
        else:
            display_value = str(digit_value)
    3:
        display_value = "F" + str(data_class)
    _:
        display_value = str(data_class)
```

**Step 3: Run the game. Start training — points should still spawn and label correctly (Stage 0 behavior unchanged).**

**Step 4: Commit**

```bash
git add scripts/data_point.gd
git commit -m "feat: add point_type and digit_value fields with Stage 2 display logic"
```

---

### Task 3: Data Spawner — Mixed Number/Sign Spawn Logic

**Files:**
- Modify: `scripts/data_spawner.gd`

**Step 1: Update `_spawn_data_point()` — Stage 2 class assignment**

Replace the `# Assign data class` block (lines 82-88) with:

```gdscript
# Assign data class and point type
match GameData.current_stage:
    0:  # Binary
        point.data_class = randi() % 2
    1:  # Numbers
        point.data_class = randi() % 10
    2:  # Math — 75% numbers, 25% signs
        if randf() < 0.25:
            point.point_type = "sign"
            point.data_class = 1  # Routes to Signs output node
            point.digit_value = randi() % 3  # 0=+, 1=−, 2=×
        else:
            point.point_type = "number"
            point.data_class = 0  # Routes to Numbers output node
            point.digit_value = randi() % 10  # 0-9
    _:
        point.data_class = randi() % GameData.get_output_count()
```

**Step 2: Update `_spawn_aug_point()` — Same Stage 2 logic**

Replace the `# Assign data class` block in `_spawn_aug_point()` (lines 135-141) with the same logic:

```gdscript
# Assign data class and point type
match GameData.current_stage:
    0:
        point.data_class = randi() % 2
    1:
        point.data_class = randi() % 10
    2:  # Math — 75% numbers, 25% signs
        if randf() < 0.25:
            point.point_type = "sign"
            point.data_class = 1
            point.digit_value = randi() % 3
        else:
            point.point_type = "number"
            point.data_class = 0
            point.digit_value = randi() % 10
    _:
        point.data_class = randi() % GameData.get_output_count()
```

**Step 3: Run the game. Cheat to Stage 2 (or temporarily set `current_stage = 2` in game_data.gd). Verify a mix of number and sign data points spawn. Numbers should display digits, signs should display +/−/×.**

**Step 4: Commit**

```bash
git add scripts/data_spawner.gd
git commit -m "feat: mixed 75/25 number/sign spawn logic for Stage 2"
```

---

### Task 4: Network — 3 Output Nodes with Labels & Routing

**Files:**
- Modify: `scripts/network.gd`

**Step 1: Update `_get_output_label()` for Stage 2**

Replace the `match` block in `_get_output_label()` (lines 142-154) with:

```gdscript
func _get_output_label(index: int) -> String:
    match GameData.current_stage:
        0:
            return str(index)
        1:
            return str(index)
        2:
            var math_labels = ["Num", "Sign", "Eq"]
            return math_labels[index % math_labels.size()]
        3:
            return "F" + str(index)
        _:
            return str(index)
```

**Step 2: Add shiny glow effect for the Equations output node (index 2) in `_draw()`**

In the output node label drawing section (around line 271), after the existing label drawing, add a glow effect for the equations node:

```gdscript
# After the output label drawing loop, add equations node glow
if GameData.current_stage == 2 and output_layer.size() > 2:
    var eq_pos = output_layer[2]
    var eq_glow_alpha = 0.12 + pulse * 0.08
    draw_circle(eq_pos, 14.0 + pulse * 2.0, Color(0.7, 0.3, 1.0, eq_glow_alpha))
    # Inner bright core
    draw_circle(eq_pos, 9.0, Color(0.8, 0.5, 1.0, 0.08 + pulse * 0.04))
```

This goes right after the `for node_i in range(output_layer.size()):` loop ends (after line 279), still inside the `if total_layers > 0:` block.

**Step 3: Run the game with Stage 2 active. Verify 3 output nodes labeled "Num", "Sign", "Eq". The "Eq" node should have a purple glow.**

**Step 4: Commit**

```bash
git add scripts/network.gd
git commit -m "feat: 3 output nodes for Stage 2 with shiny equations node"
```

---

### Task 5: Combo Detection — Track Simultaneous Labels

**Files:**
- Modify: `scripts/data_spawner.gd`

This is the core mechanic. We track points that were recently labeled and check for valid combos.

**Step 1: Add combo buffer state**

Add these variables near the top of `data_spawner.gd`, after the existing variable declarations (line 8):

```gdscript
# Combo detection
var recently_labeled: Array = []  # Array of {point, time}
const COMBO_WINDOW: float = 0.15  # Seconds within which labels count as simultaneous
```

**Step 2: Add combo buffer cleanup in `_process()`**

At the beginning of `_process()`, after the `if not GameData.is_epoch_active: return` check (line 17), add:

```gdscript
# Clean up expired combo buffer entries
var now = Time.get_ticks_msec() / 1000.0
recently_labeled = recently_labeled.filter(func(entry):
    return is_instance_valid(entry["point"]) and (now - entry["time"]) < COMBO_WINDOW
)
```

**Step 3: Update `_on_point_discovered()` to feed the combo buffer**

Replace the beginning of `_on_point_discovered()` (starting at line 164). The full replacement:

```gdscript
func _on_point_discovered(source_point: Area2D) -> void:
    # Flash the cursor on label
    var cursor = get_parent().get_node_or_null("Cursor")
    if cursor and cursor.has_method("on_point_labeled"):
        cursor.on_point_labeled()

    # Combo detection for Stage 2 (Math)
    if GameData.current_stage == 2 and not source_point.is_augmented:
        var now = Time.get_ticks_msec() / 1000.0
        recently_labeled.append({"point": source_point, "time": now})
        _check_combo()

    # Batch label logic (existing)
    var chance = GameData.get_batch_label_chance()
    if chance <= 0.0:
        return

    var cursor_points: Array = []
    if cursor:
        cursor_points = cursor.hovering_points.duplicate()

    var batch_delay = 0.0
    for point in active_points:
        if not is_instance_valid(point):
            continue
        if point == source_point:
            continue
        if point.is_labeled or point.is_consumed:
            continue
        if point.data_class != source_point.data_class:
            continue
        if point in cursor_points:
            continue
        if randf() < chance:
            if batch_delay > 0.0:
                _draw_chain_line(source_point.global_position, point.global_position, batch_delay)
            point._discover()
            batch_delay += 0.08
```

**Step 4: Add `_check_combo()` method**

Add this new method to `data_spawner.gd`:

```gdscript
func _check_combo() -> void:
    # Need at least 3 recently labeled points
    if recently_labeled.size() < 3:
        return

    # Collect valid (not yet merging/consumed) points by type
    var numbers: Array = []
    var signs: Array = []
    for entry in recently_labeled:
        var p = entry["point"]
        if not is_instance_valid(p) or p.is_consumed:
            continue
        if p.has_meta("is_merging"):
            continue
        if p.point_type == "number":
            numbers.append(p)
        elif p.point_type == "sign":
            signs.append(p)

    # Check for valid combo: 2 numbers + 1 sign
    if numbers.size() >= 2 and signs.size() >= 1:
        var combo_numbers = [numbers[0], numbers[1]]
        var combo_sign = signs[0]
        _trigger_combo(combo_numbers, combo_sign)

        # Remove used points from buffer
        for p in combo_numbers:
            recently_labeled = recently_labeled.filter(func(e): return e["point"] != p)
        recently_labeled = recently_labeled.filter(func(e): return e["point"] != combo_sign)
```

**Step 5: Add stub `_trigger_combo()` that just prints for now**

```gdscript
func _trigger_combo(numbers: Array, sign_point: Area2D) -> void:
    # Calculate the equation
    var a = numbers[0].digit_value
    var b = numbers[1].digit_value
    var sign_idx = sign_point.digit_value
    var signs_display = ["+", "−", "×"]
    var sign_str = signs_display[sign_idx % signs_display.size()]

    var result: int = 0
    match sign_idx:
        0: result = a + b
        1: result = a - b
        2: result = a * b

    var equation = "%d%s%d=%d" % [a, sign_str, b, result]
    print("COMBO! ", equation)

    # Mark points as merging (prevents double-combo)
    for p in numbers:
        p.set_meta("is_merging", true)
    sign_point.set_meta("is_merging", true)
```

**Step 6: Run the game at Stage 2. Label multiple data points with cursor. When 2 numbers + 1 sign are labeled within the combo window, verify "COMBO!" prints in console.**

**Step 7: Commit**

```bash
git add scripts/data_spawner.gd
git commit -m "feat: combo detection system — identifies 2 numbers + 1 sign triples"
```

---

### Task 6: Combo Merge Animation & Purple Equation Points

**Files:**
- Modify: `scripts/data_point.gd`
- Modify: `scripts/data_spawner.gd`

**Step 1: Add merge animation state to `data_point.gd`**

Add these fields after the existing animation state variables (after line 32):

```gdscript
# Combo merge state
var is_merging: bool = false
var merge_target: Vector2 = Vector2.ZERO
var merge_timer: float = 0.0
const MERGE_DURATION = 0.3
var is_combo: bool = false
var combo_cash: int = 0
var merge_fade: bool = false  # True for the 2 points that fade out
```

**Step 2: Add merge animation in `_process()` — right after the spawn fade-in block (after line 49)**

Insert this block after `spawn_timer += delta` and before the discover flash decay:

```gdscript
# Combo merge animation
if is_merging:
    merge_timer += delta
    var t = clampf(merge_timer / MERGE_DURATION, 0.0, 1.0)
    # Slide toward merge target
    global_position = global_position.lerp(merge_target, t * 0.15)
    if merge_timer >= MERGE_DURATION:
        if merge_fade:
            queue_free()
            return
        else:
            # This point becomes the combo point
            is_merging = false
            is_combo = true
            base_color = Color(0.7, 0.3, 1.0)  # Purple
            data_class = 2  # Route to Equations output
            # Rebuild traversal path to equations node
            if network_ref and network_ref.has_method("get_traversal_path"):
                traversal_path = network_ref.get_traversal_path(2)
                current_waypoint = 0
                if traversal_path.size() > 0:
                    target_position = traversal_path[0]
    queue_redraw()
    return
```

**Step 3: Update `_on_consumed()` — combo cash override**

Replace the `_on_consumed()` function:

```gdscript
func _on_consumed() -> void:
    is_consumed = true
    consume_timer = 0.0
    var earned: int
    if is_combo:
        earned = combo_cash
    elif is_augmented:
        earned = int(GameData.get_cash_per_point() * 0.5 * cash_multiplier)
    else:
        earned = int(GameData.get_cash_per_point() * cash_multiplier)
    cached_cash_earned = earned
    consumed.emit(earned)
```

**Step 4: Update `_draw()` — purple color for combo points**

In the labeled section of `_draw()` (line 215 area), update the text color to use `base_color` (which is already set to purple for combos). The existing code already uses `base_color` for `text_color`, so this should work automatically. But add a larger font for equations:

Replace the font_size line (line 224):

```gdscript
var font_size = 13 if is_augmented else (14 if is_combo else 18)
```

Also add a purple glow behind combo points. After the discover flash block (around line 220), add:

```gdscript
# Combo glow
if is_combo:
    draw_circle(Vector2.ZERO, 18.0, Color(0.7, 0.3, 1.0, 0.15 + (sin(spawn_timer * 4.0) + 1.0) * 0.05))
```

**Step 5: Update `_trigger_combo()` in `data_spawner.gd` — replace the stub with full merge logic**

Replace the `_trigger_combo()` method:

```gdscript
func _trigger_combo(numbers: Array, sign_point: Area2D) -> void:
    var a = numbers[0].digit_value
    var b = numbers[1].digit_value
    var sign_idx = sign_point.digit_value
    var signs_display = ["+", "−", "×"]
    var sign_str = signs_display[sign_idx % signs_display.size()]

    var result: int = 0
    match sign_idx:
        0: result = a + b
        1: result = a - b
        2: result = a * b

    var equation = "%d%s%d=%d" % [a, sign_str, b, result]

    # Calculate combo cash: 2× sum of 3 individual points
    var combo_cash = GameData.get_combo_cash(3)

    # Calculate merge center
    var center = (numbers[0].global_position + numbers[1].global_position + sign_point.global_position) / 3.0

    # Set merge state — sign_point becomes the combo host, numbers fade out
    sign_point.is_merging = true
    sign_point.merge_target = center
    sign_point.merge_fade = false
    sign_point.display_value = equation
    sign_point.combo_cash = combo_cash
    sign_point.is_labeled = true

    for p in numbers:
        p.is_merging = true
        p.merge_target = center
        p.merge_fade = true  # These fade out

    # Spawn a brief flash at merge point
    var flash_timer = Timer.new()
    flash_timer.wait_time = 0.3
    flash_timer.one_shot = true
    get_tree().current_scene.add_child(flash_timer)
    flash_timer.timeout.connect(func():
        _spawn_merge_flash(center)
        flash_timer.queue_free()
    )
    flash_timer.start()


func _spawn_merge_flash(pos: Vector2) -> void:
    # Brief purple flash at combo merge point
    var flash = Node2D.new()
    flash.global_position = pos
    flash.set_script(null)
    get_tree().current_scene.add_child(flash)

    # Use a tween to fade it
    var tween = flash.create_tween()
    tween.tween_interval(0.2)
    tween.tween_callback(flash.queue_free)
```

**Step 6: Run the game at Stage 2. Label 2 numbers + 1 sign simultaneously. Verify:**
- The 3 points slide toward their center
- 2 fade out, 1 transforms into a purple equation (e.g. "3+7=10")
- The purple point flies to the Equations output node
- Cash earned is 2× normal

**Step 7: Commit**

```bash
git add scripts/data_point.gd scripts/data_spawner.gd
git commit -m "feat: combo merge animation — purple equation points with 2× cash"
```

---

### Task 7: Stage Transition — 10→3 Output Node Collapse

**Files:**
- Modify: `scripts/network.gd`

**Step 1: Add transition state tracking**

Add these variables after `stage_transition_timer` (line 7):

```gdscript
var prev_output_positions: Array = []  # Stores old output node positions for collapse animation
var transition_phase: int = 0  # 0=none, 1=collapsing old, 2=expanding new
```

**Step 2: Update `on_stage_changed()` to capture old positions before regenerating**

Replace `on_stage_changed()`:

```gdscript
func on_stage_changed() -> void:
    # Capture old output positions for collapse animation
    if node_positions.size() > 0:
        prev_output_positions = node_positions[node_positions.size() - 1].duplicate()
    else:
        prev_output_positions = []
    transition_phase = 1  # Start with collapse
    stage_transition_timer = STAGE_TRANSITION_DURATION
    _generate_network()
```

**Step 3: Update the output node drawing in `_draw()` to handle the collapse-then-expand animation**

Replace the block that handles output node transition animation (around line 218):

```gdscript
# Animate output nodes during stage transition
if layer_idx == total_layers - 1 and stage_transition_timer > 0:
    var progress = 1.0 - (stage_transition_timer / STAGE_TRANSITION_DURATION)
    if prev_output_positions.size() > node_positions[layer_idx].size():
        # Collapsing (e.g. 10→3): scale up from 0 in second half
        var expand_t = clampf((progress - 0.4) / 0.6, 0.0, 1.0)
        radius *= expand_t
    else:
        # Expanding: existing behavior
        radius *= clampf(progress * 2.0, 0.0, 1.0)
```

**Step 4: Draw collapsing old output nodes during first half of transition**

In `_draw()`, after the main node drawing loop ends but before the output label section, add:

```gdscript
# Draw collapsing old output nodes during transition
if stage_transition_timer > 0 and prev_output_positions.size() > 0:
    var progress = 1.0 - (stage_transition_timer / STAGE_TRANSITION_DURATION)
    var collapse_t = clampf(progress / 0.4, 0.0, 1.0)  # Collapse in first 40% of transition
    if collapse_t < 1.0:
        var center_x = 0.0
        for p in prev_output_positions:
            center_x += p.x
        center_x /= maxf(prev_output_positions.size(), 1)
        var center_y = 0.0
        for p in prev_output_positions:
            center_y += p.y
        center_y /= maxf(prev_output_positions.size(), 1)
        var collapse_center = Vector2(center_x, center_y)

        for old_pos in prev_output_positions:
            var collapsed_pos = old_pos.lerp(collapse_center, collapse_t)
            var old_radius = 8.0 * (1.0 - collapse_t)
            if old_radius > 0.5:
                var old_alpha = 1.0 - collapse_t
                var old_color = Color(0.4, 0.4, 0.5, old_alpha * 0.6)
                draw_circle(collapsed_pos, old_radius, old_color)
```

**Step 5: Run the game. Progress from Stage 1 to Stage 2. Verify the old 10 output nodes visually collapse toward center, then 3 new output nodes (Num, Sign, Eq) expand outward.**

**Step 6: Commit**

```bash
git add scripts/network.gd
git commit -m "feat: collapse-then-expand output node transition for Stage 2"
```

---

### Task 8: Integration & Polish

**Files:**
- Modify: `scripts/data_spawner.gd`
- Modify: `scripts/data_point.gd`

**Step 1: Clear combo buffer on round end**

In `data_spawner.gd`, update `clear_all_points()`:

```gdscript
func clear_all_points() -> void:
    for point in active_points:
        if is_instance_valid(point):
            point.queue_free()
    active_points.clear()
    batch_remaining = 0
    recently_labeled.clear()
```

**Step 2: Prevent combo points from triggering batch label**

In `_on_point_discovered()`, skip batch labeling for points that are about to merge. The `is_merging` meta check in `_check_combo` handles this, but also add a guard in the batch label loop:

After the combo detection block, before the batch label section, add:

```gdscript
# Don't trigger batch label for points that are part of a combo
if source_point.has_meta("is_merging") or source_point.is_merging:
    return
```

**Step 3: Handle consumed signal for combo points properly**

In `data_spawner.gd`, the combo host's `consumed` signal is already connected from when it was spawned as a normal point. The `_on_point_consumed` callback will fire with the combo_cash amount. Verify the accuracy addition works:

The combo point should give accuracy scaled to the combo. Update `_on_point_consumed` to give bonus accuracy for combos:

```gdscript
func _on_point_consumed(cash_earned: int, point: Area2D) -> void:
    GameData.add_cash(cash_earned)
    var accuracy_amount = GameData.get_accuracy_per_point()
    if is_instance_valid(point) and point.is_combo:
        accuracy_amount *= 3.0  # Combo counts as 3 points of accuracy
    GameData.add_accuracy(accuracy_amount)

    # Augmentation — only non-augmented, non-combo data can spawn copies
    if is_instance_valid(point) and not point.is_augmented and not point.is_combo:
        var aug_chance = GameData.get_aug_chance()
        if aug_chance > 0.0 and randf() < aug_chance:
            _spawn_aug_point()
```

**Step 4: Update consume animation text for combos — show purple "COMBO +$X" instead of green "+$X"**

In `data_point.gd`, in the `_draw()` consume animation section (around line 211), update the text color:

```gdscript
var text_color = Color(0.7, 0.3, 1.0, text_alpha) if is_combo else Color(0.3, 1.0, 0.4, text_alpha)
var cash_text = ("COMBO +$%d" if is_combo else "+$%d") % cached_cash_earned
```

**Step 5: Full playtest. Verify:**
- [ ] Stage 0 (Binary): Blue, 0/1, 2 output nodes — unchanged
- [ ] Stage 1 (Numbers): Green, 0-9, 10 output nodes — unchanged
- [ ] Stage 2 (Math): Purple stage color, mix of numbers and signs spawning
- [ ] Individual labels: Green text, fly to Numbers or Signs output node
- [ ] Combo: 2 numbers + 1 sign under cursor → merge into purple equation
- [ ] Combo scoring: 2× the sum of individual point values
- [ ] Equations output node: Purple glow/shimmer
- [ ] Stage transition 1→2: Old 10 outputs collapse, 3 new outputs expand
- [ ] Combo points show "COMBO +$X" in purple on consume
- [ ] Combo buffer clears between rounds
- [ ] Augmentation doesn't trigger from combo points

**Step 6: Commit**

```bash
git add scripts/data_spawner.gd scripts/data_point.gd
git commit -m "feat: integrate Stage 2 Math — combo scoring, polish, edge cases"
```

---

## Execution Notes

- Tasks 1-3 are foundational — do them sequentially
- Task 4 (network) can be done in parallel with Task 2-3 but depends on Task 1
- Task 5 (combo detection) depends on Tasks 2-3
- Task 6 (merge animation) depends on Task 5
- Task 7 (transition animation) is independent after Task 1
- Task 8 (integration) is last

## File Change Summary

| File | Tasks |
|------|-------|
| `scripts/game_data.gd` | 1 |
| `scripts/data_point.gd` | 2, 6, 8 |
| `scripts/data_spawner.gd` | 3, 5, 6, 8 |
| `scripts/network.gd` | 4, 7 |
