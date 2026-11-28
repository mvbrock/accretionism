# People Prototype

Three hundred passengers travel in parties between Earth, the Moon and Mars on transit's fleet of
cyclers and transports. A sortable, filterable table lists everyone with their location and progress;
a detail panel on the right shows the selected passenger's journey, party, health, relationships and
history. Events (changes of mind, medical emergencies, malfunctions, rescues) re-route parties as the
clock runs. The UI only watches; it never changes the sim. Design: `docs/design.md`.

## Run

- Editor: `godot -e --path .` (from this folder), then press F5.
- Directly: `godot --path .`

## Controls

| Input | Action |
|---|---|
| Space, or the Pause/Play button | Pause or resume the clock |
| Speed button | Step through the clock speeds |
| Click a column header | Sort by that column; click again to reverse |
| Filter box | Show only rows with a cell containing the text; Enter leaves the box |
| Click a table row | Show that passenger in the detail panel |
| Click a party member or relation in the panel | Select that passenger and scroll the table to them |
| Esc | Quit |

The table scrolls to the selected row only when you select, sort or filter, so you can scroll
away from it while the clock runs.

## Tests

```sh
godot --headless --path . --import   # once, or after adding a class_name script
godot --headless --path . -s res://tests/run_tests.gd                 # all
godot --headless --path . -s res://tests/run_tests.gd -- detail       # filter by file/test name
```

A test fails if it logs an engine or script error (a call on `null`, a type mismatch, `push_error`).
A test that deliberately triggers one declares it with `expect_error("part of the message")`, and
fails if that error never arrives.
