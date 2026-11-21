# Transit Prototype: Design

## Intent

Prove a **logistics view** of an Earth–Moon–Mars fleet: which ship is where, where it is headed, how far along its trip it is, and roughly how long a trip takes. Orbital mechanics is only there to give believable distances and travel times. It is not the thing being tested.

## Goals

- Simulate Earth, the Moon and Mars on 2D orbits, plus a fleet of named ships, on a clock the player can pause and speed up.
- Show the fleet in two views, switched with tabs:
  - a **table**: Ship | Origin | Progress | Destination
  - a **diagram**: Earth and the Moon on the left, Mars on the right, cyclers shuttling between them, and a line for each transport's trip
- Let the player send a transport to any valid destination and see its estimated travel time before it leaves.
- Aldrin cyclers shuttle between Earth and Mars forever. Transports can dock with them and ride along.

## Non-goals

No to-scale map of orbits (the diagram is a schematic, not a map). No fuel, delta-v, cargo, crew, launch windows, gravity, collisions, avoiding the Sun, save/load, art or audio. Any of these can come later.

## Decisions

| Topic | Decision |
|---|---|
| Tech | Godot 4.7, GDScript, in `prototypes/transit` (same setup as `prototypes/ship`) |
| Ship classes | Aldrin cycler, transport. Every ship has a unique name |
| Model | Logistical. Ships fly straight lines at a constant speed; 2D orbits supply the distances |
| Speeds | Transports 50 km/s, measured in the Sun's frame. Earth ↔ Moon trips are 5 km/s, measured in Earth's frame. Each cycler leg has a fixed duration close to a real Aldrin leg, and its speed follows from that. Cyclers are always slower than 50 km/s, so a transport can always catch one |
| Table | Ship, Origin, Progress (% of the trip done), Destination |
| Parked or docked | Progress and Destination show "-" |
| Views | A table and a diagram, on separate tabs |
| Diagram | Earth (blue circle) and the Moon (white circle) on the left, Mars (red circle) on the right. Cyclers are squares, transports are triangles. Lines are solid for the part of the trip done and dotted for the part still to go. Overlapping lines are kept to a minimum |
| Cyclers | No destination; they shuttle Earth ↔ Mars forever |
| Transports | Travel to Earth, Moon, Mars or a cycler |
| Docking | A transport can dock only with a cycler, never with another transport |
| Starting fleet | 6 cyclers and 30 transports with random origins, some of them docked to cyclers |

## World model

All motion happens in one plane, with the Sun at the origin. A body's position is a pure function of sim time, so any moment, past or future, can be computed directly without stepping through the ones before it. Internal units are **km** and **days**.

| Body | Orbits | Radius | Period |
|---|---|---|---|
| Earth | Sun, circular | 1.000 AU (149,597,871 km) | 365.256 d |
| Mars | Sun, circular | 1.524 AU | 686.98 d |
| Moon | Earth, circular | 384,400 km | 27.32 d |

Each body has a starting angle at epoch (sim day 0), set in the data file.

## Moving at constant speed

Every leg is a straight line flown at constant speed. Transports and cyclers decide where and when they arrive in different ways:
- **Transports** fly at a fixed speed. The arrival time comes from the intercept below.
- **Cyclers** keep to a fixed timetable. Each leg's speed comes from it (see Cyclers).

### Transport intercept

A transport leaves from a **departure point** at time `t0`, heading for a target whose future position is known. The **intercept** is the earliest `t` where

```
|target(t0 + t) − departure point| = speed × t
```

The sim searches forward in coarse steps up to a horizon (2 years), then refines with bisection. The transport flies the straight line from the departure point to the intercept point and arrives at `t0 + t`. Its position in between is a straight-line interpolation by time.

- Every possible target (a planet, the Moon, a cycler) follows a fully predictable path, so the intercept worked out at departure is exact. The sim never has to steer mid-flight or re-estimate.
- The fastest target is the Moon, at about 31 km/s in the Sun's frame. Transports fly at 50 km/s, so an intercept always exists. The horizon only guards against bugs. If the search ever fails, departure is refused with the message *unreachable*.
- **Local legs.** Earth's 30 km/s drift through the Sun's frame would make Earth → Moon (about 5 h) and Moon → Earth (about 1.4 h) very unequal, so Earth ↔ Moon trips use Earth's frame instead. A **local leg** is one that leaves Earth or the Moon for the other of the two. A ship on a local leg that is redirected to Earth or the Moon stays on a local leg. Every other leg is flown in the Sun's frame at 50 km/s.
  - A local leg is solved and flown relative to Earth: every position is an offset from Earth's position that day, and the ship flies at 5 km/s through those offsets. The Moon moves about 1 km/s relative to Earth, slower than the ship, so the intercept is still unique.
  - Both directions take about 384,400 km ÷ 5 km/s ≈ 21 h. Progress and leg length use the leg's own speed.
- Because arrival times are worked out exactly, a fast clock can't skip past an arrival.

| Trip | Estimate |
|---|---|
| Transport, Earth → Moon | about 21 h |
| Transport, Moon → Earth | about 21 h |
| Transport, Earth → Mars | about 21 d at the closest (Mars moves sideways during the trip); longer as the planets separate |
| Cycler, short leg | 146 d always |
| Cycler, long leg | 634 d always |

Straight lines may pass through the Sun's position. The model allows that.

## Ships

```
Ship
  name: String          # unique; a duplicate name fails setup with an error
  ship_class: CYCLER | TRANSPORT

Cycler
  direction: UP (Earth → Mars short leg) | DOWN (Mars → Earth short leg)
  phase: day of its first short-leg departure, within one cycle

Transport
  location: one of
    AtBody(body)        # Earth, Moon or Mars; position follows the body
    DockedTo(cycler)    # position follows the cycler
    InTransit(leg)      # origin name, departure point, t0, target, intercept point, t_arrive
```

### Cyclers

A cycler is an automated ship that never stops. It runs on a timetable that mimics a real Aldrin cycler:

- **The cycle lasts 780 days**, about one Earth–Mars synodic period. It has a **short leg of 146 days** (about 5 months, like a real Aldrin transfer) and a **long leg of 634 days** back. All three numbers are in the data file.
- An **UP** cycler flies Earth → Mars on its short leg. A **DOWN** cycler flies Mars → Earth on its short leg. Each one returns on its long leg.
- **Every leg is a straight line** from the planet's position at the leg's start to the planet's position at the leg's end, flown at the constant speed that takes exactly the leg's duration. A planet's position is known for any day, so every flyby meets its planet exactly, wherever the planets happen to be.
- **The six cyclers are spread evenly through the cycle,** one every 130 days, alternating UP and DOWN. The UP cyclers start their short legs on days 0, 260 and 520 of the cycle; the DOWN cyclers on days 130, 390 and 650. Their phases are in the data file.
- **The synodic period is faked.** A real cycler can make its short trip only when Earth and Mars are lined up for it, once every 26 months. The timetable ignores how the planets are lined up, which is what lets six cyclers spread through one cycle.
- **Speeds come from the timetable.** A short leg spans 0.5–2.5 AU in a straight line, so it runs at about 6–30 km/s. A long leg runs at about 1.5–7 km/s. Both are well under a transport's 50 km/s.
- Cyclers can't be stopped or redirected. Because the timetable fixes every flyby date, the sim can say where any cycler is on any day, past or future, without stepping through time. That is what the transport intercept needs.

### Transports

- A transport can be sent to Earth, the Moon, Mars, or any cycler. It can't target the place it is already at or docked to.
- It can leave from a body, from the cycler it's docked to (the departure point is the cycler's current position), or mid-flight, which redirects it. A redirected trip keeps its original origin. The new leg starts from the ship's current position.
- On arrival a transport becomes `AtBody` or `DockedTo`. Any number of transports can dock with one cycler. A docked transport rides through the cycler's flybys until it is sent somewhere.

## Screen

The window has three parts:
- a **clock bar** along the top
- a **tab area**: Table and Diagram
- a **dispatch panel** at the side

All text is 19 px (20% above Godot's default of 16), and the dispatch panel's ship name is 26 px.

The clock bar and dispatch panel stay on screen in both tabs. Switching tabs keeps the selected ship selected. Clicking a row in the table, or a shape in the diagram, selects that ship.

## Table view

36 rows: the cyclers first, then the transports, in data-file order. The table refreshes every frame while the clock runs.

| Ship's state | Origin | Progress | Destination |
|---|---|---|---|
| Transport at a body | the body | - | - |
| Transport docked | cycler's name | - | - |
| Transport in flight | where the trip started | % of the trip done | target's name |
| Cycler | planet it last flew past | % of the current leg done | - |

**Progress** is `distance flown ÷ trip length`, rounded down to a whole percent, so 100% shows only on arrival. For a redirected trip, the distance flown before the redirect counts toward both numbers:

```
progress = (flown before redirect + flown on new leg) ÷ (flown before redirect + new leg length)
```

A redirect to a farther target can make progress go down.

## Diagram view

The diagram is a schematic. It draws trips and how far along they are, not where ships are in space. The only sim values it uses are each ship's state, origin, destination and progress, so it never reads an orbital position.

### Layout

```
  ( Moon )
       \
        \
 ( EARTH ) ═══ cycler lanes ═══ ( MARS )
```

- **Earth:** a blue circle, centered vertically on the left side.
- **Moon:** a smaller white circle above and to the left of Earth. Earth–Moon trips then sit outside the Earth–Mars corridor.
- **Mars:** a red circle, centered vertically on the right side.
- **Background:** dark, so the white Moon shows up.
- **Labels:** each body is always labeled. A ship shows its name when hovered or selected.

### Cyclers

- **Lanes:** each cycler has its own lane, a gently curved line from Earth's edge to Mars's edge. The six lanes are stacked in the middle band and fan into each planet at different points, so no two lanes meet.
- **The square:** a cycler is drawn as a square on its lane. How far it is across the lane is its progress on the current leg. On an Earth → Mars leg it moves left to right, and on a Mars → Earth leg it moves right to left.
- **Lane line:** solid from the planet it last passed to the square, and dotted from the square to the next planet.
- **Lane order:** fixed by phase, so a lane never changes position.

### Transports

- **Parked at a body:** the triangle sits in a ring around that body's circle, spaced evenly. No line is drawn.
- **Docked to a cycler:** the triangle sits in a small row just above the cycler's square and moves with it. No line is drawn.
- **In flight:**
  - A curve runs from the origin's node to the destination's node, where a node is a body circle or a cycler square.
  - The triangle sits on the curve at its progress fraction and points toward the destination.
  - The curve is solid from the origin to the triangle and dotted from the triangle onward.
  - When an end of the curve is a cycler, it follows the square as it moves.

### Keeping lines from overlapping

The layout follows fixed rules, worked out every frame by a pure function, so each line stays put and doesn't jump between frames:

1. **Body-to-body trips stay out of the cycler band.** Trips toward Mars arc above the band, and trips toward Earth or the Moon arc below it. Traffic in each direction keeps to its own side.
2. **Trips on the same route nest.** When several transports share an origin, a destination and a direction, each one gets its own arc, a step further from the band than the one before. Order is by departure time, so an arc moves only when a trip inside it ends.
3. **Earth–Moon trips are short arcs on the left.** Trips toward the Moon bow to one side and trips back to Earth bow to the other.
4. **Trips to and from cyclers are straight lines** between the body and the square. They cross only the lanes between that body and the cycler's own lane. Every square is on a lane, so this can't be avoided entirely.
5. **Lines end at different points around a node.** When several lines meet one circle, they start or end at points spread around its edge, ordered by the direction each line leaves in. They don't all converge on the center.

The rules minimize overlaps without eliminating them. A crossing can happen only under rule 4, or between trips headed in opposite directions to a cycler.

### Colors and shapes

Cycler squares are 14.4 px wide and transport triangles 12 px long. A click within 14.4 px of a ship selects it.

| Thing | Shape | Color |
|---|---|---|
| Earth | circle | blue |
| Moon | small circle | white |
| Mars | circle | red |
| Cycler | square | amber |
| Transport | triangle | light gray |
| Selected ship | its usual shape | highlighted outline, and its line drawn on top |

## Controls

- **Clock:** pause/play, speed steps of 1 h, 1 d and 10 d per real second, and the current sim date.
- **Dispatch:** select a transport (in either view), pick a destination from the valid targets, and see *"Est. travel time: 31 d 4 h"* before pressing **Depart**. Selecting a cycler row shows no dispatch controls.

## Starting fleet

The data file holds:
- the seed for random setup, so the same seed always builds the same fleet
- the bodies' angles at epoch
- the cycler timetable (cycle, short-leg and long-leg lengths)
- the names of 6 cyclers, each with its direction and phase, and 30 transports, each name unique
- each transport's origin, either set by hand or left as `random`. A random origin is picked evenly from Earth, Moon, Mars and the six cyclers, so about two thirds of the transports start docked to a cycler

All transports start parked or docked. None start in flight.

## Code structure

- **Simulation core**: plain GDScript classes, no nodes. It holds orbits, the intercept solver, cycler legs, transports and the clock. Everything that can be tested lives here.
- **Diagram layout**: a pure function from the fleet's state to shapes and curves in screen space. It holds no nodes and is tested headless.
- **UI**: a thin layer of scenes for the clock bar, the tabs, the table, the diagram and the dispatch panel. The diagram is a `Node2D` that draws the layout's output with `_draw()`. The UI reads the core's state and sends commands to it.
- **Tests**: headless, with the same runner pattern as `prototypes/ship/tests`. They cover:
  - orbit positions and periods
  - intercept times against cases solved by hand
  - cyclers meeting each planet exactly, and keeping to their 146/634-day legs, over many cycles
  - six cyclers spaced 130 days apart, alternating UP and DOWN
  - transport arrival and docking
  - docked ships moving with their cycler
  - refused targets (another transport, the current location)
  - redirect progress
  - formatting of every row state
  - building the same fleet from the same seed
  - the diagram layout:
    - nested arcs on the same route never coincide
    - trips to Mars sit above the band and trips to Earth below it
    - the triangle sits at its progress fraction
    - the split between solid and dotted falls at the triangle
    - parked and docked transports get no line
    - the same fleet state always gives the same layout
