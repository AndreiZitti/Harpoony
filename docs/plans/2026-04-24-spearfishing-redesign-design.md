# Spearfishing Redesign — Design

**Date:** 2026-04-24
**Status:** Design validated, ready for implementation plan

## Premise

Pivot `feed-the-network` from a neural-network training game into a scuba spearfishing game. The player is a diver on a boat. On the surface they shop for upgrades; they press DIVE to enter the water, where they spearfish while oxygen drains; they resurface (manually or when oxygen runs out) to cash out and shop again.

## Decisions (validated through brainstorm)

- **Dive structure:** oxygen-based. A dive ends when oxygen hits 0 (auto-resurface) or player presses resurface.
- **Fish:** multiple species present simultaneously during a dive, different values/speeds. Active tradeoff: which fish to shoot at.
- **Reel mechanic:** fixed speed, no click-to-reel. Oxygen is the only time pressure.
- **Spear behavior:** always returns. Hit = slow reel back with fish. Miss = fast return, no penalty beyond time lost.
- **Oxygen runout:** forced resurface. In-flight and mid-reel fish are lost; already-landed fish are kept.

## Game loop & screens

Single scene (`main.tscn`), four states the camera and UI transition between:

1. **Surface (boat)** — start state. Sky + boat deck. Shop overlay. Prominent DIVE button. Oxygen bar visible (full).
2. **Diving transition** (~1.5s) — shop fades out, camera scrolls down, diver drops from boat into water. Non-interactive.
3. **Underwater (fishing)** — diver anchored at screen center. Oxygen drains. Fish spawn from edges, swim across. Click fish to throw spear. Optional manual resurface button.
4. **Resurface transition** (~1s) — diver rises back to boat. In-flight fish lost. Cash tallies.

Back to surface/shop.

## Core systems

### Diver (`diver.gd`)
- Fixed position during underwater state.
- Owns N spears (1 at start, upgradeable to 5).
- Tracks per-spear state: READY / FLYING / REELING.
- Handles player click → finds a free spear → directs it at click target.

### Spear (`spear.gd`)
State machine:

```
READY → (player clicks) → FLYING → HIT → REELING(slow) → READY
                                 → MISS → REELING(fast) → READY
```

- FLYING: constant speed from diver toward click point. Collision check against fish each frame.
- HIT: attaches to fish; the pair reels back to diver at slow speed.
- MISS: continues a short distance past click point, then reels back at fast speed.
- REELING: linear interpolation to diver position. On arrival → READY. If HIT, award fish value and remove fish.

Rendered as a short spear sprite/arrow with a taut line back to the diver.

### Fish (`fish.gd`)
- Spawns just offscreen at a random edge.
- Swims across the play area in a sine-wave arc.
- Despawns when it fully exits the opposite edge.
- Fields: `species`, `value`, `speed`, `hit_radius`.

MVP species table:

| Species | Speed | Hit radius | Value | Spawn weight |
|---|---|---|---|---|
| Sardine | fast | small | $2 | 0.6 |
| Grouper | slow | medium | $10 | 0.3 |
| Tuna | medium | large | $40 | 0.1 |

### Fish spawner (`fish_spawner.gd`)
- Active only during underwater state.
- Timer-based: random interval, picks edge + species by weight, spawns fish with trajectory toward opposite side.
- Target visible fish count: 2–4.

### Oxygen
- Single `oxygen` float on `GameData`.
- Drains at 1/sec (base capacity 45s).
- Hitting 0 emits signal → `main.gd` starts resurface transition.

## Upgrades (8 MVP)

| Key | Name | Effect | Levels |
|---|---|---|---|
| `oxygen` | Oxygen Tank | +10s dive time per level (base 45s) | 5 |
| `spears` | Spears | +1 spear in inventory (base 1, max 5) | 4 |
| `spear_speed` | Spear Speed | Spear flies +20% faster | 4 |
| `reel_speed` | Reel Speed | Reel +20% faster | 4 |
| `hit_radius` | Spear Tip | Wider effective hit area | 3 |
| `lure` | Lure | +25% fish spawn rate | 4 |
| `fish_value` | Market Price | All fish worth +20% cash | 5 |
| `trophy_room` | Trophy Room | +5% cash carried over between dives | 3 |

**Later scaffold (not MVP):** `harpoon` upgrade gated behind `spear_speed >= 2`; unlocks a 4th fish species (Shark, $200) that ignores basic spears.

No stage system in MVP — every upgrade is visible and buyable from the start except future-gated ones.

## UI (HUD)

- **Oxygen bar** — top-center, large. Color shifts blue → red as it empties.
- **Cash this dive** — top-right. Tallies as fish land.
- **Spear inventory** — bottom-center. One icon per owned spear, colored by state (ready/in-flight/reeling).
- **Resurface button** — bottom-right, only during underwater state.

## File changes

### Delete
- `scenes/data_point.tscn`
- `scripts/data_point.gd` + `.uid`
- `scripts/data_spawner.gd` + `.uid`
- `scripts/network.gd` + `.uid`
- `scripts/cursor.gd` + `.uid`

### Rewrite in place
- `scripts/game_data.gd` — strip stages/accuracy/combo; replace upgrades dict; add oxygen/dive fields.
- `scripts/main.gd` — keep phase-fade framework; rename states to SURFACE / DIVING / UNDERWATER / RESURFACING.
- `scripts/hud.gd` — oxygen bar, dive cash, spear inventory icons.
- `scripts/upgrade_shop.gd` — minor updates for new upgrade keys; drop stage-gating checks.
- `scenes/main.tscn` — restructure node tree: `Surface`, `Underwater` containers; `Diver`, `FishSpawner`; remove `Network`, `DataSpawner`, `Cursor`.

### New
- `scripts/diver.gd` + `scenes/diver.tscn`
- `scripts/spear.gd` + `scenes/spear.tscn`
- `scripts/fish.gd` + `scenes/fish.tscn`
- `scripts/fish_spawner.gd`

## Build sequence (each step runnable)

1. Strip `GameData` to cash + oxygen + new upgrades table.
2. Restructure `main.tscn` skeleton + rewrite `main.gd` states + new HUD oxygen bar.
3. Add `Diver` + `Spear` with throw/return (no fish yet — verify spear flies to click and returns).
4. Add `Fish` + `FishSpawner` (fish drift across screen, not yet collidable).
5. Wire spear-fish collision + reel-back + cash award.
6. Update `upgrade_shop.gd` and wire all 8 upgrades to their effects.
7. Polish: boat scene, dive transition, resurface animation.

## Visual direction

Keep the dark-background / flat-vector look of the current project. Underwater = deeper blue gradient; surface = lighter blue sky over boat silhouette. Fish are simple flat shapes tinted by species. No asset fetching needed for MVP — all drawn in `_draw()`.
