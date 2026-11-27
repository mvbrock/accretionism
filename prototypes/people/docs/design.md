# People Prototype: Design

## Intent

Find out whether a **big cast of passengers feels alive**. Passengers board and leave ships across the Earth–Moon–Mars network from `prototypes/transit`, change their plans, and get caught up in medical events and ship malfunctions. The player only watches: they sort, filter, and read each passenger's story.

"Alive" comes from causes you can follow. Every change to a passenger's plans names its cause, the cause is written into that passenger's history, and relationships carry events from one person to another. A spouse re-routes with their partner, and a friend stays aboard with someone who is sick. A destination that changes for no visible reason is noise, and noise is what this prototype must avoid.

## Goals

- A cast of about 300 passengers, each with a journey made of real legs on transit's ships and bodies.
- A table with one row per passenger: **Name | ID# | Origin | Current location | Final destination | Progress**.
- Clicking a row opens a detail panel on the right with the passenger's attributes, journey, relationships and history.
- A daily event simulation: embark, disembark, change of mind, medical event, ship malfunction, follow a relation, new arrivals.
- Ships keep transit's rules: cyclers keep their timetable, and a transport in flight keeps its destination. Events change passengers' plans, never a ship's course.

## Non-goals

- No player actions on passengers or ships. It is watch only: no approving, refusing, triggering events, or dispatching.
- No diagram view, and no dispatch panel.
- No save/load, art or audio.
- No economy, ticket prices, or ship interiors. Console's life-support model is not used.
- No shared code with transit. This prototype has its own copy of transit's core.

## Anti-goals

- Events that fire without a cause shown anywhere.
- Relationships that are only listed in the panel and never affect what anyone does.
- A table that empties out, or freezes, over a long run.

## Decisions

| Topic | Decision |
|---|---|
| Tech | Godot 4.7, GDScript, in `prototypes/people`, set up the same way as the other prototypes |
| World | A copy of transit's simulation core: orbits, cyclers, transport intercept, sim clock, units. Transit's diagram and dispatch UI are not copied |
| Player | Watch only |
| Malfunctions | The ship keeps its course. Only passengers' plans change |
| Rescues | Use existing transports only. The dispatcher aims to keep one or two docked to every cycler |
| Progress | Measured by time (see Progress) |
| Cast size | About 300 active passengers, set in the data file |

## World

Bodies, cyclers and transports behave exactly as in `prototypes/transit/docs/design.md`. The one addition is a **dispatcher** that flies the transports, because nobody else does.

### Dispatcher

Transports run fixed services, assigned in the data file:

| Service | What it does |
|---|---|
| **Shuttle** (Earth ↔ Moon) | Flies a local leg back and forth, waiting a fixed turnaround time (data file) at each end |
| **Tender** (one planet) | Ferries passengers between its planet and cyclers. It leaves the planet so that it docks with the next cycler due to fly past, stays docked through the flyby, and then flies back to the planet |
| **Express** (Earth ↔ Mars) | Flies directly between Earth and Mars, waiting a fixed turnaround at each end. These are few and small (see Capacity), so most travellers still ride cyclers |

All bodies and cyclers follow predictable paths, so the dispatcher can work out each service's trips, with exact departure and arrival times, ahead of time. It publishes a **schedule** of every ship trip, cycler legs included, covering a fixed window ahead of now. The default window is 800 days (data file): longer than one 780-day cycler cycle, so any trip a cycler can make has its tender connections in the schedule. As the clock moves forward, it adds trips to the end. Route planning reads the schedule, and so does the detail panel when it shows a journey.

### Standby and rescues

The dispatcher aims to keep **at least one transport, ideally two, docked to every cycler** at all times as standby for emergencies. These are ordinary transports from the 30. Nothing special is added. How the dispatcher manages that, such as which transports stand by, how they rotate, and whether a tender doubles as standby through a flyby, is part of the dispatcher's design.

A **rescue** happens when someone aboard a cycler mid-leg has to leave before the next flyby: a SERIOUS medical event, a CRITICAL patient whose stable period has ended, or a life-support fault. A docked standby transport undocks and flies them to the nearest body with a hospital (for a medical case) or the nearest body (for a life-support fault), judged by soonest arrival. People who don't fit in its seats wait for the next rescue trip. With no standby docked, the dispatcher may send any idle transport to intercept the cycler. A change of mind never triggers a rescue: it waits for the next flyby. History entries name the ship: "Evacuated from Aldrin V by Petrel".

A rescue changes a transport's plans, never a cycler's course. A transport already in flight still keeps its destination.

### Fleet split

Choosing how many transports run each service is left to the builder, as is the exact timing rule for tenders. The tender rule must make each flyby's tender meet its cycler and come back. All 30 transports split between shuttles, tenders, expresses and standby, and the split must keep every route served while meeting the standby aim as often as it can. The data file sets the split.

### Capacity

Every ship has a seat count: cyclers 400, shuttles and tenders 20, expresses 8 (data file). A passenger books seats on every leg when their route is planned, and can't plan onto a full leg. Seats are what keep the cyclers in use, since a transport is far faster. Seats also make re-routes compete with each other, which adds texture: "re-routed via Aldrin II; express full".

### Places with care

Earth, the Moon and Mars have hospitals. Cyclers have an infirmary, which can stabilize a patient but not treat them. Transports have no care.

## Passengers

```
Passenger
  id: String             # "P-00001", unique, never reused
  name: String           # given name + family name
  age: int
  birthplace: String     # e.g. "Tycho Base, Luna", from a list in the data file
  occupation: String
  note: String           # one line of flavor, e.g. "Collects pressed flowers"
  reason: WORK | EMIGRATION | VISIT | MEDICAL | RETURNING
  conditions: [Condition]
  relationships: [Relationship]
  origin: place          # where the journey started; never changes
  destination: place     # final destination; changes on re-route
  journey_start: day
  route: [Leg]           # booked legs; done legs stay for the panel
  location: AtBody(body) | Aboard(ship)
  state: TRAVELLING | HELD | ARRIVED
  history: [Entry]       # day, text, cause

Condition: name, severity (MANAGED | SERIOUS | CRITICAL), daily flare chance
Relationship: other passenger id, kind (SPOUSE | PARENT | CHILD | SIBLING | FRIEND | COLLEAGUE)
Leg: ship, board place, board day, leave place, leave day
```

A **place** is Earth, the Moon or Mars. A journey always starts and ends at a body. Cyclers and transports appear only as legs.

A leg's board and leave places are where the change of ship happens: a body, or a cycler that a transport is docked to. For example, `Tern: Aldrin III → Mars` is a tender ride from a cycler down to Mars. A cycler never stops, so its **stops** are its flybys with a tender docked. A passenger gets on or off a cycler only by a tender, and that takes a tender seat.

### Attributes that drive events

- **Conditions:** cause medical events (see Events).
- **Relationships:** carry events to other people (see Follow).
- **Reason for travel:** sets the daily chance of a change of mind. An emigrant rarely changes plans and a visitor changes them most often. The rates are in the data file.
- **Age:** raises the chance of a flare-up. Any passenger under 16 travels with a parent and is always re-routed with them.

Birthplace, occupation and the note are flavor only.

### Generating the cast

From a seed (data file), the same seed always building the same cast:
- **Households first:** a single traveller, a couple, or a family of 3–5 sharing a family name. A household travels together on one route.
- **Then links between households:** friends and colleagues. A colleague link is made only between two passengers with reason WORK.
- Names, birthplaces, occupations, notes and condition types come from lists in the data file.
- The starting cast comes from a **warm-up run**. The sim starts 400 sim days before day 0 (data file) with an empty cast, runs turnover and events at full speed, and shows the result at day 0. Every passenger on screen then has a real history with real causes, and the cast is naturally spread through their journeys.

### Turnover

New households appear at each body at a steady rate (data file) that keeps the active cast near its target size. Each new arrival is a planned journey to another body. A passenger who reaches their final destination becomes ARRIVED. They stay in the table for 10 sim days (data file), shown as arrived, and then leave it. Their relations keep the link, which shows as "(arrived)".

## Route planning

A route is the chain of booked legs that reaches the destination soonest, read from the schedule, using only legs with a free seat. A transfer happens only at a place where both ships are present at the same time: a body, or a cycler that a transport is docked to. The minimum connection time is 6 hours (data file).

- A household plans and books as one group, so every seat must be free for all of them.
- When no route reaches the destination inside the schedule window, the passenger is HELD at their current place with the history entry "no route available; waiting". They try again each day.
- Re-planning starts from where the passenger is now. A passenger who is aboard a ship mid-leg has to stay on until that ship's next stop.
- **Forced exits.** Some events force a passenger off at the next stop: a life-support fault, a serious medical event, or a docking failure ending. When the stop is a flyby and every tender there is full, the passenger stays aboard to the next flyby that has a free tender seat. The history entry says so: "Tenders full at Mars; staying aboard Aldrin II".

## Events

Each sim day, the sim runs these in order. Every event that changes a passenger writes a history entry, with its cause, to everyone it touches.

| Event | Trigger | Effect |
|---|---|---|
| **Embark** | A booked leg's board time arrives | The passenger boards. Location becomes that ship |
| **Disembark** | A booked leg's leave time arrives | The passenger gets off at that place, transferring to the next leg or arriving |
| **Change of mind** | Daily chance, set by reason | A new destination, picked from the other bodies, then re-planned. Entry: "Changed plans: heading to Mars instead" |
| **Medical event** | Daily flare chance per condition, scaled up with age | See Medical events |
| **Ship malfunction** | Daily chance per ship | See Malfunctions |
| **Follow** | A relation re-routes | See Follow |
| **New arrivals** | Turnover rate | New households join the table |

Embark and disembark happen at exact times within the day, as the schedule gives them, so a fast clock never skips one. The other events roll once per sim day, and each rate is a per-day chance in the data file.

### Medical events

A flare-up of a condition at:
- **MANAGED** severity: a history entry only, like "Mild flare-up; managed aboard".
- **SERIOUS** severity: the passenger re-routes to the nearest place with a hospital, judged by soonest arrival. They get off at the next stop to do it. If the condition is untreated, the severity can rise on a later flare-up.
- **CRITICAL** severity: the passenger can't be moved. They are HELD aboard and ride past their stops for a stable period (data file, 5–20 days). When it ends, they re-route to the nearest hospital. On a cycler the entry says "stabilized in the infirmary".

Arriving at a hospital with a serious or critical condition lowers its severity one step after a stay set in the data file. The passenger then plans a route back to their previous destination.

### Malfunctions

A malfunction strikes one ship and affects everyone aboard. It never changes the ship's course.

| Kind | Effect on passengers |
|---|---|
| **Docking failure** | Nobody can board or leave at the ship's next stop. Passengers due off there stay aboard to the stop after it, and re-plan from there. Passengers due to board there re-plan |
| **Life-support fault** | Everyone aboard gets off at the next stop and re-plans, even if it isn't on their route |
| **Seat loss** | Part of the seats are lost for a time (data file). Future boardings over the new limit are dropped, newest booking first, and those passengers re-plan. Nobody already aboard loses their seat |

Malfunctions are rolled per ship each day. Each kind has its own chance and duration in the data file. Entries name the ship, like "Docking failure on Aldrin IV; staying aboard past Mars".

### Follow

When a passenger re-routes for any reason:
- Their **spouse** and **children** (and, for a child, their parent) always re-route with them, to the same destination, as one group.
- Each **sibling** and **friend** on the same ship or at the same place has a chance (data file) to follow.
- Each **colleague** on the same ship or at the same place has a smaller chance to follow.
- A sibling, friend or colleague who follows plans their own route to the same destination: they aren't booked as a group with the leader. They then **accompany** the leader until the leader arrives, and re-route with the leader each time the leader re-routes, for example from the hospital back to the original destination. While accompanying, their history entries name the leader.

A follower's history entry names the cause and the person: "Re-routed to Luna with Dana Okafor (spouse), after her cardiac event". Following is never chained: someone who follows does not pull in their own relations, which stops one event from sweeping through the whole cast.

A passenger who doesn't follow gets an entry too, "Dana Okafor re-routed to Luna; continuing to Mars", so the panel shows the bonds that held as well as the ones that pulled.

## Progress

Progress is time based: `(now − journey_start) ÷ (expected arrival − journey_start)`. The expected arrival is the leave time of the last booked leg. Transit's format applies: rounded down to two decimal places, so 100.00% shows only on arrival.

A re-route keeps `journey_start` and changes the expected arrival, so progress can jump backwards. That's intended: it is how a setback shows in the table. A HELD passenger with no route shows "-".

## Screen

The window has three parts:
- a **clock bar** along the top, copied from transit: pause/play, speed steps of 1 h, 1 d and 10 d per real second, and the sim date
- the **passenger table**, filling the left
- the **detail panel** on the right, showing the selected passenger, or "Select a passenger" when none is selected

Text sizes match transit: 19 px, with the panel's name at 26 px.

### Table

| Column | Shows |
|---|---|
| Name | Given name + family name |
| ID# | `P-00417` |
| Origin | The body the journey started at |
| Current location | A body name, or the ship's name while aboard |
| Final destination | The current destination, or "Arrived" |
| Progress | Percentage with two decimals; "-" while HELD with no route |

- Clicking a column header sorts by that column, and clicking again reverses the order.
- A filter box above the table matches any text in a row.
- The selected passenger stays selected and in view while the table re-sorts or refreshes.
- When an event touches a passenger, their row is highlighted for a few seconds, so changes can be seen happening in the table.
- The table refreshes every frame while the clock runs.

### Detail panel

```
DANA OKAFOR                       P-00417
54 · born Tycho Base, Luna
Engineer · traveling for work
"Collects pressed flowers"

JOURNEY   Earth → Mars          41.20%
  ✓ Kestrel     Earth → Aldrin III   d180–d181
  ▸ Aldrin III  Aldrin III → Mars    d181–d327
  · Tern        Aldrin III → Mars    d327–d328

HEALTH
  Heart condition (serious)

RELATIONSHIPS
  Sam Okafor     spouse     ▸
  Iris Vale      colleague  ▸

HISTORY  (newest first)
  d212  Cardiac event; re-routed to Luna for treatment
  d180  Boarded Kestrel at Earth
```

- Journey legs are marked done (✓), current (▸) or still to come (·).
- Clicking a relationship selects that passenger, and the table scrolls to them.
- The history is complete and scrolls.

## Data

`data/people.json` holds:
- the seed, the bodies' epoch angles and the cycler timetable (as in transit)
- the cyclers and transports, each transport with its service
- seat counts
- the cast target, turnover rate and arrived linger time
- every event rate and duration
- the name, birthplace, occupation, note and condition lists

## Code structure

Following transit:
- **Simulation core** (`scripts/`): plain GDScript classes with no nodes. Holds:
  - transit's copied core
  - the dispatcher and schedule
  - the passengers and cast generation
  - route planning
  - the event system
  - a table model that formats rows

  Event rolls take a seeded random generator, so a run can be replayed and tested.
- **UI** (`scripts/ui/`): a thin layer for the clock bar, the table and the detail panel. It reads the core and never changes it.
- **Tests**: headless, with transit's runner pattern. They cover:
  - each service's trips meeting their targets
  - the schedule extending as the clock moves
  - route planning: soonest arrival, full legs skipped, the connection time, a household booked together, HELD when no route exists
  - each event's effect and history entry
  - follow rules, including no chaining and children always following
  - malfunction kinds
  - progress, including jumping back on a re-route
  - turnover keeping the cast near its target
  - forced exits waiting for a tender seat
  - rescues: a standby transport taking the right people to the right body, and the overflow waiting
  - how often each cycler goes without a standby ship
  - the warm-up leaving the cast near its target
  - the same seed always giving the same run
  - row formatting

## Left to the builder

- How many transports run each service, and the tender timing rule (within the rules under Dispatcher).
- Starting values for every rate, kept in the data file. The aim is a handful of non-routine events per sim day across the cast, so that at 1 d/s something visibly happens every second or two.
- Name and flavor lists.
- The highlight color and how long it lasts.
- Column widths and the panel's width.
