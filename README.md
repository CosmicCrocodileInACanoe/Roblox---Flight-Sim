# Open Skies (working title): Roblox passenger flight simulator

Milestone 1 vertical slice: one original narrow-body twin jet (Meridian 200), a physics-driven
flight model, two airports linked by a ~25 km route, two cities, component damage with detachment
and debris, a HUD, a menu, missions with landing grades, and reset.

Everything here is original. No code, models, textures, sounds or names came from FableFlight
or any other game (see `CREDITS.md`).

## Status in one paragraph

The project builds with Rojo, and every source file compiles with `luau-compile`. The
engine-independent logic has 50 automated tests, all passing: aero, engines, gear, damage,
grading, missions, airport geometry, terrain and 13 offline 6-DOF flights through the same
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
luau tests/run.luau
```

Expected: `50 passed, 0 failed`. These tests do not start Roblox.

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
| T | Toggle Assisted / Simulation |
| C | Camera: chase / cockpit / tower |
| Right mouse drag, wheel | Look around, camera distance |
| H | Hide HUD |
| N | Show / hide the minimap |
| F3 | Debug panel |
| M | Menu (aircraft, mode, spawn, weather, time, failures) |
| R | Reset / respawn |

A typical first flight: spawn at an HBR runway threshold, press I and wait for the engines,
set flaps 2 (press F twice), hold Shift for full throttle, pull back gently at about 145 kt,
press G after a positive climb, then press V to bring the flaps up above 180 kt.

## Layout

```
default.project.json      Rojo tree, Workspace gravity (35.02 = 9.81 m/s^2 at 0.28 m/stud)
src/shared/               Pure Luau, used by the server, the client and the tests
  Units, MathUtil         scale (1 stud = 0.28 m), ISA atmosphere, heading helpers
  Aero, Engine, Gear      lift/drag per panel, spool and lapse, raycast spring-dampers
  FlightModel             6-DOF forces and torques for one aircraft (the core of the game)
  Assist                  Assisted mode: auto-trim, turn coordination, bank and stall protection
  Damage                  component health, states, propagation, detachment
  Grading, Mission        landing score, gate-to-gate mission state machine
  Airports, WorldGen      airport layouts, deterministic terrain height field
  GameConfig, AircraftRegistry, Aircraft/Meridian200
src/server/               spawn, ownership, damage validation, debris, missions, saves, world build
src/client/               input, flight controller, cameras, HUD, menu, weather and effects
tests/                    test runner, 6-DOF harness, five suites
docs/PLAN.md              architecture, schemas, boundaries, decisions, risks, roadmap
docs/PLAYTEST.md          manual Studio checklist
```

## Known limits of this milestone

- One aircraft. The registry and builder are generic, but only the Meridian 200 has data.
- No audio. Engine and wind sound need original or licensed assets.
- Weather and time of day are chosen per player, so two players can see different wind.
- StreamingEnabled is off so terrain can't vanish under a fast aircraft. The server logs the
  world part count at start (`[World] built N parts`); terrain alone is up to about 15,000
  wedges. Check frame rate on low-end devices before adding more scenery.
- Visual models are blocky placeholders built from parts.
- The Roblox API calls are untyped and unverified in Studio (see `docs/PLAYTEST.md`).
