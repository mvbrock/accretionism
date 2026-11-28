# Ship Sim Prototype

A fleet of five ships, each with rooms, an atmosphere, three life-support systems, doors, one or more hatches and a
power panel. A dashboard on the right shows the connected ship in 3D and its readings, and a command line
down the left side is the only way to act on the ship. Open the skiff's hatch and its hold vents; close it
and the hold refills. Design: `docs/design.md`.

## Run

- Editor: `godot -e --path .` (from this folder), then press F5.
- Directly: `godot --path .`

Space pauses every ship unless the command line has focus, connected or not; the clock bar also has
Pause/Play and Speed (real time, 1 min/s, 1 hour/s) buttons. Up and down recall earlier commands. Esc quits.

| Control | Effect |
|---|---|
| Left-drag in the 3D view | Orbit the camera round the ship |
| Mouse wheel in the 3D view | Zoom |
| Click a room, or its name | Select it: its readings show in the ROOM panel and its breakers in the BREAKERS panel |
| Connect, in the ship table | Same as `ships connect <ship name>` |
| Disconnect, top right | Same as `disconnect` |

Disconnected, the dashboard's place shows a table of the ships: name, class, status and a Connect button. The
status is the ship's most serious current alarm, amber or red, or a green NOMINAL.

## Ships

A ship is a class: `Ship` is the base, and each type subclasses it and lays out its rooms, doors and hatches.
The fleet is one of each type, named for it:

| Ship | Rooms | Doors | Hatches |
|---|---|---|---|
| `ring` | 12 segments, `s0` to `s11` | 12, each segment to the next, such as `s0-s1` | `hatch0` in `s0`, `hatch6` in `s6` |
| `skiff` | `cockpit`, `cabin`, `hold` | `cockpit-cabin`, `cabin-hold` | `hatch` in `hold` |
| `tug` | 2 decks `deck1`, `deck2` and 2 ladder segments `pipe1`, `pipe2` | 3 | `hatch` in `deck1` |
| `freighter` | as the tug with 4 decks and 4 segments | 7 | `hatch` in `deck1` |
| `wheel` | 3 rings of 12 segments (`a0` to `a11`, `b0` to `b11`, `c0` to `c11`), 6 spokes (`spokea0`, `spokea6`, and so on) and the `hub` | 48 | `hatch` in `b3` |

A door is named for the two rooms it joins, `<room>-<room>`. Each room has at most six doors and hatches, on any
of its faces (two may share a face); the Wheel's hub has exactly six. A hatch is any opening to outside; its id starts with
`hatch`. Opening a hatch closes every door, so only the hatch's room vents; the other rooms vent only through
doors that stay open.

Door strength scales with the door's area, and the tanks, pressure control and HVAC scale with the ship's and
room's volume, so a big ship keeps its air as a small one does. Every ship runs on the one clock, connected or
not. Each room has one light and each door and hatch one breaker, so the Wheel has 95 breakers; a big
ship sees more random trips.

## Commands

Commands and IDs are case-insensitive. A ship command prints `sent to <ship>; reply in <round trip>` at
once, then its one-line reply when it lands, as `reply to '<line>': <reply>`; `help` prints one line per
command and `ships list` one line per ship.

The console starts disconnected. Connect to a ship to see its dashboard and command it:

| Command | Effect |
|---|---|
| `ships list` | List the ships (only while disconnected) |
| `ships connect <ship name>` | Connect to that ship (only while disconnected) |
| `disconnect` | Disconnect from the ship; works even while its computer is down |

Connected, `ships`, `disconnect` and `help` answer at once, and the other commands below go to that ship.
A command takes the ship's `transmission_s` (8 minutes) to arrive and runs
then; its reply takes as long to come back. The console prints `sent to <ship>; reply in <round trip>` when
it sends, and `reply to '<line>': <reply>` when the reply lands. The console checks the line first: an
unknown command or the wrong number of arguments is answered at once with the usual `unknown command` or
`usage:` text and nothing is sent; the ship still checks the values (room, door and breaker ids). One
command is in flight at a time, and `disconnect` waits for the reply. Two bars under the scrollback show the
command's progress, each with the time left: `uplink` while it travels to the ship, `downlink` while the
reply comes back.

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
| `help` | List the commands (answered at once, even while the computer reboots) |
| `debug trip <breaker ID>` | Trip a breaker, for testing and demos |
| `debug fault <system>` | Put a system in FAULT, for testing and demos |

While the computer reboots a "COMPUTER REBOOTING" overlay covers the dashboard. In FAULT the
dashboard freezes and shows "STALE" until `computer restart`. Ship commands still go out while the
computer is down, and come back refused (in FAULT, all but `computer restart`).

## The dashboard

The connected ship shows in 3D: each room is a see-through box tinted by its status, each door and hatch a
panel on its wall coloured by its state, and each room's name always faces the screen; a name hidden behind a
higher-priority one shows again when the view or selection changes. Below it are four panels, which scroll
when long, and the log:

- ROOM: the selected room's readings.
- SYSTEMS: the three life-support systems and the computer.
- BREAKERS: the selected room's breakers (its light and the doors and hatches in its walls), then the system
  breakers, then every tripped breaker anywhere on the ship that is not already listed, each with its state and
  draw. The total is the whole ship's.
- TANKS: O₂ and N₂.

## How it works

- The simulation core (`scripts/*.gd`) has no nodes. `Ship` advances in whole steps of sim time, 0.1 s, or 5 s at
  1 hour/s, so nothing depends on frame rate.
- `scripts/ships/` holds the ship types, one class each. To add a type, subclass `Ship`, override `_build()` to
  call `add_room`, `add_door` and `add_hatch`, and override `_param_overrides()` for any params that differ; then
  add it to `Fleet.standard()`.
- `ShipLink` holds which ship the console is connected to, advances the whole fleet, and carries each ship command
  across the transmission delay and its reply back.
- `scripts/dashboard_model.gd` turns a `Ship` into the strings and levels the screen shows.
- `scripts/ui/` is a thin layer built in code: `Main` runs the clock and the command line,
  `DashboardView` draws the model, `ShipView3D` is the 3D view, `Console` is the input and scrollback (the left column), with
  `LinkStatus`'s uplink and downlink bars between them.

## Tests

```sh
godot --headless --path . --import   # once, or after adding a class_name script
godot --headless --path . -s res://tests/run_tests.gd                 # all
godot --headless --path . -s res://tests/run_tests.gd -- main_scene   # filter by file/test name
```

A test fails if it logs an engine or script error. A test that deliberately triggers one declares
it with `expect_error("part of the message")`.

Screenshots: `godot --path . -- --capture <dir>` runs at 1 min/s, connects to the skiff, opens the
hatch, selects the hold, saves `venting.png` at 20 s of sim time, closes the hatch, saves `refilled.png` at
120 s, then quits.
