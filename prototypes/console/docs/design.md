# Ship Sim Prototype: Design

## Intent

Prove a **logistics view of a ship's interior**: a dashboard that shows the state of every room and system at a glance, and a command line that is the only way to act on the ship. The atmosphere model is there to make the consequences of a command believable, such as a room venting, a room repressurizing, or a room cooling after its HVAC loses power. The prototype does not test the physics.

## Goals

- Simulate a three-room ship (cockpit, main room, cargo hold) whose atmosphere has pressure, temperature, and O₂, N₂ and CO₂ levels.
- Keep the atmosphere livable with three automatic systems: pressure control, heating/cooling (HVAC) and a CO₂ recycler.
- Model doors and a hatch, so that opening the hatch vents only the rooms connected to it through open doors.
- Power every component through its own circuit breaker. A tripped breaker takes away that component's function.
- Show everything on a dashboard, and control the ship only through a simple command line.

## Non-goals

No player character, passenger movement, walking or first-person view. No power generation, batteries or load limits. No hull damage, fire, or gases other than O₂, N₂ and CO₂. No adiabatic cooling during venting. No art, audio or save/load. Any of these can come later.

## Decisions

| Topic | Decision |
|---|---|
| Tech | Godot 4.7, GDScript, in `prototypes/shipsim` (same setup as `prototypes/ship` and `prototypes/transit`) |
| Model | Logistical. Each room is one well-mixed volume of ideal gas, and the sim steps it at a fixed rate |
| Rooms | `cockpit`, `main`, `cargo`, in a row |
| Openings | `d1` (cockpit ↔ main), `d2` (main ↔ cargo), `hatch` (cargo ↔ outside) |
| Life support reach | Each system reaches every room through its own ducts, so it works with every door closed |
| Venting | Gas leaves through the open hatch. It reaches the hatch from other rooms only through open doors |
| Repressurizing | Pressure control refills a room on its own once that room no longer connects to the outside |
| CO₂ source | Passengers, fixed in place (the ship starts with one in the cockpit and one in the main room). They breathe O₂, exhale CO₂ and give off heat. They are a load on the atmosphere, not characters |
| Gas supply | Finite O₂ and N₂ tanks. Pressure control draws from them. The recycler turns the passengers' CO₂ back into O₂ and returns it to the O₂ tank, so while it runs the O₂ tank holds nearly steady. When the recycler is down, the O₂ tank empties as the passengers breathe. Gas lost through the hatch is gone for good |
| Power | One unlimited ship bus. Each room light, each opening and each of the three life-support systems has its own breaker. The computer has no breaker |
| Restart | A restart reboots a system: it goes offline for a few seconds, then comes back running. A restart clears a fault. It does not reset a breaker |
| Breakers | Each breaker trips at random. A tripped breaker stays tripped until `breaker reset <breaker ID>` |
| Faults | System faults happen only when injected with `debug fault`. `debug trip` trips a breaker on demand, so tests and demos don't wait on chance |
| Door auto-close | When the hatch starts opening, every door except the hatch closes by itself. A door without power stays where it is |
| IDs | Short: rooms `cockpit`, `main`, `cargo`; openings `d1`, `d2`, `hatch`; breakers as listed under Power. Room and opening ids come from the data file; these are the shipped ones |
| Randomness | Seeded from the data file, so the same seed and the same commands always give the same run |
| Clock | Pause, 1×, 10× and 100× sim speed |

## Ship layout

```
 ┌──────────┐    ┌────────────────────┐    ┌──────────────┐
 │ COCKPIT  │ d1 │        MAIN        │ d2 │    CARGO     │ hatch
 │  12 m³   ├────┤        40 m³       ├────┤    30 m³     ├──────  outside (vacuum)
 │ pass. ×1 │    │     passengers ×1  │    │              │
 └──────────┘    └────────────────────┘    └──────────────┘
```

All three doors start closed, every light starts on, and every system starts running with every room at its setpoint.

## Atmosphere model

Internal units are **SI**: m³, mol, Pa, K, W and seconds. The dashboard shows kPa and °C.

Each room holds:

```
Room
  id: String              # cockpit | main | cargo
  volume: float           # m³
  mol: {O2, N2, CO2}      # moles of each gas
  temperature: float      # K, of the room as a whole (air plus structure)
```

- **Partial pressure** of a gas is `p = n R T / V`. **Pressure** is the sum of the three partial pressures.
- **Composition** shows as each gas's share of the pressure. CO₂ shows as a partial pressure, since that is what passenger safety depends on.
- **Temperature belongs to the room**, not only its air: the structure's heat capacity is far larger than the air's. So a room has a temperature even in vacuum, and gas flowing in or out doesn't change it.

The sim steps every 0.1 s of sim time. At 100× it runs 1,000 steps per real second. Every rate below is in the data file and can be tuned.

### Setpoints

| Quantity | Setpoint |
|---|---|
| ppO₂ | 21.2 kPa |
| ppN₂ | 80.1 kPa |
| Pressure | 101.3 kPa (the sum of the two above) |
| ppCO₂ | at or below 0.3 kPa |
| Temperature | 21 °C |

### Flow through an opening

An opening has an **open fraction** from 0 (closed) to 1 (open). It changes over the opening's travel time, and every flow through it scales with that fraction.

- **Door, bulk flow.** Gas moves from the higher-pressure room to the lower one: molar flow = `C_door × fraction × ΔP / (R T_source)`, with `C_door` = 10 m³/s. The gas carries the source room's composition. Two rooms at different pressures equalize in a few seconds.
- **Door, mixing.** At equal pressure, an open door still swaps 0.5 m³/s of air each way, so CO₂ from the main room reaches an open cockpit. It also adds a heat conductance of 100 W/K between the two rooms.
- **Hatch.** Gas leaves to vacuum at a volumetric rate `C_hatch × fraction`, with `C_hatch` = 5 m³/s, so a room's gas decays as `dn/dt = −n × C_hatch × fraction / V`. The cargo hold alone drops below 1 kPa in about 30 s. With both doors open, the whole ship's 82 m³ drains through the hatch, and the doors slow the flow toward the hatch, so it drops below 1 kPa in about 95 s.

### Exposure

A room is **exposed** when a path of openings that are at least partly open leads from it to the outside. Exposure is worked out on every step:

| d1 | d2 | hatch | Exposed rooms |
|---|---|---|---|
| any | any | closed | none |
| any | closed | open | cargo |
| closed | open | open | main, cargo |
| open | open | open | all three |

### Heat

Each room has a heat capacity of 5 kJ/K per m³. It loses heat through the hull to a fixed −20 °C at 0.5 W/K per m³. That loss is 820 W for the main room at setpoint, and an unheated room's temperature has a time constant of about 2.8 h.

Heat sources: each passenger gives 100 W, each powered light that is on gives 40 W, and the HVAC adds or removes heat.

### Passengers

The ship starts with one passenger in the cockpit and one in the main room. Each passenger uses 3.0 × 10⁻⁴ mol/s of O₂ and makes 2.6 × 10⁻⁴ mol/s of CO₂, about 0.84 kg and 1.0 kg a day. Consumption stops when the room's O₂ runs out. Passengers can't be hurt and never move. With the recycler off and the doors closed, the cockpit's CO₂ reaches the danger level in about 3.7 h of sim time, about 2 minutes at 100×. The larger main room takes about 12 h.

`passenger add` and `passenger remove` change the count in a room, one at a time, and a room can go down to none. A room with no passengers uses no O₂, makes no CO₂ and gives off no body heat.

## Systems

Each powered system has a state:

| State | Meaning |
|---|---|
| RUNNING | powered and working |
| BOOTING | powered, coming up after a restart or power returning; does nothing until done |
| FAULT | powered but stopped; a restart clears it, and so does losing power and getting it back, which also reboots the system |
| NO POWER | its breaker is tripped |

When its breaker is reset, a system goes to BOOTING, then RUNNING. Boot times: pressure control 10 s, HVAC 8 s, recycler 15 s, computer 20 s.

### Pressure control

- For each room that is **not exposed**, it adds O₂ while ppO₂ is below setpoint and N₂ while ppN₂ is below setpoint, at up to 20 mol/s per gas per room. The cargo hold refills in about a minute.
- **It never feeds an exposed room.** That is the breach response: gas sent into a room that is venting would be lost. When the hatch closes, or a door between the room and the hatch closes, the room stops being exposed, and refilling starts on the next step without any command.
- Gas comes from the O₂ and N₂ tanks. An empty tank stops that gas only, and the dashboard flags the tank.
- It only adds gas. It doesn't vent overpressure.

### Tanks

| Tank | Capacity | Starts | Filled by | Drained by |
|---|---|---|---|---|
| O₂ | 3,000 mol | full | the recycler | pressure control, replacing O₂ the passengers breathe and O₂ lost to venting |
| N₂ | 8,000 mol | full | nothing | pressure control, replacing N₂ lost to venting |

- Passengers don't use N₂, so the N₂ tank only drains after a vent.
- While the recycler keeps up, the O₂ tank loses only the gap between O₂ breathed and CO₂ exhaled: about 7 mol a day for two passengers, so it lasts more than a year.
- With the recycler down, the O₂ tank drains at the full rate the passengers breathe, about 52 mol a day, so it empties in about 58 days. CO₂ reaches danger long before that.
- A tank never fills past its capacity. The recycler's O₂ is discarded when the tank is full.
- The two tanks hold enough to refill the whole ship about three times.

### HVAC

- For each room, it heats or cools toward 21 °C with a proportional controller. The output is limited to ±1.5 kW per room, so a breached or freezing room recovers over minutes, not instantly.
- It runs in exposed rooms too, since the room's temperature belongs to its structure.

### CO₂ recycler

- For each room, while ppCO₂ is above 0.3 kPa, it removes CO₂ at up to 0.01 mol/s. That is about 20 times what one passenger exhales.
- Each mole of CO₂ removed becomes one mole of O₂ in the O₂ tank. Pressure control then draws that O₂ back into the rooms as the passengers use it.
- It skips a room that is exposed or whose pressure is below 10 kPa.

### Computer

- It runs the dashboard and the command line. The life support systems run on their own controllers, so they keep working while the computer is down.
- While BOOTING or in FAULT, the command line takes no input. While BOOTING, the dashboard shows *COMPUTER REBOOTING* over the panels. In FAULT, the dashboard freezes at the values it last showed and is marked *STALE*. The sim keeps running underneath.
- `computer restart` is still accepted when the computer is in FAULT, so it can always be recovered (the console is a hardware terminal, and it handles only that one command while the computer is down).

### Doors and hatch

- Each opening is CLOSED, OPENING, OPEN or CLOSING. Doors take 2 s to travel and the hatch 6 s.
- Opening or closing reverses an opening that is moving the other way.
- With no power, an opening stays where it is, partly open included, and rejects commands.
- **Auto-close.** When the hatch starts opening, every powered door that is open or opening starts closing. The doors take 2 s and the hatch 6 s, so a little air from the main room escapes before `d2` seals. The rule lives in the door controllers, so it works while the computer is down.
- A door without power when the hatch opens stays open. That, or a door reopened by command while the hatch is open, is how the whole ship vents. The auto-close fires only when the hatch starts opening, so a command to reopen a door is obeyed, and the log warns that the door connects to an open hatch.
- When the hatch opens with a door left open, the dashboard shows a warning and the log records it.

### Lights

Each room has one light with a switch that is on or off. A light shines only when its switch is on and its circuit has power. When the breaker trips, the switch keeps its position, so the light comes back on when power returns.

## Power

| Breaker ID | Component | Draw |
|---|---|---|
| `light-<room id>`, one per room (`light-cockpit`, `light-main`, `light-cargo`) | room lights | 40 W each when lit |
| the id of each opening other than the hatch (`d1`, `d2`) | door motors | 5 W idle, 200 W moving |
| `hatch` | hatch motor | 5 W idle, 500 W moving |
| `pressure-control` | pressure control | 300 W |
| `hvac` | HVAC | 200 W, plus the heat it moves |
| `air-recycler` | CO₂ recycler | 800 W while scrubbing, 50 W idle |
| — | computer, not on the breaker panel | 150 W |

The breaker IDs are the names in the first column. Breakers come from the data file: a room adds its `light-<room id>` breaker and an opening adds a breaker with its own id, alongside the three fixed system breakers. Breaker IDs are unique, so an opening cannot be named after a system (`pressure-control`, `hvac`, `air-recycler` or `computer`) or start with `light-`. The random draws go in the order room lights, openings, systems.

A breaker is CLOSED (powered) or TRIPPED. The dashboard shows each breaker's state and draw, and the total.

### Random trips

- Each closed breaker trips at random, on average once every 24 h of sim time, independently of the others. With the shipped nine breakers, the ship sees a trip about every 2.7 h of sim time, about every 1.6 minutes at 100×.
- A trip is checked on every step with probability `dt / mean_time_between_trips`. That rate is in the data file, and setting it to 0 turns random trips off.
- A trip is logged and raises a warning on the dashboard.
- The random source is seeded from the data file and draws once per breaker per step, so a run is repeatable.

## Command line

One line of input, with a scrollback above it that shows each command and its response. Up and down arrows recall earlier commands. Commands and IDs are case-insensitive. Every command prints one line saying what happened, or why it didn't.

| Command | Effect |
|---|---|
| `door open <door id>` | Start opening |
| `door close <door id>` | Start closing |
| `light on <room id>` | Switch that room's light on |
| `light off <room id>` | Switch it off |
| `passenger add <room id>` | Add a passenger to that room |
| `passenger remove <room id>` | Remove a passenger from that room |
| `pressure-control restart` | Reboot pressure control |
| `hvac restart` | Reboot the HVAC |
| `air-recycler restart` | Reboot the recycler |
| `computer restart` | Reboot the computer |
| `breaker reset <breaker ID>` | Close a tripped breaker |
| `help` | List the commands, with the door and room ids from the data file in place of `<door id>` and `<room id>`. *Added* |
| `debug trip <breaker ID>` | Trip a breaker. *Added, for testing and demos* |
| `debug fault <system>` | Put a system in FAULT. *Added, for testing and demos* |

Sample responses:

```
> door open hatch
hatch: opening (6 s)
> door open hatch
hatch: already open
> door open d1
d1: no power (breaker tripped)
> hvac restart
hvac: rebooting (8 s)
> hvac restart
hvac: no power; reset breaker 'hvac' first
> door shut d1
unknown command 'door shut'. Type 'help' for commands
```

## Screen

```
┌ console ───────────────┬ clock: ▶ 10×   T+00:42:17 ────────────────────────── ⚠ CARGO EXPOSED ┐
│                        │                                                                      │
│                        │  ┌ COCKPIT ─────┐ d1 ┌ MAIN ────────┐ d2 ┌ CARGO ───────┐ hatch      │
│                        │  │ 101.3 kPa    │ ▌▐ │ 101.2 kPa    │ ▐▌ │ 0.4 kPa   ⛔ │ ◁▷ OPEN    │
│                        │  │ 21.0 °C      │    │ 20.8 °C      │    │ 18.9 °C      │            │
│                        │  │ O₂ 20.9 %    │    │ O₂ 20.8 %    │    │ O₂ —         │            │
│                        │  │ N₂ 79.0 %    │    │ N₂ 78.9 %    │    │ N₂ —         │            │
│                        │  │ CO₂ 0.21 kPa │    │ CO₂ 0.28 kPa │    │ CO₂ —        │            │
│                        │  │ passengers 1 │    │ passengers 1 │    │ passengers 0 │            │
│                        │  │ light ●      │    │ light ●      │    │ light ○      │            │
│                        │  └──────────────┘    └──────────────┘    └──────────────┘            │
│                        │                                                                      │
│                        │  SYSTEMS                 BREAKERS                  TANKS             │
│                        │  pressure-control RUN    light-cockpit ■ 40 W      O₂ ██████░░ 78 %  │
│                        │  hvac            RUN     light-main    ■ 40 W      N₂ ███████░ 91 %  │
│                        │  air-recycler    BOOT 9s light-cargo   □ TRIP                        │
│                        │  computer        RUN     d1 ■  d2 ■  hatch ■ ...   total 3.1 kW      │
│                        │                                                                      │
│ > door open hatch      │  LOG                                                                 │
│ hatch: opening (6 s)   │  00:41:52  hatch opened; cargo exposed to vacuum                     │
│ > _                    │  00:41:52  pressure-control: not feeding cargo (exposed)             │
│                        │                                                                      │
└────────────────────────┴──────────────────────────────────────────────────────────────────────┘
```

- **Bad data file:** if `data/ship.json` can't be loaded, the window shows "Could not load data/ship.json: <problem>" in place of the dashboard, the sim doesn't run, and Esc still quits.
- **Clock bar:** pause/play, speed (1×, 10×, 100×), elapsed sim time, and the most serious current alarm. Space toggles pause unless the command line has focus.
- **Ship schematic:** a tile per room and a symbol per opening, showing its state and how far open it is.
- **Room order:** rooms draw left to right in the data file's order, each door between the rooms it joins (after the earlier of the two), so list the rooms in the order they connect.
- **Room tiles:** pressure, temperature, O₂ and N₂ share, ppCO₂, the passenger count, and the light. Below 1 kPa the shares show "—". The tile's border color is the room's worst status.
- **Systems, breakers and tanks** panels, as above.
- **Log:** the last 50 events with sim timestamps. It holds the ship's own events (system state changes, rooms exposed or sealed, warnings, breaker trips and empty tanks), not commands.
- **Command line:** a column down the left side of the window, 460 px wide and the full window height, with the dashboard filling the rest on the right. It has focus at start. Commands and their responses fill the scrollback, with the input at the bottom of the column. The console is the ship's hardware terminal, so it stays visible and usable while the computer reboots or is in FAULT. The reboot overlay and the STALE label cover only the dashboard.

All text is 19 px, matching `prototypes/transit`, and the UI scales with the display's HiDPI factor.

### Status levels

| Reading | Nominal | Warning | Danger |
|---|---|---|---|
| Pressure | 95–105 kPa | 70–95 or above 105 kPa | below 70 kPa |
| ppO₂ | 19–23.5 kPa | 16–19 or 23.5–30 kPa | below 16 or above 30 kPa |
| ppCO₂ | below 0.5 kPa | 0.5–1.0 kPa | above 1.0 kPa |
| Temperature | 18–26 °C | 10–18 or 26–32 °C | below 10 or above 32 °C |
| Tank | above 25 % | 5–25 % | below 5 % |

Colors: nominal is green, warning is amber and danger is red. A system in FAULT or NO POWER, and a tripped breaker, show amber.

## Data file

`data/ship.json` holds:
- each room's volume, its passenger count, and its starting gas and temperature
- the openings, with which rooms each joins, its conductance and its travel time
- the setpoints and status thresholds
- every rate in this spec: pressure control's feed rate, the HVAC limit, recycler capacity, passenger metabolism, hull loss and heat capacity
- tank capacities and starting levels
- breaker draws and system boot times. The breakers themselves follow the rooms and openings: one light per room, one breaker per opening
- the mean time between random trips, and the random seed

## Code structure

- **Simulation core:** plain GDScript classes, no nodes. It holds the rooms, openings, exposure, systems, breakers, tanks, passengers and the clock, and is stepped by `step(dt)`. Everything that can be tested lives here.
- **Command interpreter:** a pure function from a command string and the ship to the ship's changes and a response line. It holds no nodes and is tested headless.
- **UI:** a thin layer of scenes for the clock bar, the schematic, the panels, the log and the command line. It reads the core's state and sends it commands through the interpreter.
- **Tests:** headless, with the same runner as `prototypes/transit/tests`. They cover:
  - pressure from moles and temperature, against hand-worked cases
  - two rooms equalizing through an open door, with the total moles conserved
  - a closed door passing nothing
  - the exposure table above, every row
  - hatch open with `d2` closed: the cargo hold vents and the main room and cockpit are unchanged
  - the hatch opening: powered open doors close by themselves, and an unpowered open door stays open
  - hatch open with both doors unpowered and open: all three rooms vent
  - a door reopened by command while the hatch is open: it stays open and the log warns
  - the recycler returning one mole of O₂ to the tank per mole of CO₂, and never past capacity
  - the O₂ tank holding nearly steady with the recycler running, and draining with it down
  - random trips: about the configured rate over a long run, none at rate 0, and the same seed giving the same trips
  - the hatch closing: the cargo hold refills to setpoint on its own, with no command
  - pressure control never feeding an exposed room
  - an empty tank stopping only its own gas
  - the HVAC holding setpoint, and a room cooling with the HVAC unpowered
  - the recycler holding CO₂ below 0.5 kPa with passengers, and CO₂ rising with it unpowered
  - a tripped breaker removing each component's function, and a reset bringing it back through BOOTING
  - a restart clearing a FAULT, and being refused with no power
  - the computer down: the command line rejecting input except `computer restart`, and life support still running
  - an unpowered door holding its position, partly open included
  - a light's switch surviving a trip
  - adding a passenger raising a sealed room's CO₂ faster, a passenger adding `heat.passenger_w` of heat, and removing the last one stopping breathing in that room
  - each room tile's passenger count, in the model and on the main screen after `passenger add`
  - each command's success and error responses
  - the same commands from the same start always giving the same state

## Open questions

1. **Random system faults.** Breakers trip at random, but systems enter FAULT only through `debug fault`, so a restart is needed only after an injected fault. Systems could also fault at random, which would give `restart` a job in normal play.
