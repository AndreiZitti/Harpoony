# Stage 3: Math Operations — Design

**Goal:** Introduce a math operations stage where the player labels numbers and operation signs, with a combo mechanic that rewards simultaneously labeling valid equations.

**Tech Stack:** Godot 4.6, GDScript, custom 2D draw calls

---

## Stage Progression Context

| Stage | Name | Color | Data | Output Nodes |
|-------|------|-------|------|-------------|
| 0 | Binary | Blue `(0.3, 0.8, 1.0)` | 0, 1 | 2 |
| 1 | Numbers | Green `(0.3, 1.0, 0.5)` | 0-9 | 10 |
| **2** | **Math** | **Purple `(0.7, 0.3, 1.0)`** | **0-9, +, -, x** | **3** |

---

## Data Point Types

Stage 2 spawns a mixed pool of two data point categories:

- **Number points** (~75% of spawns): Display `0`-`9`, same digit set as Stage 1
- **Sign points** (~25% of spawns): Display `+`, `-`, or `x` (randomly chosen)

Both are gray circles when unlabeled (same as existing stages). When labeled individually, they turn **green** and fly to the network for normal points.

### Point Type Field

Each data point gets a `point_type` field:
- `"number"` — for digit data points
- `"sign"` — for operation sign data points

---

## Combo Mechanic

### Detection

The cursor scans all overlapping points in parallel via `apply_hover`. When data points finish labeling:

1. Check all points that completed labeling **in the same frame** (or within a 2-3 frame window)
2. Among those just-labeled points, check if there's a valid triple: exactly **2 numbers + 1 sign**
3. If yes -> combo fires
4. If there are extra points (e.g. 3 numbers + 1 sign), pick the best triple and label extras as green individuals

### Merge Animation

When a combo triggers:
1. The 3 individual points **stop in place**
2. They visually **slide toward their center point** over ~0.3s
3. They **merge into a single purple data point** displaying the equation (e.g. `3x7=21`)
4. The merged point flies through the network traversal path to the **Equations output node**
5. Brief flash/particle effect on merge for visual juice

### Scoring

- **2x the sum** of what the 3 individual points would have earned separately
- Example: if each green point earns 25 cash, a purple combo earns `3 x 25 x 2 = 150` cash
- All existing multipliers (data quality, activation, learning rate) apply to the base per-point value first, then the 2x combo multiplier applies on top
- Purple combo points are worth more than green individual points

---

## Network Output Nodes

Stage 2 has **3 output nodes** (down from 10 in Stage 1):

1. **Numbers** — individually labeled green number points fly here
2. **Signs** — individually labeled green sign points fly here
3. **Equations** — purple combo merges fly here; this node has a **glow/shimmer** effect to stand out

### Stage Transition Animation (Stage 1 -> Stage 2)

When the player advances from Stage 1 to Stage 2:
1. The 10 digit output nodes **collapse/merge** into a single "Numbers" node (visual animation)
2. A "Signs" output node **appears/grows** alongside
3. The **shiny "Equations"** output node **appears** with a glow effect

This visually communicates that the network is abstracting its understanding — instead of 10 individual digits, it now understands "number", "sign", and "equation" as concepts.

---

## Visual Design

### Colors
- **Green** `(0.3, 1.0, 0.5)`: Individual labeled points (numbers and signs) — same as Stage 1
- **Purple** `(0.7, 0.3, 1.0)`: Combo equation points and stage accent color
- Stage base color for network/HUD is **purple**

### Data Point Visuals
- **Unlabeled**: Gray circles (identical to other stages)
- **Labeled individually**: Green text (digit or sign symbol), flies to Numbers/Signs output
- **Combo merge**: Purple text showing equation (e.g. `3+7=10`), slightly larger font, purple glow trail

### Equations Output Node
- Brighter/shinier than other output nodes
- Subtle pulse or glow animation
- Visually distinct to reinforce that combos are the high-value mechanic

---

## File Changes

| File | Changes |
|------|---------|
| `scripts/data_point.gd` | Add `point_type` field, combo merge state, equation display, purple color rendering |
| `scripts/data_spawner.gd` | Mixed spawn logic (75/25 number/sign split), combo detection on simultaneous labels, merge orchestration |
| `scripts/network.gd` | 3 output nodes for Stage 2, shiny Equations node, collapse transition animation (10->1->3) |
| `scripts/game_data.gd` | Stage 2 definition (`output_nodes: 3`, purple color), sign/equation helpers |
| `scripts/cursor.gd` | May need adjustment to track which points are being scanned simultaneously |

---

## Stage 2 Upgrades

Existing Stage 2 upgrades (activation, learning rate, aug chance, batch label, etc.) remain as-is with `stage_available: 1`. Math-specific upgrades (e.g. combo window, equation bonus) are deferred to a separate design pass.

---

## Balance Considerations

- **Cursor size** becomes extra important in Stage 2 — larger cursor = more likely to have a valid triple underneath = more combos
- Signs at 25% spawn rate means roughly 1 sign per 4 data points; with dataset_size upgrades this scales naturally
- The 2x combo multiplier rewards skill (positioning cursor over valid triples) without being mandatory — individual green labels still progress the stage
- Combo difficulty naturally scales: with more data on screen (dataset_size upgrades), combos become easier, creating a nice upgrade synergy
