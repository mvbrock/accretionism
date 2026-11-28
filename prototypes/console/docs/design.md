# Ship Sim Prototype: Design

## Intent

Prove a **logistics view of a ship's interior**: a dashboard that shows the connected ship in 3D with the state of its rooms and systems, and a command line that is the only way to act on the ship. The atmosphere model is there to make the consequences of a command believable, such as a room venting, a room repressurizing, or a room cooling after its HVAC loses power. The prototype does not test the physics.

## Goals

- Simulate a fleet of ships, from a three-room skiff to a 43-room wheel, each with rooms whose atmosphere has pressure, temperature, and O₂, N₂ and CO₂ levels.
- Keep the atmosphere livable with three automatic systems: pressure control, heating/cooling (HVAC) and a CO₂ recycler.
- Model doors and hatches, so that opening a hatch vents only the rooms connected to it through open doors.
- Power every component through its own circuit breaker. A tripped breaker takes away that component's function.
- Show the ship in 3D with its readings on a dashboard, and control the ship only through a simple command line.

## Non-goals

No player character, passenger movement or walking. No power generation, batteries or load limits. No hull damage, fire, or gases other than O₂, N₂ and CO₂. No adiabatic cooling during venting. No art, audio or save/load. Any of these can come later.

## Decisions

| Topic | Decision |
|---|---|
| Tech | Godot 4.7, GDScript, in `prototypes/console` (same setup as `prototypes/ship` and `prototypes/transit`) |
| Model | Logistical. Each room is one well-mixed volume of ideal gas, and the sim advances it 0.1 s at a time, or 5 s at a time at 1 hour/s |
| Ships | Each ship type is a class that subclasses `Ship`: `RingShip`, `SkiffShip`, `TugShip`, `FreighterShip` and `WheelShip` (see Ship layout) |
| Rooms | A box with a size, a position and an orientation. At most six doors and hatches per room, on any of its faces; two may share a face |
| Openings | A door joins two rooms; a hatch joins a room to outside. A hatch is any opening whose id starts with `hatch` |
| Life support reach | Each system reaches every room through its own ducts, so it works with every door closed |
| Venting | Gas leaves through an open hatch. It reaches the hatch from other rooms only through open doors |
| Repressurizing | Pressure control refills a room on its own once that room no longer connects to the outside |
| CO₂ source | Passengers, fixed in place (each ship type starts with some, such as one in the skiff's cockpit and one in its cabin). They breathe O₂, exhale CO₂ and give off heat. They are a load on the atmosphere, not characters |
| Gas supply | Finite O₂ and N₂ tanks. Pressure control draws from them. The recycler turns the passengers' CO₂ back into O₂ and returns it to the O₂ tank, so while it runs the O₂ tank holds nearly steady. When the recycler is down, the O₂ tank empties as the passengers breathe. Gas lost through a hatch is gone for good |
| Power | One unlimited ship bus. Each room light, each door and hatch and each of the three life-support systems has its own breaker. The computer has no breaker |
| Restart | A restart reboots a system: it goes offline for a few seconds, then comes back running. A restart clears a fault. It does not reset a breaker |
| Breakers | Each breaker trips at random. A tripped breaker stays tripped until `breaker reset <breaker ID>` |
| Faults | System faults happen only when injected with `debug fault`. `debug trip` trips a breaker on demand, so tests and demos don't wait on chance |
| Door auto-close | When a hatch starts opening, every door closes by itself. A door without power stays where it is |
| IDs | Lowercase with no whitespace, so the command line can type them: rooms such as `cockpit` or `s0`; doors `<room>-<room>`; hatches `hatch` (the ring's are `hatch0` and `hatch6`); breakers as listed under Power. A ship refuses a room or opening id the command line cannot type, `outside`, or one that clashes with a breaker |
| Randomness | Seeded from the ship's `seed` param, so the same seed and the same commands always give the same run |
| Clock | Pause, and sim speeds of real time, 1 min/s and 1 hour/s |
| Fleet | One ship of each type, named `ring`, `skiff`, `tug`, `freighter` and `wheel`. The console starts disconnected and connects to one ship at a time. Every ship runs on the one clock whether or not the console is connected to it |
| 3D view | The dashboard draws the connected ship as an orthographic 3D view; see Screen |

## Ship layout

A ship is a class. `Ship` is the base: it holds the rooms, openings, systems, breakers and tanks and runs them. A ship type subclasses it, overrides `_build()` to add its rooms, doors and hatches, and may override `_param_overrides()` to change the params it runs on. The fleet is one of each type:

| Type | Rooms | Doors | Hatches |
|---|---|---|---|
| `RingShip` | 12 segments `s0`…`s11`, each 10 × 5 m and 24.5 m long, round a ring 50 m out | 12, a ring: `s0-s1`…`s11-s0` | `hatch0` in `s0`, `hatch6` in `s6` |
| `SkiffShip` | `cockpit`, `cabin`, `hold`, each 8 × 4 m, in a row | `cockpit-cabin`, `cabin-hold` | `hatch` in `hold` |
| `TugShip` | 2 decks `deck1`, `deck2` (12 × 4 × 12 m), and a ladder pipe split into one segment per deck, `pipe1`, `pipe2` | `deck1-pipe1`, `deck2-pipe2`, `pipe1-pipe2` | `hatch` in `deck1` |
| `FreighterShip` | as the tug with 4 decks and 4 pipe segments | 7 | `hatch` in `deck1` |
| `WheelShip` | 3 rings of 12 segments (`a0`…`a11`, `b0`…`b11`, `c0`…`c11`), 6 spokes `spoke<ring><k>` (`spokea0`, `spokea6`, `spokeb0`, …) and the `hub` | 48: 36 ring doors `a0-a1`, 6 segment-to-spoke doors `a0-spokea0`, 6 spoke-to-hub doors `spokea0-hub` | `hatch` in `b3` |

The tug and freighter share one class, `DeckShip`, which takes the deck count. A ring's segments hang from its axis: `s0` is the one straight down, and the number grows round the ring. A deck ship stacks its decks under thrust.

**Naming.** A door is named for the two rooms it joins, `<room>-<room>`. Ring segments are `<prefix><k>`: `s` for the ring ship and `a`, `b` and `c` for the wheel's rings. Hatches start with `hatch`.

**Six doors per room.** A room has at most six doors and hatches together, on any of its faces; two may share a face, and a ship that gives a room more is an error. A door sits on a face of each room it joins. The Wheel's hub has exactly six, one to each of its six spokes: three in its floor and three in its ceiling. The ladder pipe is one segment per deck so that no pipe room needs more than three.

**Hatches.** A hatch is any opening to outside. The ring has two; every other ship has one. A hatch has its own breaker and motor, and opening one closes every door.

Skiff (not to scale):

```
 ┌──────────┐              ┌──────────────────┐              ┌──────────────┐
 │ COCKPIT  │ cockpit-cabin│       CABIN      │  cabin-hold  │     HOLD     │ hatch
 │  192 m³  ├──────────────┤      320 m³      ├──────────────┤    256 m³    ├──────  outside (vacuum)
 │ crew ×1  │              │     crew ×1      │              │              │
 └──────────┘              └──────────────────┘              └──────────────┘
```

Every door and hatch starts closed, every light starts on, and every system starts running with every room at its setpoint.

**Scale.** Door strength scales with the door's area: conductance, mixing and heat conductance are 10 m³/s, 0.5 m³/s and 100 W/K for a 1 × 2 m door, times the door's area over 2 m². A hatch is not scaled. Tank capacity and starting level, and pressure control's feed rate, scale with the ship's volume over 82 m³ (never below 1); the HVAC's gain and limit scale with each room's volume over 40 m³ (never below 1).

**Adding a ship type.** Subclass `Ship`. Override `_build()` and call `add_room(id, size_m, position, orientation, passengers)`, `add_door(id, room_a, face_a, room_b, face_b, size_m, at)` and `add_hatch(id, room, face)`; a door can name a room added later. Override `_param_overrides()` to return the params that differ from `Ship.default_params()` as a partial Dictionary. Add the type to `Fleet.standard()`.

## Atmosphere model

Internal units are **SI**: m³, mol, Pa, K, W and seconds. The dashboard shows kPa and °C.

Each room holds:

```
Room
  id: String              # such as cockpit, s0 or deck1
  volume: float           # m³
  mol: {O2, N2, CO2}      # moles of each gas
  temperature: float      # K, of the room as a whole (air plus structure)
```

- **Partial pressure** of a gas is `p = n R T / V`. **Pressure** is the sum of the three partial pressures.
- **Composition** shows as each gas's share of the pressure. CO₂ shows as a partial pressure, since that is what passenger safety depends on.
- **Temperature belongs to the room**, not only its air: the structure's heat capacity is far larger than the air's. So a room has a temperature even in vacuum, and gas flowing in or out doesn't change it.

The sim steps every 0.1 s of sim time, or every 5 s at 1 hour/s so it keeps up with the clock. At 1 min/s it runs 600 steps per real second. Every rate below is a param of `Ship` and can be tuned.

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

- **Door, bulk flow.** Gas moves from the higher-pressure room to the lower one: molar flow = `C_door × fraction × ΔP / (R T_source)`, with `C_door` = 10 m³/s for a 1 × 2 m door, scaled by the door's area. The gas carries the source room's composition. Two rooms at different pressures equalize in a few seconds.
- **Door, mixing.** At equal pressure, an open door still swaps 0.5 m³/s of air each way, so CO₂ from one room reaches an open neighbour. It also adds a heat conductance of 100 W/K between the two rooms. Both scale with the door's area.
- **Hatch.** Gas leaves to vacuum at a volumetric rate `C_hatch × fraction`, with `C_hatch` = 5 m³/s, so a room's gas decays as `dn/dt = −n × C_hatch × fraction / V`. A 30 m³ room alone drops below 1 kPa in about 30 s. With doors open, the rooms behind them drain through the hatch too, and the doors slow the flow toward it.

### Exposure

A room is **exposed** when a path of openings that are at least partly open leads from it to the outside. Exposure is worked out on every step. On the skiff:

| cockpit-cabin | cabin-hold | hatch | Exposed rooms |
|---|---|---|---|
| any | any | closed | none |
| any | closed | open | hold |
| closed | open | open | cabin, hold |
| open | open | open | all three |

### Heat

Each room has a heat capacity of 5 kJ/K per m³. It loses heat through the hull to a fixed −20 °C at 0.5 W/K per m³. That loss is 820 W for a 40 m³ room at setpoint, and an unheated room's temperature has a time constant of about 2.8 h.

Heat sources: each passenger gives 100 W, each powered light that is on gives 40 W, and the HVAC adds or removes heat.

### Passengers

Each ship type starts with passengers in some rooms (the skiff has one in its cockpit and one in its cabin). Each passenger uses 3.0 × 10⁻⁴ mol/s of O₂ and makes 2.6 × 10⁻⁴ mol/s of CO₂, about 0.84 kg and 1.0 kg a day. Consumption stops when the room's O₂ runs out. Passengers can't be hurt and never move. With the recycler off and the doors closed, a 12 m³ room's CO₂ reaches the danger level in about 3.7 h of sim time, about 4 minutes at 1 min/s. A 40 m³ room takes about 12 h.

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

- For each room that is **not exposed**, it adds O₂ while ppO₂ is below setpoint and N₂ while ppN₂ is below setpoint, at up to 20 mol/s per gas per room. A 30 m³ room refills in about a minute.
- **It never feeds an exposed room.** That is the breach response: gas sent into a room that is venting would be lost. When the hatch closes, or a door between the room and the hatch closes, the room stops being exposed, and refilling starts on the next step without any command.
- Gas comes from the O₂ and N₂ tanks. An empty tank stops that gas only, and the dashboard flags the tank.
- It only adds gas. It doesn't vent overpressure.

### Tanks

| Tank | Capacity (at 82 m³) | Starts | Filled by | Drained by |
|---|---|---|---|---|
| O₂ | 3,000 mol | full | the recycler | pressure control, replacing O₂ the passengers breathe and O₂ lost to venting |
| N₂ | 8,000 mol | full | nothing | pressure control, replacing N₂ lost to venting |

- Passengers don't use N₂, so the N₂ tank only drains after a vent.
- While the recycler keeps up, the O₂ tank loses only the gap between O₂ breathed and CO₂ exhaled: about 7 mol a day for two passengers, so it lasts more than a year.
- With the recycler down, the O₂ tank drains at the full rate the passengers breathe, about 52 mol a day, so it empties in about 58 days at the 82 m³ reference size (the tank scales with the ship's volume, so the skiff's takes about 540 days). CO₂ reaches danger long before that.
- A tank never fills past its capacity. The recycler's O₂ is discarded when the tank is full.
- The two tanks hold enough to refill the whole ship about three times. Capacity grows with the ship's volume over 82 m³.

### HVAC

- For each room, it heats or cools toward 21 °C with a proportional controller. The output is limited to ±1.5 kW for a 40 m³ room (larger rooms get more, as does their gain), so a breached or freezing room recovers over minutes, not instantly.
- It runs in exposed rooms too, since the room's temperature belongs to its structure.

### CO₂ recycler

- For each room, while ppCO₂ is above 0.3 kPa, it removes CO₂ at up to 0.01 mol/s. That is about 20 times what one passenger exhales.
- Each mole of CO₂ removed becomes one mole of O₂ in the O₂ tank. Pressure control then draws that O₂ back into the rooms as the passengers use it.
- It skips a room that is exposed or whose pressure is below 10 kPa.

### Computer

- It runs the dashboard and answers ship commands. The life support systems run on their own controllers, so they keep working while the computer is down.
- While BOOTING, the computer refuses every ship command with `computer: rebooting; try again in <n> s`, and the dashboard shows *COMPUTER REBOOTING* over the panels. In FAULT, it refuses every ship command but `computer restart` with `computer: fault; only 'computer restart' works`, and the dashboard freezes at the values it last showed and is marked *STALE*. The sim keeps running underneath.
- `computer restart` is still accepted in FAULT, so the computer can always be recovered. The console is separate hardware, so it keeps taking input while the computer is down: ship commands still travel, and the refusal comes back as the reply, with `; 'disconnect' also works` added by the console.

### Doors and hatches

- Each opening is CLOSED, OPENING, OPEN or CLOSING. Doors take 2 s to travel and a hatch 6 s.
- Opening or closing reverses an opening that is moving the other way.
- With no power, an opening stays where it is, partly open included, and rejects commands.
- **Auto-close.** When a hatch starts opening, every powered door that is open or opening starts closing. The doors take 2 s and the hatch 6 s, so a little air from the next room escapes before its door seals. The rule lives in the door controllers, so it works while the computer is down.
- A door without power when a hatch opens stays open. That, or a door reopened by command while a hatch is open, is how the whole ship vents. The auto-close fires only when a hatch starts opening, so a command to reopen a door is obeyed, and the log warns that the door opened onto an open hatch.
- When a hatch opens with a door left open, the dashboard shows a warning and the log records it.

### Lights

Each room has one light with a switch that is on or off. A light shines only when its switch is on and its circuit has power. When the breaker trips, the switch keeps its position, so the light comes back on when power returns.

## Power

| Breaker ID | Component | Draw |
|---|---|---|
| `light-<room id>`, one per room (`light-cockpit`, `light-cabin`, `light-hold`) | room lights | 40 W each when lit |
| the id of each door (`cockpit-cabin`, `cabin-hold`) | door motors | 5 W idle, 200 W moving |
| the id of each hatch (`hatch`) | hatch motors | 5 W idle, 500 W moving |
| `pressure-control` | pressure control | 300 W |
| `hvac` | HVAC | 200 W, plus the heat it moves |
| `air-recycler` | CO₂ recycler | 800 W while scrubbing, 50 W idle |
| — | computer, not on the breaker panel | 150 W |

The breaker IDs are the names in the first column. Breakers come from the ship's rooms and openings: a room adds its `light-<room id>` breaker and a door or hatch adds a breaker with its own id, alongside the three fixed system breakers. The skiff has nine breakers and the Wheel 95 (43 lights, 48 doors, 1 hatch and 3 systems). Breaker IDs are unique, so an opening cannot be named after a system (`pressure-control`, `hvac`, `air-recycler` or `computer`) or start with `light-`. The random draws go in the order room lights, openings, systems.

A breaker is CLOSED (powered) or TRIPPED. The BREAKERS panel shows breaker states and draws (see Screen), and the whole ship's total.

### Random trips

- Each closed breaker trips at random, on average once every 24 h of sim time, independently of the others. With the skiff's nine breakers, the ship sees a trip about every 2.7 h of sim time, about every 2.7 minutes at 1 min/s; the Wheel's trips come about ten times as often.
- A trip is checked on every step with probability `dt / mean_time_between_trips`. That rate is the `breakers.mean_time_between_trips_h` param, and setting it to 0 turns random trips off.
- A trip is logged and raises a warning on the dashboard.
- The random source is seeded from the ship's `seed` param and draws once per breaker per step, so a run is repeatable.

## Command line

One line of input, with a scrollback above it that shows each command and its response. Up and down arrows recall earlier commands. Commands and IDs are case-insensitive. A ship command prints `sent to <ship>; reply in <round trip>` at once, then its one-line reply when it lands, as `reply to '<line>': <reply>`; `help` prints one line per command and `ships list` one line per ship.

### Connecting

The console starts disconnected. Disconnected, only these work; any other command says the console isn't connected:

| Command | Effect |
|---|---|
| `ships list` | List the ships |
| `ships connect <ship name>` | Connect to that ship. Its dashboard replaces the ship table |
| `help` | List these two |

Connected, every command below except `help` goes to that ship, `help` is answered by the console and also lists `disconnect`, and `ships` commands say to disconnect first. `disconnect` drops the connection and the dashboard. It works even while the ship's computer reboots or is in FAULT, since the link is the console's, not the ship's, and the computer's refusals say so.

### Ship commands

A ship command is transmitted. It reaches the ship after the ship's `transmission_s` (default 480 s, a param, never negative), runs there at that sim time, and its reply takes `transmission_s` more to come back. On sending, the console prints `sent to <ship>; reply in <round trip>`, such as `sent to skiff; reply in 16:00` (`m:ss`, or `h:mm:ss` from an hour up), and the reply prints as `reply to '<line>': <reply>` when it lands, naming the command it answers. Before sending, the console checks the line's syntax against the ship's command table: an unknown command or the wrong number of arguments is answered at once with the interpreter's own `unknown command` or `usage:` text, and nothing is sent, whatever the computer's state; the ship checks argument values (room, door, breaker ids) on arrival. The computer's refusal while it reboots or is in FAULT is decided on arrival and is the reply. One command is in flight at a time: another ship command says `waiting on '<line>'; one command at a time`, and `disconnect` says `waiting on '<line>'; disconnect when the reply is in`. `ships` commands, `disconnect` and `help` never travel. Every ship keeps running on the clock throughout.

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
| `help` | List the commands, with the ship's door and room ids in place of `<door id>` and `<room id>` |
| `debug trip <breaker ID>` | Trip a breaker, for testing and demos |
| `debug fault <system>` | Put a system in FAULT, for testing and demos |

Sample responses (each reply lands one round trip after its `sent to` line; the unknown command is answered at once):

```
> door open hatch
sent to skiff; reply in 16:00
reply to 'door open hatch': hatch: opening (6 s)
> door open hatch
sent to skiff; reply in 16:00
reply to 'door open hatch': hatch: already open
> door open cabin-hold
sent to skiff; reply in 16:00
reply to 'door open cabin-hold': cabin-hold: no power (breaker tripped)
> hvac restart
sent to skiff; reply in 16:00
reply to 'hvac restart': hvac: rebooting (8 s)
> hvac restart
sent to skiff; reply in 16:00
reply to 'hvac restart': hvac: no power; reset breaker 'hvac' first
> door shut cabin-hold
unknown command 'door shut'. Type 'help' for commands
```

## Screen

```
┌ console ───────────────┬ clock: ▶ 1 min/s   T+00:42:17 ────────────────────── ⚠ HOLD EXPOSED ┐
│                        │                                                                      │
│                        │        ┌────────┐   ┌─────────────┐   ┌───────────┐                 │
│                        │       ╱ COCKPIT ╱   ╱    CABIN    ╱   ╱   HOLD    ╱ ◁▷ hatch        │
│                        │      └────────┘   └─────────────┘   └───────────┘                  │
│                        │         (the ship in 3D; drag to orbit, wheel to zoom)               │
│                        │                                                                      │
│                        │  HOLD          SYSTEMS           BREAKERS           TANKS            │
│                        │  0.4 kPa       pressure-control  light-hold   ■ 40 W  O₂ ██████░░ 78 %│
│                        │  18.9 °C       hvac         RUN  cabin-hold   ■ 5 W   N₂ ███████░ 91 %│
│                        │  O₂ —          air-recycler BOOT hatch        ■ 5 W                   │
│                        │  N₂ —          computer     RUN  pressure-control ■ 300 W             │
│                        │  CO₂ —                           hvac ■ 200 W  air-recycler ■ 50 W    │
│                        │  passengers 0                    light-cabin □ TRIP                   │
│ > door open hatch      │  light ○                         total 3.1 kW                         │
│ sent to skiff; ...     │                                                                      │
│ uplink: ... — 3:12 left│  LOG                                                                 │
│ ███████░░░             │  00:41:52  hold: exposed to vacuum                                  │
│ downlink: waiting      │  00:41:52  pressure-control: not feeding hold (exposed)              │
│ ░░░░░░░░░░             │                                                                      │
│ > _                    │                                                                      │
└────────────────────────┴──────────────────────────────────────────────────────────────────────┘
```

The sketch isn't to scale: the console takes the left 40% of the window, on a darker panel, and the dashboard the right 60%.

- **Disconnected:** the dashboard's place shows "NO SHIP CONNECTED" over the ship table, and the console says how to connect. The table has one row per ship: its name, its class (`Ring`, `Skiff`, `Tug`, `Freighter`, `Wheel`), its status and a Connect button. The status is the ship's most serious current alarm, as the clock bar would show it: amber if anything on the ship (a room reading, a tank, a system, a breaker) is amber and nothing is red, red if anything is red, and a green NOMINAL otherwise. It is always live, even while a ship's computer reboots or is in FAULT, when that ship's dashboard would be frozen. Connect does what typing `ships connect <ship name>` does, and the line echoes in the console. The clock bar is part of the dashboard, so it is gone too; Space still pauses and resumes every ship.
- **Connecting:** the new dashboard draws the ship at once. If its computer is down, that first drawing stays under the overlay or STALE until the computer runs again.
- **Clock bar:** pause/play, speed (real time, 1 min/s, 1 hour/s), elapsed sim time, the most serious current alarm, and a Disconnect button in the top-right corner that does what typing `disconnect` does. Space toggles pause unless the command line has focus.
- **3D view:** the connected ship, orthographic, under the clock bar and filling about half the dashboard's height. Each room is a see-through box tinted by its status, and the selected room's box is brighter. Each door and hatch is a panel on its wall, coloured by its state: closed, open, moving or without power. Each room's name is flat text at the room's centre that moves with the room and always faces the screen. A name that overlaps a higher-priority name is hidden until the view or the selection changes.
- **View controls:** left-drag orbits the camera round the ship, the wheel zooms, and a click (press and release without dragging) selects the room under the cursor, or the room whose name is under it. Where rooms stand in front of one another, the nearest wins, and a room that holds the camera is not picked. While the computer reboots or is in FAULT the dashboard is frozen and clicks do nothing.
- **Selection:** the first room of the ship is selected at start.
- **ROOM panel:** the left-most panel, headed by the selected room's name in its status color. It shows pressure, temperature, O₂ and N₂ share, ppCO₂, the passenger count, and the light. Below 1 kPa the shares show "—".
- **Systems and tanks** panels, as above.
- **BREAKERS panel:** it lists, in this order, the selected room's breakers (its light, then the doors and hatches in its walls), the system breakers, then every tripped breaker anywhere on the ship that is not already listed. Each row shows the breaker's id with its state and draw. Selecting another room changes the list. The total under it is the whole ship's draw.
- **Scrolling:** the panels sit in a scroll area under the 3D view, so a long breaker list scrolls instead of shrinking the view.
- **Log:** the last 50 events with sim timestamps. It holds the ship's own events (system state changes, rooms exposed or sealed, warnings, breaker trips and empty tanks), not commands.
- **Command line:** a column down the left side of the window, the left 40% of its width and the full height, on a darker panel, with the dashboard taking the right 60%. It has focus at start. Commands and their responses fill the scrollback, with the input at the bottom of the column. Between them sit two progress bars, `uplink` and `downlink`, each with a label: idle, or the command with its time left (`uplink: door open hatch — 3:12 left`). While the uplink runs the downlink reads `waiting`; while the reply comes back the uplink stays full and reads `sent`. Both read idle when disconnected. The console is separate hardware linked to one ship, so it stays visible and usable while the computer reboots or is in FAULT. The reboot overlay and the STALE label cover only the dashboard.

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

## Code structure

- **Simulation core:** plain GDScript classes, no nodes. It holds the rooms, openings, exposure, systems, breakers, tanks, passengers and the clock, and is stepped by `step(dt)`. Everything that can be tested lives here.
- **Command interpreter:** a pure function from a command string and the ship to the ship's changes and a response line. It holds no nodes and is tested headless.
- **Fleet and link:** `Fleet` holds the ships by name, builds one of each type with `Fleet.standard()`, and advances them all; `ShipLink` holds which ship the console is connected to, answers `ships`, `disconnect`, `help` and syntax errors (`CommandInterpreter.syntax_problem`) itself, and sends every other line to the ship's interpreter with the transmission delay. Main advances the whole fleet through `ShipLink.advance`.
- **Ship types:** one class per type in `scripts/ships/`, each a subclass of `Ship` that builds its rooms, doors and hatches in code.
- **UI:** a thin layer of scenes for the clock bar, the 3D view (`ShipView3D`), the panels, the log and the command line. It reads the core's state and sends it commands through the interpreter.
- **Tests:** headless, with the same runner as `prototypes/transit/tests`. They cover:
  - pressure from moles and temperature, against hand-worked cases
  - two rooms equalizing through an open door, with the total moles conserved
  - a closed door passing nothing
  - the exposure table above, every row
  - hatch open with `cabin-hold` closed: the hold vents and the cabin and cockpit are unchanged
  - the hatch opening: powered open doors close by themselves, and an unpowered open door stays open
  - hatch open with both doors unpowered and open: all three rooms vent
  - each ship type: its rooms, doors and hatches, at most six doors per room, a 24 h steady state in range, and its hatches sealing and venting
  - a door reopened by command while the hatch is open: it stays open and the log warns
  - the recycler returning one mole of O₂ to the tank per mole of CO₂, and never past capacity
  - the O₂ tank holding nearly steady with the recycler running, and draining with it down
  - random trips: about the configured rate over a long run, none at rate 0, and the same seed giving the same trips
  - the hatch closing: the hold refills to setpoint on its own, with no command
  - pressure control never feeding an exposed room
  - an empty tank stopping only its own gas
  - the HVAC holding setpoint, and a room cooling with the HVAC unpowered
  - the recycler holding CO₂ below 0.5 kPa with passengers, and CO₂ rising with it unpowered
  - a tripped breaker removing each component's function, and a reset bringing it back through BOOTING
  - a restart clearing a FAULT, and being refused with no power
  - the computer down: ship commands refused on arrival (in FAULT, all but `computer restart`), and life support still running
  - an unpowered door holding its position, partly open included
  - a light's switch surviving a trip
  - adding a passenger raising a sealed room's CO₂ faster, a passenger adding `heat.passenger_w` of heat, and removing the last one stopping breathing in that room
  - each room's passenger count, in the model and on the main screen after `passenger add`
  - the 3D view: a box and a name per room, a panel per opening, status tints, picking, orbit, zoom and click
  - the BREAKERS panel: the selected room's breakers, then the systems, then a breaker tripped elsewhere, and the list changing with the selection
  - each command's success and error responses
  - the same commands from the same start always giving the same state

## Open questions

1. **Random system faults.** Breakers trip at random, but systems enter FAULT only through `debug fault`, so a restart is needed only after an injected fault. Systems could also fault at random, which would give `restart` a job in normal play.
