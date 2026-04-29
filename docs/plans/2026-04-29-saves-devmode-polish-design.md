# Save System, Dev Mode, and Title/Summary Polish

Date: 2026-04-29
Scope: fix the save-leak bug, redesign Dev Mode for a non-programmer collaborator, polish the title flow and post-dive summary.

## Problem

1. **Save leak.** `main.gd:43` calls `GameData.load_dev_tuning()` at boot, before the player picks Normal vs Dev. That file (`user://dev_tuning.json`) currently stores `spear_upgrade_levels`, `dev_infinite_oxygen`, `dev_skip_shop`, capacity overrides, `fish_stat_overrides`, and raw spear base stats. `spear_upgrade_levels` is *also* the player's normal-mode upgrade progression. Result: anything the dev panel touches leaks into every future Normal launch.
2. **No real player save.** Cash, unlocks, and upgrades are never written to disk. Only `run_history` (dive log) and `discovered_species` (bestiary) persist.
3. **Dev Mode is dense.** Six tabs of raw multipliers (`speed_mult = 1.20`, `value_bonus = 0.15`) — fine for a programmer, opaque to a collaborator who just wants to playtest a scenario.
4. **Title flow assumes one path.** "Start Run" is the only primary action; there is no New Game / Continue distinction.
5. **Post-dive summary** has minor rough edges: empty-dive case looks broken, Continue press feels instant, no assert protecting `last_dive_cash` ordering.

---

## Section 1 — Save system rebuild

**Two files, non-overlapping responsibilities.**

### `user://progress.json` (new — player progression)

Holds:
- `cash`, `unlocked_zone_index`, `selected_zone_index`
- `unlocked_spear_types`, `spear_upgrade_levels`
- `upgrade_levels` (oxygen / spear_bag / reload_speed)
- `bag_loadout`, `dive_number`

Saved on:
- end of dive (after `finish_dive()` rolls `dive_cash` into `cash`)
- after any shop purchase
- after zone or spear unlock

Debounced 0.4s, same pattern as `request_dev_tuning_save`.

**Saved only at `DiveState.SURFACE`.** A mid-dive quit will not corrupt the save — on relaunch, Continue restores the last surface state with full oxygen.

### `user://dev_tuning.json` (existing — narrowed)

Keeps:
- `dev_infinite_oxygen`, `dev_skip_shop`
- `oxygen_capacity_override`, `bag_capacity_override`, `dive_travel_duration`
- `fish_stat_overrides`
- raw spear base fields (speed_mult etc.)

Removes:
- `spear_upgrade_levels` (moves to progress.json)

Loaded **only when Dev Mode is selected** on the title screen, not at boot. Normal mode boots from a clean baseline + `progress.json`.

### Title screen states

| State | Primary action | Other buttons |
|---|---|---|
| `progress.json` exists | **Continue** | New Game, Bestiary, Dev Mode |
| No save | **New Game** | Bestiary, Dev Mode |

- **Continue**: load `progress.json`, skip boat-slide intro, drop in shop.
- **New Game**: if save exists, inline confirm ("Wipe your saved progress? This can't be undone.") — Wipe & start / Cancel. Then delete `progress.json`, reset in-memory state, play boat-slide intro, drop in shop.
- **Dev Mode**: load `dev_tuning.json`, skip shop, auto-unlock everything as today.

### Migration

On first boot after this change, if `dev_tuning.json` contains `spear_upgrade_levels`, copy them into a fresh `progress.json` so existing players don't lose Normal-mode progression. Then strip that key from dev tuning.

---

## Section 2 — Dev Mode redesign

Reframe around scenarios, not knobs. Tabs reduced 6 → 4.

### Tab order

1. **Scenarios** (was Presets) — default tab, the front door.
2. **Live tweaks** (was Game) — in-dive cheats: oxygen, bag, infinite, skip shop.
3. **Spawn** — same as today, friendlier labels.
4. **Balance** — Spears + Fish + Costs merged, presented as **collapsible sections**, all collapsed by default. Each section has its own *Reset section* button.

### Scenarios tab

Plain-English buttons with one-line subtitles. Pressing a scenario applies state and drops the player straight into the relevant zone/state. A toast confirms: *"Scenario loaded: Mid-game Zone 2"*.

- *Fresh start in Zone 1* — "Empty wallet, no upgrades, default spear"
- *Mid-game Zone 2* — "$500, oxygen lvl 2, normal+net spears"
- *Late-game Zone 3* — "$2000, all spears unlocked, mid-tier upgrades"
- *Whale hunt ready* — "$500, heavy spear maxed, full oxygen"
- *Maxed everything* — "All zones, all spears at max, $5000"
- *Just the whale* — Whale-ready + spawns the whale immediately on dive
- *Empty scene* — current zone, no fish spawning (for testing UI/oxygen)

### Humanized labels

Internally still floats. Display formatter changes only.

| Current | New |
|---|---|
| `oxygen_capacity_override = 30.0` | "Oxygen seconds: 30s" |
| `dive_travel_duration = 1.5` | "Dive travel: 1.5s" |
| `speed_mult = 1.20` | "Spear speed: +20%" |
| `value_bonus = 0.15` | "Value bonus: +15%" |
| `crit_chance = 0.05` | "Crit chance: 5%" |
| `pierce_count = 2` | "Pierces: 2 fish" |

Each row shows the default value greyed out next to the current value: `Spear speed: +20%  (default +0%)`.

### Reset buttons

- **Reset section** at the top of each Balance section.
- **Reset all dev tuning** at the top of the panel — also turns off live-tweak toggles (infinite oxygen, skip shop), so it's a true return-to-vanilla. Does **not** touch `progress.json`.

---

## Section 3 — Title flow + post-dive summary polish

### Title screen

- Update the hint label (`main_menu.gd:112`) from *"Dev mode: infinite oxygen, dev spawn panel, skip shop."* to *"Dev Mode is a sandbox — your saved game won't be touched."*
- New Game confirm uses an inline overlay (same fade style as menu, 0.2s), not a system modal. Skip if no save exists.
- Continue skips the boat-slide intro and goes straight to the shop (resuming, not starting). New Game keeps the boat-slide intro as the "first time setting sail" beat.

### Post-dive summary

1. **Assert `last_dive_cash` ordering.** `finish_dive()` (`game_data.gd:767`) sets it before the summary reads it (`dive_summary.gd:130`). Add an assert so a future refactor can't silently break the readout.
2. **Continue button feedback.** On press: button briefly desaturates, panel slides up 8px before fading out (200ms total). Makes the transition feel intentional rather than instant.
3. **Empty-dive placeholder.** If the player surfaces with 0 catches, replace the empty fish table with a single italic line: *"No catches this dive — the fish got lucky."*

---

## Out of scope

- HUD readability changes (oxygen bar / bag fill / depth indicator). Flagged as "maybe later" — not part of this design.
- Adding new juice (screen shake, additional sfx, music swells). User explicitly redirected from "add new feel" to "polish what's there."
- Save slots / multiple campaigns. Single active campaign is sufficient.

---

## Verification

After implementation:
- Wipe `user://*.json`. Launch → only New Game shown. Click → boat-slide → shop.
- Play one dive, surface, quit. Relaunch → Continue shown. Click → straight to shop, cash matches.
- Enter Dev Mode, change spear speed_mult to +50%, set infinite oxygen, return to title, choose Continue. Spear speed should be unchanged from saved progression; infinite oxygen off.
- Enter Dev Mode again. Spear speed +50% and infinite oxygen should still be there (dev tuning persists across Dev sessions).
- Dev Mode → "Reset all dev tuning" → infinite oxygen toggles off, all sliders return to default.
- Surface with 0 catches → summary shows the empty-dive placeholder.
- Quit mid-dive (force quit), relaunch, Continue → land at surface with full oxygen, no corrupted state.
