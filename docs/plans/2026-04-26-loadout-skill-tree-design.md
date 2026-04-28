# Loadout / Upgrade Screen — Skill Tree Redesign

Date: 2026-04-26

## Problem

The current "Aboard the Boat" screen feels **empty** and the per-spear upgrade row reads as a flat strip of tiles rather than a progression system. With 3 spear types and roughly the same upgrade shapes per spear, we need a layout that:

1. Fills the screen visually.
2. Reads as a tree (branching pacing, gated tiers).
3. Keeps each spear's upgrades **spear-specific** (no shared trunk).
4. Doesn't punish players with permanent build commitments — eventually you can buy everything.

## High-Level Direction

**Triptych of three vertical "branched-ladder" trees**, one per spear, all visible at once. No tabs. No shared trunk.

- Each spear card becomes tall and column-shaped.
- Each card holds a **7-node skill tree** in a vertical branched-ladder shape.
- Boat upgrades (oxygen, spear-bag), depth selector, and DIVE stay in the top strip — they're global, they don't belong inside a spear tree.

## Page Layout

```
┌─────────────────────────────────────────────────────────────┐
│  ⛵ ABOARD THE BOAT                              💰  $1,240  │
├─────────────────────────────────────────────────────────────┤
│  [DEPTH 1│2│3│4 +unlock] │ [BOAT: oxygen][bag] │   [DIVE]   │
├─────────────────────────────────────────────────────────────┤
│ ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│ │   NORMAL    │  │     NET     │  │    HEAVY    │           │
│ │  [sprite]   │  │  [sprite]   │  │  [sprite]   │           │
│ │   ─ 3 +     │  │   ─ 1 +     │  │   ─ 0 +     │           │
│ │   ╔═══╗     │  │   ╔═══╗     │  │   🔒 LOCKED │           │
│ │   ║TREE║    │  │   ║TREE║    │  │   $300      │           │
│ │   ╚═══╝     │  │   ╚═══╝     │  │             │           │
│ └─────────────┘  └─────────────┘  └─────────────┘           │
│                                              [Cheat: OFF]    │
└─────────────────────────────────────────────────────────────┘
```

Card layout, top to bottom:
1. Sprite banner (existing).
2. Spear name + status pill.
3. Bag stepper `─ N +` (existing).
4. **Tree area** (new — fills remaining vertical space).
5. Locked spears replace the tree area with a single big "🔒 UNLOCK — $X" panel so column widths don't shift on unlock.

Sizing target: at 1280px window, each column is ~395px wide. Tree footprint is ~200px wide (2 nodes max + gap), leaving comfortable padding inside the card.

## Tree Shape — Vertical Branched Ladder

Strict binary pyramids (1 → 2 → 4) get too wide for narrow columns. The branched-ladder shape stays **2 nodes wide max** and grows tall:

```
        ┌──────────┐
        │   ROOT   │     auto-owned (the spear itself)
        └────┬─────┘
        ┌───┴───┐
     ┌──┴──┐ ┌──┴──┐
     │ T1A │ │ T1B │     Tier 1 — quality-of-life / minor stat
     └──┬──┘ └──┬──┘
        └───┬───┘
        ┌───┴───┐
        │  T2   │        Tier 2 hub — signature mechanic
        └───┬───┘
        ┌───┴───┐
     ┌──┴──┐ ┌──┴──┐
     │ T3A │ │ T3B │     Tier 3 — power amplifier
     └──┬──┘ └──┬──┘
        └───┬───┘
        ┌───┴───┐
        │  CAP  │        Capstone — build-defining keystone
        └───────┘
```

Seven upgrade nodes per tree. Across three spears: **21 distinct nodes**, ~48 total purchases of meaningful progression (vs. ~15 today).

## Slot Archetypes

The seven slots fill the same archetypal roles in every tree, so trees scan as parallel structures. Flavor is spear-specific.

| Slot | Role | Levels | Cost band |
|------|------|--------|-----------|
| **T1A** | Quality-of-life / minor stat | 3 | Cheap |
| **T1B** | Quality-of-life / minor stat | 3 | Cheap |
| **T2 (hub)** | Signature mechanic boost | 3 | Mid |
| **T3A** | Power amplifier | 3 | Expensive |
| **T3B** | Power amplifier | 3 | Expensive |
| **CAP** | Keystone (binary, single purchase) | 1 | Premium (~3-5× T3 max) |

### Example flavor fills (placeholder — to be replaced with the curated upgrade list)

|  | NORMAL | NET | HEAVY |
|---|---|---|---|
| **T1A** | Sharp Tip *(+crit)* | Wider Hoop *(+radius)* | Sharper Head *(+dmg)* |
| **T1B** | Quick Reel | Sticky Net *(+catch time)* | Faster Reel |
| **T2** | Razor Edge *(+pierce)* | Bigger Hoop *(catch medium)* | Armor Pierce |
| **T3A** | Twin Shot | Lure Net | Cluster Strike |
| **T3B** | Perfect Strike | Megaschool | Charge Shot |
| **CAP** | "One-Shot": crits one-tap trophies | "Tidal Net": catches all on screen | "Earthshatter": AoE stun |

## Gating Rules

**Lenient unlock** — to buy *any* level of a child node, you need **at least level 1 of every parent**. You do not need to max parents.

- T1A, T1B: buyable from the start (parent = root, auto-owned).
- T2: buyable once T1A ≥ 1 **and** T1B ≥ 1.
- T3A, T3B: buyable once T2 ≥ 1.
- CAP: buyable once T3A ≥ 1 **and** T3B ≥ 1.

This keeps decisions alive: once a tier opens, you juggle "deepen what I have vs. push forward" every dive. Strict (max-to-progress) becomes a treadmill.

## Node Visual

```
┌──────────────────┐
│        🩸         │   icon glyph (24px)
│  ●●●○○            │   level pips
│      $80         │   price OR "MAX"
└──────────────────┘
```

~80×80px tile. Reuse existing `_style_tile()` state machine.

| State | Tile | Connector |
|-------|------|-----------|
| **Locked** (parent < 1) | 40% opacity, no price, lock icon | dashed dim gray |
| **Buyable** | full opacity, accent border, green price | solid colored |
| **In-progress** | full opacity, partial pip fill | solid colored |
| **MAX** | green border, "MAX" badge | solid green |
| **Capstone owned** | gold glow, crown icon | gold |

Locked nodes stay **visible** (not hidden) so the path forward is obvious. Tooltip on a locked node reads e.g. "*Requires Sharp Tip Lv 1 + Quick Reel Lv 1*".

### Connector lines

Drawn in `_draw()` on the tree container (parent of the node tiles). ~3px wide, anti-aliased, color matches spear accent. Five line segments per tree (root→T1A, root→T1B, T1A→T2, T1B→T2, T2→T3A, T2→T3B, T3A→CAP, T3B→CAP — actually eight; cheap regardless).

## Capstone Behavior

- Single binary purchase, no levels.
- Most expensive node by far.
- Distinct visual: bigger tile, gold border, glow when buyable.
- Once owned, the entire spear card border lights up gold permanently — the spear feels "completed."

## Data Model Changes

The current `SpearType.upgrades: Dictionary` already supports per-spear upgrade definitions with `costs`, `max_level`, `name`, `description`, `icon`, `field`, `step`. Two extensions needed:

1. **Add `tier: String`** to each upgrade entry — one of `"T1A"`, `"T1B"`, `"T2"`, `"T3A"`, `"T3B"`, `"CAP"`. Used by the layout to place the node in its slot.
2. **Add `parents: Array[String]`** — list of upgrade keys that gate this node. Empty for T1A/T1B. Used by the gating rule.

Capstone uses `max_level: 1`. No new resource type needed.

## Implementation Sketch

`upgrade_shop.gd` changes:

- Replace `_build_spear_card()`'s flat tile row with `_build_skill_tree(spear_id)`.
- New `_build_skill_tree()`: lays out node tiles in fixed slot positions inside a `Control` parent, draws connectors via `_draw()`.
- New helper `_is_node_buyable(spear_id, key)`: walks `parents`, returns true if all are at level ≥ 1.
- Existing `_style_tile()` extended with the `locked-by-parent` state.
- `GameData.buy_spear_upgrade()` already validates cost; add a parent check before deducting cash.

Locked-spear panel reuses the existing unlock button at full size where the tree would live.

## YAGNI'd / Out of Scope

- **Mutually exclusive branches.** Earlier discussion considered "pick A or B, lock out the other." Rejected — not the feel we want.
- **Shared trunk across spears.** Considered for global upgrades like reload speed. Rejected — boat upgrades already cover that, and forcing shared nodes creates fake symmetry.
- **Focused/tabbed mode.** Rejected — fights the "too empty" complaint by hiding two-thirds of the content.
- **Capstone with levels.** Rejected — a binary keystone reads as a clearer prize.
- **Animations on unlock.** Polish item, not part of the structural redesign.

## Open Questions

1. **Final upgrade list** per spear (the user has a list to share — placeholder flavor in this doc until then).
2. **Cost bands** — concrete cash values per tier. Calibrate against current dive earnings curve.
3. **Capstone uniqueness** — should each spear's CAP be a wildly different mechanic (current sketch), or all variants of the same theme (e.g., all "trophy hunters")? Current direction: wildly different.
