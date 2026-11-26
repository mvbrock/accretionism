# Ship Sim Prototype

A fleet of ships, each with rooms (such as a cockpit, main room and cargo hold), an atmosphere, three life-support systems,
doors, a hatch and a power panel. A dashboard on the right shows every room and system at a glance,
and a command line down the left side is the only way to act on the ship. Open the hatch and the
cargo hold vents; close it and the hold refills. Design: `docs/design.md`.

## Run

- Editor: `godot -e --path .` (from this folder), then press F5.
- Directly: `godot --path .`

Space pauses every ship unless the command line has focus, connected or not; the clock bar also has Pause/Play and Speed (1×, 10×,
100×) buttons. Up and down recall earlier commands. Esc quits.

| Control | Effect |
|---|---|
| Click a room | Show that room's readings in the ROOM panel |

## Commands

Commands and IDs are case-insensitive. Every command prints one line, except `help` and `ships list` (one line per ship).

The console starts disconnected. Connect to a ship to see its dashboard and command it:

| Command | Effect |
|---|---|
| `ships list` | List the ships (only while disconnected) |
| `ships connect <ship name>` | Connect to that ship (only while disconnected) |
| `disconnect` | Disconnect from the ship; works even while its computer is down |

Connected, these act on that ship:

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
| `help` | List the commands |
| `debug trip <breaker ID>` | Trip a breaker, for testing and demos |
| `debug fault <system>` | Put a system in FAULT, for testing and demos |

While the computer reboots a "COMPUTER REBOOTING" overlay covers the dashboard. In FAULT the
dashboard freezes and shows "STALE" until `computer restart`.

## Data

Each file in `data/ships/` is one ship, named by its file: `kestrel.json` is `kestrel`. Add a file to add a
ship. Every ship runs on the one clock, connected or not. A ship file holds every tunable number: room volumes and starting air, the openings, setpoints
and status bands, system rates, tank sizes, breaker draws, boot times and the random seed. The same
seed gives the same random breaker trips. Add a room or a door there and it gets its own breaker.

## How it works

- The simulation core (`scripts/*.gd`) has no nodes. `Ship` advances in whole 0.1 s steps of sim
  time, so nothing depends on frame rate.
- `scripts/dashboard_model.gd` turns a `Ship` into the strings and levels the screen shows.
- `scripts/ui/` is a thin layer built in code: `Main` runs the clock and the command line,
  `DashboardView` draws the model, `Console` is the input and scrollback (the left column).

## Tests

```sh
godot --headless --path . --import   # once, or after adding a class_name script
godot --headless --path . -s res://tests/run_tests.gd                 # all
godot --headless --path . -s res://tests/run_tests.gd -- main_scene   # filter by file/test name
```

A test fails if it logs an engine or script error. A test that deliberately triggers one declares
it with `expect_error("part of the message")`.

Screenshots: `godot --path . -- --capture <dir>` runs at 100×, connects to the first ship, opens the hatch, selects cargo, saves `venting.png`
at 20 s of sim time, closes the hatch, saves `refilled.png` at 120 s, then quits.
