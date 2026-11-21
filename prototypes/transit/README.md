# Transit Prototype

A logistics view of an Earth–Moon–Mars fleet: six Aldrin cyclers shuttle between Earth and Mars on
a fixed timetable, and 30 transports can be sent to Earth, the Moon, Mars or any cycler. The fleet
shows as a table and as a schematic diagram, on separate tabs. Design: `docs/design.md`.

## Run

- Editor: `godot -e --path .` (from this folder), then press F5.
- Directly: `godot --path .`

## Controls

| Input | Action |
|---|---|
| Space, or the Pause/Play button | Pause or resume the clock |
| Speed button | Step through 1 h, 1 d and 10 d per real second |
| Click a table row or a diagram shape | Select that ship |
| Target list, then **Depart** | Send the selected transport, after showing its estimated travel time |
| Esc | Quit |

Cyclers keep to their timetable, so selecting one shows no dispatch controls. Sending a transport
that is already in flight redirects it.

## Data

`data/fleet.json` holds the random seed, the bodies' angles at epoch, the cycler timetable, and
every ship's name. A transport's origin is a body name, a cycler name or `random`. The same seed
always builds the same fleet.

## How it works

- The simulation core (`scripts/*.gd`) has no nodes. Every position is a pure function of the
  sim day, and a transport's arrival time is worked out exactly when it departs, so a fast clock
  can't skip an arrival.
- `scripts/diagram_layout.gd` turns the fleet's state into screen shapes. It reads only each
  ship's state, origin, destination and progress, never an orbital position.
- `scripts/ui/` is a thin layer that reads the core and sends it dispatch commands.

## Tests

```sh
godot --headless --path . --import   # once, or after adding a class_name script
godot --headless --path . -s res://tests/run_tests.gd                 # all
godot --headless --path . -s res://tests/run_tests.gd -- diagram      # filter by file/test name
```

Screenshots after a scripted run at 10 d/s: `godot --path . -- --capture <dir>` saves
`table.png` and `diagram.png`, then quits.
