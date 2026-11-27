# Ship Sim Prototype

A fleet of ships, each with rooms (such as a cockpit, main room and cargo hold), an atmosphere, three life-support systems,
doors, a hatch and a power panel. A dashboard on the right shows every room and system at a glance,
and a command line down the left side is the only way to act on the ship. Open the hatch and the
cargo hold vents; close it and the hold refills. Design: `docs/design.md`.

## Run

- Editor: `godot -e --path .` (from this folder), then press F5.
- Directly: `godot --path .`

Space pauses every ship unless the command line has focus, connected or not; the clock bar also has Pause/Play and Speed (real time, 1 min/s,
1 hour/s) buttons. Up and down recall earlier commands. Esc quits.

| Control | Effect |
|---|---|
| Click a room | Show that room's readings in the ROOM panel |

## Commands

Commands and IDs are case-insensitive. A ship command prints `sent to <ship>; reply in <round trip>` at once, then its one-line reply when it lands, as `reply to '<line>': <reply>`; `help` prints one line per command.

The console starts disconnected. Connect to a ship to see its dashboard and command it:

| Command | Effect |
|---|---|
| `ships list` | List the ships (only while disconnected) |
| `ships connect <ship name>` | Connect to that ship (only while disconnected) |
| `disconnect` | Disconnect from the ship; works even while its computer is down |

Connected, these go to that ship. A command takes the ship's `transmission_s` (8 minutes unless its file says
otherwise) to arrive and runs then; its reply takes as long to come back. The console prints
`sent to <ship>; reply in <round trip>` when it sends, and `reply to '<line>': <reply>` when the reply lands. The console checks the line first: an unknown command or the wrong number of arguments is answered at once
with the usual `unknown command` or `usage:` text and nothing is sent; the ship still checks the values (room, door and breaker ids). One command is in flight
at a time, and `disconnect` waits for the reply. Two bars under the scrollback show the command's
progress, each with the time left: `uplink` while it travels to the ship, `downlink` while the reply comes
back. `ships`, `disconnect` and `help` answer at once:

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
dashboard freezes and shows "STALE" until `computer restart`.

## Data

Each file in `data/ships/` is one ship, named by its file: `kestrel.json` is `kestrel`. Add a file to add a
ship. Every ship runs on the one clock, connected or not. A ship file holds every tunable number: room volumes and starting air, the openings, setpoints
and status bands, system rates, tank sizes, breaker draws, boot times and the random seed. The same
seed gives the same random breaker trips. An optional `transmission_s` (default 480, never negative) is the one-way
time for a command or reply to cross the link to that ship. Add a room or a door there and it gets its own breaker.

## How it works

- The simulation core (`scripts/*.gd`) has no nodes. `Ship` advances in whole steps of sim time, 0.1 s, or 1 s at
  1 hour/s, so nothing depends on frame rate.
- `ShipLink` holds which ship the console is connected to, advances the whole fleet, and carries each ship command
  across the transmission delay and its reply back.
- `scripts/dashboard_model.gd` turns a `Ship` into the strings and levels the screen shows.
- `scripts/ui/` is a thin layer built in code: `Main` runs the clock and the command line,
  `DashboardView` draws the model, `Console` is the input and scrollback (the left column), with `LinkStatus`'s uplink and downlink bars between them.

## Tests

```sh
godot --headless --path . --import   # once, or after adding a class_name script
godot --headless --path . -s res://tests/run_tests.gd                 # all
godot --headless --path . -s res://tests/run_tests.gd -- main_scene   # filter by file/test name
```

A test fails if it logs an engine or script error. A test that deliberately triggers one declares
it with `expect_error("part of the message")`.

Screenshots: `godot --path . -- --capture <dir>` runs at 1 min/s, connects to the first ship, opens the hatch, selects cargo, saves `venting.png`
at 20 s of sim time, closes the hatch, saves `refilled.png` at 120 s, then quits.
