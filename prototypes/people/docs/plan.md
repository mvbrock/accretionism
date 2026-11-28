# People Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A watch-only Godot prototype where 300 passengers in travel parties ride transit's Earth–Moon–Mars fleet, re-route for medical emergencies, malfunctions and changes of mind, and show in a table with a detail panel.

**Architecture:** Transit's node-free simulation core is copied in. A dispatcher works out every transport trip ahead of time, and those trips form the schedule. A route planner books parties onto the schedule's trips. One ordered event loop (`Sim.advance_to`) does three things: it replays trips on transit's `Fleet`, moves parties, runs timers, and rolls the daily incidents. The UI only reads the core.

**Tech Stack:** Godot 4.7, GDScript, the headless test runner copied from transit.

**Spec:** `prototypes/people/docs/design.md`

## Global Constraints

- Godot 4.7, GDScript, in `prototypes/people`, set up the same way as the other prototypes (`project.godot` features `"4.7", "Forward Plus"`, 1600×900, `gui/theme/default_font_size=19`).
- No data files. Every tunable is a constant in `scripts/config.gd`. The 300 passengers live in `scripts/cast.gd`. Nothing is generated at run time.
- No shared code with transit. Its core is copied, and transit's diagram, dispatch panel, ship icons and loader are not.
- Watch only: the UI never changes the core.
- Ships keep transit's rules. Cyclers keep their timetable, and a transport in flight keeps its destination. Events change passengers' plans, never a ship's course.
- Emergencies are SERIOUS or CRITICAL only. The malfunction kinds are docking failure and life-support fault only.
- A party is never split.
- Every change to a party writes a history entry, with its cause, to every member.
- Progress is `(now − journey_start) ÷ (expected arrival − journey_start)`, rounded down to two decimals. It shows "-" while HELD with no route.
- Text 19 px, and the panel's name 26 px.
- Cyclers 400 seats, shuttles and tenders 20, expresses 8. The schedule window is 800 days, the connection time 6 hours, and the arrived linger time 10 days. The CRITICAL stable period is 5–20 days. The warm-up starts at day −400.

## Drift and side-effect sweep

- **Transit's core is copied deliberately.** The user chose this (approach A in the design) to keep prototypes disposable. The two copies are expected to diverge, and nothing keeps them in step.
- **`Fleet` gains a public `solve_trip`.** It is added in the people copy only, and transit's copy is untouched. `depart` is rewritten to call it, so the trip the dispatcher works out ahead of time and the trip `depart` flies come from one function and can't disagree.
- No other prototype reads or writes anything this one does. Nothing in the repo would be skipped as a side effect.

## Research checks

1–3. **Not applicable:** this is a new, standalone project. No interface, type or data path is shared with running code elsewhere.

4. **Existing patterns.** No `## Patterns` section exists in the repo, and no kind of thing here has two competing patterns. The change uses:

| Kind of thing | Pattern followed |
|---|---|
| Project setup | `prototypes/transit/project.godot`, with `.gitignore` containing `.godot` |
| Headless tests | `prototypes/transit/tests/run_tests.gd` and `tests/support/{test_case,error_log}.gd`, copied as-is |
| Clock bar | Transit's `main.tscn` ClockBar plus `SimClock`. The `--capture` code is dropped |
| Table | Transit's `FleetTable` (a `Tree` with `refresh` updating text in place), adapted |
| Scene wiring | `%UniqueName` `@onready` vars in `main.gd`, with the scene built in `.tscn` |
| Settings | Transit uses `data/fleet.json`. The user's no-data-files rule replaces it with `Config` constants |

## Review Focus

1. **One frame at 10 d/s crosses many timed events.** They must run in time order, and every history stays in ascending day order. Test in Task 5.
2. **Two incidents hit one party on the same day.** For example, an emergency, and then a change of mind rolled for the same party. A party on a medical route (`medical_return` set or a stable period running) never rolls a change of mind. Test in Task 6.
3. **Seat counts through repeated re-plans.** Cancelling frees seats. `booked` never goes negative, and never goes above `seats` for a booking. Riding past a stop may overfill a trip, and that's the only way to overfill one. Test in Task 4 (planner) and Task 7 (riding past a stop).
4. **A party HELD aboard a cycler with no route.** It retries daily, stays visible, and gets a route once one exists. Test in Task 5.
5. **The filter hides the selected passenger.** The panel keeps showing them, and clearing the filter brings their row back selected. Test in Task 9.

---

### Task 1: Project skeleton, copied core, world from Config

**Files:**
- Create: `prototypes/people/project.godot` (`config/name="People Prototype"`, `run/main_scene="res://scenes/main.tscn"`), `.gitignore`
- Copy as-is from `prototypes/transit/scripts/`: `units.gd`, `orbits.gd`, `cycler.gd`, `intercept.gd`, `transport.gd`, `sim_clock.gd`
- Copy and modify: `scripts/fleet.gd`
- Copy as-is: `tests/run_tests.gd`, `tests/support/*`, `tests/test_{orbits,cycler,intercept,sim_clock,fleet}.gd`
- Create: `scripts/config.gd`, `scripts/world.gd`, `tests/test_world.gd`, and a placeholder `scenes/main.tscn` (an empty Control, replaced in Task 9)

**Interfaces:**
- Produces:
  - `Fleet.solve_trip(from: Variant, t0: float, target: Variant) -> Dictionary`. `from` is an `Orbits.Body` or a `Cycler`. It returns `{ok: bool, t_arrive: float, intercept_point: Vector2, leg_km: float}`, with `ok` false when the trip is unreachable or `from == target`. It uses transit's local-leg rule (Earth ↔ Moon in Earth's frame at `LOCAL_SPEED`). `depart(t, target)` calls `solve_trip(_from_of(t), day, target)`, and the private `_leg_*` helpers take a `day` parameter.
  - `class_name Config` constants:
    - `SEED := 1`
    - `EPOCH_ANGLES_DEG := {"Earth": 0, "Moon": 0, "Mars": 45}`
    - `CYCLE_DAYS := 780.0`, `SHORT_LEG_DAYS := 146.0`
    - `CYCLERS` (transit's six, verbatim)
    - `TRANSPORTS: Array[Dictionary]` of `{name, service, home}`, where `service` is one of `"shuttle" | "tender" | "express" | "standby" | "spare"`, and `home` is a body name, or a cycler name for standby
    - `SEATS := {"cycler": 400, "shuttle": 20, "tender": 20, "express": 8, "standby": 20, "spare": 20}`
    - `WINDOW_DAYS := 800.0`, `CONNECTION_DAYS := 0.25`, `WARMUP_START := -400.0`, `ARRIVED_LINGER_DAYS := 10.0`
    - the rates and durations listed in Tasks 6–8
  - Fleet split, using transit's 30 bird names: 8 shuttles (4 at Earth, 4 at the Moon), 10 tenders (5 Earth, 5 Mars), 4 expresses (2 Earth, 2 Mars), 6 standby (one per cycler), 2 spares (Earth, Mars).
  - `World.build() -> Fleet`: applies `Orbits.configure` and the `Cycler` statics from Config, and builds every cycler and transport at its home at `fleet.day = Config.WARMUP_START`. It also adds `fleet.service_of: Dictionary[Transport, String]`, set when building.

- [ ] **Step 1: Copy the files above and run the copied tests.** Run `godot --headless --path . --import`, then `godot --headless --path . -s res://tests/run_tests.gd`. Expected: all copied tests pass.
- [ ] **Step 2: Write failing tests** in `test_world.gd` and `test_fleet.gd`:
  - `test_world_counts`: 6 cyclers, 30 transports, and the split 8/10/4/6/2.
  - `test_standby_docked_to_its_cycler`: standby transports start DOCKED to their home cycler.
  - `test_solve_trip_matches_depart`: for Earth→Mars, Earth→Moon and a cycler→Earth trip, `solve_trip(from, fleet.day, target).t_arrive == ` the `t_arrive` after `depart`.
  - `test_solve_trip_future`: `solve_trip(Earth, 100.0, Mars)` equals `depart` after `advance_to(100.0)`.
  - `test_cast_fits_a_cycler`: `Cast.PASSENGERS.size() <= Config.SEATS.cycler`. This is skipped until Task 3, and it's the reason the planner never checks cycler seats.
- [ ] **Step 3: Implement** `solve_trip`, `Config` and `World`.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** `people: project skeleton, copied transit core, world from config`.

### Task 2: Trips, dispatcher and schedule

**Files:**
- Create: `scripts/trip.gd`, `scripts/dispatcher.gd`, `scripts/schedule.gd`, `tests/test_dispatcher.gd`

**Interfaces:**
- Consumes: `Fleet.solve_trip`, `Cycler.leg_at(day)`, and `World.build()`.
- Produces:
  - `class_name Trip`, with fields `ship: Transport`, `from: Variant`, `to: Variant` (Body or Cycler), `depart_day: float`, `arrive_day: float`, `seats: int`, `booked: int`, `blocked: bool`, `kind: String` (`"service" | "rescue" | "return"`). It also has `seats_left() -> int`.
  - `class_name Schedule`:
    - `trips: Array[Trip]`, sorted by `depart_day`
    - `add(trip)`
    - `departing_after(day) -> Array[Trip]`
    - `trips_of(ship) -> Array[Trip]`
    - `next_trip_of(ship, after_day) -> Trip`
  - `class_name Dispatcher`:
    - `_init(fleet, schedule)`
    - `extend_to(day: float)`, which plans each service's trips up to `day`
    - `transport_trips_due(day_from, day_to) -> Array[Trip]`
  - Service rules, with these constants added to Config:
    - **Shuttle:** flies to the other body of Earth/Moon, then waits `SHUTTLE_TURNAROUND_DAYS := 0.5`.
    - **Express:** flies Earth ↔ Mars, waiting `EXPRESS_TURNAROUND_DAYS := 3.0`.
    - **Tender:** for each flyby `F` of any cycler at its planet (where `leg_at(d).end_day == F` and `.to == planet`), it departs the planet at `F − TENDER_LEAD_DAYS (1.0)`, which takes it to the cycler. It then departs the cycler at `F + TENDER_LINGER_DAYS (1.0)`, flying back to the planet. The tenders at a planet each take every flyby, and a tender that hasn't returned skips that flyby.
    - **Standby and spare:** no service trips. They stay at home until Task 8.

- [ ] **Step 1: Write failing tests:**
  - `test_schedule_sorted_and_covers_window`: after `extend_to(Config.WARMUP_START + Config.WINDOW_DAYS)`, every service ship has trips up to the window's end, and the trips are sorted.
  - `test_shuttle_alternates_with_turnaround`
  - `test_express_alternates_earth_mars`
  - `test_tender_meets_every_flyby`: every flyby at Earth and Mars in the window has at least one tender trip to that cycler that arrives before `F` and departs after it.
  - `test_trips_chain`: each ship's trip `n+1` departs from trip `n`'s `to` at or after its `arrive_day`.
  - `test_extend_is_idempotent`: extending twice to the same day adds nothing.
- [ ] **Step 2: Run** with filter `dispatcher`. Expected: FAIL.
- [ ] **Step 3: Implement.** Trips come from `fleet.solve_trip`, and none of them dispatch.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `people: dispatcher plans shuttle, express and tender trips ahead`.

### Task 3: Cast script and passenger model

**Files:**
- Create: `scripts/cast.gd`, `scripts/passenger.gd`, `scripts/party.gd`, `scripts/cast_loader.gd`, `tests/test_cast.gd`
- Not committed: a throwaway generator in the session scratchpad that writes `cast.gd`

**Interfaces:**
- Produces:
  - `class_name Cast` constants:
    - `PASSENGERS: Array[Dictionary]`, each with `{id, name, age, birthplace, occupation, note, reason, conditions: [{name, chance}]}`
    - `PARTIES: Array[Dictionary]`, each with `{members: [id], start_body, destination, start_day}`
    - `RELATIONSHIPS: Array[Dictionary]`, each with `{a, b, kind}`, where `kind` is the passenger `a`'s relationship to `b` and the loader adds the inverse
  - `class_name Passenger`: the design's fields, plus `history: Array[Dictionary]` of `{day, text, cause}`, with `add_history(day, text, cause)`.
  - `class_name Party`:
    - `members`, `origin`, `destination`, `journey_start`, `route: Array[Trip]`, `done_trips: Array[Trip]`, `state` (`TRAVELLING | HELD | ARRIVED`), and `place: Variant`, the Body or Cycler it is at while not aboard a transport
    - `aboard: Trip`, the current transport trip or null
    - `medical_return: Variant`, `stable_until: float`, `hospital_until: float`, `arrived_until: float`
    - `size() -> int`
    - `write(day, text, cause)`, which writes the entry to every member
  - `CastLoader.load(fleet) -> Array[Party]`, which resolves body names.

- [ ] **Step 1: Write and run the generator** in the scratchpad. It writes 300 passengers, with ids `P-00001` to `P-00300`, in parties of 1, 2 or 3–5 that share a family name, and every passenger under 16 is in a party with a parent. It adds friend and colleague links across parties, with colleague links only between two WORK passengers. About 30% of passengers have a condition. Each party gets a start day in [−400, 0] and a destination body different from its start body.
- [ ] **Step 2: Write failing tests:**
  - `test_three_hundred_unique_ids`
  - `test_every_relationship_names_a_real_passenger`
  - `test_children_travel_with_a_parent`
  - `test_start_days_in_warmup`
  - `test_destination_differs_from_start`
  - `test_inverse_relationships_added`
  - un-skip `test_cast_fits_a_cycler`
- [ ] **Step 3: Implement** the loader and models.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `people: cast of 300 passengers in travel parties`.

### Task 4: Route planner

**Files:**
- Create: `scripts/planner.gd`, `tests/test_planner.gd`

**Interfaces:**
- Consumes: `Schedule`, `Trip`, `Party`.
- Produces:
  - `Planner.plan(schedule, from: Variant, ready_day: float, to: Variant, party_size: int, first_trip: Trip = null) -> Array[Trip]`. It returns an empty array when there is no route.
  - `Planner.book(party, trips)` and `Planner.cancel(party)`. `cancel` frees the seats of every trip in `party.route` the party hasn't boarded yet.
  - `Planner.legs(party) -> Array[Dictionary]`, each `{ship_name, from_name, to_name, start, end, status}`, where `status` is `"done" | "current" | "next"`. It is built from the done and booked trips. A cycler ride is a leg from the trip that docks at a cycler to the trip that leaves it, with `ship_name` set to the cycler.

**Algorithm:** a connection scan over `schedule.departing_after(ready_day)`, in departure order.
- A place is a Body or a Cycler. Waiting at a cycler is riding it.
- `earliest[from] = ready_day`.
- A trip is usable when it's not `blocked`, `seats_left() >= party_size`, and `earliest[trip.from] + CONNECTION_DAYS <= trip.depart_day`. The very first boarding from `from` skips the connection time.
- When a usable trip gives a better arrival, set `earliest[trip.to]` and its parent.
- Stop at the first trip departing after `earliest[to]`.
- `first_trip` forces the route to begin with the trip the party is already aboard. Planning then starts from `first_trip.to` at `first_trip.arrive_day`.
- Cycler seats aren't checked (see `test_cast_fits_a_cycler`).

- [ ] **Step 1: Write failing tests**, on hand-built schedules:
  - `test_soonest_arrival_over_two_hops`
  - `test_full_trip_skipped`
  - `test_connection_time_enforced`
  - `test_party_needs_all_seats`
  - `test_no_route_returns_empty`
  - `test_blocked_trip_skipped`
  - `test_first_trip_kept`
  - `test_cycler_ride_via_tenders`: Earth tender → cycler → Mars tender.
  - `test_book_then_cancel_restores_seats`: books are never negative after repeated book/cancel.
  - `test_legs_mark_cycler_ride`
- [ ] **Step 2: Run** with filter `planner`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `people: route planner over the schedule`.

### Task 5: Sim event loop, journeys and warm-up

**Files:**
- Create: `scripts/sim.gd`, `tests/test_sim.gd`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `class_name Sim`:
    - `_init()` builds the world, schedule, dispatcher and parties, and seeds `rng` with `Config.SEED`. It then runs `advance_to(0.0)`, which is the warm-up.
    - `day: float`, `fleet`, `schedule`, `parties: Array[Party]`, and `passengers_by_id: Dictionary`.
    - `advance_to(new_day: float)`
    - `replan(party, to: Variant, ready_day: float, cause: String)`
    - `progress(party) -> float` returns 0–1, or −1 for a HELD party with no route.
    - `location_name(passenger) -> String`
    - `on_daily: Array[Callable]` is called with `(sim, int_day)` once for each whole day crossed. Tasks 6–8 add their rolls here, in the order change of mind, medical, malfunction.

**`advance_to` contract:**
1. Before each step, extend the schedule to `new_day + WINDOW_DAYS`.
2. Collect every timed point in `(day, new_day]`:
   - trip departures and arrivals
   - each party's `stable_until`, `hospital_until` and `arrived_until`
   - malfunction ends
   - every whole day
3. Process them in time order. Ties go in this order: arrivals, then departures, then timers, then daily rolls.
4. At each point, `fleet.advance_to(t)` runs first, then `fleet.depart(trip.ship, trip.to)` for each transport trip departing at `t`. When `depart` returns false, or its `t_arrive` differs from the trip's by more than 1e-6, raise `push_error`.
5. **Embark:** a party whose next booked trip departs at `t` boards it: `aboard` is that trip, and it writes "Boarded <ship> at <place>".
6. **Disembark:** at a trip's arrival, `aboard` is cleared and `place` becomes the trip's `to`. A Cycler `to` writes "Boarded <cycler>". Reaching the destination does one of two things:
   - with `medical_return` set, it starts the hospital stay (Task 6);
   - otherwise it sets ARRIVED with `arrived_until = t + ARRIVED_LINGER_DAYS` and writes "Arrived at <body>".
7. **New journey:** at `arrived_until`, pick a new destination with `rng` from the other bodies, then `replan` with the cause "new journey". It writes "Set off for <body>".
8. **HELD:** a `replan` with no route sets HELD and writes "No route available; waiting". The daily step retries every HELD party with no other hold, without writing more history unless it finds a route.
9. **Warm-up:** each party starts HELD-free and waiting at `start_body`. Its first journey is planned at `start_day`, with `journey_start = start_day`.

- [ ] **Step 1: Write failing tests:**
  - `test_warmup_spreads_parties`: at day 0, some parties are aboard a transport, some are on a cycler, and some are at a body.
  - `test_same_seed_same_run`: two Sims, each advanced to day 200, produce identical histories.
  - `test_fast_step_matches_slow_steps`: one `advance_to(+30)` equals 720 steps of 1/24 day.
  - `test_histories_ascending`
  - `test_fleet_replay_never_errors`: advance to 400 with no logged error.
  - `test_arrival_then_new_journey`
  - `test_held_on_cycler_retries`: block every trip from a cycler, check the party is HELD, then unblock and check a route appears.
  - `test_progress_formula_and_held_dash`
  - `test_cast_stays_300`
- [ ] **Step 2: Run** with filter `sim`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the whole suite. Expected: PASS.
- [ ] **Step 5: Commit** `people: event loop, journeys and warm-up`.

### Task 6: Change of mind and medical emergencies

**Files:**
- Create: `scripts/incidents.gd`, `tests/test_incidents.gd`

**Interfaces:**
- Consumes: `Sim.on_daily`, `Sim.replan`, `Party`.
- Produces:
  - `Incidents.install(sim)`, which registers `change_of_mind` and `medical` in `on_daily`.
  - `Incidents.start_emergency(sim, party, patient, condition, severity)`, public for tests and for Task 8.
  - Config constants:
    - `CHANGE_OF_MIND := {"VISIT": 0.004, "WORK": 0.002, "RETURNING": 0.002, "MEDICAL": 0.001, "EMIGRATION": 0.0005}` per day. A party uses its members' highest rate.
    - `AGE_RISK_PER_YEAR := 0.02`: a condition's daily chance is multiplied by `1 + max(0, age − 40) × 0.02`.
    - `CRITICAL_BASE := 0.2` and `CRITICAL_PER_YEAR := 0.005`: the chance an emergency is CRITICAL.
    - `STABLE_DAYS := [5, 20]` and `HOSPITAL_STAY_DAYS := [7, 21]`.

**Rules:**
- Parties roll in id order with `sim.rng`.
- ARRIVED parties and parties on a medical route (`medical_return` set, or `stable_until > day`) don't roll a change of mind.
- **Change of mind:** pick a destination from the bodies other than the current one, then `replan`. It writes "Changed plans: heading to <body> instead".
- **SERIOUS emergency:** set `medical_return` to the old destination. Find the soonest-reached hospital body: plan to each of Earth, Moon and Mars and take the earliest arrival. Then `replan` there. When the party is at a body, that body is the hospital, and the stay starts at once.
  - Aboard a transport: plan with `first_trip = aboard`.
  - On a cycler: hand off to `Rescues.request` (Task 8). Until Task 8 lands, plan normally.
- **CRITICAL emergency:** cancel the route, set HELD with `stable_until = day + randi_range(5, 20)`, and stay aboard.
  - Aboard a transport: the party rides on through that ship's next trips, overfilling them if needed.
  - On a cycler: the entry says "stabilized in the infirmary".
  - When the stable period ends, the party is treated as SERIOUS.
- **Hospital stay:** `hospital_until = t + randi_range(7, 21)`, then `replan(medical_return, ready_day = hospital_until)`, then clear `medical_return`.
- **Entries:**
  - the patient: "<Condition> emergency; re-routed to <body> for treatment"
  - everyone else in the party: "Re-routed to <body>: <patient name>'s <condition> emergency"

- [ ] **Step 1: Write failing tests:**
  - `test_change_of_mind_replans_and_writes`
  - `test_no_change_of_mind_on_medical_route`
  - `test_serious_aboard_transport_gets_off_at_next_stop`
  - `test_serious_at_body_starts_stay`
  - `test_critical_rides_past_stops_then_reroutes`
  - `test_hospital_then_back_to_previous_destination`
  - `test_party_entries_name_patient`
  - `test_only_serious_or_critical`
- [ ] **Step 2: Run** with filter `incidents`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the whole suite. Expected: PASS.
- [ ] **Step 5: Commit** `people: change of mind and medical emergencies`.

### Task 7: Malfunctions and forced exits

**Files:**
- Create: `scripts/malfunctions.gd`, `tests/test_malfunctions.gd`

**Interfaces:**
- Consumes: `Sim`, `Schedule`, `Planner`.
- Produces:
  - `Malfunctions.install(sim)`
  - `Malfunctions.strike(sim, ship: Variant, kind: String)`, public for tests
  - Config constants: `DOCKING_FAILURE_CHANCE := 0.003`, `LIFE_SUPPORT_CHANCE := 0.002` per ship per day.

**Rules:**
- Ships roll in fleet order, and a ship that is already under a malfunction doesn't roll.
- **Docking failure, on a transport:** its current or next trip's arrival is blocked. Parties aboard ride on to the end of the following trip, and then `replan`. Parties booked to board that ship at that stop `replan`.
- **Docking failure, on a cycler:** every trip arriving at or departing it, from now to its next flyby plus `TENDER_LINGER_DAYS`, becomes `blocked`. Bookings on those trips are cancelled, and those parties `replan`. A party aboard a trip heading to it rides on, as above.
- **Life-support fault, on a transport:** every party aboard gets off at the current trip's `to`, then `replan`s from there.
- **Life-support fault, on a cycler:** every party aboard needs to leave. Until Task 8, they plan the next trip off the cycler.
- **Forced exit with no room:** when no trip off the cycler has seats for the whole party, it stays aboard and writes "Tenders full at <planet>; staying aboard <cycler>" once per flyby until one has room.
- **Entries** name the ship, e.g. "Docking failure on Aldrin IV; staying aboard past Mars".

- [ ] **Step 1: Write failing tests:**
  - `test_transport_docking_failure_rides_on`
  - `test_cycler_docking_failure_blocks_trips`
  - `test_life_support_transport_everyone_off`
  - `test_tenders_full_stays_aboard`
  - `test_ride_on_may_overfill_only_that_way`
  - `test_ship_course_unchanged`: the fleet replay never errors, and cycler positions are unchanged.
- [ ] **Step 2: Run** with filter `malfunctions`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the whole suite. Expected: PASS.
- [ ] **Step 5: Commit** `people: docking failures and life-support faults`.

### Task 8: Standby and rescues

**Files:**
- Create: `scripts/rescues.gd`, `tests/test_rescues.gd`
- Modify: `scripts/dispatcher.gd` (adds unscheduled trips)

**Interfaces:**
- Consumes: Tasks 2 and 5–7.
- Produces:
  - `Rescues.request(sim, party, reason: String)`, where `reason` is `"medical"` or `"life_support"`.
  - `Dispatcher.add_rescue(ship, from, to, t0) -> Trip` and `Dispatcher.add_return(ship, cycler, t0) -> Trip`. Each one is solved with `solve_trip` and added to the schedule with `kind` set.
  - `Rescues.standby_gap_days(sim) -> Dictionary[Cycler, float]`, a running total.

**Rules:**
- Each cycler has a FIFO queue of rescue requests.
- At each step, a standby transport docked to that cycler and not in flight takes the queue in order. A party boards when all of it fits. A party that doesn't fit is skipped, and it stays first in line for the next trip.
- The transport departs at once to the target:
  - for a medical request, the soonest-reached hospital body
  - for life support, the soonest-reached body
  - each party already has its target set by its request, and one trip goes to the target of the first party in line
- After the arrival plus `RESCUE_TURNAROUND_DAYS := 1.0`, `add_return` flies it back to its cycler.
- With no standby docked, the nearest `spare` at a body (by `solve_trip` arrival) flies to the cycler first. That trip is kind `rescue` with no passengers. It then works as standby.
- The rescued party writes "Evacuated from <cycler> by <ship>". Once it lands, it `replan`s or starts the hospital stay as Task 6 says.
- Incidents and Malfunctions route cycler cases here: a SERIOUS emergency, a CRITICAL patient whose stable period has ended, and a life-support fault.
- A change of mind never calls `request`.

- [ ] **Step 1: Write failing tests:**
  - `test_medical_rescue_to_nearest_hospital`
  - `test_life_support_rescue_overflow_waits`
  - `test_party_never_split`
  - `test_spare_sent_when_no_standby`
  - `test_standby_returns_to_its_cycler`
  - `test_change_of_mind_never_rescues`
  - `test_standby_gap_small`: over 800 days, each cycler's gap is under 25% of the time.
- [ ] **Step 2: Run** with filter `rescues`. Expected: FAIL.
- [ ] **Step 3: Implement**, and change the Task 6 and Task 7 cycler branches to call `Rescues.request`.
- [ ] **Step 4: Run** the whole suite. Expected: PASS.
- [ ] **Step 5: Commit** `people: standby transports and rescues`.

### Task 9: Table model, passenger table and main screen

**Files:**
- Create: `scripts/table_model.gd`, `scripts/ui/passenger_table.gd`, `scripts/ui/main.gd`, `scenes/main.tscn`, `tests/test_table_model.gd`, `tests/test_main_scene.gd`

**Interfaces:**
- Consumes: `Sim`.
- Produces:
  - `TableModel.row(sim, passenger) -> PackedStringArray`, which gives `[name, id, origin, location, destination or "Arrived", percent or "-"]`. `TableModel.percent` is transit's.
  - `TableModel.sort_key(sim, passenger, column) -> Variant`. Progress sorts numerically, and the other columns as text.
  - `PassengerTable extends Tree` with:
    - `show_passengers(passengers)`
    - `refresh(sim)`
    - `set_sort(column, ascending)`: clicking a header toggles it
    - `set_filter(text)`: case-insensitive, matching any cell
    - `signal passenger_selected(p)`
    - `show_selected(p)`
  - Sorting and filtering re-apply at most every 0.5 s real time and keep the selection.
  - A row whose passenger's `history.size()` grew gets `set_custom_bg_color` for `HIGHLIGHT_SECONDS := 3.0` real time. The UI tracks history sizes, so the core never knows about real time.
- The layout follows transit's `main.tscn`: Background, then Layout (VBox, 12 px margins), then ClockBar (PlayPause, Speed, ClockLabel), a Filter `LineEdit`, and Body (HBox: Table, and DetailPanel as a placeholder `Label` reading "Select a passenger"). Space pauses unless the filter has focus, and Esc quits. `_process` calls `sim.advance_to(clock.tick(delta))`, then `table.refresh(sim)`.

- [ ] **Step 1: Write failing tests:**
  - `test_row_states`: aboard, at a body, arrived, and HELD.
  - `test_percent_floor`
  - `test_sort_progress_numeric`
  - `test_filter_matches_any_cell`
  - `test_main_scene_loads_and_ticks`
  - `test_selection_survives_sort`
  - `test_filter_hides_selected_but_keeps_it` (Review Focus 5)
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the whole suite. Expected: PASS. Then run `godot --path .` and check that the table fills and changes at 1 d/s.
- [ ] **Step 5: Commit** `people: passenger table and main screen`.

### Task 10: Detail panel, rate check and README

**Files:**
- Create: `scripts/ui/detail_panel.gd`, `tests/test_detail_panel.gd`, `tests/test_rates.gd`, `README.md`
- Modify: `scenes/main.tscn`, `scripts/ui/main.gd`

**Interfaces:**
- Consumes: `Sim`, `Planner.legs`, `PassengerTable.show_selected`.
- Produces: `DetailPanel` (a VBox) with `show_passenger(sim, p)` and `signal passenger_clicked(p)`. It has these sections, in the design's layout:
  - the header: the name at 26 px, the ID, "age · born birthplace", "occupation · traveling for reason", and the note
  - JOURNEY, with ✓, ▸ and · marks and its progress
  - TRAVELLING WITH
  - HEALTH
  - RELATIONSHIPS
  - HISTORY, newest first, in a scrolling `RichTextLabel`

  Party members and relationships are `LinkButton`s that emit `passenger_clicked`, and Main selects that passenger and scrolls the table. When nothing is selected, the panel shows "Select a passenger".

- [ ] **Step 1: Write failing tests:**
  - `test_panel_sections_present`
  - `test_history_newest_first`
  - `test_relationship_click_selects`
  - `test_arrived_relation_still_listed`
  - `test_rates_handful_per_day` (`test_rates.gd`): from day 0 to 365, the non-routine entries (change of mind, emergency, malfunction, rescue) average between 0.3 and 3 per day. When it fails, tune the Config rates, not the test.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement**, and write the README with Run, Controls (Space, Speed, header click, filter, Esc) and Tests sections in transit's format.
- [ ] **Step 4: Run** the whole suite. Expected: PASS. Then run `godot --path .`, pick a passenger, and click through a relationship.
- [ ] **Step 5: Commit** `people: detail panel, rate check and README`.
