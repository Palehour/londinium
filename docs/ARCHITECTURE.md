# Architecture — Londinium M1 (proposal)

Technical companion to `docs/GDD.md`. The GDD says *what*; this says *how the code is organized*.
Changes to this file go through a normal PR reviewed by Cristian.

## Principles
1. **Simulation is pure data + logic.** `src/sim/` never touches nodes, scenes or the UI, so it runs
   headless in tests at thousands of ticks per second. (Same split as IndustrieLite and gatewarden:
   fixed-timestep sim, data-driven recipes, headless tests in CI.)
2. **Deterministic fixed tick.** 1 tick = 1 game second at 1x speed. A thin `SimClock` node accumulates
   real `delta × speed` and calls `sim.tick()` in whole steps (capped per frame). Same seed + same
   commands ⇒ same state. Randomness (wheat price) only via the sim's seeded `RandomNumberGenerator`.
3. **Everything tunable lives in `data/`** as JSON, read through `Params.get_value(key)`, which applies the
   active role's modifier list (empty for the neutral administrator in M1, D-014 / D-019).
4. **UI sends commands, reads snapshots.** `Simulation.apply_command(cmd)` (build, demolish, set_tax,
   order_wheat, toggle_tea, …) is the only way to change state. After each tick the sim emits a read-only
   snapshot + per-minute stats for the panel. The command log also gives free replays and, later, saves.
5. **Nodes, not ECS.** M1 has tens of buildings, not thousands; plain typed classes + arrays are enough.
   No ECS framework, no C#.

## Folder structure
```
londinium/
├── AGENTS.md                 # rules for coding agents (CLAUDE.md just imports it)
├── project.godot             # Godot 4.7.2, Compatibility renderer, untyped_declaration = error,
│                             #   keep debug/gdscript/warnings/exclude_addons=true (vendored GUT)
├── export_presets.cfg        # Windows Desktop / macOS / Linux (committed, no secrets)
├── .gutconfig.json
├── addons/gut/               # GUT 9.7.x vendored (never edited by agents)
├── data/                     # ALL balance + content, JSON, edited by agents/Mason, approved by Cristian
│   ├── economy/
│   │   ├── goods.json        # wheat, flour, bread, tea, money unit
│   │   ├── buildings.json    # wharf, mill, bakery, housing, wheat_field: cost, upkeep, jobs, recipe, tags
│   │   ├── population.json   # consumption, satisfaction weights, growth thresholds, tax rules
│   │   ├── market.json       # wheat base price, fluctuation range, imported flour/tea prices (P-011/P-004, solo cuando se aprueben)
│   │   └── defeat.json       # warning/defeat thresholds and durations (GDD "Derrota")
│   ├── roles/
│   │   └── neutral_administrator.json   # { "modifiers": [] }  ← the role hook (D-014)
│   └── maps/
│       └── whitechapel_1850s.json       # grid size, river cells, cultivable cells (none, D-010)
├── src/
│   ├── sim/                  # pure simulation (RefCounted, no Node)
│   │   ├── simulation.gd     # owns state, tick(), apply_command(), snapshot()
│   │   ├── economy_state.gd  # stocks (global warehouse, D-011), money (int pence), buildings, population
│   │   ├── params.gd         # get_value(key) = base data ∘ role modifiers
│   │   ├── modifier.gd       # {key, op: add|mul|set, value}
│   │   ├── data_loader.gd    # JSON → typed defs, with validation errors
│   │   ├── defs/             # building_def.gd, good_def.gd, recipe_def.gd …
│   │   ├── systems/          # one file per tick step (see order below)
│   │   ├── commands/         # command classes / validation
│   │   └── stats.gd          # rolling 60-tick windows for "per minute" figures
│   ├── game/                 # Node side: sim_clock.gd, game.gd (autoload), map_view (colored squares), camera
│   └── ui/                   # stats_panel/, build_bar/, controls/, defeat_banner/, strings.gd
├── scenes/
│   └── main.tscn             # composes map view + UI; no logic
├── tests/
│   ├── sim/                  # unit tests per system (test_production.gd, test_needs.gd, test_defeat.gd …)
│   ├── data/                 # test_data_valid.gd: every JSON loads, keys exist, no orphan params
│   └── scenarios/            # 15-minute scripted games (balance harness, GDD success criteria)
├── tools/                    # run_tests.sh / run_tests.ps1, balance report script
├── docs/                     # GDD.md, DECISIONS.md (canonical), ARCHITECTURE.md, WORKFLOW.md
└── .github/                  # ci.yml, export.yml, PR template
```

## Tick order (one place, `simulation.gd`)
1. Apply queued commands.
2. Assign workers automatically by fixed priority: bakery → mill → wharf (GDD, D-012).
3. Sources: wharf buys wheat at the current (fluctuating) price; wharf buys imported flour that skips the mill
   (P-011, pending: only once approved); wheat fields on cultivable cells only.
4. Converters: mill (wheat→flour), bakery (flour→bread), limited by staffed jobs and input stock.
5. Consumption: bread eaten per person; tea if available (only if P-004 approved); stale bread decays.
6. Satisfaction 0–100 with breakdown (bread covered, tea, tax burden, overcrowding).
7. Growth: immigration if satisfaction high and housing free; emigration if low.
8. Money: taxes from employed workers only; minus wages and building upkeep.
9. Defeat: update warning/defeat timers (bankruptcy, hunger riot, depopulation).
10. Stats + snapshot emitted.

## Data example (shape only — numbers are placeholders owned by Mason, approved by Cristian)
```json
// data/economy/buildings.json
{
  "bakery": {
    "cost": 0, "upkeep_per_minute": 0, "jobs": 0,
    "recipe": { "inputs": { "flour": 0 }, "outputs": { "bread": 0 }, "seconds": 0 },
    "tags": ["producer"]
  }
}
// data/roles/neutral_administrator.json
{ "id": "neutral_administrator", "modifiers": [] }
// a future role would add e.g. { "key": "building.bakery.recipe.seconds", "op": "mul", "value": 0.9 }
```
Parameter keys are dotted paths into the data (`building.bakery.jobs`, `defeat.hunger.threshold`).
`test_data_valid.gd` fails if code asks for a key that doesn't exist or a modifier targets a missing key.

## Conventions worth stating
- Money is `int` in pence; display converts to £/s/d or decimals in the UI only.
- Monetary parameters round to the nearest penny once, after the entire modifier list;
  ties round away from zero (2.5 → 3, -2.5 → -3). Non-monetary parameters are not rounded.
- Time in data is in game seconds; the UI may show minutes.
- Save/load is out of M1, but state classes expose `to_dict()`/`from_dict()` so it's cheap later.
- Renderer: **Compatibility** (OpenGL) — enough for 2D squares, runs on older Macs/PCs and in CI.
