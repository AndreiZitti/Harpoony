# Campaign Arc & Spear Progression Design

Date: 2026-04-26
Status: Validated, ready for implementation

## Scope

A 2–3 hour finite campaign. Arcade spearfishing with shop progression. Sits between Ridiculous Fishing and Cat Goes Fishing in genre. Ship the small sharp version, do not expand mid-development.

## Campaign Arc — 4 Zones

```
Z1  REEF          $0–300       ~15 min   intro / learn loop
   Fish: sardine, grouper, puffer
   Spears: Normal only
   Teaches: aim, bag management, puffer rhythm

Z2  KELP FOREST   $300–1000    ~30 min   defense puzzles
   Fish: + mahimahi, triggerfish, lanternfish schools
   Unlocks: Net spear ($500)
   Teaches: shield angles, schooling targets

Z3  OPEN BLUE     $1000–2500   ~30 min   volume + speed
   Fish: tuna runs, jellyfish swarms, marlin
   Unlocks: Heavy spear ($1500)
   Teaches: AoE mastery, fast targets, deep upgrade choices

Z4  THE ABYSS     $2500+       ~45 min   trophy hunt / finale
   Fish: rare legendary (1-3 per dive), heavily armored
   Win: catch The White Whale → ending screen
```

Win condition: legendary catch triggers credits. Player can keep diving after for completion (trophy log).

## Spear Identity Carving

Each spear is the only tool for its problem.

| Spear | Identity | Solves |
|---|---|---|
| **Normal** | PRECISION | "hit the one fish I aimed at, get max value" |
| **Net** | VOLUME | "harvest small-fish schools" — *cannot break defenses, cannot catch large fish* |
| **Heavy** | POWER | "break defenses, plow stacked targets, jackpot trophy fish" |

Critical changes from current code:
- Net **loses defense bypass** — that becomes Heavy's exclusive lane
- Net is **size-gated**: catches small fish only by default; medium unlocked mid-tree; large/trophy never
- **Razor Edge (pierce) moves from Normal to Heavy** — pierce is a heavy-weapon mechanic
- Normal stays pure precision

## Upgrade Trees

Branches are both available (not forced choice). Tier-2 nodes are expensive enough that natural specialization happens. Avoids "missed half the game" regret in a one-playthrough campaign.

```
NORMAL SPEAR
└─ Aerodynamic Shaft (faster flight)
   ├─ SPEED ──→ Rapid Reel ──→ Twin Shot (fire 2 per click)
   └─ POWER ──→ Wider Tip (hit radius) ──→ Polished Tip (+50% value)

NET SPEAR (unlocks Z2, $500)
└─ Mesh Quality (baseline radius, small-fish only)
   ├─ WIDE  ──→ Cast Wide (+50% radius) ──→ Bigger Hoop (catches MEDIUM fish too)
   └─ SMART ──→ Weighted Net (faster reel) ──→ Lure Net (pulls fish to center before snap)

HEAVY SPEAR (unlocks Z3, $1500)
└─ Reinforced Shaft (breaks defenses, slow)
   ├─ CRIT      ──→ Sharp Tip (25% crit, 2x) ──→ Perfect Strike (100% crit on center hit, 3x)
   └─ PENETRATE ──→ Drill Tip (pierce 3) ──→ Sonic Boom (stuns nearby fish on impact)

GLOBAL
├─ Oxygen Tank (5 levels — longer dives)
└─ Spear Bag (5 levels — more shots per dive)
```

Total: 12 spear upgrade nodes + 2 global tracks.

## Fish Size Classes

| Class | Species | Net catches? |
|---|---|---|
| small | sardine, lanternfish | Always |
| medium | grouper, mahimahi, pufferfish | Only after Bigger Hoop |
| large | tuna, marlin, triggerfish | Never |
| trophy | Z4 legendaries | Never — Heavy only |

The size gate is a hard rule. Net can never poach trophy lane.

## Per-Zone Problem → Upgrade Mapping

Every upgrade node solves a problem a specific zone introduces. If a zone doesn't demand it, it shouldn't exist.

| Zone | New problem | Upgrade that solves it |
|---|---|---|
| Z1 Reef | Aim accuracy, puffer rhythm, sardines 1-by-1 | Aerodynamic Shaft, Oxygen L1, Bag L1 |
| Z2 Kelp | Trigger shields (angle puzzles), bigger schools | Net unlock, Net Mesh Quality, Normal Speed path |
| Z3 Open Blue | Fast tuna, swarms, first armored species | Heavy unlock, Net Wide path, Bag/Oxygen L3-4 |
| Z4 Abyss | Trophy fish (rare, armored, high-value) | Heavy CRIT path, Normal Power path, maxed globals |

## Out of Scope (Sequel Concepts)

- Boat metagame
- Story / NPCs
- Day/night cycle (already cut)
- Multiple tanks / sub-dives (already cut)
- Zones 5–6 (deep-sea, shipwreck, hydrothermal)
- Roguelike runs / meta-currency
- Endless prestige
- Multiplayer
