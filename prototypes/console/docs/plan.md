# Ship Sim Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Godot 4.7 prototype of a three-room ship interior: a dashboard shows each room's atmosphere and every system, breaker and tank, and a command line is the only way to act on the ship.

**Architecture:** A node-free simulation core (rooms, openings, power, systems, tanks, controllers) is stepped at a fixed 0.1 s by `Ship.step()`. A pure command interpreter turns a typed line into calls on the `Ship` and a response line. A pure dashboard model turns the `Ship` into display strings and status levels. A thin UI layer draws the model and feeds the console's lines to the interpreter.

**Tech Stack:** Godot 4.7 (`/opt/homebrew/bin/godot`), GDScript, the headless test runner from `prototypes/transit/tests`.

**Spec:** `prototypes/shipsim/docs/design.md`

## Global Constraints

- Everything lives under `prototypes/shipsim/`, the Godot project root. Commands below run from there.
- Internal units are SI: m³, mol, Pa, K, W, s. Only the dashboard model converts to kPa and °C.
- `R = 8.314462618`. 21 °C is 294.15 K.
- The sim steps at exactly `Ship.STEP_S = 0.1` s of sim time. Nothing advances the sim except whole steps.
- IDs, exactly: rooms `cockpit`, `main`, `cargo`; openings `d1`, `d2`, `hatch`; breakers `light-cockpit`, `light-main`, `light-cargo`, `d1`, `d2`, `hatch`, `pressure-control`, `hvac`, `air-recycler`; systems `pressure-control`, `hvac`, `air-recycler`, `computer`; gases `O2`, `N2`, `CO2`.
- Every tunable number in the spec lives in `data/ship.json`. Scripts hold no copies of them.
- All randomness comes from one `RandomNumberGenerator` seeded from the data file.
- Text is 19 px (`gui/theme/default_font_size=19`), the window is 1600×900, and the UI scales with the display's HiDPI factor the way `prototypes/transit/scripts/ui/main.gd` does.
- Every command prints exactly one line, except `help` and `ships list` (one line per ship).
- Tests: `godot --headless --path . --import` once (and after adding a `class_name` script), then `godot --headless --path . -s res://tests/run_tests.gd [-- <filter>]`. The runner prints `ok:` or `FAIL:` per test and ends with `N passed, M failed`. A test that logs an unexpected error fails.
- Commits are prefixed `shipsim: `.

## Drift and side-effect sweep

Not applicable: this is a new, standalone Godot project. It reads and writes no data and calls no functions that exist elsewhere in the repo.

## Research checks

1–3. Not applicable: no shared interface, data pipeline or response path. The project shares nothing at runtime with the other prototypes.

4. Existing patterns, from `prototypes/transit`, which every kind of thing here follows:
- **Test runner and base class:** `tests/run_tests.gd`, `tests/support/test_case.gd`, `tests/support/error_log.gd`, copied unchanged. Each prototype is its own Godot project, so it carries its own copy, as `ship` and `transit` do.
- **Loading the data file:** `scripts/fleet_loader.gd`. Static `load_file(path)` and `from_dict(data)`, a `_find_problem(data) -> String` check, and `push_error` plus `null` on bad data.
- **Core classes:** `class_name X extends RefCounted`, no nodes, a `##` doc comment under the class line (`scripts/sim_clock.gd`).
- **Clock:** `SimClock` with `paused`, `speed_index`, `tick(real_delta)` and `label()`.
- **Main scene:** `scripts/ui/main.gd`: `_match_display_scale()` and the static `scaled_window_size()`, and a `--capture <dir>` screenshot mode.
- No `## Patterns` section exists in the repo, and no kind of thing here has two competing patterns.

## Review Focus

1. **The hatch opening while a door is still opening.** `d2` at 50 % and opening must reverse and close, not finish opening. Test in Task 7.
2. **A breaker tripping mid-travel.** A hatch tripped at 50 % open stays half open, its room stays exposed, and it vents at half the rate. Test in Task 7.
3. **Messy typing.** Upper case, extra spaces, a missing argument, or an extra argument (`door open d1 now`) must each give a clear response, never a crash or a silent no-op. Tests in Task 9.
4. **A long frame at 100×.** One `advance()` of 25 s must run exactly 250 steps, and moles must never go negative through a full vent. Test in Task 6.
5. **A room in vacuum.** Shares and controllers must not divide by zero at 0 Pa, and the tile must show "—". Tests in Tasks 1 and 8.

---

### Task 1: Project skeleton, test runner, units and rooms

**Files:**
- Create: `project.godot`, `.gitignore`, `scripts/units.gd`, `scripts/room.gd`
- Copy from `prototypes/transit`: `tests/run_tests.gd`, `tests/support/test_case.gd`, `tests/support/error_log.gd`
- Test: `tests/test_room.gd`
- Also commit `docs/design.md` and `docs/plan.md` if the worktree doesn't have them yet.

**Interfaces:**
- Produces:
  - `Units.R: float`, `Units.GASES: Array[String] = ["O2", "N2", "CO2"]`, `Units.kelvin(celsius: float) -> float`, `Units.celsius(kelvin: float) -> float`
  - `Room.new(id: String, volume: float, temperature: float, crew: int)`
  - `Room` fields: `id`, `volume`, `temperature` (K), `crew`, `mol: Dictionary` (gas → mol, all three keys present, starting at 0), `heat_capacity: float` (J/K), `hull_conductance: float` (W/K). The loader sets the last two.
  - `Room.partial_pressure(gas: String) -> float` (Pa), `Room.pressure() -> float`, `Room.share(gas: String) -> float` (0–1, and 0 when the pressure is 0), `Room.total_mol() -> float`, `Room.set_partial_pressure(gas: String, pa: float) -> void`
  - `static Room.mol_for(pa: float, volume: float, temperature: float) -> float`

- [ ] **Step 1: Create `project.godot`** with `config/name="Ship Sim Prototype"`, `run/main_scene="res://scenes/main.tscn"`, features `"4.7", "Forward Plus"`, viewport 1600×900 and `theme/default_font_size=19`, matching transit's file. Create `.gitignore` containing `.godot`. Copy the three runner files.

- [ ] **Step 2: Write the failing tests in `tests/test_room.gd`**

```gdscript
extends TestCase

func test_partial_pressure_from_moles() -> void:
	var room := Room.new("main", 40.0, 294.15, 0)
	room.mol["O2"] = 1000.0
	assert_near(room.partial_pressure("O2"), 61142.48, 0.01, "nRT/V")
	assert_near(room.pressure(), 61142.48, 0.01, "only O2 present")

func test_setpoint_air_is_101_3_kpa() -> void:
	var room := Room.new("main", 40.0, 294.15, 0)
	room.set_partial_pressure("O2", 21200.0)
	room.set_partial_pressure("N2", 80100.0)
	assert_near(room.pressure(), 101300.0, 1e-6, "sum of partial pressures")
	assert_near(room.share("O2"), 21200.0 / 101300.0, 1e-9, "O2 share")

func test_vacuum_has_zero_shares() -> void:
	var room := Room.new("cargo", 30.0, 294.15, 0)
	assert_near(room.pressure(), 0.0, 0.0, "empty room")
	assert_near(room.share("O2"), 0.0, 0.0, "no divide by zero")

func test_mol_for_round_trips() -> void:
	var n := Room.mol_for(101300.0, 30.0, 294.15)
	assert_near(n, 1242.59, 0.01, "PV/RT for the cargo hold")
```

- [ ] **Step 3: Run the tests.** `godot --headless --path . --import`, then `godot --headless --path . -s res://tests/run_tests.gd -- room`. Expected: FAIL, because `Room` doesn't exist.

- [ ] **Step 4: Implement `scripts/units.gd` and `scripts/room.gd`** to the interfaces above.

- [ ] **Step 5: Run the tests.** Expected: `4 passed, 0 failed`.

- [ ] **Step 6: Commit.** `git add . && git commit -m "shipsim: project skeleton, test runner, rooms"`

### Task 2: Openings and exposure

**Files:**
- Create: `scripts/opening.gd`, `scripts/exposure.gd`
- Test: `tests/test_opening.gd`, `tests/test_exposure.gd`

**Interfaces:**
- Produces:
  - `Opening.State { CLOSED, OPENING, OPEN, CLOSING }`, `Opening.CommandResult { STARTED, ALREADY, NO_POWER }`
  - `Opening.new(id: String, room_a: String, room_b: String, travel_s: float)`. `room_b == Opening.OUTSIDE` (`"outside"`) marks the hatch.
  - Fields: `id`, `room_a`, `room_b`, `travel_s`, `fraction: float` (0–1), `state`, plus `conductance` (m³/s), `mixing` (m³/s) and `heat_conductance` (W/K), which the loader sets.
  - `Opening.command(want_open: bool, powered: bool) -> CommandResult`. Returns ALREADY when the opening is already in, or already moving toward, the wanted position. A command in the other direction reverses a moving opening.
  - `Opening.step(dt: float, powered: bool) -> void`. Moves `fraction` by `dt / travel_s` toward the target, and sets OPEN at 1 and CLOSED at 0. Without power, nothing changes.
  - `Opening.is_hatch() -> bool`, `Opening.passes() -> bool` (`fraction > 0`), `Opening.seconds_to_finish() -> float`
  - `static Exposure.exposed(room_ids: Array[String], openings: Array[Opening]) -> Dictionary` (room id → bool). A room is exposed when a chain of openings that `passes()` leads from it to `Opening.OUTSIDE`.

- [ ] **Step 1: Write the failing tests.**
  - `test_opening.gd`:
    - `test_door_opens_in_travel_time`: 20 steps of 0.1 s → OPEN with fraction 1; 10 steps → OPENING at 0.5 ± 1e-9.
    - `test_command_results`: open on CLOSED → STARTED; open again while OPENING → ALREADY; open when OPEN → ALREADY; close while OPENING at 0.5 → STARTED and state CLOSING with fraction still 0.5.
    - `test_unpowered_opening_holds_position`: open to 0.5, then 10 unpowered steps → fraction 0.5 and state OPENING; `command(false, false)` → NO_POWER.
    - `test_seconds_to_finish`: hatch (`travel_s` 6) at 0.25 and OPENING → 4.5 ± 1e-9.
  - `test_exposure.gd`: one test per row of the spec's exposure table, `test_hatch_closed_exposes_nothing` through `test_all_open_exposes_all_three`. Set fractions directly (1 for open, 0 for closed) and assert the whole dictionary. Add `test_partly_open_hatch_exposes`: hatch at 0.01 → cargo exposed.

- [ ] **Step 2: Run** `-- opening` and `-- exposure`. Expected: FAIL, because the classes don't exist.

- [ ] **Step 3: Implement** `scripts/opening.gd` and `scripts/exposure.gd`. Exposure is a breadth-first search from `OUTSIDE` over openings that pass.

- [ ] **Step 4: Run.** Expected: all pass.

- [ ] **Step 5: Commit.** `git commit -m "shipsim: doors, hatch and exposure"`

### Task 3: Gas flow and heat

**Files:**
- Create: `scripts/atmosphere.gd`
- Test: `tests/test_atmosphere.gd`

**Interfaces:**
- Consumes: `Room`, `Opening`
- Produces, all static on `Atmosphere`:
  - `flow_through_door(a: Room, b: Room, door: Opening, dt: float) -> void`. Bulk flow is `door.conductance × fraction × ΔP / (R × T_source) × dt` mol, taken from the source room in proportion to its composition. It is capped at the amount that would equalize the two pressures, which is `|ΔP| / (R T) / (1/V_a + 1/V_b)` with the source's T. Mixing then moves `door.mixing × fraction × dt / V` of each gas each way. Heat conduction moves `door.heat_conductance × fraction × (T_a − T_b) × dt` J from the warmer room to the cooler one.
  - `vent_through_hatch(room: Room, hatch: Opening, dt: float) -> float`. Multiplies every gas by `exp(−hatch.conductance × fraction × dt / V)` and returns the moles lost.
  - `add_heat(room: Room, joules: float) -> void` (`T += J / heat_capacity`)
  - `hull_loss(room: Room, hull_temperature: float, dt: float) -> void`

- [ ] **Step 1: Write the failing tests.** Build the rooms with `Room.new` and set `heat_capacity = 5000 × V` and `hull_conductance = 0.5 × V` by hand. Use door conductance 10, mixing 0.5 and heat conductance 100; for the hatch, conductance 5.
  - `test_rooms_equalize_and_conserve_moles`: cockpit (12 m³) at 101.3 kPa and main (40 m³) at 50 kPa, both at 294.15 K, door fraction 1, 300 steps of 0.1 s → both within 0.1 kPa of 61.838 kPa, and the total moles within 1e-6 of the start.
  - `test_closed_door_passes_nothing`: the same rooms with fraction 0 → moles unchanged and temperatures unchanged.
  - `test_mixing_carries_co2_at_equal_pressure`: equal pressures, with CO₂ only in main → cockpit CO₂ above 0 after 10 s.
  - `test_cargo_vents_on_schedule`: cargo at 101.3 kPa, hatch fully open → 37.27 ± 0.1 kPa after 6 s and below 1 kPa after 30 s.
  - `test_whole_ship_vents_in_about_95_s`: three rooms, both doors and the hatch open, stepped in the order door d1, door d2, hatch → every room above 1 kPa at 75 s and below 1 kPa at 110 s (the spec's "about 95 s" sits between them).
  - `test_unheated_room_cools`: main at 21 °C with 140 W added each step and hull loss to −20 °C → 10.72 ± 0.1 °C after 1 h.

- [ ] **Step 2: Run** `-- atmosphere`. Expected: FAIL.

- [ ] **Step 3: Implement `scripts/atmosphere.gd`.**

- [ ] **Step 4: Run.** Expected: all pass.

- [ ] **Step 5: Commit.** `git commit -m "shipsim: gas flow, venting and heat"`

### Task 4: Breakers and system states

**Files:**
- Create: `scripts/power_panel.gd`, `scripts/system_unit.gd`
- Test: `tests/test_power_panel.gd`, `tests/test_system_unit.gd`

**Interfaces:**
- Produces:
  - `PowerPanel.BREAKER_IDS: Array[String]`, in the order listed in Global Constraints
  - `PowerPanel.new(seed: int, mean_time_between_trips_s: float)`. The field `tripped: Dictionary` (id → bool) starts all false.
  - `PowerPanel.has(id: String) -> bool`, `PowerPanel.is_powered(id: String) -> bool`, `PowerPanel.trip(id: String) -> bool` (false when already tripped), `PowerPanel.reset(id: String) -> bool` (false when not tripped)
  - `PowerPanel.roll_random_trips(dt: float) -> Array[String]`. When the mean is above 0, it draws one `randf()` per breaker, in `BREAKER_IDS` order, every call, and trips each closed breaker whose draw is below `dt / mean`. It returns the IDs it tripped. When the mean is 0, it draws nothing and returns `[]`.
  - `SystemUnit.State { RUNNING, BOOTING, FAULT, NO_POWER }`, `SystemUnit.RestartResult { REBOOTING, NO_POWER }`
  - `SystemUnit.new(id: String, boot_s: float)`, with fields `id`, `boot_s`, `boot_left_s` and `state`, starting RUNNING
  - `SystemUnit.step(dt: float, powered: bool) -> bool`, true when the state changed. Losing power → NO_POWER. Power coming back to NO_POWER → BOOTING with `boot_left_s = boot_s`. BOOTING counts down, then RUNNING.
  - `SystemUnit.restart(powered: bool) -> RestartResult` (BOOTING from any powered state, FAULT included), `SystemUnit.fault() -> bool` (false when NO_POWER or already FAULT), `SystemUnit.is_running() -> bool`

- [ ] **Step 1: Write the failing tests.**
  - `test_power_panel.gd`:
    - `test_trip_and_reset`: the return values for each case.
    - `test_no_random_trips_at_rate_zero`: 10,000 calls → none.
    - `test_random_trip_rate`: mean 10 s, 10,000 calls of 0.1 s, resetting every tripped breaker after each call → total trips 900 ± 120.
    - `test_same_seed_same_trips`: two panels with seed 7 give the same sequence of returned arrays over 2,000 calls.
  - `test_system_unit.gd`:
    - `test_power_loss_and_boot`: unpowered → NO_POWER; powered again → BOOTING; after `boot_s` → RUNNING.
    - `test_restart_clears_fault`: `fault()`, then `restart(true)` → REBOOTING and BOOTING.
    - `test_restart_without_power`: `restart(false)` → NO_POWER, state unchanged.
    - `test_fault_without_power_refused`: `fault()` while NO_POWER → false.

- [ ] **Step 2: Run** `-- power_panel` and `-- system_unit`. Expected: FAIL.

- [ ] **Step 3: Implement both scripts.**

- [ ] **Step 4: Run.** Expected: all pass.

- [ ] **Step 5: Commit.** `git commit -m "shipsim: breakers with random trips, system states"`

### Task 5: Tanks, crew and the three controllers

**Files:**
- Create: `scripts/tank.gd`, `scripts/life_support.gd`
- Test: `tests/test_tank.gd`, `tests/test_life_support.gd`

**Interfaces:**
- Consumes: `Room`, `Units`
- Produces:
  - `Tank.new(gas: String, capacity: float, mol: float)`, `Tank.draw(want: float) -> float` (what it actually gives), `Tank.fill(amount: float) -> float` (what it accepted, never past capacity), `Tank.fraction() -> float`
  - These are static on `LifeSupport`, and each is one room for one step:
    - `breathe(room: Room, o2_mol_s: float, co2_mol_s: float, dt: float) -> void`. Scales by `room.crew`. When less O₂ is available than the crew need, it uses what there is and scales CO₂ by the same ratio.
    - `pressure_control(room: Room, exposed: bool, tanks: Dictionary, setpoints_pa: Dictionary, max_mol_s: float, dt: float) -> void`. For `O2` and `N2`, it adds `min(mol to reach the setpoint at the room's current T, max_mol_s × dt, what the tank gives)`. It does nothing when the room is exposed.
    - `hvac_heat_w(room: Room, setpoint_k: float, gain_w_per_k: float, max_w: float) -> float`. Returns `clamp(gain × (setpoint − T), −max_w, max_w)`.
    - `recycle(room: Room, exposed: bool, o2_tank: Tank, max_co2_pa: float, min_pressure_pa: float, max_mol_s: float, dt: float) -> float`. Removes `min(mol above max_co2_pa, max_mol_s × dt)` of CO₂ and fills the O₂ tank with the same moles. Skips the room when it is exposed or below `min_pressure_pa`. Returns the moles removed.

- [ ] **Step 1: Write the failing tests.**
  - `test_tank.gd`: `test_draw_limited_by_contents`, `test_fill_limited_by_capacity` (capacity 3000, mol 2999, `fill(5)` → 1, then mol 3000).
  - `test_life_support.gd`:
    - `test_refill_cargo_from_vacuum`: cargo at 0 Pa, not exposed, full tanks, 20 mol/s, 600 steps → pressure 101.3 ± 0.1 kPa and ppO₂ 21.2 ± 0.05 kPa.
    - `test_never_feeds_exposed_room`: exposed → moles and tank levels unchanged after 100 steps.
    - `test_empty_o2_tank_stops_only_o2`: O₂ tank at 0 → N₂ reaches its setpoint and O₂ stays 0.
    - `test_hvac_output_clamped`: T 0 °C, setpoint 21 °C, gain 5000, max 1500 → 1500; T 30 °C → −1500.
    - `test_recycler_returns_o2_one_for_one`: main at 1.0 kPa CO₂, one step at 0.01 mol/s → removed 0.001, and the tank gained 0.001.
    - `test_recycler_stops_at_target`: CO₂ at 0.3 kPa → removes 0.
    - `test_recycler_skips_vacuum`: pressure 5 kPa → removes 0, and no error is logged.
    - `test_crew_stop_breathing_without_o2`: O₂ at 0 → CO₂ unchanged, and no negative moles.

- [ ] **Step 2: Run** `-- tank` and `-- life_support`. Expected: FAIL.

- [ ] **Step 3: Implement both scripts.**

- [ ] **Step 4: Run.** Expected: all pass.

- [ ] **Step 5: Commit.** `git commit -m "shipsim: tanks, crew, pressure control, HVAC, recycler"`

### Task 6: The ship, its data file and loader

**Files:**
- Create: `data/ship.json`, `scripts/event_log.gd`, `scripts/ship.gd`, `scripts/ship_loader.gd`, `tests/support/ship_fixture.gd`
- Test: `tests/test_ship_loader.gd`, `tests/test_ship.gd`

**Interfaces:**
- Consumes: everything from Tasks 1–5
- Produces:
  - `EventLog.CAPACITY = 50`, `EventLog.Level { INFO, WARNING, DANGER }`, `EventLog.add(time_s: float, text: String, level := Level.INFO) -> void`, `EventLog.entries: Array[Dictionary]` (`{time_s, text, level}`, oldest first, the last 50 kept), `EventLog.has_text(substring: String) -> bool`
  - `Ship.STEP_S = 0.1`, `Ship.SYSTEM_IDS = ["pressure-control", "hvac", "air-recycler", "computer"]`
  - `Ship` fields: `rooms: Array[Room]`, `openings: Array[Opening]`, `power: PowerPanel`, `systems: Dictionary` (id → SystemUnit), `tanks: Dictionary` (`"O2"`/`"N2"` → Tank), `light_switches: Dictionary` (room id → bool), `exposed: Dictionary`, `params: Dictionary` (the data file's sections as loaded), `time_s: float`, `events: EventLog`, `last_hvac_w: Dictionary` (room id → W), `recycler_scrubbing: bool`
  - `Ship.room(id: String) -> Room`, `Ship.opening(id: String) -> Opening` (null when unknown)
  - `Ship.step() -> void` and `Ship.advance(sim_seconds: float) -> int`. `advance` returns the steps it ran, and carries any leftover under one step into the next call.
  - `Ship.light_lit(room_id: String) -> bool` (the switch is on and `light-<room>` has power)
  - Command API, used by Task 9: `set_opening(id: String, want_open: bool) -> Dictionary` (`{result: Opening.CommandResult, auto_closed: Array[String], left_open: Array[String], onto_open_hatch: bool}`; Task 7 fills the last three), `set_light(room_id: String, on: bool) -> bool` (false when it was already in that position), `restart_system(id: String) -> SystemUnit.RestartResult`, `breaker_reset(id: String) -> bool`, `breaker_trip(id: String) -> bool`, `fault_system(id: String) -> bool`
  - `ShipLoader.load_file(path: String) -> Ship`, `ShipLoader.from_dict(data: Dictionary) -> Ship`
  - `ShipFixture.make(overrides := {}) -> Ship`. It loads `res://data/ship.json`, sets `breakers.mean_time_between_trips_h` to 0, deep-merges `overrides` (Dictionaries merge, everything else replaces), and calls `from_dict`.

**`data/ship.json`**, with these keys and the spec's values:

```json
{
  "seed": 7,
  "setpoints": { "o2_kpa": 21.2, "n2_kpa": 80.1, "co2_max_kpa": 0.3, "temperature_c": 21.0 },
  "rooms": [
    { "id": "cockpit", "volume_m3": 12, "crew": 1, "start": { "o2_kpa": 21.2, "n2_kpa": 80.1, "co2_kpa": 0.04, "temperature_c": 21.0 } },
    { "id": "main", "volume_m3": 40, "crew": 1, "start": { "...": "same as cockpit" } },
    { "id": "cargo", "volume_m3": 30, "crew": 0, "start": { "...": "same as cockpit" } }
  ],
  "openings": [
    { "id": "d1", "between": ["cockpit", "main"], "travel_s": 2, "conductance_m3s": 10, "mixing_m3s": 0.5, "heat_w_per_k": 100 },
    { "id": "d2", "between": ["main", "cargo"], "travel_s": 2, "conductance_m3s": 10, "mixing_m3s": 0.5, "heat_w_per_k": 100 },
    { "id": "hatch", "between": ["cargo", "outside"], "travel_s": 6, "conductance_m3s": 5 }
  ],
  "heat": { "capacity_j_per_k_m3": 5000, "hull_w_per_k_m3": 0.5, "hull_temperature_c": -20, "crew_w": 100, "light_w": 40 },
  "crew": { "o2_mol_s": 3.0e-4, "co2_mol_s": 2.6e-4 },
  "pressure_control": { "max_mol_s": 20, "boot_s": 10 },
  "hvac": { "gain_w_per_k": 5000, "max_w": 1500, "boot_s": 8 },
  "air_recycler": { "max_mol_s": 0.01, "min_pressure_kpa": 10, "boot_s": 15 },
  "computer": { "boot_s": 20 },
  "tanks": { "O2": { "capacity_mol": 3000, "start_mol": 3000 }, "N2": { "capacity_mol": 8000, "start_mol": 8000 } },
  "breakers": {
    "mean_time_between_trips_h": 24,
    "draw_w": { "light": 40, "door_idle": 5, "door_moving": 200, "hatch_idle": 5, "hatch_moving": 500,
                "pressure_control": 300, "hvac_base": 200, "air_recycler_scrubbing": 800, "air_recycler_idle": 50, "computer": 150 }
  },
  "status": {
    "pressure_kpa": { "nominal": [95, 105], "danger_below": 70, "danger_above": null },
    "o2_kpa": { "nominal": [19, 23.5], "danger_below": 16, "danger_above": 30 },
    "co2_kpa": { "nominal": [0, 0.5], "danger_below": null, "danger_above": 1.0 },
    "temperature_c": { "nominal": [18, 26], "danger_below": 10, "danger_above": 32 },
    "tank_percent": { "nominal": [25, 100], "danger_below": 5, "danger_above": null }
  }
}
```

Write each room's `start` out in full. The `"..."` above only shortens the plan.

**`Ship.step()` order:**
1. Roll random trips, logging `"<id>: breaker tripped"` as a WARNING.
2. Step every system with its breaker's power (the computer is always powered), logging each state change as `"<id>: running"`, `"<id>: no power"` or `"<id>: fault"`.
3. Step every opening with its breaker's power.
4. Recompute `exposed`. When a room becomes exposed, log `"<room>: exposed to vacuum"` as DANGER, and also `"pressure-control: not feeding <room> (exposed)"` when pressure control is running. When it stops being exposed, log `"<room>: sealed"`.
5. Doors' flow, then the hatch's venting.
6. Crew breathe.
7. Pressure control, when running.
8. The recycler, when running. Set `recycler_scrubbing` when any room removed more than 0.
9. When a tank has just reached 0, log `"<gas> tank empty"` as DANGER, once each time it empties.
10. Heat: crew, lit lights, and the HVAC when running (recorded in `last_hvac_w`, and 0 when it isn't running), then hull loss.
11. `time_s += STEP_S`.

- [ ] **Step 1: Write the failing tests.**
  - `test_ship_loader.gd`:
    - `test_loads_three_rooms_at_setpoint`: each room at 101.34 ± 0.01 kPa (with 0.04 kPa CO₂) and 21 °C.
    - `test_missing_key_is_reported`: drop `"tanks"`, `expect_error("missing 'tanks'")`, result null.
    - `test_unknown_room_in_opening_is_reported`: `expect_error("unknown room 'galley'")`.
  - `test_ship.gd`, all using `ShipFixture.make()`:
    - `test_cargo_vents_alone_with_d2_closed`: `set_opening("hatch", true)`, advance 60 s → cargo below 1 kPa; main and cockpit within 0.05 kPa of where they started.
    - `test_cargo_refills_after_hatch_closes`: vent as above, then `set_opening("hatch", false)` and advance 90 s → cargo 101.3 ± 0.2 kPa, with no command in between.
    - `test_hvac_holds_setpoint`: advance 2 h → every room within 0.5 K of 21 °C.
    - `test_recycler_holds_co2_down`: advance 24 h → every room's ppCO₂ below 0.5 kPa.
    - `test_co2_rises_with_recycler_tripped`: `breaker_trip("air-recycler")`, advance 6 h → cockpit ppCO₂ above 1.0 kPa.
    - `test_o2_tank_steady_with_recycler`: advance 24 h → the O₂ tank lost less than 20 mol.
    - `test_o2_tank_drains_without_recycler`: trip it, advance 24 h → the O₂ tank lost more than 45 mol.
    - `test_trip_removes_function` (one assertion per component): a tripped light → `light_lit` false; a tripped door → `set_opening` NO_POWER; a tripped `pressure-control` → no refill after a vent; a tripped `hvac` → `last_hvac_w` all 0.
    - `test_reset_boots_system`: trip and reset `hvac` → BOOTING, then RUNNING after 8 s.
    - `test_light_switch_survives_trip`: trip `light-main` → not lit; reset → lit.
    - `test_life_support_runs_with_computer_down`: `fault_system("computer")`, then vent and reseal cargo → it still refills.
    - `test_long_frame_runs_whole_steps`: `advance(25.0)` returns 250, then `advance(0.05)` returns 0 and `advance(0.05)` returns 1.
    - `test_no_negative_moles_through_full_vent`: open the hatch with d2 tripped open (set `opening("d2").fraction = 1` and state OPEN before tripping), advance 300 s → every gas in every room ≥ 0.
    - `test_same_seed_same_run`: two ships with random trips on (`mean_time_between_trips_h` 0.01), the same commands, advance 1 h → the same `power.tripped`, and the same moles in every room to 1e-9.

- [ ] **Step 2: Run** `-- ship`. Expected: FAIL.

- [ ] **Step 3: Implement** the data file, `EventLog`, `Ship`, `ShipLoader` (in the `FleetLoader` pattern, checking every top-level key and every room referenced by an opening) and `ShipFixture`. In this task, `set_opening` just calls `Opening.command` with the breaker's power.

- [ ] **Step 4: Run** the whole suite. Expected: all pass.

- [ ] **Step 5: Commit.** `git commit -m "shipsim: ship, data file and loader"`

### Task 7: Auto-close, ship warnings and power draw

**Files:**
- Modify: `scripts/ship.gd`
- Test: `tests/test_ship_doors.gd`, `tests/test_power_draw.gd`

**Interfaces:**
- Consumes: `Ship` from Task 6
- Produces:
  - `set_opening` fills `auto_closed`, `left_open` and `onto_open_hatch`
  - `Ship.draw_w(breaker_id: String) -> float`, `Ship.computer_draw_w() -> float`, `Ship.total_draw_w() -> float`

**Rules:**
- When `set_opening("hatch", true)` returns STARTED, each door that `passes()` or is OPENING is commanded closed, if powered, and logged `"<door>: closing (hatch opening)"`. An unpowered door goes in `left_open` and is logged `"<door>: no power, left open with hatch opening"` as a WARNING. A door whose fraction is 0 and which isn't opening is left alone.
- `set_opening(door, true)` while the hatch `passes()` obeys and sets `onto_open_hatch`, and logs `"<door>: opened onto an open hatch"` as a WARNING.
- Draw comes from `params.breakers.draw_w`. A light draws only while lit. A door or the hatch draws `*_moving` while OPENING or CLOSING with power, and `*_idle` otherwise. Pressure control draws while not NO_POWER. The HVAC draws `hvac_base + Σ|last_hvac_w|`. The recycler draws `scrubbing` while `recycler_scrubbing`, and `idle` otherwise. A tripped breaker draws 0. The total includes the computer.

- [ ] **Step 1: Write the failing tests.**
  - `test_ship_doors.gd`:
    - `test_hatch_closes_open_doors`: d1 and d2 OPEN; open the hatch → `auto_closed == ["d1", "d2"]`; after 2 s both CLOSED.
    - `test_hatch_reverses_opening_door` (Review Focus 1): d2 OPENING at 0.5; open the hatch → d2 CLOSING; after 1 s CLOSED; cargo exposed and main not.
    - `test_unpowered_door_stays_open`: d2 OPEN then tripped; open the hatch → `left_open == ["d2"]`; after 120 s, main below 1 kPa too.
    - `test_whole_ship_vents_with_both_doors_unpowered`: d1 and d2 OPEN and tripped; open the hatch, advance 120 s → all three rooms below 1 kPa.
    - `test_reopening_door_onto_open_hatch_warns`: hatch OPEN, `set_opening("d2", true)` → STARTED, `onto_open_hatch` true, and the event log has `"opened onto an open hatch"`.
    - `test_hatch_tripped_half_open_vents_at_half_rate` (Review Focus 2): open the hatch, advance 3 s, trip `hatch` → fraction 0.5 ± 0.02. After 12 more seconds cargo is near `p₃ × exp(−5 × 0.5 × 12 / 30)` ± 2 %, where p₃ is cargo's pressure at the trip, and cargo is still exposed.
    - `test_exposure_events_logged`: open and close the hatch → the log has `"cargo: exposed to vacuum"`, `"pressure-control: not feeding cargo (exposed)"` and `"cargo: sealed"`.
  - `test_power_draw.gd`:
    - `test_idle_ship_draw`: at start, after 1 s → `draw_w("light-main")` 40, `draw_w("d1")` 5, `computer_draw_w()` 150.
    - `test_moving_door_draw`: d1 opening → 200.
    - `test_tripped_breaker_draws_nothing`: trip `hvac` → 0.
    - `test_total_is_sum`: total equals the sum over `BREAKER_IDS` plus the computer.

- [ ] **Step 2: Run** `-- ship_doors` and `-- power_draw`. Expected: FAIL.

- [ ] **Step 3: Implement the rules in `scripts/ship.gd`.**

- [ ] **Step 4: Run** the whole suite. Expected: all pass.

- [ ] **Step 5: Commit.** `git commit -m "shipsim: hatch auto-closes doors, warnings, power draw"`

### Task 8: Status levels and the dashboard model

**Files:**
- Create: `scripts/status.gd`, `scripts/dashboard_model.gd`
- Test: `tests/test_status.gd`, `tests/test_dashboard_model.gd`

**Interfaces:**
- Consumes: `Ship`
- Produces:
  - `Status.Level { NOMINAL, WARNING, DANGER }`, `static Status.classify(value: float, band: Dictionary) -> Level`, using the data file's band shape. Both ends of `nominal` are inclusive. A value below `danger_below` or above `danger_above` is DANGER, and everything else is WARNING. `static Status.worst(levels: Array) -> Level`
  - These are static on `DashboardModel`:
    - `room_tile(ship: Ship, room_id: String) -> Dictionary` with keys `title` (`"COCKPIT"`), `pressure` (`"101.3 kPa"`), `temperature` (`"21.0 °C"`), `o2` (`"20.9 %"`), `n2` (`"79.0 %"`), `co2` (`"0.04 kPa"`), `lit: bool` and `level: Status.Level`. Below 1 kPa, `o2`, `n2` and `co2` are `"—"`. The level is the worst of pressure, ppO₂, ppCO₂ and temperature.
    - `opening_text(ship: Ship, id: String) -> String`: `"OPEN"`, `"CLOSED"`, `"OPENING 40 %"` or `"CLOSING 60 %"`, with `" (no power)"` appended when its breaker is tripped
    - `system_text(ship: Ship, id: String) -> String`: `"RUN"`, `"BOOT 9s"` (rounded up), `"FAULT"` or `"NO POWER"`
    - `breaker_text(ship: Ship, id: String) -> String`: `"■ 40 W"` (whole watts) or `"□ TRIP"`
    - `tank_percent(ship: Ship, gas: String) -> int` (rounded down), `tank_level(ship: Ship, gas: String) -> Status.Level`
    - `clock_text(time_s: float) -> String`: `"T+00:42:17"`
    - `total_draw_text(ship: Ship) -> String`: `"total 3.1 kW"`
    - `top_alarm(ship: Ship) -> Dictionary`, `{text: String, level: Status.Level}`. It collects candidates in this order: an exposed room as `"<ROOM> EXPOSED"` (DANGER); each room's readings in the order pressure, O₂, CO₂, temperature, as `"<ROOM> PRESSURE LOW"`, `"<ROOM> O₂ HIGH"`, `"<ROOM> CO₂ HIGH"`, `"<ROOM> TEMPERATURE LOW"` and so on, at their level; tanks as `"O₂ TANK LOW"`; systems in FAULT or NO POWER as `"<ID> FAULT"` or `"<ID> NO POWER"` (WARNING); tripped breakers as `"BREAKER <id> TRIPPED"` (WARNING). It returns the first candidate at the highest level present, or `{text: "", level: NOMINAL}` when there are none.

- [ ] **Step 1: Write the failing tests.**
  - `test_status.gd`: the boundaries of every row of the spec's status table. Pressure 95 → NOMINAL, 94.9 → WARNING, 69.9 → DANGER, 110 → WARNING. CO₂ 0.5 → NOMINAL, 0.51 → WARNING, 1.01 → DANGER. Temperature 9.9 → DANGER, 32.1 → DANGER. Tank 25 → NOMINAL, 4.9 → DANGER.
  - `test_dashboard_model.gd`:
    - `test_tile_at_start`: cockpit → `"101.3 kPa"`, `"21.0 °C"`, `"20.9 %"`, `"79.0 %"`, `"0.04 kPa"`, lit, NOMINAL.
    - `test_vacuum_tile_shows_dashes` (Review Focus 5): cargo vented → `"—"` ×3 and DANGER, with no error logged.
    - `test_opening_and_system_text`: d1 at 0.4 and OPENING → `"OPENING 40 %"`; tripped → `"OPENING 40 % (no power)"`; hvac restarted, 0.5 s later → `"BOOT 8s"`.
    - `test_breaker_text`: `"■ 40 W"`, and `"□ TRIP"` after a trip.
    - `test_clock_text`: 2537 s → `"T+00:42:17"`; 90061 s → `"T+25:01:01"`.
    - `test_top_alarm_prefers_exposure`: cargo vented and hvac tripped → `"CARGO EXPOSED"`, DANGER.
    - `test_top_alarm_trip_only`: only `hvac` tripped → `"HVAC NO POWER"`, WARNING (systems come before breakers).
    - `test_top_alarm_nominal`: at start → `""`.

- [ ] **Step 2: Run** `-- status` and `-- dashboard_model`. Expected: FAIL.

- [ ] **Step 3: Implement both scripts.** The status bands come from `ship.params.status`.

- [ ] **Step 4: Run.** Expected: all pass.

- [ ] **Step 5: Commit.** `git commit -m "shipsim: status levels and dashboard model"`

### Task 9: Sim clock and command interpreter

**Files:**
- Create: `scripts/sim_clock.gd`, `scripts/command_interpreter.gd`
- Test: `tests/test_sim_clock.gd`, `tests/test_command_interpreter.gd`

**Interfaces:**
- Consumes: the `Ship` command API (Tasks 6–7)
- Produces:
  - `SimClock.SPEEDS = [1.0, 10.0, 100.0]`, `paused: bool`, `speed_index: int` (starts at 0), `tick(real_delta: float) -> float` (sim seconds to advance, 0 when paused), `label() -> String` (`"▶ 10×"` or `"❚❚ Paused"`)
  - `static CommandInterpreter.run(ship: Ship, line: String) -> String`. It lower-cases the line, splits on whitespace, and returns `""` for a blank line. For any other line, it logs `"> <line as typed>"` and then the response to `ship.events`, and returns the response.

**Responses**, exactly (`<s>` is `ceil(seconds_to_finish)`):

| Input | Response |
|---|---|
| `door open X`, started | `X: opening (<s> s)` |
| hatch opening that auto-closed doors | `hatch: opening (6 s); closing d1, d2` |
| hatch opening with a door left open | `hatch: opening (6 s); d2 has no power and stays open` (both suffixes when both apply, closing first) |
| door opened onto an open hatch | `d2: opening (2 s); warning: hatch is open` |
| `door close X`, started | `X: closing (<s> s)` |
| ALREADY | `X: already open`, `already closed`, `already opening` or `already closing`, by state |
| NO_POWER | `X: no power (breaker tripped)` |
| unknown door | `unknown door 'X'. Doors: d1, d2, hatch` |
| `light on/off R` | `R light: on` or `R light: off`; `R light: already on`/`off`; switched on without power: `R light: on (no power; reset breaker 'light-R')` |
| unknown room | `unknown room 'X'. Rooms: cockpit, main, cargo` |
| `S restart` | `S: rebooting (<boot_s> s)`, or `S: no power; reset breaker 'S' first` |
| `breaker reset B` | `B: breaker reset`, or `B: breaker is not tripped` |
| unknown breaker | `unknown breaker 'X'. Breakers: <the nine IDs, comma-separated>` |
| `debug trip B` | `B: breaker tripped`, or `B: breaker already tripped` |
| `debug fault S` | `S: fault injected`, or `S: no power`, or `S: already in fault` |
| unknown system after `debug fault` | `unknown system 'X'. Systems: pressure-control, hvac, air-recycler, computer` |
| right verb, wrong argument count | `usage: door open <d1\|d2\|hatch>` (each command's own usage line) |
| anything else | `unknown command '<first two words>'. Type 'help' for commands` (one word when only one is given) |
| `help` | one line per command in the spec's table, `<usage> — <effect>` |
| computer BOOTING, any input | `computer: rebooting; try again in <s> s` |
| computer FAULT, anything but `computer restart` | `computer: fault; only 'computer restart' works` |

- [ ] **Step 1: Write the failing tests.**
  - `test_sim_clock.gd`: paused → 0; speed 2 → `tick(0.5)` = 50; labels.
  - `test_command_interpreter.gd`: one test per row of the table, named after it. Assert the exact string with `ShipFixture.make()`. Also:
    - `test_case_and_spacing`: `"  DOOR   Open   HATCH "` with every door closed → `"hatch: opening (6 s)"`.
    - `test_extra_argument`: `door open d1 now` → `"usage: door open <d1|d2|hatch>"` (Review Focus 3).
    - `test_missing_argument`: `door open` → the same usage line.
    - `test_blank_line`: `"   "` → `""`, and nothing logged.
    - `test_command_logged`: after `light off main`, the log's last two entries are `"> light off main"` and `"main light: off"`.
    - `test_computer_fault_allows_only_restart`: `debug fault computer`; `light off main` → the fault line; `computer restart` → `"computer: rebooting (20 s)"`; `light off main` right after → `"computer: rebooting; try again in 20 s"`.

- [ ] **Step 2: Run** `-- sim_clock` and `-- command_interpreter`. Expected: FAIL.

- [ ] **Step 3: Implement both scripts.** Dispatch on the first word through a dictionary of verb → handler, so each command's handler, usage line and help line sit together.

- [ ] **Step 4: Run.** Expected: all pass.

- [ ] **Step 5: Commit.** `git commit -m "shipsim: sim clock and command interpreter"`

### Task 10: Dashboard UI, console, screenshot mode and README

**Files:**
- Create: `scenes/main.tscn`, `scripts/ui/main.gd`, `scripts/ui/dashboard_view.gd`, `scripts/ui/console.gd`, `README.md`
- Test: `tests/test_main_scene.gd`

**Interfaces:**
- Consumes: `ShipLoader`, `Ship`, `SimClock`, `CommandInterpreter`, `DashboardModel`, `Status`
- Produces:
  - `Main` (Control, the root of `main.tscn`), with fields `ship`, `clock`, `dashboard: DashboardView`, `console: Console`. `_process(delta)` calls `ship.advance(clock.tick(delta))` and then `refresh()`.
  - `Main.refresh() -> void`. While the computer is RUNNING, the dashboard redraws from `DashboardModel`. While it is BOOTING, an overlay label `"COMPUTER REBOOTING"` covers the panels. In FAULT, the dashboard stops redrawing and a `"STALE"` label shows.
  - `DashboardView` (VBoxContainer, built in code): `show_ship(ship: Ship) -> void`, plus `tile_label(room_id: String, key: String) -> Label` for tests. It draws the clock bar, three room tiles with an opening symbol between each and the hatch at the end, the Systems, Breakers and Tanks panels, and the last 50 log lines. Level colors: green NOMINAL, amber WARNING, red DANGER, on tile borders, alarm text, and the status texts for systems, breakers and tanks.
  - `Console` (VBoxContainer, built in code): `signal line_submitted(line: String)`, `input: LineEdit`, `scrollback: RichTextLabel`, `print_line(text: String) -> void`. Up and down step through the submitted lines.

**Main's rules:**
- `console.line_submitted` → `CommandInterpreter.run`. A non-empty response prints after `"> <line>"`.
- The console's input has focus at start.
- Space toggles pause only when the console's input doesn't have focus. The clock bar has Pause/Play and Speed buttons.
- Esc quits.
- HiDPI uses `_match_display_scale()` and `scaled_window_size()`, copied from transit's `main.gd`.
- `--capture <dir>`: at 100×, it opens the hatch at sim time 0, saves `venting.png` at 20 s, closes the hatch, saves `refilled.png` at 120 s, then quits. The ship advances by sim time, so the capture doesn't depend on frame rate.

- [ ] **Step 1: Write the failing tests in `tests/test_main_scene.gd`.** Instantiate the scene, `own()` it, and `set_process(false)`, as transit's main-scene test does.
  - `test_command_runs_from_console`: emit `line_submitted("door open hatch")` → the scrollback contains `"hatch: opening (6 s)"` and the ship's hatch is OPENING.
  - `test_history_recall`: submit two lines; one Up → the input shows the second line; another Up → the first.
  - `test_tile_shows_pressure`: `tile_label("cockpit", "pressure").text == "101.3 kPa"`.
  - `test_reboot_overlay`: `computer restart`, `refresh()` → the overlay is visible; advance 21 s, `refresh()` → hidden.
  - `test_stale_freeze`: `debug fault computer`, `refresh()`, note the cockpit pressure text, vent the cockpit by hand (zero its moles), `refresh()` → the text is unchanged and `"STALE"` is visible.
  - `test_space_pauses_only_without_console_focus`: send a Space key event with the console focused → not paused; release focus, send Space → paused.

- [ ] **Step 2: Run** `-- main_scene`. Expected: FAIL.

- [ ] **Step 3: Implement the scene and the three UI scripts.**

- [ ] **Step 4: Run** the whole suite. Expected: all pass.

- [ ] **Step 5: Run it.** `godot --path .`, and check by eye that the dashboard matches the spec's mockup, then type `door open hatch`, watch the cargo vent, `door close hatch`, and watch it refill. Then `godot --path . -- --capture /tmp/ls-shots` and open both PNGs.

- [ ] **Step 6: Write `README.md`** in transit's shape: what it is, Run, Commands (the table from the spec), Data, How it works, Tests.

- [ ] **Step 7: Commit.** `git commit -m "shipsim: dashboard, console and README"`
