# Research Screen Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the flat category-based upgrade tree with a radial neural-network graph, circular nodes with level arcs, and effect-preview tooltips.

**Architecture:** Two files change: `game_data.gd` gets a new `get_effect_preview()` function, and `upgrade_shop.gd` is rewritten to use radial layout with circular nodes. The rewrite is done in-place — same file, same class, same signals.

**Tech Stack:** Godot 4.6 / GDScript. All rendering is custom `_draw()` calls on a Control node.

**Design doc:** `docs/plans/2026-02-07-research-screen-redesign.md`

---

### Task 1: Add `get_effect_preview()` to game_data.gd

**Files:**
- Modify: `scripts/game_data.gd` (add function at end, before closing)

**Step 1: Add the function**

Add this function at the end of `scripts/game_data.gd`:

```gdscript
func get_effect_preview(key: String) -> Array:
	var level = upgrade_levels[key]
	var max_level = upgrades[key]["max_level"]
	var is_maxed = level >= max_level

	match key:
		"nodes":
			var cur = neurons_per_layer
			if is_maxed:
				return ["Neurons/layer: %d" % cur]
			return ["Neurons/layer: %d → %d" % [cur, cur + 1]]
		"layers":
			var cur = num_hidden_layers
			if is_maxed:
				return ["Hidden layers: %d" % cur]
			return ["Hidden layers: %d → %d" % [cur, cur + 1]]
		"dataset_size":
			var cur = get_dataset_size()
			if is_maxed:
				return ["Points/round: %d" % cur]
			return ["Points/round: %d → %d" % [cur, cur + 5]]
		"data_quality":
			var cur = get_data_quality_multiplier()
			if is_maxed:
				return ["Quality mult: x%.2f" % cur]
			var nxt = 1.0 + (level + 1) * 0.25
			return ["Quality mult: x%.2f → x%.2f" % [cur, nxt]]
		"cursor_size":
			var cur = get_cursor_radius()
			if is_maxed:
				return ["Cursor radius: %dpx" % int(cur)]
			var nxt = 25.0 + (level + 1) * 8.0
			return ["Cursor radius: %dpx → %dpx" % [int(cur), int(nxt)]]
		"label_speed":
			var cur_time = get_label_time()
			if is_maxed:
				return ["Label time: %.1fs" % cur_time]
			var base = stages[current_stage]["label_time"]
			var nxt_reduction = 1.0 - (level + 1) * 0.08
			var nxt_time = base * maxf(nxt_reduction, 0.2)
			return ["Label time: %.1fs → %.1fs" % [cur_time, nxt_time]]
		"activation_func":
			var cur = get_activation_multiplier()
			if is_maxed:
				return ["Activation mult: x%.1f" % cur]
			var nxt = 1.0 + (level + 1) * 0.3
			return ["Activation mult: x%.1f → x%.1f" % [cur, nxt]]
		"learning_rate":
			var cur = get_learning_rate_multiplier()
			if is_maxed:
				return ["LR mult: x%.1f" % cur]
			var nxt = 1.0 + (level + 1) * 0.2
			return ["LR mult: x%.1f → x%.1f" % [cur, nxt]]
		"aug_chance":
			var cur = get_aug_chance() * 100.0
			if is_maxed:
				return ["Aug chance: %d%%" % int(cur)]
			var nxt = (level + 1) * 15.0
			return ["Aug chance: %d%% → %d%%" % [int(cur), int(nxt)]]
		"aug_quality":
			var cur = get_aug_quality_multiplier()
			if is_maxed:
				return ["Aug mult: x%.1f" % cur]
			var nxt = 1.0 + (level + 1) * 0.5
			return ["Aug mult: x%.1f → x%.1f" % [cur, nxt]]
		"batch_label":
			var cur = get_batch_label_chance() * 100.0
			if is_maxed:
				return ["Batch chance: %d%%" % int(cur)]
			var nxt = (level + 1) * 12.0
			return ["Batch chance: %d%% → %d%%" % [int(cur), int(nxt)]]
	return []
```

**Step 2: Verify**

Run the game. Open the research screen. No visual change yet — this just adds a data function. Confirm no errors in the Godot console.

**Step 3: Commit**

```bash
git add scripts/game_data.gd
git commit -m "feat: add get_effect_preview() for upgrade tooltip data"
```

---

### Task 2: Replace constants, remove category system, add abbreviations

**Files:**
- Modify: `scripts/upgrade_shop.gd` (top section, lines 1-30)

**Step 1: Replace the top section of upgrade_shop.gd**

Replace everything from `var hovered_node` through `var category_labels` (lines 13-26) with:

```gdscript
var hovered_node: String = ""

# Visual config — circular nodes
const NODE_RADIUS = 25.0

# Node abbreviations displayed inside circles
var node_abbreviations: Dictionary = {
	"nodes": "Nd",
	"layers": "Ly",
	"dataset_size": "DS",
	"data_quality": "DQ",
	"cursor_size": "Cs",
	"label_speed": "Ls",
	"activation_func": "Ac",
	"learning_rate": "Lr",
	"aug_chance": "Au",
	"aug_quality": "AQ",
	"batch_label": "Bl",
}
```

This removes: `NODE_SIZE`, `CAT_SIZE`, `category_keys`, `category_labels`.

**Step 2: Remove `_is_category()` function**

Delete lines 178-179:
```gdscript
func _is_category(key: String) -> bool:
	return key in category_keys
```

**Step 3: Commit**

```bash
git add scripts/upgrade_shop.gd
git commit -m "refactor: remove category system, add node abbreviations and circle constants"
```

---

### Task 3: Rewrite `_get_tree_layout()` to radial positions

**Files:**
- Modify: `scripts/upgrade_shop.gd` — replace `_get_tree_layout()` function (lines 512-555)

**Step 1: Replace `_get_tree_layout()` with radial layout**

```gdscript
func _get_tree_layout() -> Dictionary:
	var positions: Dictionary = {}
	var edges: Array = []

	# Root at center
	positions["root"] = Vector2(0, 0)

	# Ring 1 — Stage 1 upgrades, ~130px from center
	# Network zone: ~240-300 deg
	# Data zone: ~340-40 deg
	# Player zone: ~100-160 deg
	var ring1_r = 130.0
	positions["nodes"] = Vector2(ring1_r, 0).rotated(deg_to_rad(250))
	positions["layers"] = Vector2(ring1_r, 0).rotated(deg_to_rad(290))
	positions["dataset_size"] = Vector2(ring1_r, 0).rotated(deg_to_rad(345))
	positions["data_quality"] = Vector2(ring1_r, 0).rotated(deg_to_rad(25))
	positions["cursor_size"] = Vector2(ring1_r, 0).rotated(deg_to_rad(110))
	positions["label_speed"] = Vector2(ring1_r, 0).rotated(deg_to_rad(150))

	# Root connects to all Ring 1
	for key in ["nodes", "layers", "dataset_size", "data_quality", "cursor_size", "label_speed"]:
		edges.append(["root", key])

	# Ring 2 — Stage 2 upgrades, ~250px from center
	if GameData.current_stage >= 1:
		var ring2_r = 250.0
		positions["activation_func"] = Vector2(ring2_r, 0).rotated(deg_to_rad(240))
		positions["learning_rate"] = Vector2(ring2_r, 0).rotated(deg_to_rad(280))
		positions["aug_chance"] = Vector2(ring2_r, 0).rotated(deg_to_rad(5))
		positions["batch_label"] = Vector2(ring2_r, 0).rotated(deg_to_rad(130))

		# Stage 2 edges — connect to thematic parents
		edges.append(["nodes", "activation_func"])
		edges.append(["layers", "learning_rate"])
		edges.append(["data_quality", "aug_chance"])
		edges.append(["label_speed", "batch_label"])

		# Ring 3 — deep chain, ~350px
		var ring3_r = 350.0
		positions["aug_quality"] = Vector2(ring3_r, 0).rotated(deg_to_rad(5))
		edges.append(["aug_chance", "aug_quality"])

	return {"positions": positions, "edges": edges}
```

**Step 2: Verify**

Run the game. The tree will look broken (still drawing rectangles for upgrade nodes), but positions should be radial. Category nodes will error since `_is_category` and `_draw_category_node` are gone — fix in next task.

**Step 3: Commit**

```bash
git add scripts/upgrade_shop.gd
git commit -m "feat: radial tree layout — upgrades on concentric rings"
```

---

### Task 4: Rewrite `_draw_tree()` and node drawing to circles

**Files:**
- Modify: `scripts/upgrade_shop.gd` — replace `_draw_tree()`, `_draw_upgrade_node()`, delete `_draw_category_node()`

**Step 1: Replace `_draw_tree()`**

```gdscript
func _draw_tree() -> void:
	var font = ThemeDB.fallback_font
	var time = Time.get_ticks_msec() / 1000.0

	# 1. Draw edges
	for edge in current_layout["edges"]:
		_draw_edge(edge[0], edge[1], time)

	# 2. Draw root node (small decorative circle)
	if "root" in current_layout["positions"]:
		var root_pos = _get_node_screen_pos("root")
		tree_canvas.draw_circle(root_pos, 12.0, Color(0.15, 0.2, 0.35, 0.9))
		tree_canvas.draw_arc(root_pos, 12.0, 0, TAU, 32, Color(0.3, 0.5, 0.8, 0.6), 1.5)
		var r_text = "R"
		var r_size = font.get_string_size(r_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		tree_canvas.draw_string(font, root_pos - Vector2(r_size.x / 2.0, -4), r_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.7, 1.0, 0.8))

	# 3. Draw upgrade nodes
	for key in current_layout["positions"]:
		if key != "root":
			_draw_node_circle(key, font, time)
```

**Step 2: Delete `_draw_category_node()` entirely** (lines 360-372)

**Step 3: Replace `_draw_upgrade_node()` with `_draw_node_circle()`**

Replace the entire `_draw_upgrade_node` function with:

```gdscript
func _draw_node_circle(key: String, font: Font, time: float) -> void:
	if key not in GameData.upgrades:
		return
	var pos = _get_node_screen_pos(key)
	var upgrade = GameData.upgrades[key]
	var level = GameData.upgrade_levels[key]
	var max_level = upgrade["max_level"]
	var state = _get_upgrade_state(key)
	var is_hover = key == hovered_node

	# Appear animation
	var appear_progress = 1.0
	if key in node_appear_timers:
		appear_progress = clampf(node_appear_timers[key] / NODE_APPEAR_DURATION, 0.0, 1.0)

	var draw_radius = NODE_RADIUS * (0.5 + 0.5 * appear_progress)

	# Colors based on state
	var fill_color: Color
	var ring_color: Color
	var name_color: Color
	var cost_color: Color

	match state:
		"locked":
			fill_color = Color(0.08, 0.08, 0.1, 0.5)
			ring_color = Color(0.15, 0.15, 0.2, 0.0)
			name_color = Color(0.3, 0.3, 0.38)
			cost_color = Color(0.0, 0.0, 0.0, 0.0)  # hidden
		"available":
			fill_color = Color(0.1, 0.12, 0.2, 0.9)
			ring_color = Color(0.25, 0.3, 0.5, 0.4)
			name_color = Color(0.5, 0.5, 0.6)
			cost_color = Color(0.6, 0.3, 0.3)
		"affordable":
			fill_color = Color(0.12, 0.15, 0.28, 0.95)
			ring_color = Color(0.3, 0.5, 0.9, 0.7)
			name_color = Color(0.8, 0.85, 1.0)
			cost_color = Color(0.3, 1.0, 0.4)
		"owned":
			fill_color = Color(0.15, 0.2, 0.35, 0.95)
			ring_color = Color(0.3, 0.55, 1.0, 0.6)
			name_color = Color.WHITE
			cost_color = Color(0.6, 0.3, 0.3)
		"owned_affordable":
			fill_color = Color(0.15, 0.2, 0.35, 0.95)
			ring_color = Color(0.3, 0.55, 1.0, 0.6)
			name_color = Color.WHITE
			cost_color = Color(0.3, 1.0, 0.4)
		"maxed":
			fill_color = Color(0.2, 0.35, 0.25, 0.95)
			ring_color = Color(0.3, 0.9, 0.7, 0.7)
			name_color = Color(0.7, 1.0, 0.6)
			cost_color = Color(0.5, 0.85, 0.3)

	# Hover effect
	if is_hover and state != "locked":
		fill_color = fill_color.lightened(0.12)
		ring_color.a = minf(ring_color.a + 0.25, 1.0)

	# Appear fade
	if appear_progress < 1.0:
		fill_color.a *= appear_progress
		ring_color.a *= appear_progress
		name_color.a *= appear_progress
		cost_color.a *= appear_progress

	# Pulsing glow for affordable nodes
	if state in ["affordable", "owned_affordable"]:
		var pulse = (sin(time * 3.0) + 1.0) / 2.0
		var glow_r = draw_radius + 4 + pulse * 4
		tree_canvas.draw_circle(pos, glow_r, Color(0.3, 0.6, 1.0, 0.06 + pulse * 0.05))

	# Fill circle
	tree_canvas.draw_circle(pos, draw_radius, fill_color)

	# Outer ring (thin border)
	if ring_color.a > 0.01:
		tree_canvas.draw_arc(pos, draw_radius, 0, TAU, 32, ring_color, 1.5)

	# Radial level arc — progress ring
	if level > 0 and state != "locked":
		var arc_angle = (float(level) / float(max_level)) * TAU
		var start_angle = -PI / 2.0  # start from top
		var arc_color = ring_color.lightened(0.2)
		if state == "maxed":
			arc_color = Color(0.3, 0.9, 0.7, 0.8)
		tree_canvas.draw_arc(pos, draw_radius + 3, start_angle, start_angle + arc_angle, 32, arc_color, 2.5)

	# Abbreviation inside circle
	var abbr = node_abbreviations.get(key, "?")
	var abbr_fs = 13
	var abbr_size = font.get_string_size(abbr, HORIZONTAL_ALIGNMENT_LEFT, -1, abbr_fs)
	var abbr_pos = Vector2(pos.x - abbr_size.x / 2.0, pos.y + 5)
	tree_canvas.draw_string(font, abbr_pos, abbr, HORIZONTAL_ALIGNMENT_LEFT, -1, abbr_fs, name_color)

	# Name below circle
	var name_text = upgrade["name"]
	var name_fs = 11
	var name_size = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs)
	var name_pos = Vector2(pos.x - name_size.x / 2.0, pos.y + draw_radius + 14)
	tree_canvas.draw_string(font, name_pos, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs, name_color)

	# Cost below name
	var cost_text = ""
	if state == "maxed":
		cost_text = "MAX"
		cost_color = Color(0.5, 0.85, 0.3)
	elif state != "locked":
		var cost = GameData.get_upgrade_cost(key)
		if cost > 0:
			cost_text = "%d CP" % cost
	if cost_text != "":
		var cost_fs = 10
		var cost_size = font.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, cost_fs)
		var cost_pos = Vector2(pos.x - cost_size.x / 2.0, pos.y + draw_radius + 26)
		tree_canvas.draw_string(font, cost_pos, cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, cost_fs, cost_color)
```

**Step 4: Verify**

Run the game. Research screen should now show circular nodes in a radial layout with level arcs, abbreviations inside, and name+cost below. Root is a small circle at center.

**Step 5: Commit**

```bash
git add scripts/upgrade_shop.gd
git commit -m "feat: circular node rendering with radial level arcs and abbreviations"
```

---

### Task 5: Update edge drawing with dashed lines for locked

**Files:**
- Modify: `scripts/upgrade_shop.gd` — replace `_draw_edge()` function

**Step 1: Replace `_draw_edge()`**

```gdscript
func _draw_edge(from_key: String, to_key: String, time: float) -> void:
	var from_pos = _get_node_screen_pos(from_key)
	var to_pos = _get_node_screen_pos(to_key)

	# Determine style from target node state
	var line_alpha = 0.15
	var line_width = 1.5
	var is_dashed = false

	if to_key == "root" or from_key == "root":
		# Edges from root to Ring 1
		if to_key != "root" and to_key in GameData.upgrades:
			var state = _get_upgrade_state(to_key)
			match state:
				"locked":
					line_alpha = 0.1
					line_width = 1.0
					is_dashed = true
				"available":
					line_alpha = 0.25
					line_width = 1.5
				"affordable":
					line_alpha = 0.5
					line_width = 2.0
				"owned", "owned_affordable":
					line_alpha = 0.6
					line_width = 2.0
				"maxed":
					line_alpha = 0.7
					line_width = 2.5
		else:
			line_alpha = 0.3
	elif to_key in GameData.upgrades:
		var state = _get_upgrade_state(to_key)
		match state:
			"locked":
				line_alpha = 0.1
				line_width = 1.0
				is_dashed = true
			"available":
				line_alpha = 0.25
				line_width = 1.5
			"affordable":
				line_alpha = 0.5
				line_width = 2.0
			"owned", "owned_affordable":
				line_alpha = 0.6
				line_width = 2.0
			"maxed":
				line_alpha = 0.7
				line_width = 2.5

	var line_color = Color(0.3, 0.5, 0.8, line_alpha)

	# Fade edge during node appearance
	if to_key in node_appear_timers:
		var edge_progress = clampf(node_appear_timers[to_key] / NODE_APPEAR_DURATION, 0.0, 1.0)
		line_color.a *= edge_progress

	if is_dashed:
		# Draw dashed line
		var direction = (to_pos - from_pos)
		var length = direction.length()
		var norm = direction / length
		var dash_len = 6.0
		var gap_len = 4.0
		var d = 0.0
		while d < length:
			var seg_start = from_pos + norm * d
			var seg_end = from_pos + norm * minf(d + dash_len, length)
			tree_canvas.draw_line(seg_start, seg_end, line_color, line_width)
			d += dash_len + gap_len
	else:
		tree_canvas.draw_line(from_pos, to_pos, line_color, line_width)

	# Glow on bright edges
	if line_alpha > 0.4:
		var glow = 0.03 + sin(time * 1.5) * 0.02
		tree_canvas.draw_line(from_pos, to_pos, Color(0.4, 0.6, 1.0, glow), 5.0)
```

**Step 2: Verify**

Run the game. Edges should be dashed for locked/unavailable targets, solid for others, with glow on owned+.

**Step 3: Commit**

```bash
git add scripts/upgrade_shop.gd
git commit -m "feat: dashed edges for locked nodes, glow for owned connections"
```

---

### Task 6: Update hit detection from rectangle to circle

**Files:**
- Modify: `scripts/upgrade_shop.gd` — update `_process()` hover detection

**Step 1: Replace the hover detection loop in `_process()`**

In the `_process()` function, replace the hover detection block (the `for key in current_layout["positions"]` loop) with:

```gdscript
	for key in current_layout["positions"]:
		if key == "root":
			continue
		if key not in GameData.upgrades:
			continue
		var pos = _get_node_screen_pos(key)
		if mouse_pos.distance_to(pos) <= NODE_RADIUS:
			new_hover = key
```

**Step 2: Verify**

Run the game. Hover detection should work as circles — hovering near the edge of a node triggers the tooltip.

**Step 3: Commit**

```bash
git add scripts/upgrade_shop.gd
git commit -m "fix: circle-based hover detection for radial nodes"
```

---

### Task 7: Update tooltip with effect preview

**Files:**
- Modify: `scripts/upgrade_shop.gd` — update `_build_tooltip()` and `_update_tooltip()`

**Step 1: Add effect preview label to `_build_tooltip()`**

Add a new label between `tooltip_desc` and `tooltip_stats`. After the line that adds `tooltip_desc` to the vbox, add:

```gdscript
	tooltip_effect = Label.new()
	tooltip_effect.add_theme_font_size_override("font_size", 11)
	tooltip_effect.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))
	tooltip_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(tooltip_effect)
```

Also add `var tooltip_effect: Label` to the top of the file alongside the other tooltip vars (near line 10).

**Step 2: Update `_update_tooltip()` to show effect previews**

Replace the entire `_update_tooltip()` function:

```gdscript
func _update_tooltip() -> void:
	if hovered_node == "":
		tooltip_panel.visible = false
		return

	var upgrade = GameData.upgrades[hovered_node]
	var level = GameData.upgrade_levels[hovered_node]
	var max_level = upgrade["max_level"]
	var state = _get_upgrade_state(hovered_node)

	tooltip_name.text = "%s   Lv %d/%d" % [upgrade["name"], level, max_level]
	tooltip_desc.text = upgrade["description"]

	# Effect preview
	if state == "locked":
		tooltip_effect.text = ""
		tooltip_effect.visible = false
	else:
		var previews = GameData.get_effect_preview(hovered_node)
		tooltip_effect.text = "\n".join(previews)
		tooltip_effect.visible = true
		if state == "maxed":
			tooltip_effect.add_theme_color_override("font_color", Color(0.5, 0.85, 0.3))
		else:
			tooltip_effect.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))

	# Stats line (cost or status)
	if state == "locked":
		var prereq = GameData.upgrade_prerequisites[hovered_node]
		if prereq != "":
			var prereq_name = GameData.upgrades[prereq]["name"]
			tooltip_stats.text = "Requires: " + prereq_name
		else:
			tooltip_stats.text = "Locked"
		tooltip_stats.add_theme_color_override("font_color", Color(0.6, 0.4, 0.3))
	elif state == "maxed":
		tooltip_stats.text = "MAXED"
		tooltip_stats.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	else:
		var cost = upgrade["costs"][level]
		tooltip_stats.text = "Cost: %d CP" % cost
		if GameData.can_buy_upgrade(hovered_node):
			tooltip_stats.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		else:
			tooltip_stats.add_theme_color_override("font_color", Color(0.7, 0.35, 0.3))

	tooltip_panel.visible = true

	# Position tooltip near hovered node
	var node_pos = _get_node_screen_pos(hovered_node)
	var tip_pos = node_pos + Vector2(NODE_RADIUS + 14, -20)

	var tip_size = tooltip_panel.size
	if tip_pos.x + tip_size.x > tree_canvas.size.x - 20:
		tip_pos.x = node_pos.x - NODE_RADIUS - tip_size.x - 14
	if tip_pos.y < 80:
		tip_pos.y = 80
	if tip_pos.y + tip_size.y > tree_canvas.size.y - 80:
		tip_pos.y = tree_canvas.size.y - 80 - tip_size.y

	tooltip_panel.position = tip_pos
```

**Step 3: Update tooltip panel width**

In `_build_tooltip()`, change the minimum size:

```gdscript
	tooltip_panel.custom_minimum_size = Vector2(220, 0)
```

**Step 4: Verify**

Run the game. Hover over an upgrade node. Tooltip should show:
- Name with level
- Description
- Effect preview (e.g. "Neurons/layer: 1 → 2")
- Cost (colored green/red)

**Step 5: Commit**

```bash
git add scripts/upgrade_shop.gd
git commit -m "feat: tooltip with effect preview showing current → next values"
```

---

### Task 8: Final cleanup and verify

**Files:**
- Modify: `scripts/upgrade_shop.gd` — remove any dead code

**Step 1: Verify no remaining references to removed code**

Search for any remaining references to `_is_category`, `category_keys`, `category_labels`, `CAT_SIZE`, `NODE_SIZE`, `_draw_category_node`, `_draw_upgrade_node`. Remove any found.

**Step 2: Full playthrough test**

Run the game and verify:
1. Research screen shows radial graph with root at center
2. Ring 1 nodes visible (6 stage-1 upgrades) connected to root
3. Circular nodes with abbreviations inside, name + cost below
4. Hover shows tooltip with effect preview
5. Clicking affordable nodes purchases them
6. Level arcs grow after purchase
7. Enable cheats, buy enough to trigger stage 2
8. Stage 2 nodes animate in on Ring 2
9. Aug. Quality appears on Ring 3 connected to Aug. Chance
10. Dashed edges for locked nodes
11. START TRAINING button works

**Step 3: Commit**

```bash
git add scripts/upgrade_shop.gd scripts/game_data.gd
git commit -m "chore: cleanup dead code from research screen redesign"
```
