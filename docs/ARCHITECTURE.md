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
   difficulty's layers and then the active role's modifier list (empty for the neutral administrator in M1,
   D-014 / D-019). The layers and their order are in "Data layers" below.
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
│   │   ├── buildings.json    # wharf, mill, bakery, malthouse, brewery, housing, artisan_housing, wheat_field, public_fountain, lea_bridge_fountain and well (tag `water`, no recipe, #63, #202): cost, upkeep, jobs, recipe, tags;
│   │   │                     #   a water building names `coverage` (the section of its radius_m) and optionally `water_source` (the section of its own source_risk; without it, the district's source); `priced_as` another building reads that one's cost, upkeep, wage and jobs (Params aliases the keys, #202)
│   │   │                     #   optional service_radius_m (metres along the streets) + distributes (goods handed out to houses) and supplies (the wharf's barley and imported flour), #67, #186;
│   │   │                     #   optional footprint [w, h], the cells it covers from its north-west corner (1x1 when missing; all 2x2 since #186), #184, D-086
│   │   ├── roads.json        # the player's streets: cost and upkeep per minute, per piece of `footprint` cells (2x2, the old 50 m cell) (#67, D-070, #186)
│   │   ├── transport.json    # cost per unit and metre, and the metres from which a leg is "expensive" (#67, D-070, D-080, #186)
│   │   ├── map.json          # cell_size_m, the side of a map cell: 25 m (#186, D-086); min_riverside_buildable, the least buildable cells beside the river of a map drawn as rows (#61, provisional)
│   │   ├── zones.json        # all_unlocked: every zone of the full map is open until their unlocking is decided (#61, D-091)
│   │   ├── fountain.json     # radius_m, the houses a public fountain covers, centre to centre in metres (#63, D-089)
│   │   ├── crisis.json       # per crisis type (only `health`, D-105): response_cost and response_min of the disinfection (D-104), quarantine_min and the shorter quarantine_post_min within post_radius_m of a health post (D-106, D-107), exposure_tiles and exposure_diamond (square by default) for who is exposed (#222); provisional values
│   │   ├── well.json         # radius_m and source_risk of the well, 1x1 (#202, D-090)
│   │   ├── lea_bridge.json   # source_risk of the Lea Bridge water and max_fountains, the cap on its fountains (#202, D-090)
│   │   ├── events.json       # historic events (#63): `enabled` (off: no water building can be built), the risk of each water source, `cholera.trigger_min` (the outbreak) and `prep.w_*`, the weights of a district's preparation, which add up to 1 (D-088, #202)
│   │   ├── cholera.json      # what a district that fails the Old Ford mission suffers: fail_mortality, vacancy_min, recovery_mult, recovery_min (#202, D-090)
│   │   ├── mission.json      # min_water_d, the water a district needs at the close of the Old Ford mission (#202, D-090)
│   │   ├── population.json   # consumption, satisfaction weights, growth thresholds, tax rules
│   │   ├── market.json       # wheat base price, fluctuation range, warehouse capacity, spoilage, accumulate factor; barley market (same walk as wheat, own parameters); malt and beer warehouse cap and spoilage; imported flour/tea prices (D-026/D-025)
│   │   ├── policy.json       # defaults of the player's wheat purchase policy (accumulate price, max price, target stock, `reserve_minutes`) and the default barley share of the wharf's unloading (`unloading.default_barley_percent`) and the notch of its on-screen control (`unloading.step_percent`)
│   │   ├── defeat.json       # warning/defeat thresholds and durations (GDD "Derrota"); `enabled` is the defeats switch (D-065)
│   │   └── events.json       # historical events (#63): `cholera.defeat_pause`, the switch a mission names to pause the depopulation timer (D-090)
│   ├── difficulty/           # optional (D-065): without it the game runs on the base values
│   │   ├── presets.json      # easy, normal, hard: relative modifiers (mul|add) and `events` (reserved, empty until #63)
│   │   └── knobs.json        # loose knobs: kind (switch, value, price_volatility), keys, min, max, step
│   ├── eras/
│   │   └── victorian/        # one folder per era, same engine (D-027, D-032)
│   │       ├── needs.json    # need categories with their threshold, and the housing bonus per met category
│   │       ├── classes.json  # per class (worker, artisan): base class and whether it takes jobs, housing building, maximum housing bonus, satisfaction weights, growth thresholds and rates (and, optionally, `served_categories`: the need categories a house must have within reach for immigrants to count it, D-085), head tax, needs (good → category, value, satisfaction and consumption keys), and optionally `mobility` (the class people rise from, the minimum category scores and source satisfaction to rise, the category, score and seconds to fall back, and both rates); a field is a Params key that exists or a number that becomes class.<class>.*
│   │       └── missions/     # optional, one mission per file (#63, D-090): duration_min, goal (metric `population` or `water`; at_least a number or a Params key), the effects of on_completed, on_failed and on_abandoned (`money`, `source_risk` with the `source` whose districts it sets, `cholera`), and optionally defeat_pause (a boolean Params key), on_started, trigger (its id and the minute key it closes at, #202) and card (Chronicler's year, location, tag, sources and liberties; never [A VERIFICAR]); every number becomes mission.<id>.*. oldford.json is the 1866 cholera (#202)
│   │       ├── archive/      # the Archive's read-only cards (#64, D-096/D-097/D-099/D-103), one per file, never loaded by the sim: order, kind (moment, character, finding), unlock.mission_closed (the mission whose close, met or not, opens it) and image (null, or its full credit: title, author, publication, date, held_at, license, url, and context; a context image needs archive.<id>.image_context in locale/ui.csv). Words in locale/ui.csv as archive.<id>.title/date/body/sources (D-100)
│   │       └── crisis.json   # optional: Chronicler's texts per crisis type, the tooltip note and a card (year, title, text, sources); placeholders until Chronicler writes them (#222)
│   ├── scenarios/             # optional playable scenarios: victory.stages (D-064) and the map they are played on
│   ├── game/
│   │   └── save.json          # autosave interval and rotating slots (#57); not economy, read by SaveSettings
│   ├── roles/
│   │   └── neutral_administrator.json   # { "modifiers": [] }  ← the role hook (D-014)
│   └── maps/
│       ├── whitechapel_1850s.json       # the 8x8 of the harness, 16x16 cells of 25 m since #186: grid size, river cells, cultivable cells (none, D-010); scripted scenarios; no streets
│       ├── riverside_strip.json         # 32x24 strip of Wapping in 1870 played by the game, cells of 25 m (D-069, D-074, #152, D-086);
│       │                                #   generated by tools/map_import; roads_enabled and road_diagonals (the
│       │                                #   distance model, #67, D-080); anchors and named_sites (#152);
│       │                                #   period_houses, damaged_wharves and lot_styles (#176, D-083)
│       ├── <map>.json with `size`        # a map drawn as rows of text (#61, D-093), y=0 to the north: `size` [w, h],
│       │                                #   `cell_size_m` (must be map.cell_size_m), `cells` (one character per cell:
│       │                                #   `~` river, `D` dock, `s` stairs, `#` street, `.` buildable), `districts`
│       │                                #   (id, name, one-character symbol, optional water_source: neutral by
│       │                                #   default, old_ford or lea_bridge, #209),
│       │                                #   `district_by_cell` (rows of symbols, `.` none), `zones` (id + cells); optional
│       │                                #   roads_enabled, road_diagonals, named_sites, history_notes. On load: whole street
│       │                                #   pieces, every buildable cell in a district, every patch of buildable land with a
│       │                                #   street on a side (stairs are none) and at least map.min_riverside_buildable
│       │                                #   buildable cells with a side on the river. Stairs block building.
│       ├── whitechapel_full.json        # the full map in that format (#204, D-093): 48x80, three parishes on old_ford,
│       │                                #   drawn from sources/whitechapel_full_sources.csv; played by scenarios/whitechapel_full
│       └── sources/<map>/               # traced layers (GeoJSON, EPSG:27700) + import.json + overrides.json (README.md)
├── locale/
│   └── ui.csv                # player-facing strings (keys, es, en); read only through src/ui/strings.gd
├── src/
│   ├── sim/                  # pure simulation (RefCounted, no Node)
│   │   ├── simulation.gd     # owns state, tick(), apply_command(), snapshot()
│   │   ├── economy_state.gd  # stocks (global warehouse, D-011), money (int pence), buildings, the player's streets, population
│   │   ├── road_network.gd   # streets of the distance model (#67): connection, street steps (pieces, #186), diagonal edges
│   │   ├── params.gd         # get_value(key) = base data ∘ difficulty layers ∘ role modifiers
│   │   ├── data_layers.gd    # preset + knobs → `set` modifiers, with clear errors for a knob out of range
│   │   ├── modifier.gd       # {key, op: add|mul|set, value}
│   │   ├── data_loader.gd    # JSON → typed defs, with validation errors
│   │   ├── mod_layer.gd      # mods (D-049, D-065): user://mods/<name>/data/ merged over data/ before validation
│   │   ├── defs/             # building_def.gd, good_def.gd, recipe_def.gd, class_def.gd, need_def.gd …
│   │   ├── systems/          # one file per tick step (see order below); water_system.gd is not one yet: the share
│   │   │                     #   of houses a fountain covers (water_d, #63, D-089), each house taking its safest water (#202), which the events will read
│   │   ├── commands/         # command classes / validation
│   │   ├── stats.gd          # rolling 60-tick windows for "per minute" figures
│   │   ├── series_def.gd, series_registry.gd  # statistics series: label, unit, aggregation, dimensions (D-066)
│   │   └── stats_history.gd, cause_log.gd     # chapter history in three levels and the cause events (D-066)
│   ├── game/                 # Node side: sim_clock.gd, game.gd (autoload), map_view (colored squares), camera,
│   │                         #   save_file.gd, save_settings.gd, autosave.gd (#57), gamepad_bindings.gd (#68);
│   │                         #   city_camera.gd and city_layout.gd for the 3D greybox (#65)
│   └── ui/                   # stats_panel/, stats_screen/, mods_menu/, saves_menu/, build_bar/, controls/, defeat_banner/, strings.gd,
│                             #   map_presentation.gd (data/ui/map.json), city_presentation.gd (data/ui/city.json, #65)
├── scenes/
│   └── main.tscn             # composes map view + UI; no logic
├── tests/
│   ├── sim/                  # unit tests per system (test_production.gd, test_needs.gd, test_defeat.gd …)
│   ├── data/                 # test_data_valid.gd: every JSON loads, keys exist, no orphan params
│   ├── game/                 # Node side: sim clock, game session, map geometry, panels (test_sim_clock.gd …)
│   ├── tools/                # test_map_import.gd: rasterizing, overrides, and committed maps match their sources;
│   │                         #   map_sources (#170): projection, OHM, sheet fits, digitizer, comparison image
│   └── scenarios/            # 15-minute scripted games (balance harness, GDD success criteria)
│       ├── long/             # longer games (70 min, 4 h, 8 h); their many-seed checks (long_test_*.gd) stay out of CI
│       └── hard/             # the scripts above rewritten for Hard's 800 d (*_hard); only balance_report --preset hard plays them
├── tools/                    # run_tests.sh / run_tests.ps1, check_gdscript.sh / .ps1, run_long_tests.sh / .ps1, balance report script,
│                             # map_import.sh / .ps1 (map_import/: data/maps/sources/<map>/ → data/maps/<map>.json),
│                             # map_sources.sh / .ps1 (map_sources/, #170: OHM export and NLS sheets → GeoJSON layers,
│                             #   comparison image and nls_report.md; README.md there)
├── docs/                     # GDD.md, DECISIONS.md (canonical), ARCHITECTURE.md, WORKFLOW.md
└── .github/                  # ci.yml, export.yml, PR template
```

## Tick order (one place, `simulation.gd`)
1. Apply queued commands. A build is checked against the map over its whole footprint (`EconomyContext.placement_reason`,
   issue #184, D-086: the building's `cell` is the north-west corner of `footprint` w x h cells, all inside the map and
   none taken by another footprint or a street; any of its cells demolishes it, and a street cannot go on one): the
   standing buildings (`existing_cells`) block new building (D-075), but a saved building on one of them stays and
   works (D-076). Before tick 0, `Simulation.create_new` puts down the map's starting dense housing
   (`dense_housing_cells`, as many as `startup.dense_housing_occupied`; not buildable by the player) and the other
   anchors with a use (`anchors`, #152). A demolish never removes an anchor (`historic_anchor`). The 1870 houses of the
   map (`period_houses`, #176, D-083) stand there too as dense housing with their `start_population` (0 on the strip),
   and a demolish never removes them either (`historic_anchor`, #180, D-085). A `RepairWharfCommand` turns a damaged
   wharf of the map (`damaged_wharves`) with nothing on it into a wharf for `repair.wharf_cost_ratio`
   (`economy/repair.json`) of a new wharf, rounded down (#177, D-083). A new wharf may still be built there instead.
   A demolish never removes a house in a crisis either (`CrisisSystem.lock_reason`, #222): sick (`house_sick`, D-106)
   or exposed and in quarantine (`house_quarantine`, D-107). A `DisinfectCommand` pays the disinfection of a sick house
   within a health post's radius (D-104).
1a. Houses in a crisis (`CrisisSystem`, #222): quarantines and disinfections count down; a finished disinfection
   leaves the house clean, and once no house is sick every quarantine ends. Nothing makes a house sick yet: the D-054
   outbreaks (#87) will call `Simulation.mark_house_sick()` / `cure_house()`, which the tests use. A cure while a
   disinfection runs pays it back.
1b. Streets (`RoadSystem`, issue #67, D-034, D-070, D-080), only on a map with `roads_enabled` (the strip; the 8x8 of the
   harness has none, so nothing changes there). It runs here because the layout only changes in step 1 and the
   connection decides who works. From the historic streets of the map, the player's streets that join them side by
   side and the diagonal edges the map lists (`RoadNetwork`). A street is a piece of `roads.json` `footprint` cells
   (2x2 since issue #186, D-086): the historic ones are whole pieces on the grid of pieces, the player places one at a
   time from its north-west cell. A building with no street of the network beside any cell
   on the edge of its footprint (one of its four sides for a 1x1, D-079 with D-086) does not work (`no_road_access`),
   nor one whose inputs have suppliers but none it can reach (`no_route`); step 2 gives neither of them workers and a house without a street holds nobody. Each input comes
   from the nearest supplier (a building whose recipe makes it, or a good its data `supplies`; the wharf's imported
   flour only while flour imports are on), and its leg is recorded with its street steps, the pieces walked with both
   ends included, and its metres: steps times the side of a piece (`RoadSystem.metres`, piece side times
   `map.cell_size_m`, 50 m), so a route measures what it measured on cells of 50 m. A leg of `transport.expensive_m` or
   more is "expensive". A house gets a good only within the `service_radius_m` (metres along the streets, 0 = the
   whole network) of a building that `distributes` it; a class's
   access to a good is the room of its served houses over its people who have a house, because people move into the
   served houses first (D-081): a badly placed house is room nobody uses. The city's bread access weights the classes
   by their people. The satisfaction, the housing bonus and the hunger read the coverage times that
   access (`NeedsSystem.coverage`, `EconomyState.hunger_coverage`); consumption does not change. All of it is derived
   from the layout and the people, recomputed each tick and never saved.
2. Assign workers automatically: first one worker per building in chain order (wharf → mill → bakery → malthouse → brewery), then the rest by priority bakery → mill → wharf → malthouse → brewery; emigration frees jobs in reverse order (D-021). Only the classes that take jobs look for one: artisans never fill a post (D-021, D-033).
3. Sources: the market reprices (every `price_update_seconds`), stored wheat spoils a little, and the wharf buys wheat at the
   current price under the player's policy (`SetWheatPolicy`: accumulate price, max price, target stock and a safety reserve in minutes of mill,
   under which the max price stops applying; the pause toggle stops all buying). The warehouse has a capacity. The wharf buys imported flour that skips the mill
   (D-026); wheat fields on cultivable cells only.
   The wharf has one unloading capacity (its staffed wheat output per minute) that wheat, barley and the imported flour share; the tea is exempt (issue #50). The player's `SetUnloadingSplit` (whole percent to barley) is reserved first and the flour never touches it (issue #116). A lot of flour is paid at once and leaves a debt of units that the next ticks unload, before the wheat, from the rest (`MarketSystem._pay_flour_unloading`); the wheat keeps its purchase policy inside what that leaves. Barley's price walks on its own seeded generator so the wheat series does not move.
   `snapshot()["diagnostics"]["unloading_split"]` (`BreadDiagnostics.unloading_split`, issue #106) only reads this: the wheat per minute the split lets the staffed wharves unload against what the staffed mills grind, `active` when it falls short and barley has a share; the panel says it under the mill and in the bread's "why".
4. Converters: mill (wheat→flour), bakery (flour→bread), malthouse (barley→malt), brewery (malt→beer), limited by staffed jobs and input stock. Malt and beer have a warehouse cap (`market.malt.*`, `market.beer.*`): a full warehouse stops its producer instead of discarding output (only the artisans drink it, D-033, so a city without their housing still fills the warehouse and stops), and beer spoils a little each minute. Several producers of a capped good share its room and its fractions (ADR 0006).
5. Consumption: each class eats the goods it lists as needs at its own rate (bread by everyone, tea by the workers, beer by the artisans, D-025, D-033); tea and beer are drawn from the global store like a single balance; stale bread decays.
6. Hunger coverage: smooth bread coverage once, shared by hunger emigration and hunger riot defeat.
7. Satisfaction 0–100 with breakdown (one term per need good: bread, tea; tax burden, overcrowding). Inside this step `NeedsSystem` first scores every class's need categories (`Σ coverage × value`, met at the threshold) and sets the housing capacity (base + `min(bonus per met category, class maximum)`, issue #86), so the order of the tick does not change.
8. Growth: for each class, with its own housing, satisfaction and rates, hunger emigration with hysteresis takes priority; otherwise immigration if satisfaction is high and its housing has room, emigration if low (ADR 0008). With `population.growth.served_capacity_only`, the room immigrants count is only that of the served houses: those with every good of the class's `growth.served_categories` within reach (step 1b), minus the people, who fill the served houses first (D-081). No served room means no arrivals and no backlog; losing the bread evicts nobody (#180, D-085). Without streets every house counts. After a cholera failure (#202, D-090) the immigration of every class waits for
   `cholera.vacancy_min` and then goes `cholera.recovery_mult` times as fast for `cholera.recovery_min`
   (`MissionSystem.immigration_multiplier`, which reads the timers step 9b left the tick before).
   Then class mobility (`MobilitySystem`, issue #53, ADR 0009): people of a class's `mobility.from` rise into it while its category scores reach their minimums, the source class is satisfied enough and its housing still has room after this tick's arrivals; they fall back once its demotion category has been under its score for the set seconds. Both at a rate per minute through a fraction; promoted people leave their jobs, so the unemployed rise first.
9. Money: head tax per class, on the jobs it holds or on all of its residents (`tax.basis`), at the one rate the player sets; minus wages and building upkeep.
   Then the streets (issue #67): the units each building took out of the store this tick (counted in step 4) times its
   leg's metres times `transport.cost_per_unit_per_m` (worked out per piece, the order of the sums on cells of 50 m,
   issue #186), plus `roads.upkeep_per_minute` per player street, added to
   the upkeep in whole pence with the fraction carried, outside the administration multiplier (D-063).
9b. Missions (`MissionSystem`, issue #63, D-090): `MissionCommand` starts one (once per game) or abandons an active one
   in step 1; its effects run then. Each active mission counts down `mission.<id>.duration_min`, turned into ticks only
   by `SimTime.minutes_to_ticks`, the start tick included; on its last tick `goal_met` checks the goal once, on the state
   this tick left, and the mission is completed or failed for good, with that outcome's effects. It runs before defeat
   so that a mission whose `defeat_pause` key is true, while active, freezes the depopulation timer of this same tick
   (not reset: it goes on from there afterwards). With no mission started nothing changes.
   Old Ford (#202, D-090): with `events.enabled`, a mission with a `trigger` starts by itself after the countdown of
   the tick on which `closes_at_min` minus its duration falls (minute 40 − 6.5), so its single check is the tick of
   the outbreak. Its `source_risk` effects name a source (`old_ford`) and set the risk of the districts that drink
   from it (`EconomyState.district_source_risk`: 1 while it is cut and after a failure or an abandon, 0 once it is
   met). Its goal `water` compares the `WaterSystem.district_water` of each district with houses with
   `mission.min_water_d`; empty districts are skipped (D-098), and with no house in any district it fails (D-102).
   Each house belongs to the district of its placed cell (`district_by_cell`) and drinks from that district's `water_source`
   (`neutral`, `old_ford` or `lea_bridge`, #209); a map without districts is the one district `default`, drinking from
   the neutral source, and the cut falls on it. The `cholera` effect of a failure kills, in each failing district,
   `pop_d × cholera.fail_mortality × (1 − prep_d)` (pop_d = the district's share of the houses of the population; prep
   = `events.prep.w_water` × water_d, sewer and health 0 until they exist), rounded and spread over
   the classes by the largest remainders, not as emigration, and starts the vacancy and then the recovery. The
   `defeat_pause` lasts from the start to the end of the recovery. Nothing here draws a random number.
10. Defeat: update warning/defeat timers (bankruptcy, hunger riot, depopulation). Then evaluate victory objectives, unless this tick lost the city. Victory never blocks ticks or commands.
11. Stats + snapshot emitted. The chapter history (`StatsHistory`, D-066) samples every series and notes the causes
    that changed; step 1 also notes each command's outcome. It only reads the state.

## Data layers (D-049, D-065, ADR 0010)
Every value goes through the same layers, in this order: **base → mods → preset → knobs → role**.
1. **Base:** `data/` as shipped.
2. **Mods:** a mod is a folder `user://mods/<name>/data/` with JSON files at the same paths as `data/`
   (`economy/startup.json`, `eras/victorian/needs.json`…). `ModLayer` merges each one over its base document before
   `DataLoader` validates anything: objects merge field by field, numbers, switches and lists replace. So a mod
   passes the same schemas, `ParameterRanges` and cross rules as `data/`, and each error names the mod; a value a mod
   breaks is reported once, not again by the preset, knob or role that targets it. Order: the list in
   `user://mods/load_order.json` and then, alphabetically, any folder it leaves out; without the list, every folder
   alphabetically. When two mods set the same value the last wins and `DataLoadResult.mod_conflicts` records it.
   A path that is not in `data/` is an error; another era's files are skipped. A mod file over
   `ModLayer.MAX_FILE_BYTES` or nested deeper than `ModLayer.MAX_DEPTH` is rejected before it merges, and so is a
   symbolic link anywhere in `user://mods` (the mod folder, a folder or file inside it, or `load_order.json`): a mod
   is only what is inside its folder, and the error names the mod.
3. **Preset:** relative (`mul`/`add` on the values below it, so on base + mods). Normal has no modifiers.
4. **Knobs:** absolute; they replace the preset's value.
5. **Role:** last, through the single modifier function (D-014).

`DataLayers` resolves the preset and the knobs once, into `set` modifiers that `Params` applies before the role's;
whole keys are rounded there. The mods are already inside the catalog the other layers start from.

Only the game loads mods (`map_view`, from `ModLayer.DEFAULT_ROOT`); tests and `balance_report` call `load_all()`
without them, so nothing on the machine changes their results. The mods menu (`src/ui/mods_menu/`, inside the
stats panel) lists the active mods in order, their conflicts and the winner of each, and moves a mod up or down: the
map view saves the new `load_order.json`, loads the data again and starts a new game on the same difficulty. If the
new order does not validate, the previous list is written back and the game goes on. `GameSession` keeps the
difficulty, the active mods and their conflicts for saving (#57, see "Save and load").

## Chapter objectives (D-064, issue #56)
`data/scenarios/victorian_demo.json` defines `victory.stages`; a scenario without that property has no victory.
`DataCatalog.scenarios` holds only the structural stage definitions. Numbers use scenario-specific keys through
`Params`: `victory.<scenario>.<stage>.threshold` and either `.duration_seconds` (population/class population means)
or `.required_minutes` (consecutive tax minutes). `ParameterRanges` validates them, including role modifiers.
`GameSession` selects the demo by default and passes its definitions explicitly to `Simulation`; the balance runner
passes none, so its scenarios and CSV columns stay unchanged.

`VictorySystem` runs after money and defeat, before stats. Means require a full rolling window of tick samples.
Tax objectives sum actual integer `taxes_tick` over non-overlapping blocks of 60 ticks from game start. A complete
minute at or above the threshold adds one to the streak; a low minute resets it, with no tolerance or averaging
across minutes. Stages are independent and latch permanently. Completing all of them records a single victory;
a simultaneous defeat takes priority, and defeat after victory keeps the win record but ends the game.

`EconomyState.victory` (`VictoryState`) serializes windows, the partial tax minute, streaks, completion ticks and
the last shortfall. `snapshot()["victory"]` exposes stage progress and the last break (minute, revenue, threshold,
reason), without mutable state aliases. The panel renders it and announces victory once; it contains no objective
rules. Archive/statistics and autosave consumers can use this record when their features exist (#57, #82).

## Statistics history (D-066, issue #82)
`SeriesRegistry.build(params, context, victory_stages)` declares every series: metric, label key (`ui.stats.<metric>`,
translated in `locale/ui.csv`), unit, aggregation (`sum` for flows, `mean` or `last` for levels) and dimensions
(`class`, `good`, `building`, `category`, `source`, `cause`, `stage`, `condition`, `district`). Members come from the
data, so a new class or good gets its series without code. A series id is the metric and its members joined by `:`
(`income:tax:artisan`). Each series has a sampler that reads one tick of the state and never writes to it.

Part 2 (#130) adds per-tick counters to `EconomyState`, reset in `reset_flows()`, never saved and never read by a
system: per good, the units a converter made, took from the store (a converter's input, or what people ate), lost to
spoilage, and bought or imported (`count_produced`, `count_consumed`, `count_spoiled`, `count_bought`); per class,
arrivals, departures for `hunger` or `satisfaction`, and promotions and demotions; the share of `upkeep_tick` that
administration added; and demolition refunds. Each system writes its counter next to the stock or money it already
moves, in its own step of the tick. `expense:upkeep` is the base upkeep and `expense:administration` the rest;
`expense:construction` is what was paid and `income:refund` what demolitions gave back (the panel's
`construction_spent_tick` stays net).

`StatsHistory` keeps three levels, sized in `data/economy/stats.json` and read through `Params`: one value per second
for `stats.fine.span_seconds` (a ring, not saved), buckets of `stats.medium.bucket_seconds` for
`stats.medium.span_seconds`, and buckets of `stats.chapter.bucket_seconds` for the whole chapter. A closed bucket
keeps four float32 fields (16 B): min, max, mean and a total, which is the sum for `sum` and `mean` series and the
last value for `last` series. Buckets line up on the history's own clock of recorded seconds, which is saved with it.
`CauseLog` keeps `{second, kind, subject, cause}` events only when the cause of a `kind|subject` changes, up to
`stats.causes.max_events` (a ring: the oldest are dropped). A change is logged once it lasts
`stats.causes.min_duration_seconds`, with the second it began; a subject that flips faster gets one `intermittent`
event whose `count` grows with every change that did not last, until a cause holds and is logged. The first cause of
a subject, `gone`, and the `command`, `defeat` and `victory` kinds skip that filter. Kinds: `command` (accepted or the refusal reason), `building`
(`BreadDiagnostics.building_reason` per building with jobs, `gone` once demolished), `import` (tea and flour
reasons), `emigration` (`hungry_leaving`, `unhappy_leaving` or `none` per class), `policy` (tax, wheat purchases
and policy, unloading split, imports), `defeat` (each condition's status) and `victory` (each stage).

`Simulation` exposes it read-only: `stats_series_defs()`, `stats_series(id, tier)`, `stats_events(from_second)` and
`stats_history_to_dict()`; its constructor takes the saved dictionary as its last argument. A missing history starts
empty; a malformed one (other version, sizes that do not match, buckets of another length) starts empty with a
warning. A series the save lacks reads as NaN for the saved buckets. The saved form uses packed arrays per series and
is meant for `var_to_bytes` + compression (`StatsHistory.compressed_size`, the measure of the 5 MB criterion).

## Save and load (D-037, D-067, issue #57, ADR 0011)
A save is one Variant written with `store_var` into a ZSTD-compressed file, never with objects, in `user://saves/`.
`SaveFile.build(session)` makes the envelope: `format`, `version` (`SaveFile.VERSION`), `saved_at`, `scenario`,
`difficulty`, `knobs` (empty until something sets them), `mods` in load order and `simulation`, which is
`Simulation.to_save()`: `EconomyState.to_dict()`, the stats window, `stats_history_to_dict()`, the tick, the seed and
both generators' states. `Simulation.from_save()` rebuilds it and restores the tick and the generators, so a game
saved at minute N and played to M ends in the same state as one never saved (`tests/sim/test_save_round_trip.gd`).
The tick and its order do not change.

A save holds the state at the end of the last tick; commands still queued stay in the running game and are not
in the file (the panel says so when that happens). `SaveFile.read` refuses a file that is not a save or whose economy
lacks a field (or its kind of value) that a new `EconomyState` has, and one of another version (the player's streets and
the transport fraction of issue #67 are the exception: a save from before them loads with no streets, D-080);
`SaveFile.check_compatible` refuses another scenario, an unknown difficulty and other mods (another set or order).
A save of format 1 was played on cells of 50 m and still loads (D-087, issue #186): `GameSession.load_save` passes it
through `SaveFile.upgraded`, which puts every old cell (x, y) at the corner of its 2x2 block (2x, 2y), in the
buildings, the player's streets and the buildings the causes of the history name (`<id>@<x>,<y>`). The converted game
plays on as it did (`tests/game/test_save_upgrade.gd`) and is saved again in the current format.
Each refusal is a message from `Strings.save_refusal` and the current game goes on. A missing or broken history
still loads (D-066).

`Autosave` listens to `GameSession.snapshot_changed`, so it always runs right after a tick: every
`autosave_interval_seconds` into `autosave_slots` rotating files (`autosave_<n>.sav`, going on after the newest one on
disk), plus one file per chapter stage the moment it is met (`stage_<id>.sav`), outside the rotation; a loaded game
does not save its met stages again. Manual saves (`manual_<unix time>.sav`) are unlimited and never overwritten. The
saves menu (`src/ui/saves_menu/`, inside the stats panel) saves and lists every file newest first; the map view
writes and reads them and loads a save on the parameters of its difficulty (`GameSession.load_save`).

The Archive (issue #64, D-110) is a panel in the game, opened by the stats panel's Archive button. `ArchiveCatalog`
(`src/ui/archive_catalog.gd`) loads `data/eras/victorian/archive/` and `ArchivePanel` (`src/ui/archive_panel/`) only
reads `snapshot()["economy"]["missions"]`: a card opens once its mission is completed, failed or abandoned
(`ArchiveCatalog.is_unlocked`), and until then shows only its kind. It sends no command.

## Input: mouse, keyboard and gamepad (D-048, issue #68)
`GamepadBindings.install()` (called by the map view) adds the gamepad actions to the `InputMap` in code, and A and B
to `ui_accept` and `ui_cancel`, which Godot leaves without a gamepad button. The map view has two modes. **Map**
(nothing has the focus): the d-pad moves a cell cursor, which is the selection (`MapGeometry.move_selection`, and
`follow_selection` moves the camera when it leaves the view); LB/RB pick among the buildings that can be built now,
and last the player's street on a map with streets (`GameSession.ROAD`, issue #168, D-080; key 9 and a click with the
keyboard, Delete demolishes it, D-082), A builds at the cursor (a street is a `BuildRoadCommand`, one cell). The map draws the player's streets
from the snapshot (`distance.player_roads`) in their own colour, and the panel names each transport leg the snapshot
marks `expensive` under the buildings. X demolishes only after it is held for `demolish_hold_seconds` (`MapPresentation.input`, from
`data/ui/map.json`); a ring on that cell fills during the hold (issue #164, D-078). Releasing X early, or moving the
cell cursor, cancels without a command, and finishing the hold submits one demolish even if X stays down. The stick
does not cancel it. While the panel has the focus, X does not start or finish a hold. B goes back to selecting, the
stick pans and the triggers zoom one step. Delete still demolishes on press.
Tierra de época (issue #178, D-083): free land is drawn in the colour of its lot style (`lot_styles` of the map,
colours in `data/ui/map.json`, a second legend row), and each damaged wharf the snapshot lists as repairable
(`snapshot()["repair"]["wharves"]`: cell and cost, from `RepairWharfCommand.snapshot`) is drawn over its footprint with
its price. The mode line names the selected lot and, on any cell of a damaged wharf, the repair and its cost; R (Y on
the gamepad) sends a `RepairWharfCommand` for that wharf. Elsewhere it goes for the selected cell and the simulation
answers `not_damaged_wharf`.
**Panel**: Menu calls `StatsPanel.enter_focus()`, which makes buttons, switches and sliders focusable and focuses the
first visible one; the d-pad moves the focus, left and right step sliders and numbers, and B, Menu or a click on the
map call `leave_focus()`. View pauses in either mode. With the mouse, buttons never keep the focus, so the map's keys
keep working after a click. The saves and mods menus give the focus back to the same button after rebuilding. The
help in the header switches to the gamepad's buttons (`ui.help_gamepad`) while a gamepad is in use. The window opens
at 1280×800, the Steam Deck's resolution.
**Statistics screen** (`src/ui/stats_screen/`, issue #83, D-052): the panel's Statistics button opens a full-window
`StatsScreen` over the map and the panel. It only reads the history of #82 (`Simulation.stats_series`, medium level) and
sends no command. While it shows, the map view passes it every event and polls nothing: LB/RB change tab and B or Esc
go back. Its look (palette, dash of each stroke, 16 px text, summary window) is in `data/ui/stats.json`.

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
- State classes expose `to_dict()`/`from_dict()`; saving builds on them (see "Save and load"), so a new field has to
  travel in both.
- Player-facing text is a key in `locale/ui.csv` (Spanish and English) and is read only through `Strings` in `src/ui/strings.gd`. It is presentation and is not part of the tick.
- Renderer: **Compatibility** (OpenGL) — enough for 2D squares, runs on older Macs/PCs and in CI.
