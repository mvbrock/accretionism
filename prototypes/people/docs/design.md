# People Prototype: Design

## Intent

Find out whether a **big cast of passengers feels alive**. Passengers board and leave ships across the Earth–Moon–Mars network from `prototypes/transit`, change their plans, and get caught up in medical emergencies and ship malfunctions. The player only watches: they sort, filter, and read each passenger's story.

"Alive" comes from causes you can follow. Every change to a passenger's plans names its cause, and the cause is written into that passenger's history. People who travel together re-route together, so one person's emergency shows up in several histories. Relationships give the cast depth in the detail panel. A destination that changes for no visible reason is noise, and noise is what this prototype must avoid.

## Goals

- A cast of 300 passengers, each with a journey made of real legs on transit's ships and bodies.
- A table with one row per passenger: **Name | ID# | Origin | Current location | Final destination | Progress**.
- Clicking a row opens a detail panel on the right with the passenger's attributes, journey, travel party, relationships and history.
- A daily event simulation: embark, disembark, change of mind, medical emergency, ship malfunction, new journey.
- Ships keep transit's rules: cyclers keep their timetable, and a transport in flight keeps its destination. Events change passengers' plans, never a ship's course.

## Non-goals

- No player actions on passengers or ships. It is watch only: no approving, refusing, triggering events, or dispatching.
- No diagram view, and no dispatch panel.
- No save/load, art or audio.
- No economy, ticket prices, or ship interiors. Console's life-support model is not used.
- No shared code with transit. This prototype has its own copy of transit's core.
- No data files. The cast, the fleet and every setting live in scripts.
- Relationships don't drive logistics. Travel parties set who travels with whom.

## Anti-goals

- Events that fire without a cause shown anywhere.
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
| Cast | 300 passengers, written out in `scripts/cast.gd` |
| Settings | Every tunable is a constant in `scripts/config.gd`. No data files |
| Travel parties | Passengers who travel together are routed together. Relationships are shown in the panel only |
| Emergencies | SERIOUS or CRITICAL only |

## World

Bodies, cyclers and transports behave exactly as in `prototypes/transit/docs/design.md`. The one addition is a **dispatcher** that flies the transports, because nobody else does.

### Dispatcher

Transports run fixed services, assigned in `config.gd`:

| Service | What it does |
|---|---|
| **Shuttle** (Earth ↔ Moon) | Flies a local leg back and forth, waiting a fixed turnaround time at each end |
| **Tender** (one planet) | Ferries passengers between its planet and cyclers. It leaves the planet so that it docks with the next cycler due to fly past, stays docked through the flyby, and then flies back to the planet |
| **Express** (Earth ↔ Mars) | Flies directly between Earth and Mars, waiting a fixed turnaround at each end. These are few and small (see Capacity), so most travellers still ride cyclers |
| **Standby** (one cycler) | Stays docked to a cycler for emergencies (see Standby and rescues) |

All bodies and cyclers follow predictable paths, so the dispatcher can work out each service's trips, with exact departure and arrival times, ahead of time. It publishes a **schedule** of every ship trip, cycler legs included, covering a window of 800 days ahead of now. That is longer than one 780-day cycler cycle, so any trip a cycler can make has its tender connections in the schedule. As the clock moves forward, the dispatcher adds trips to the end. Route planning reads the schedule, and so does the detail panel when it shows a journey.

### Standby and rescues

The dispatcher aims to keep **at least one transport, ideally two, docked to every cycler** at all times as standby for emergencies. These are ordinary transports from the 30. Nothing special is added. How the dispatcher manages that, such as which transports stand by, how they rotate, and whether a tender doubles as standby through a flyby, is part of the dispatcher's design.

A **rescue** happens when a party aboard a cycler mid-leg has to leave before the next flyby: a SERIOUS emergency, a CRITICAL patient whose stable period has ended, or a life-support fault. A docked standby transport undocks and flies them to the nearest body with a hospital (for an emergency) or the nearest body (for a life-support fault), judged by soonest arrival. Parties that don't fit in its seats wait for the next rescue trip. A party is never split. With no standby docked, the dispatcher may send any idle transport to intercept the cycler. A change of mind never triggers a rescue: it waits for the next flyby. History entries name the ship: "Evacuated from Aldrin V by Petrel".

A rescue changes a transport's plans, never a cycler's course. A transport already in flight still keeps its destination.

### Fleet split

Choosing how many transports run each service is left to the builder, as is the exact timing rule for tenders. The tender rule must make each flyby's tender meet its cycler and come back. All 30 transports split between shuttles, tenders, expresses and standby. The split must keep every route served and meet the standby aim as often as it can. `config.gd` sets the split.

### Capacity

Every ship has a seat count: cyclers 400, shuttles and tenders 20, expresses 8. A party books seats on every leg when its route is planned, and can't plan onto a leg without seats for all its members. Seats are what keep the cyclers in use, since a transport is far faster. Seats also make re-routes compete with each other, which adds texture: "Re-routed via Aldrin II; express full".

### Places with care

Earth, the Moon and Mars have hospitals. Cyclers have an infirmary, which can stabilize a patient but not treat them. Transports have no care.

## Passengers

```
Passenger
  id: String             # "P-00001", unique
  name: String           # given name + family name
  age: int
  birthplace: String     # e.g. "Tycho Base, Luna"
  occupation: String
  note: String           # one line of flavor, e.g. "Collects pressed flowers"
  reason: WORK | EMIGRATION | VISIT | MEDICAL | RETURNING
  party: Party           # who they travel with
  conditions: [Condition]
  relationships: [Relationship]   # shown in the panel only
  location: AtBody(body) | Aboard(ship)
  history: [Entry]       # day, text, cause

Party
  members: [Passenger]   # one passenger travelling alone is a party of one
  origin: place          # where the journey started
  destination: place     # final destination; changes on re-route
  journey_start: day
  route: [Leg]           # booked legs; done legs stay for the panel
  state: TRAVELLING | HELD | ARRIVED

Condition: name, daily emergency chance
Relationship: other passenger id, kind (SPOUSE | PARENT | CHILD | SIBLING | FRIEND | COLLEAGUE)
Leg: ship, board place, board day, leave place, leave day
```

Origin, destination, journey start, route and state belong to the **party**, so every member of a party always shows the same ones. Each member keeps their own attributes, conditions, relationships and history.

A **place** is Earth, the Moon or Mars. A journey always starts and ends at a body. Cyclers and transports appear only as legs.

A leg's board and leave places are where the change of ship happens: a body, or a cycler that a transport is docked to. For example, `Tern: Aldrin III → Mars` is a tender ride from a cycler down to Mars. A cycler never stops, so its **stops** are its flybys with a tender docked. A passenger gets on or off a cycler only by a tender, and that takes a tender seat.

### Attributes that drive events

- **Party:** everyone in a party is planned, booked, moved and re-routed together. Whatever happens to one member happens to the whole party.
- **Conditions:** cause medical emergencies (see Events).
- **Reason for travel:** sets the daily chance of a change of mind. An emigrant rarely changes plans and a visitor changes them most often. A party's chance comes from its members' reasons. How they combine, for example by taking the highest, is the builder's call.
- **Age:** raises the chance of an emergency, and of that emergency being CRITICAL.

Relationships, birthplace, occupation and the note are flavor only: they're shown in the panel and never change what happens.

### The cast script

`scripts/cast.gd` holds all 300 passengers, written out as constants, together with the parties and relationships:
- **Parties:** a passenger travelling alone, a couple, or a family of 3–5. Any passenger under 16 is in a party with a parent.
- **Relationships:** spouse, parent, child, sibling, friend or colleague. They may link people in different parties.
- **Each party's first journey:** a starting body, a destination and a start day between day −400 and day 0.

How the 300 get written, whether by hand or by a throwaway generator whose output is pasted in, is up to the builder. The script is the source of truth, and nothing is generated at run time.

### Warm-up

The sim starts at day −400 with every party waiting at its starting body. It runs at full speed to day 0, with each party setting off on its start day, and the screen opens at day 0. Every passenger on screen then has a real history with real causes, and the cast is spread through their journeys.

### New journeys

The cast stays at 300. A party that reaches its final destination becomes ARRIVED and shows as arrived for 10 sim days. It then plans a new journey from where it is to another body, and its members' histories carry on: "d512 Set off for the Moon". The table never empties, and nobody is added or removed.

## Route planning

A route is the chain of booked legs that reaches the destination soonest, read from the schedule, using only legs with seats for the whole party. A transfer happens only at a place where both ships are present at the same time: a body, or a cycler that a transport is docked to. The minimum connection time is 6 hours.

- A party plans and books as one group.
- When no route reaches the destination inside the schedule window, the party is HELD at its current place with the history entry "No route available; waiting". It tries again each day.
- Re-planning starts from where the party is now. A party aboard a ship mid-leg has to stay on until that ship's next stop, unless it is rescued.
- **Forced exits.** Some events force a party off at the next stop: a life-support fault, a SERIOUS emergency, or the end of a docking failure. When the stop is a flyby and no tender there has seats for the whole party, the party stays aboard to the next flyby that has room. The history entry says so: "Tenders full at Mars; staying aboard Aldrin II".

## Events

Each sim day, the sim runs these in order. Every event that changes a party writes a history entry, with its cause, to every member.

| Event | Trigger | Effect |
|---|---|---|
| **Embark** | A booked leg's board time arrives | The party boards. Location becomes that ship |
| **Disembark** | A booked leg's leave time arrives | The party gets off at that place, transferring to the next leg or arriving |
| **Change of mind** | Daily chance, set by the party's reasons | A new destination, picked from the other bodies, then re-planned. Entry: "Changed plans: heading to Mars instead" |
| **Medical emergency** | Daily chance per condition, scaled up with age | See Medical emergencies |
| **Ship malfunction** | Daily chance per ship | See Malfunctions |
| **New journey** | 10 days after a party arrives | See New journeys |

Embark and disembark happen at exact times within the day, as the schedule gives them, so a fast clock never skips one. The other events roll once per sim day, and each rate is a per-day chance in `config.gd`.

### Medical emergencies

Every emergency is either SERIOUS or CRITICAL. There are no minor ones. When a condition causes one, its severity is rolled, with CRITICAL more likely at higher ages. The whole party is affected:
- **SERIOUS:** the party re-routes to the nearest place with a hospital, judged by soonest arrival. It gets off at the next stop to do it, or is rescued if it is on a cycler mid-leg.
- **CRITICAL:** the patient can't be moved. The party is HELD aboard and rides past its stops for a stable period of 5–20 days. When that ends, it re-routes to the nearest hospital. On a cycler the entry says "stabilized in the infirmary".

After a hospital stay (its length is set in `config.gd`), the party plans a route back to its previous destination. The patient's entry names the condition: "Cardiac event; re-routed to Luna for treatment". The other members' entries name the patient: "Re-routed to Luna: Dana Okafor's cardiac event".

### Malfunctions

A malfunction strikes one ship and affects everyone aboard. It never changes the ship's course.

| Kind | Effect on passengers |
|---|---|
| **Docking failure** | Nobody can board or leave at the ship's next stop. Parties due off there stay aboard to the stop after it, and re-plan from there. Parties due to board there re-plan |
| **Life-support fault** | Every party aboard gets off at the next stop and re-plans, even if that stop isn't on its route |

Malfunctions are rolled per ship each day. Each kind has its own chance in `config.gd`. Entries name the ship, like "Docking failure on Aldrin IV; staying aboard past Mars".

## Progress

Progress is time based: `(now − journey_start) ÷ (expected arrival − journey_start)`. The expected arrival is the leave time of the party's last booked leg. Transit's format applies: rounded down to two decimal places, so 100.00% shows only on arrival.

A re-route keeps `journey_start` and changes the expected arrival, so progress can jump backwards. That's intended: it is how a setback shows in the table. A HELD party with no route shows "-".

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

TRAVELLING WITH
  Sam Okafor                ▸
  Ada Okafor                ▸

HEALTH
  Heart condition

RELATIONSHIPS
  Sam Okafor     spouse     ▸
  Iris Vale      colleague  ▸

HISTORY  (newest first)
  d212  Cardiac event; re-routed to Luna for treatment
  d180  Boarded Kestrel at Earth
```

- Journey legs are marked done (✓), current (▸) or still to come (·).
- Clicking a party member or a relationship selects that passenger, and the table scrolls to them.
- The history is complete and scrolls.

## Settings and cast

There are no data files.
- `scripts/config.gd` holds every tunable as a constant:
  - the seed, the bodies' epoch angles and the cycler timetable (as in transit)
  - the cyclers and transports, each transport with its service
  - seat counts, the schedule window and the connection time
  - every event rate and duration, the hospital stay, and the arrived linger time
- `scripts/cast.gd` holds the 300 passengers, their parties and relationships, and each party's first journey.

## Code structure

Following transit:
- **Simulation core** (`scripts/`): plain GDScript classes with no nodes. Holds:
  - transit's copied core
  - the dispatcher and schedule
  - the passengers and parties, loaded from `cast.gd`
  - route planning
  - the event system
  - a table model that formats rows

  Event rolls take a seeded random generator, so a run can be replayed and tested.
- **UI** (`scripts/ui/`): a thin layer for the clock bar, the table and the detail panel. It reads the core and never changes it.
- **Tests**: headless, with transit's runner pattern. They cover:
  - each service's trips meeting their targets
  - the schedule extending as the clock moves
  - route planning: soonest arrival, full legs skipped, the connection time, a party booked together, HELD when no route exists
  - each event's effect, and its history entry for every member of the party
  - medical emergencies: only SERIOUS and CRITICAL, the stable period, and the trip back after hospital
  - malfunction kinds
  - forced exits waiting for a tender with room
  - rescues: a standby transport taking the right parties to the right body, the overflow waiting, and no party split
  - how often each cycler goes without a standby ship
  - progress, including jumping back on a re-route
  - new journeys after arrival, with the cast staying at 300
  - the cast script: unique ids, every relationship pointing at a real passenger, every child in a party with a parent
  - the warm-up spreading parties through their journeys by day 0
  - the same seed always giving the same run
  - row formatting

## Left to the builder

- How many transports run each service, and the tender timing rule (within the rules under Dispatcher).
- Starting values for every rate, kept in `config.gd`. The aim is a handful of non-routine events per sim day across the cast, so that at 1 d/s something visibly happens every second or two.
- The cast itself: names, ages, parties, relationships and flavor.
- How a party's reasons combine into one change-of-mind chance.
- The highlight color and how long it lasts.
- Column widths and the panel's width.
