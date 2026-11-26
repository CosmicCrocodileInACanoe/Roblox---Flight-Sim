# Open Skies (working title): Roblox passenger flight simulator

Milestone 1 vertical slice: one original narrow-body twin jet (Meridian 200), a physics-driven
flight model, two airports linked by a ~25 km route, two cities, component damage with detachment
and debris, a HUD, a menu, missions with landing grades, and reset.

Everything here is original. No code, models, textures, sounds or names came from FableFlight
or any other game (see `CREDITS.md`).

## Status in one paragraph

The project builds with Rojo, and every source file compiles with `luau-compile`. The
engine-independent logic has 649 automated tests, all passing: aero, engines, gear, damage,
grading, missions, audio mixing, airport geometry, terrain and offline 6-DOF flights for every aircraft (take-off, landing, stall, cruise, Easy and Free modes, rudder handling) through the same
`FlightModel` the game runs. **None of it has been run in Roblox Studio yet.** Anything that
touches the engine (parts, welds, Motor6Ds, network ownership, GUIs, cameras, DataStores,
collisions) is unverified until someone works through `docs/PLAYTEST.md` in Studio.
I couldn't type-check against the Roblox API either, because the typedefs download was blocked
in my build environment.

## Requirements

- Roblox Studio
- [Rojo](https://rojo.space) 7.4.x: the CLI plus the Studio plugin
- Optional: the [Luau CLI](https://github.com/luau-lang/luau/releases) (`luau`) for the offline tests

## Run it

Option A: open the prebuilt place.

```
rojo build default.project.json -o build/OpenSkies.rbxlx
```

Open `build/OpenSkies.rbxlx` in Studio and press Play. The server builds the world on start,
which takes a few seconds; the menu says so while it waits.

Option B: live sync while editing.

```
rojo serve default.project.json
```

In Studio, open an empty Baseplate, delete the Baseplate part, click Connect in the Rojo
plugin, then Play. Workspace and Lighting properties come from `default.project.json`.

For saving progress in Studio, publish the place and turn on
Game Settings → Security → "Enable Studio Access to API Services". Without it the game still
runs, but progress is not saved; `ProgressService` logs a warning and carries on.

## Offline tests

From the repo root:

```
sh tests/run.sh
```

Expected: `649 passed, 0 failed`. These tests do not start Roblox. (`run.sh` embeds the builder source for the builder tests, then runs `luau tests/run.luau`.)

## Controls

| Key | Action |
| --- | --- |
| W / S | Pitch down / up |
| A / D | Roll left / right |
| Q / E | Rudder and nose-wheel steering (in the air: a steady yaw that eases back when released) |
| Shift / Ctrl | Throttle up / down |
| I | Start / stop engines |
| G | Landing gear |
| F / V | Flaps down / up |
| B | Wheel brakes (hold) |
| P | Parking brake |
| Z | Reverse thrust (hold, on the ground) |
| 3 | Autoland on / off (any aircraft) |
| L | Drop water (hold; Rainmaker water bomber only) |
| 1 | Refill the water tank right away (Rainmaker) |
| 2 | Auto refill: fly to the sea, scoop, take off and climb out (Rainmaker) |
| X | Speedbrake |
| [ / ] | Pitch trim (Simulation mode) |
| T | Cycle Easy (default) / Free / Assisted / Simulation |
| U | Show / hide the on-screen buttons (throttle lever, stick, gear, flaps, brakes...) |
| C | Camera: chase / cockpit / tower |
| Right mouse drag, wheel | Look around (re-centres after 10 s), camera distance |
| H | Hide HUD |
| O | Background music on / off |
| N | Show / hide the minimap |
| J | Failures and weather events menu (also the red **Events** button, top right) |
| F3 | Debug panel |
| M | Menu (aircraft, airport, mode, route, start point, weather, time, failures) |
| R | Reset / respawn |

A typical first flight: spawn at an HBR runway threshold, press I and wait for the engines,
set flaps 2 (press F twice), hold Shift for full throttle, pull back gently at about 145 kt,
press G after a positive climb, then press V to bring the flaps up above 180 kt.

## Failures and weather events

Press **J**, or click the red **! Events** button in the top-right row, to open the
FAILURES & WEATHER menu. It works in every mode, at any time in flight. Hover a button to
see what it does.

Failures break things right now, through the same damage model as a crash, so torn-off
parts fall away as real debris and the aircraft flies differently:

| Button | What happens |
| --- | --- |
| Engine fire | One engine catches fire (flames and smoke), shuts down and can't be restarted |
| Engine falls off | One engine tears off its pylon: no thrust on that side, and lighter |
| Wing snaps | The outer part of one wing breaks away: a strong roll toward that side |
| Tail damage | Part of the fin or tailplane breaks off: weaker pitch and yaw |
| Controls jam | Ailerons, elevator or rudder stick where they are |
| Hydraulics | Gear and flaps stop moving |
| Fuel leak | Fuel drains fast |
| Gear collapse | One landing-gear leg folds |
| Random failure | Any of the above that can still happen |

Weather and hazards:

| Button | What happens |
| --- | --- |
| Tornado | A funnel touches down about 1.3 km ahead and drifts across your path for 75 s. Its swirl (up to ~145 kt), inflow and updraft act on the flight model's wind; close to the core it spins the airframe and flying debris dents and breaks parts. Fly around it |
| Lightning | A bolt and a flash, a strike on a wing or the tail, and often an engine flameout (press **I** to relight) |
| Bird strike | A flock appears ahead and hits the nose; an engine swallows birds and loses power or fails |
| Strong winds | 45 s of 40-55 kt crosswind with gusts and turbulence, and a downburst halfway through |
| Clear weather | Ends the tornado, winds and birds. Damage stays until you reset with **R** |

Resetting (R) gives you a fresh aircraft and clears every event. R works even after the
aircraft is gone (lost at sea, say). **Fix all** (Y, or the green button top right) repairs
the aircraft in place: torn-off parts go back on, dents, bends and failures disappear and
every part is back to 100%. You keep your position, speed, engines and controls, and the
flight, mission or race carries on. Only a wreck lying still on its side or roof is stood
back up on its wheels.

## Firefighting

Pick the **Rainmaker** water bomber. Four wildfires burn on wooded hills around the map at
once: look for the tall smoke, the orange "WILDFIRE" label (it shows from far away) and the
pulsing orange dots on the minimap.

1. **Scoop.** Fly to the sea (south of Harbor City), gear up, flaps 10 or 15, and touch the
   hull down on the water. Keep it skimming at 50 kt or more and the tank fills in about
   12 seconds (the HUD's WATER bar says SCOOP). Add power, the extra 6 tonnes make it
   heavy, and climb away.
2. **Drop.** Come in low (under about 150 ft is best) and slow over the fire and hold **L**
   (or the DROP WATER button). The tank empties in about 3 seconds. The water carries
   forward as it falls, so let go a little before the fire. Drops from high up mostly blow
   away as mist.
3. About one full load on target puts a fire out (it flares back up slowly if you leave
   it half done). Everyone gets a message when a fire goes out, and a new one starts
   somewhere else a minute or so later.

Parked at an airport, a hose refills the tank too, more slowly. In a hurry, press **1**
(or REFILL WATER) to fill it straight away, or press **2** (AUTO REFILL AT SEA) and the
autopilot flies to the nearest open sea, lands on the hull, scoops a full tank, takes off and
climbs to about 800 ft, then hands back to you. Each wildfire's label shows how far away it
is.

## Emergency services and sinking

After a crash the emergency services come, and everyone in the server sees them:

| What happened | Who comes | What happens to the aircraft |
| --- | --- | --- |
| Crash on land | Police cars, fire trucks and ambulances drive in from the nearest airport or town, park round the wreck with their lights flashing, and the fire trucks spray it | It stays where it is |
| Crash into the sea | Rescue boats sail out, two helicopters circle with searchlights | The wreck floats for about 8 s, then sinks: completely under by 60 s |
| A landplane puts down on the water in one piece | Rescue boats and a ferry; life rafts take the passengers across, and the HUD counts them ("Rescued 120 of 180 passengers"); a helicopter circles | Half under after 20 s, completely under after 60 s; the HUD counts down |

Seaplanes and amphibians (Puffin, Rainmaker) on the water in one piece are fine: nothing
sinks and nobody is called. Wrecked, they sink like anything else.

**Y (Fix all)** works while sinking or sunk: the aircraft comes back up, whole, floating on
the surface, and the crews go home. A landplane fixed out on the sea is still on the sea,
so after a moment it starts to sink again (and the boats come back): fly off or press R.
**R** respawns as usual and the crews go home.

Seaplanes and amphibians can also **start on the water**: pick "On the water" in the menu's
Start at row (one per airport, on the nearest open sea). You float there with the engines
running and the flaps set, ready to take off.

## Autoland

Press **3** (or the AUTOLAND button) in the air with the engines running, in any aircraft.
The autopilot picks the nearest runway end it can reach without a big turn, flies out and
turns in if it has to, follows a 3 degree glide path at the approach speed with the gear and
flaps out, flares, touches down, brakes and reverses to a stop and sets the parking brake.
It goes around and tries again if it isn't lined up close in. Move the stick (or press 3
again) to take over at any time. The HUD shows what it is doing.

## Stunts mode

Pick **Stunts: Ring Race** in the menu's Mode row. You start in the air over Harbor City's
runway 09 end in a tiny aerobatic racer, lined up with a course of 12 neon rings that sit
high and low over the open farmland just east of the airport (all inside a 1 km square).
Fly through them in order from START to FINISH:

- The clock starts at the START ring. The next ring glows green and shows through hills,
  the one after is yellow, and a big arrow (or a circle marker when it is on screen) points
  at the next ring with its distance.
- Missing a ring adds 3 seconds and moves you on to the next one. Touching the ground or
  breaking the plane ends the run.
- The results card shows your time, medal (gold under 0:36, silver under 0:45, bronze under
  1:00), rings hit and your best time (saved with your progress). FLY AGAIN or R restarts
  instantly; M opens the menu.
- Easy assist is tuned for racing in this mode: up to 70 degrees of bank and quicker pulls,
  so the tight turns are possible with the stick held over.
- Racers are ghosts to each other, since everyone starts at the same gate.

The course, race rules and medal times live in `src/shared/Stunts.luau`; the server times
the race (`MissionService`), and `client/StuntsHud.luau` draws it. The offline tests fly the
whole course with the Easy assist and check every ring clears the ground.

## Sound

All audio is set up in `src/shared/AudioConfig.luau`. Every slot ships with starter IDs from
the Creator Store, and a slot can list several candidates. When you start flying, the game
checks them and uses the first one that loads. Output then prints
`[Audio] N sounds loaded`, plus the name of any slot with no working ID. To change a sound,
paste another Creator Store audio ID (just the number) into that slot's `id`. An empty slot
stays silent and never errors.

- Engines: every plane has its own engine sound. There are nine types in
  `AudioConfig.profiles`: airliner turbofan, jumbo (deeper, more rumble), business jet
  (higher whine), fighter (turbojet roar), supersonic (roar, plus an `afterburner` layer
  while the afterburners are lit), turboprop (prop drone with a turbine hum), piston,
  vintage radial and stunt. `AudioConfig.aircraftPitch` gives planes of the same type
  their own pitch. Each layer's pitch and volume follow N1 and thrust. `engineStart`
  plays once when you start the engines.
- `wind` grows with airspeed, louder with gear down or speedbrake out; `runwayRoll` rumbles
  with ground speed while the wheels are down.
- `gearMotor`, `flapMotor` loop while they move; `gearLock` clunks when the gear locks.
- `touchdown` thump (louder on hard landings), `tyreSqueal` above 40 kt.
- `impactLight`, `impactHeavy` for hits and parts breaking off, `crash` when the aircraft is destroyed.
- `stallWarning` (about to stall, and while stalled), `stickShaker` (while stalled), `gearWarning` (gear not down below 1,000 ft with low throttle or landing flaps).
- Voice callouts, like a real ground proximity warning system: `calloutPullUp` ("whoop whoop,
  pull up"), `calloutTerrain`, `calloutSinkRate`, `calloutTooLowGear` and `calloutStall`. They
  repeat while the danger lasts. Terrain ahead is found by a ray along the flight path, and
  sink rate is checked against height. A normal approach with the gear and landing flaps down
  stays quiet. A callout slot without an id is spoken with Roblox text-to-speech
  (`AudioConfig.useTextToSpeech`). If that isn't available, it stays silent.
- Pilot callouts: "eighty knots" and "rotate" on the takeoff roll, and radio-altitude callouts
  on approach (1000, 500, 100, 50, 40, 30, 20, 10).
- `cabinChime` through 10,000 ft, `cockpitAmbience` (avionics hum loop).
- Background ATC chatter, never constant. Exchanges are a call and a reply: some start
  with the controller, some with a pilot. Controllers and pilots use different
  text-to-speech voices, and each callsign keeps its own voice and pitch. After each
  exchange there are a random 5 to 35 s of quiet, and each exchange is cut off at 15 s.
  Most calls are other pilots calling ATC. Roblox limits text-to-speech to about 7 requests a minute, so new exchanges are
  generated slowly (warnings first) and reused. Recorded chatter clips in `atcChatter1..5`
  are mixed in.
- Background music: soft, upbeat tracks from Roblox's licensed music library
  (`AudioConfig.music`), shuffled at low volume. It ducks under warnings, callouts and ATC.
  Press O to turn it on or off.
- Cockpit alarms: GPWS "whoop whoop, pull up" (the whoop is a siren sound, then a spoken
  "pull up" in the warning voice), "bank angle", the stall alarm and stick shaker, a fire bell while an
  engine burns, an overspeed clacker above Vmo, and master warning and caution chimes.
  The warning chime sounds for fire, a part failing or breaking off, and overspeed. The
  caution chime sounds for an engine out, jammed controls, hydraulics, a fuel leak, low
  fuel and damage. The Events menu failures and weather set these off.

In the cockpit view, outside sounds are muffled by an equaliser and warnings are at full
volume. In the tower view, outside sounds fade with distance.

## Layout

```
default.project.json      Rojo tree, Workspace gravity (35.02 = 9.81 m/s^2 at 0.28 m/stud)
src/shared/               Pure Luau, used by the server, the client and the tests
  Units, MathUtil         scale (1 stud = 0.28 m), ISA atmosphere, heading helpers
  Aero, Engine, Gear      lift/drag per panel, spool and lapse, raycast spring-dampers
  FlightModel             6-DOF forces and torques for one aircraft (the core of the game)
  Assist                  Easy mode (self-levelling, pitch/bank limits, no stalls, speed floor, flare help,
                          tougher airframe), Free mode (roll/pitch rate commands, holds bank and pitch,
                          no bank or pitch limits, extra authority) and Assisted mode (auto-trim, turn coordination,
                          protections); Q/E yaw-rate control with a yaw damper in all three
  Damage                  component health, states, propagation, detachment, lost sections
  Crash                   crash feel: per-component profiles, dents, break points, debris breakup
  Grading, Mission        landing score, gate-to-gate mission state machine
  Airports, WorldGen      airport layouts, deterministic terrain height field
  Selection               what the menu offers and the server accepts: aircraft, airport, starts, routes
  Stunts                  Stunts ring course, race rules (passes, misses, penalties, medals), race tune
  Wildfire                fire sites, where dropped water lands, how much reaches a fire
  Autopilot               autoland and the water bomber's auto refill (writes the flight controls)
  GameConfig, AircraftRegistry, Aircraft/*  one data file per aircraft; Aircraft/Kit has shared helpers
  AudioConfig, AudioMix   every sound asset ID in one file; pure loop/one-shot mixing
src/server/               spawn, ownership, damage validation, debris, missions, saves, world build
src/client/               input, flight controller, cameras, HUD, menu, weather, effects, sound
tests/                    test runner, 6-DOF harness, Roblox mock, test suites
docs/PLAN.md              architecture, schemas, boundaries, decisions, risks, roadmap
docs/PLAYTEST.md          manual Studio checklist
```

## Crash physics

Roblox has no soft bodies, so crashes fake one in three layers (`src/shared/Crash.luau` holds
the maths, `src/server/CrashService.luau` applies it, the client adds local shards and sparks):

1. **Dents.** Hard contacts push nearby parts inward along the hit and twist them a little,
   scaled by impact speed, accumulating up to a cap. The server re-welds the moved parts, so
   everyone sees the crumpled shape.
2. **Break points.** Wings lose their outer section, stabilisers their tips and the fin its top
   before the whole component lets go. The aircraft keeps flying, lopsided.
3. **Debris breakup.** Torn pieces keep the aircraft's momentum (v + w x r) and split again
   across their longest axis on hard secondary hits, until their integrity runs out. Total
   pieces stay inside the existing debris caps.

Adding an aircraft needs no crash code. Profiles come from each component's name
(Wing/Engine/Prop/Stab/Fin/Tail/Gear, anything else is fuselage) and break planes from
`geometry.wing/hstab/vstab`. Override any field per component:

```lua
LeftOuterEngine = { ..., crash = { maxDent = 0.5, secondaryBreakDv = 12 } },
UpperDeck = { ..., crash = { sections = { { id = "Hump", normal = { 0, 1, 0 }, offset = 4.5, lost = 0.3 } } } },
LeftWing = { ..., crash = { sections = false } }, -- no break point
```

Tunables shared by all aircraft are in `GameConfig.crash`.

### Breaking apart

`GameConfig.crash.breakApart = true` (the default). Parts dent and bend first. When a
component's health runs out it tears off as debris that keeps its momentum, taking its
children with it: a wing takes its engines and gear. A wrecked centre fuselage breaks the
plane into pieces. Outer wing sections and stabiliser tips can tear off before the whole
wing goes, and debris splits again on hard secondary hits.

Set `breakApart = false` to keep planes in one piece. A wrecked component then stays
attached and collapses instead: wings droop, gear folds and the fuselage sags. Parts come
off only in truly extreme hits, at `Damage.EXTREME_FACTOR` (2.2) times their destroy speed.

### Bending metal (soft-body look)

Two more layers on top, in `src/shared/SoftBody.luau`:

- **Beam bending** (server, everyone sees it). Wings, tailplanes, the fin and the nose and tail
  sections bend like a beam at a hinge just inboard of the hit. The angle builds up over a bend
  zone, so the structure curves instead of snapping. A hit along the beam, like a nose-first
  crash, crushes it like an accordion. Bending adds up to a cap per component, and easy mode
  needs harder hits. This works in every game with no special settings. Override it per
  component with `crash = { bend = { maxBendDeg = 10 } }`, or turn it off with
  `crash = { bend = false }`.
- **Mesh skins** (each client, uses EditableMesh). A dented part is swapped, on screen only,
  for a subdivided mesh of the same shape (box, wedge, cylinder or ellipsoid, 150 vertices).
  Vertices near the hit are pushed in, so panels bow and crease. EditableMesh doesn't
  replicate, so the server broadcasts each dent (`DentFx`) and every client deforms its own
  copy. Collisions still use the original parts. At most 6 skins live per client, and the
  oldest goes back to a plain part when a new one is needed.
  **Turn this on** in Studio under Game Settings > Security > "Allow Mesh / Image APIs". For
  the published game, use Creator Dashboard > Configure > Settings > "Enable Mesh / Image
  APIs". With it off, skins switch themselves off after one warning in the output, and part
  dents and bending carry on.

## Aircraft

Seventeen original, unbranded aircraft, smallest to largest (the menu shows them in this order).
All of them pass the same offline flight tests.

| Aircraft | Type | Notes |
|---|---|---|
| Bumble | Vintage biplane | two wings with struts and wires, open cockpit behind a small windscreen |
| Meadowlark 4 | Four-seat trainer | high wing with struts, fixed gear with wheel spats; the default and the gentlest |
| Sprite | Aerobatic stunt plane | rolls very fast; Easy mode still levels it when you let go |
| Ridgehopper | STOL bush plane | giant soft tyres, big flaps, takes off in about 200 m |
| Puffin | Floatplane (amphibian) | lands and takes off on the sea, wheels in the floats for runways |
| Breeze Twin | Light twin | two wing-mounted propellers |
| Silverline 8 | Business jet | engines on the rear fuselage, T-tail, winglets |
| Swiftlet J3 | Jet trainer | tandem two-seat canopy, side intakes |
| Vector X1 | Light fighter | chin intake, bubble canopy with HUD |
| Nightjar T2 | Twin-engine fighter | two canted fins, two nozzles |
| Kestrel 72 | Regional turboprop | |
| Rainmaker | Firefighting flying boat (amphibian) | boat hull, wingtip floats, wheels for runways; scoops 6 t of water from the sea and drops it on wildfires |
| Meridian 200 | Narrow-body twin jet | |
| Hauler 4 | Cargo freighter | four turboprops, T-tail, upswept tail with a ramp |
| Atlas 400 | Four-engine jumbo | upper-deck hump |
| Arrowstar | Supersonic-style airliner | delta wing, needle nose, four engines with afterburners (full throttle, gear up); passes Mach 2 above about 1,200 ft, held near Mach 1 right down low. The HUD shows the Mach number |
| Celestia 800 | Double-deck superjumbo | four engines, the biggest wing in the game |

Adding one is a data file in `src/shared/Aircraft/` plus a line in `AircraftRegistry`. The
builder reads everything from the config's `geometry` block (see the header of
`src/server/AircraftBuilder.luau`), and `cfg.assist` can set per-aircraft Easy-mode limits.

## Known limits of this milestone

- Sound uses starter Creator Store IDs; any that fail to load stay silent and are named in Output (see Sound).
- Weather and time of day are chosen per player, so two players can see different wind.
- StreamingEnabled is off so terrain can't vanish under a fast aircraft. The server logs the
  world part count at start (`[World] built N parts`); terrain alone is up to about 15,000
  wedges. Check frame rate on low-end devices before adding more scenery.
- Visual models are blocky placeholders built from parts.
- The Roblox API calls are untyped and unverified in Studio (see `docs/PLAYTEST.md`).
