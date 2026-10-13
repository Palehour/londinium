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
│   │   ├── goods.json        # wheat, barley, flour, bread, malt, beer, tea, money unit
│   │   ├── buildings.json    # wharf, mill, bakery, malthouse, brewery, housing, artisan_housing, wheat_field: cost, upkeep, jobs, recipe, tags
│   │   ├── population.json   # consumption, satisfaction weights, growth thresholds, tax rules
│   │   ├── market.json       # wheat base price, fluctuation range, warehouse capacity, spoilage, accumulate factor; barley market (same walk as wheat, own parameters); malt and beer warehouse cap and spoilage; imported flour/tea prices (D-026/D-025)
│   │   ├── policy.json       # defaults of the player's wheat purchase policy (accumulate price, max price, target stock, `reserve_minutes`) and the default barley share of the wharf's unloading (`unloading.default_barley_percent`)
│   │   └── defeat.json       # warning/defeat thresholds and durations (GDD "Derrota")
│   ├── eras/
│   │   └── victorian/        # one folder per era, same engine (D-027, D-032)
│   │       ├── needs.json    # need categories with their threshold, and the housing bonus per met category
│   │       └── classes.json  # per class (worker, artisan): base class and whether it takes jobs, housing building, maximum housing bonus, satisfaction weights, growth thresholds and rates, head tax, needs (good → category, value, satisfaction and consumption keys); a field is a Params key that exists or a number that becomes class.<class>.*
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
│   │   ├── defs/             # building_def.gd, good_def.gd, recipe_def.gd, class_def.gd, need_def.gd …
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
│   ├── game/                 # Node side: sim clock, game session, map geometry, panels (test_sim_clock.gd …)
│   └── scenarios/            # 15-minute scripted games (balance harness, GDD success criteria)
├── tools/                    # run_tests.sh / run_tests.ps1, balance report script
├── docs/                     # GDD.md, DECISIONS.md (canonical), ARCHITECTURE.md, WORKFLOW.md
└── .github/                  # ci.yml, export.yml, PR template
```

## Tick order (one place, `simulation.gd`)
1. Apply queued commands.
2. Assign workers automatically: first one worker per building in chain order (wharf → mill → bakery → malthouse → brewery), then the rest by priority bakery → mill → wharf → malthouse → brewery; emigration frees jobs in reverse order (D-021). Only the classes that take jobs look for one: artisans never fill a post (D-021, D-033).
3. Sources: the market reprices (every `price_update_seconds`), stored wheat spoils a little, and the wharf buys wheat at the
   current price under the player's policy (`SetWheatPolicy`: accumulate price, max price, target stock and a safety reserve in minutes of mill,
   under which the max price stops applying; the pause toggle stops all buying). The warehouse has a capacity. The wharf buys imported flour that skips the mill
   (D-026); wheat fields on cultivable cells only.
   The wharf has one unloading capacity (its staffed wheat output per minute) that wheat, barley and the imported flour share; the tea is exempt (issue #50). A lot of flour is paid at once and leaves a debt of units that the next ticks unload first (`MarketSystem._pay_flour_unloading`); what is left is split by the player's `SetUnloadingSplit` (whole percent to barley, the rest to wheat, which keeps its purchase policy inside its share). Barley's price walks on its own seeded generator so the wheat series does not move.
4. Converters: mill (wheat→flour), bakery (flour→bread), malthouse (barley→malt), brewery (malt→beer), limited by staffed jobs and input stock. Malt and beer have a warehouse cap (`market.malt.*`, `market.beer.*`): a full warehouse stops its producer instead of discarding output (only the artisans drink it, D-033, so a city without their housing still fills the warehouse and stops), and beer spoils a little each minute. Several producers of a capped good share its room and its fractions (ADR 0006).
5. Consumption: each class eats the goods it lists as needs at its own rate (bread by everyone, tea by the workers, beer by the artisans, D-025, D-033); tea and beer are drawn from the global store like a single balance; stale bread decays.
6. Hunger coverage: smooth bread coverage once, shared by hunger emigration and hunger riot defeat.
7. Satisfaction 0–100 with breakdown (one term per need good: bread, tea; tax burden, overcrowding). Inside this step `NeedsSystem` first scores every class's need categories (`Σ coverage × value`, met at the threshold) and sets the housing capacity (base + `min(bonus per met category, class maximum)`, issue #86), so the order of the tick does not change.
8. Growth: for each class, with its own housing, satisfaction and rates, hunger emigration with hysteresis takes priority; otherwise immigration if satisfaction is high and its housing has room, emigration if low (ADR 0008).
9. Money: head tax per class, on the jobs it holds or on all of its residents (`tax.basis`), at the one rate the player sets; minus wages and building upkeep.
10. Defeat: update warning/defeat timers (bankruptcy, hunger riot, depopulation).
11. Stats + snapshot emitted.

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
Keys with ids from the era's data follow the same rule: `needs.<category>.threshold`, `needs.housing_bonus_per_category`, `class.<class>.housing_max_bonus`, `class.<class>.need.<good>.value`; `ParameterRanges.PATTERNS` validates them by shape, and structure (which good counts in which category, which building houses a class) lives in `ClassDef`/`NeedDef` and reaches the sim through `EconomyContext` (ADR 0007). `EconomyState.class_needs` holds the result per class and category; the base class keeps its satisfaction and growth in the flat fields of `EconomyState` and the other classes in `class_states` (ADR 0008); `snapshot()["needs"]` explains it (`NeedsDiagnostics`).
`test_data_valid.gd` fails if code asks for a key that doesn't exist or a modifier targets a missing key.

## Conventions worth stating
- Money is `int` in pence; display converts to £/s/d or decimals in the UI only.
- Monetary parameters round to the nearest penny once, after the entire modifier list;
  ties round away from zero (2.5 → 3, -2.5 → -3). Non-monetary parameters are not rounded.
- Time in data is in game seconds; the UI may show minutes.
- Save/load is out of M1, but state classes expose `to_dict()`/`from_dict()` so it's cheap later.
- Renderer: **Compatibility** (OpenGL) — enough for 2D squares, runs on older Macs/PCs and in CI.
