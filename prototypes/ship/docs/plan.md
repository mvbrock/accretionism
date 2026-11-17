# Ship Ring Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Godot 4 prototype in which a capsule walks all the way around the inside of a spinning 12-sided ring, seen through a fixed isometric camera.

**Architecture:** The ship is static geometry built from code around the world X axis. The player is a CharacterBody3D whose `up_direction` always points toward the hub (radial spin gravity). A camera rig on the axis rotates to match the player's angle, so on screen the ship appears to turn under a fixed isometric camera. A fader runs rays along the camera's view direction to fade any wall or ceiling panel that blocks the player.

**Tech Stack:** Godot 4.7 (Homebrew cask `godot`), GDScript, Forward+ renderer. Headless tests use a plain `SceneTree` runner with no plugins.

**Spec:** `prototypes/ship/docs/design.md`

## Global Constraints

- Everything lives under `prototypes/ship/` (the Godot project root).
- Ring: 12 sections; floor corner radius 50 m; corridor 10 m wide (x ∈ [−5, 5]); ceiling 5 m above the floor.
- Spin axis = world X. Section 0 is centered straight down (−Y); section *k* is centered at angle 30°·*k*.
- Gravity 9.8 m/s², radially outward from the X axis.
- Controls: W/S move around the ring, A/D move across it. No jump, no sprint.
- Collision layers: 1 = world (everything the player collides with), 2 = occluder (walls and ceilings only).
- Not a git repo: skip the commit steps.

Godot binary: `GODOT=/Applications/Godot.app/Contents/MacOS/Godot`.
Test command (from `prototypes/ship`): `$GODOT --headless --path . -s res://tests/run_tests.gd`. It exits 0 when all tests pass and prints `FAIL: <name> — <message>` for each failure.

## Review Focus

1. **Crossing a seam**: the player must not catch, bounce, or leave the floor at the 15° valleys. Covered by the full-lap test in Task 3.
2. **Pushing into a wall at a seam**: wall slabs meet at an angle, so the player must not squeeze through the gap. Covered by the wall test at a seam in Task 3.
3. **Standing still on a slope**: with no input, the player must not drift toward the seam valley. Covered by the drift test in Task 3.
4. **Lap wraparound**: the rig angle crosses ±180° and must not spin the camera the long way around. Covered by the rig test at section 6 in Task 4.
5. **Fading several panels at once**: when a ceiling and a wall both block the view, both must fade. Covered by the multi-occluder test in Task 5.

---

### Task 1: Install Godot, create the project skeleton, and add the ring geometry math

**Files:**
- Create: `project.godot`, `scripts/ring_geometry.gd`, `tests/run_tests.gd`, `tests/test_ring_geometry.gd`

**Interfaces:**
- Produces: `class_name RingGeometry` (static only):
  - constants `SECTIONS := 12`, `FLOOR_CORNER_RADIUS := 50.0`, `HALF_WIDTH := 5.0`, `CEILING_HEIGHT := 5.0`, `SLAB_THICKNESS := 0.4`
  - `static func floor_apothem() -> float` (≈ 48.296), `ceiling_apothem() -> float` (floor − 5), `floor_side_length() -> float` (≈ 25.882), `ceiling_side_length() -> float`
  - `static func section_angle(k: int) -> float` returns 30°·k in radians
  - `static func section_down(k: int) -> Vector3` returns the outward unit normal of panel k: `(0, -cos θ, -sin θ)`
  - `static func section_tangent(k: int) -> Vector3` returns the unit direction along panel k toward increasing angle: `(0, sin θ, -cos θ)`
  - `static func angle_of(p: Vector3) -> float` returns `atan2(-p.z, -p.y)`, the player's angle around the axis
  - `static func up_at(p: Vector3) -> Vector3` returns the unit vector from p toward the axis (perpendicular to X)
  - `static func section_of(p: Vector3) -> int` returns the nearest section index, 0–11
- Test runner contract: each `tests/test_*.gd` extends `RefCounted` and has `test_*` methods that take an optional `tree: SceneTree` argument. Assertions use `assert_true(cond, msg)` and `assert_near(a, b, tol, msg)`, which are inherited from `tests/test_case.gd`. The runner finds every `test_*.gd`, runs each method (awaiting it if it is a coroutine), and exits with the failure count.

- [ ] **Step 1: `brew install --cask godot`**, then confirm `$GODOT --version` prints 4.7.x.
- [ ] **Step 2: Write `project.godot`** (name "Ship Ring Prototype", main scene `res://scenes/main.tscn`, Forward+, window 1600×900) and the runner plus `tests/test_case.gd`.
- [ ] **Step 3: Write the failing tests** in `test_ring_geometry.gd`:
  - `floor_apothem() ≈ 48.296`, `floor_side_length() ≈ 25.882`, `ceiling_apothem() ≈ 43.296` (tol 0.001)
  - `angle_of(section_down(k) * 48.0) ≈ section_angle(k)` for every k, wrapped to (−π, π]
  - `section_of(section_down(k) * 48.0 + Vector3(3, 0, 0)) == k` for all k
  - `up_at(Vector3(2, -10, 0)) == Vector3(0, 1, 0)`
  - `section_tangent(k).dot(section_down(k)) ≈ 0`
- [ ] **Step 4: Run the tests and confirm they fail** (RingGeometry is missing).
- [ ] **Step 5: Implement `ring_geometry.gd`** and run the tests: all pass.

### Task 2: Ship builder (sections, colors, collision, lights, crates)

**Files:**
- Create: `scripts/ship_builder.gd`, `tests/test_ship_builder.gd`

**Interfaces:**
- Consumes: RingGeometry.
- Produces: `class_name ShipBuilder extends Node3D` that builds everything in `_ready()`:
  - per section k, a `Node3D` named `Section<k>` containing StaticBody3D children `Floor`, `Ceiling`, `WallLeft` (x = −5), `WallRight` (x = +5); each has a `MeshInstance3D` named `Mesh` and a `CollisionShape3D` with a `ConvexPolygonShape3D` made from the same 8 corner points
  - `Floor`: collision layer 1. `Ceiling` and walls: layers 1 and 2, with `set_meta("fade_mesh", mesh_instance)`
  - each panel mesh gets its own `StandardMaterial3D`; the floor uses `section_color(k)`, while walls and ceiling use the same hue, desaturated and lighter
  - `static func section_color(k: int) -> Color` returns `Color.from_hsv(k / 12.0, 0.65, 0.85)`
  - one `OmniLight3D` per section at 0.6 m below the ceiling at the section center (range 22, shadows on), plus a `WorldEnvironment` with dark background and ambient energy around 0.4
  - crates: `Crates` node containing StaticBody3D cubes (layer 1), 2 per section from a seeded RNG (seed 1337), with size 1.0 or 1.5 m, local x in [−4, 4] and tangent offset in [−10, 10], skipping |offset| < 3 in section 0 (spawn). Each crate's bottom face rests on its panel and is oriented with that panel's normal.
- Slab corner math: in a panel's (x, along, radial) frame, the floor slab spans radial [apothem, apothem + 0.4] and the ceiling spans [ceiling_apothem − 0.4, ceiling_apothem]. Along-panel half-length scales with the radius (`r * tan 15°`) so neighboring slabs meet exactly at the seams. Walls span radial [ceiling_apothem, apothem] and x ∈ [±5, ±5.4], with along-panel half-length `r * tan 15°` at each radius (a trapezoid).

- [ ] **Step 1: Write the failing tests**, which instantiate ShipBuilder, add it to the tree, and await one frame:
  - 12 `Section*` children, each with Floor, Ceiling, WallLeft, and WallRight
  - a downward ray from `section_down(k) * 47` toward `section_down(k) * 49` hits Floor of Section k at a distance ≈ `floor_apothem() − 47` for k = 0, 4, 9
  - a ray along +X from (0, −46, 0) hits Section0/WallRight at x ≈ 5
  - a ray restricted to mask 2 from the axis toward `section_down(3) * 46` hits Section3/Ceiling
  - `section_color` returns 12 distinct colors
  - 24 crates; for each crate, a ray from its center along its panel's outward normal hits a Floor within (size/2 + 0.05)
- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement ShipBuilder.** Build meshes with `SurfaceTool` from the 8 points (6 quads, `generate_normals()`, with outward-facing winding).
- [ ] **Step 4: Run the tests: all pass.**

### Task 3: Player controller with radial gravity

**Files:**
- Create: `scripts/player.gd`, `scenes/player.tscn`, `tests/test_player.gd`

**Interfaces:**
- Consumes: RingGeometry, ShipBuilder.
- Produces: `class_name Player extends CharacterBody3D`, with the scene root `Player` containing a capsule `CollisionShape3D` (radius 0.4, height 1.8, centered 0.9 m up), a capsule `MeshInstance3D`, and a small box `Nose` at (0, 1.5, −0.4):
  - `@export var walk_speed := 3.0`, `@export var gravity := 9.8`, `@export var turn_speed := 12.0`
  - `var move_input := Vector2.ZERO`: x = across (D = +1), y = around (W = +1). `_physics_process` reads `Input.get_vector` into it unless `drive_by_code` is true, so tests can drive the player directly.
  - `static func ensure_input_actions()` registers `move_forward` (W), `move_back` (S), `move_left` (A), and `move_right` (D) if they're missing
- Per physics frame:
  - `up_direction = RingGeometry.up_at(global_position)`
  - The around-the-ring direction is `up.cross(Vector3.RIGHT)`, chosen so that W moves up-right on screen. The across direction is `Vector3.RIGHT`.
  - Set horizontal velocity to `walk_speed` in the input direction. Keep the vertical component along up and apply gravity when not on the floor.
  - Set `floor_stop_on_slope`, `floor_constant_speed`, `floor_snap_length = 0.6`, and `floor_max_angle = 40°`.
  - Rebuild the body basis with Y = up, then turn the facing (−Z) toward the movement direction.

- [ ] **Step 1: Write the failing tests** (the ship plus the player spawned at `section_down(0) * (floor_apothem() - 0.05)`, stepped with `await tree.physics_frame`):
  - after 60 idle frames, `is_on_floor()` and the drift is < 0.05 m
  - idle for 120 frames at tangent offset +10 on section 0 (on the slope): drift < 0.05 m
  - full lap: `move_input = Vector2(0, 1)`, `walk_speed = 30` (test only); each frame, accumulate the unwrapped change in `angle_of`; every frame after the first 10 is on the floor, and after the total exceeds 2π the player's radius from the axis stays within [floor_apothem − 0.1, 50.1]
  - walls: hold `move_input = (1, 0)` for 120 frames, so x < 5 − 0.4 + 0.02; repeat at a seam (tangent offset ≈ 12.9 on section 0) with the same bound
- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement the player script and scene.**
- [ ] **Step 4: Run the tests: all pass.**

### Task 4: Camera rig

**Files:**
- Create: `scripts/camera_rig.gd`, `tests/test_camera_rig.gd`

**Interfaces:**
- Consumes: RingGeometry, Player.
- Produces: `class_name CameraRig extends Node3D` (at the origin) with a `Camera3D` child named `Camera`:
  - `@export var target: Node3D`, `@export var ortho_size := 24.0`, `@export var distance := 40.0`, `@export var follow_sharpness := 10.0`
  - `func update_rig(delta: float)` (called in `_process`) sets `rotation.x = RingGeometry.angle_of(target.global_position)`. Ring rotation is exact with no smoothing, to keep the continuous behavior honest. The camera's local position eases toward `to_local(target_pos) + iso_back * distance`, where `iso_back` comes from `Basis.from_euler(Vector3(deg_to_rad(-35.264), deg_to_rad(45), 0)).z`.
  - The camera is orthographic, with `size = ortho_size`, `near = 0.1`, and `far = 200`.
  - `func snap()` jumps the camera to its target position with no easing (used on start).

- [ ] **Step 1: Write the failing tests:**
  - with the target at `section_down(k) * 48 + Vector3(2, 0, 0)` and calling update_rig then snap, `rig.to_local(target).z ≈ 0` and `.y < 0` for k = 0, 3, 6, 11
  - moving the target from k = 5 to k = 7 changes `rotation.x` by ≈ +60° measured the short way (wrapped), not by −300°
  - the camera's forward vector (−basis.z) in rig-local space points downward (y < 0)
- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement the camera rig.**
- [ ] **Step 4: Run the tests: all pass.**

### Task 5: Occlusion fader

**Files:**
- Create: `scripts/occlusion_fader.gd`, `tests/test_occlusion_fader.gd`

**Interfaces:**
- Consumes: CameraRig's `Camera`, the Player, and the `fade_mesh` metadata on occluder bodies.
- Produces: `class_name OcclusionFader extends Node`:
  - `@export var camera: Camera3D`, `@export var target: Node3D`, `@export var faded_alpha := 0.15`, `@export var fade_speed := 8.0`
  - `func find_occluders() -> Array[MeshInstance3D]`: for sample points along the target's up axis at 0.2, 0.9, and 1.7 m, plus ±0.4 m sideways along the camera's right vector at 0.9 m, cast rays from `point - cam_forward * 80` to `point` with mask 2. On each hit, add the body to the exclude list and cast again, up to 6 hits per ray.
  - `func _process(delta)`: move each tracked mesh's alpha toward `faded_alpha` if it is occluding and toward 1 otherwise. The material uses `TRANSPARENCY_ALPHA` while alpha < 0.99 and `TRANSPARENCY_DISABLED` once fully opaque.

- [ ] **Step 1: Write the failing tests** (with the full main scene in place):
  - with the player at the spawn point, run `find_occluders()` after rig.snap(): it includes Section0/Ceiling
  - with the player at x = +4.3 (beside the camera-side wall), the result includes both Section0/Ceiling and Section0/WallRight
  - no Floor mesh is ever returned
  - after 2 s of `_process` steps, the occluding ceiling's material alpha is < 0.2. After moving the player to section 6, stepping 2 s more, and re-checking, the old ceiling's alpha is > 0.98 with transparency disabled.
- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement the occlusion fader.**
- [ ] **Step 4: Run the tests: all pass.**

### Task 6: Main scene assembly and visual check

**Files:**
- Create: `scenes/main.tscn`, `scripts/main.gd`, `README.md`

**Interfaces:**
- Consumes: everything above.
- `main.tscn`: root `Main` (Node3D, with `main.gd`) containing `Ship` (ShipBuilder), `Player` (instance of player.tscn), `CameraRig` → `Camera`, and `OcclusionFader`, with the fader and rig targeting the Player. `main.gd._ready()` calls `Player.ensure_input_actions()`, places the player at the spawn point, and calls `rig.snap()`. Esc quits.

- [ ] **Step 1: Run all tests: they pass.**
- [ ] **Step 2: Run the game headless for 120 frames** (`$GODOT --headless --path . --quit-after 120`): no script errors in the output.
- [ ] **Step 3: Capture screenshots** by running the game windowed with a capture flag (`main.gd` saves `user://shot_<n>.png` at frames 60 and 300 while auto-walking when started with `-- --capture`). Inspect the image: ring colors, transparent ceiling over the player, rising ring visible. Tune `ortho_size` if needed.
- [ ] **Step 4: Write `README.md`** with how to open and run the project, the controls, and the tuning knobs.
