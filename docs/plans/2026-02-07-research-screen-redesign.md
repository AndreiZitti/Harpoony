# Research Screen Redesign

## Goal

Replace the flat category-based tree layout with a radial neural-network graph.
Drop the explicit NETWORK / DATA / PLAYER categories. Add effect previews to the tooltip.

## Layout: Radial Graph

The RESEARCH root sits at screen center. Upgrade nodes radiate outward
in concentric rings. No category nodes — related upgrades cluster
naturally through spatial proximity and shared connections.

### Rings

| Ring | Distance | Contents |
|------|----------|----------|
| Center | 0 | "RESEARCH" root node (small, decorative) |
| Ring 1 | ~130px | Stage 1 upgrades: Nodes, Layers, Dataset Size, Data Quality, Cursor Size, Label Speed |
| Ring 2 | ~250px | Stage 2 upgrades: Activation, Learn Rate, Aug. Chance, Batch Label |
| Ring 3 | ~350px | Deep upgrades: Aug. Quality, future upgrades (Training Time, etc.) |

### Angular placement

Upgrades are spread around 360 degrees. Thematically related upgrades
sit in the same arc (network-related roughly upper-left, data upper-right,
player bottom) but there are no dividing lines or labels enforcing this.

Approximate angular zones:
- ~210-330 deg: network-related (Nodes, Layers, Activation, Learn Rate)
- ~330-90 deg: data-related (Dataset Size, Data Quality, Aug. Chance, Aug. Quality)
- ~90-210 deg: player-related (Cursor Size, Label Speed, Batch Label)

New upgrades (like Training Time) slot into the appropriate arc at the
appropriate ring distance.

### Edges

Each upgrade connects to what it depends on or extends:
- Root -> all Ring 1 nodes
- Nodes -> Activation (network upgrade chain)
- Aug. Chance -> Aug. Quality (prerequisite chain)
- Category adjacency edges are removed entirely

## Node Visuals

### Shape

Uniform circles, ~50px diameter. Replaces the current 120x58 rectangles.

### Anatomy (top to bottom)

```
    ( Ab )       <- circle with 1-2 letter abbreviation
   Name          <- label, 12px, below circle
   50 CP         <- cost, 10px, colored by affordability
```

### Level progress

A radial arc ring drawn around the circle border. Empty at level 0,
full circle at max level. Replaces the small dot pips.

Arc length = (current_level / max_level) * TAU, drawn clockwise from top.

### Color states

| State | Circle fill | Ring/border | Cost text |
|-------|------------|-------------|-----------|
| Locked | Color(0.08, 0.08, 0.1, 0.5) | none | hidden |
| Available | Color(0.1, 0.12, 0.2, 0.9) | thin dim outline | red-ish |
| Affordable | Color(0.12, 0.15, 0.28, 0.95) | bright blue, gentle pulse | green |
| Owned (can't afford next) | Color(0.15, 0.2, 0.35, 0.95) | partial bright arc | red-ish |
| Owned + affordable | Color(0.15, 0.2, 0.35, 0.95) | partial arc + pulse | green |
| Maxed | Color(0.2, 0.35, 0.25, 0.95) | full arc, steady cyan glow | "MAX" gold |

### Hover effect

- Circle lightens ~12%
- Border alpha increases
- Tooltip appears

### Node abbreviations

| Key | Abbreviation |
|-----|-------------|
| nodes | Nd |
| layers | Ly |
| dataset_size | DS |
| data_quality | DQ |
| cursor_size | Cs |
| label_speed | Ls |
| activation_func | Ac |
| learning_rate | Lr |
| aug_chance | Au |
| aug_quality | AQ |
| batch_label | Bl |

## Edge Visuals

| Target state | Style | Width | Alpha |
|-------------|-------|-------|-------|
| Locked | dashed / dotted | 1.0 | 0.1 |
| Available | solid | 1.5 | 0.25 |
| Affordable | solid | 2.0 | 0.5 |
| Owned | solid + subtle glow | 2.0 | 0.6 |
| Maxed | solid + bright glow | 2.5 | 0.7 |

Bright edges (owned+) get a secondary wider line underneath at low alpha
for a glow effect, same as current implementation.

### Appear animation

New nodes (stage unlock) animate in over 0.8s:
- Scale from 50% to 100%
- Alpha fade in
- Connected edge alpha also fades in
(Same behavior as current, adapted to circles.)

## Tooltip: Effect Preview

Tooltip appears on hover, positioned to the right of the node (flips left
if near screen edge, same logic as current).

### Layout

```
+-----------------------------+
|  Node Name          Lv N/M  |
|  Description text           |
|                             |
|  Stat A:  current -> next   |
|  Stat B:  current -> next   |
|                             |
|  Cost: X CP                 |
+-----------------------------+
```

### Effect preview data

Each upgrade maps to 1-2 preview lines showing current -> next level values.
A new function `get_effect_preview(key) -> Array[String]` in game_data.gd
returns these strings.

| Upgrade | Preview lines |
|---------|--------------|
| nodes | "Neurons/layer: N -> N+1", "Accuracy/pt: X -> Y" |
| layers | "Hidden layers: N -> N+1", "Accuracy/pt: X -> Y" |
| dataset_size | "Points/round: N -> N+5" |
| data_quality | "Quality mult: x.xx -> x.xx" |
| cursor_size | "Cursor radius: Npx -> Npx" |
| label_speed | "Label time: X.Xs -> X.Xs", "Speed: N -> N" |
| activation_func | "Activation mult: x.x -> x.x" |
| learning_rate | "LR mult: x.x -> x.x" |
| aug_chance | "Aug chance: N% -> N%" |
| aug_quality | "Aug mult: x.x -> x.x" |
| batch_label | "Batch chance: N% -> N%" |

For maxed upgrades: show final values only (no arrow).
For locked upgrades: show "Requires: <prereq name>" instead.

### Tooltip style

Same dark panel style as current, with blue border.
Slightly wider (220px min width) to fit effect preview lines.

## Header & Bottom Bar

**Header** stays the same: compute counter + round label, top center.

**Bottom bar** stays the same: cheats toggle (left) + START TRAINING button (right).

No other changes to these elements.

## What Gets Removed

- `category_keys` array and `category_labels` dictionary
- `_draw_category_node()` function
- `_is_category()` helper
- `CAT_SIZE` constant
- All `cat_*` entries from position layout

## What Gets Added

- `NODE_RADIUS = 25.0` constant (replaces NODE_SIZE)
- Radial position calculation in `_get_tree_layout()`
- `_draw_node_circle()` function replacing `_draw_upgrade_node()`
- Radial level arc drawing logic
- `get_effect_preview(key)` function in game_data.gd
- Updated tooltip layout with effect preview section
- Node abbreviation dictionary

## What Gets Modified

- `_get_tree_layout()` — radial positions, no category nodes
- `_draw_tree()` — call new circle draw function
- `_draw_edge()` — dashed line support for locked targets
- `_update_tooltip()` — add effect preview lines
- `_process()` — hit detection uses circle radius instead of rectangle
- `_build_tooltip()` — add effect preview label(s) to tooltip vbox
