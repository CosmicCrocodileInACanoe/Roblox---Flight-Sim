# Open Skies (working title): Roblox passenger flight simulator

Milestone 1 vertical slice: one original narrow-body twin jet (Meridian 200), a physics-driven
flight model, two airports linked by a ~25 km route, two cities, component damage with detachment
and debris, a HUD, a menu, missions with landing grades, and reset.

Everything here is original. No code, models, textures, sounds or names came from FableFlight
or any other game (see `CREDITS.md`).

## Status in one paragraph

The project builds with Rojo, and every source file compiles with `luau-compile`. The
engine-independent logic has 420 automated tests, all passing: aero, engines, gear, damage,
grading, missions, audio mixing, airport geometry, terrain and offline 6-DOF flights for every aircraft (take-off, landing, stall, cruise, Easy mode) through the same
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

Expected: `199 passed, 0 failed`. These tests do not start Roblox. (`run.sh` embeds the builder source for the builder tests, then runs `luau tests/run.luau`.)

## Controls

| Key | Action |
| --- | --- |
| W / S | Pitch down / up |
| A / D | Roll left / right |
| Q / E | Rudder and nose-wheel steering |
| Shift / Ctrl | Throttle up / down |
| I | Start / stop engines |
| G | Landing gear |
| F / V | Flaps down / up |
| B | Wheel brakes (hold) |
| P | Parking brake |
| Z | Reverse thrust (hold, on the ground) |
| X | Speedbrake |
| [ / ] | Pitch trim (Simulation mode) |
| T | Cycle Easy (default) / Assisted / Simulation |
| U | Show / hide the on-screen buttons (throttle lever, stick, gear, flaps, brakes...) |
| C | Camera: chase / cockpit / tower |
| Right mouse drag, wheel | Look around, camera distance |
| H | Hide HUD |
| N | Show / hide the minimap |
| F3 | Debug panel |
| M | Menu (aircraft, airport, mode, route, start point, weather, time, failures) |
| R | Reset / respawn |

A typical first flight: spawn at an HBR runway threshold, press I and wait for the engines,
set flaps 2 (press F twice), hold Shift for full throttle, pull back gently at about 145 kt,
press G after a positive climb, then press V to bring the flaps up above 180 kt.

## Sound

All audio is set up in `src/shared/AudioConfig.luau`. Each slot has an `id`; paste a Creator
Store audio asset ID there (just the number) and it plays. Empty slots stay silent and never
error. What each slot does:

- Engines: `jetWhine` (pitch and volume follow N1) and `jetRumble` (follows thrust and
  reverse). Propeller aircraft use `propDrone` and `propRumble` instead (each config's `soundProfile`,
  with `AudioConfig.aircraftProfile` as a fallback).
  `engineStart` plays once when you start the engines.
- `wind` grows with airspeed, louder with gear down or speedbrake out; `runwayRoll` rumbles
  with ground speed while the wheels are down.
- `gearMotor`, `flapMotor` loop while they move; `gearLock` clunks when the gear locks.
- `touchdown` thump (louder on hard landings), `tyreSqueal` above 40 kt.
- `impactLight`, `impactHeavy` for hits and parts breaking off, `crash` when the aircraft is destroyed.
- `stallWarning`, `gearWarning` (gear not down below 1,000 ft with low throttle or landing flaps).

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
                          tougher airframe) and Assisted mode (auto-trim, turn coordination, protections)
  Damage                  component health, states, propagation, detachment, lost sections
  Crash                   crash feel: per-component profiles, dents, break points, debris breakup
  Grading, Mission        landing score, gate-to-gate mission state machine
  Airports, WorldGen      airport layouts, deterministic terrain height field
  Selection               what the menu offers and the server accepts: aircraft, airport, starts, routes
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

### Planes stay in one piece by default

`GameConfig.crash.breakApart = false` (the default). A wrecked component stays attached
and collapses instead of falling off: wings and tailplanes droop from the root, the fin
leans over, gear folds up under the plane, and a wrecked centre fuselage breaks its back,
so the nose and tail sag. Outer wing sections and stabiliser tips tear off only on hits
twice as hard as normal (`extremeSectionFactor`). A whole component comes off only in a
truly extreme hit: `Damage.EXTREME_FACTOR` (2.2) times its destroy speed, which is a
50 m/s (about 100 kt) smash into something solid for a wing. Set `breakApart = true` to
get the old behaviour back, where parts detach as soon as their health runs out.

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

Sixteen original, unbranded aircraft, smallest to largest (the menu shows them in this order).
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
| Meridian 200 | Narrow-body twin jet | |
| Hauler 4 | Cargo freighter | four turboprops, T-tail, upswept tail with a ramp |
| Atlas 400 | Wide-body twin jet | |
| Arrowstar | Supersonic-style airliner | delta wing, needle nose, four engines; the fastest |
| Celestia 800 | Four-engine jumbo | |

Adding one is a data file in `src/shared/Aircraft/` plus a line in `AircraftRegistry`. The
builder reads everything from the config's `geometry` block (see the header of
`src/server/AircraftBuilder.luau`), and `cfg.assist` can set per-aircraft Easy-mode limits.

## Known limits of this milestone

- Sound ships with empty asset IDs, so the game is silent until they're filled in (see Sound).
- Weather and time of day are chosen per player, so two players can see different wind.
- StreamingEnabled is off so terrain can't vanish under a fast aircraft. The server logs the
  world part count at start (`[World] built N parts`); terrain alone is up to about 15,000
  wedges. Check frame rate on low-end devices before adding more scenery.
- Visual models are blocky placeholders built from parts.
- The Roblox API calls are untyped and unverified in Studio (see `docs/PLAYTEST.md`).
