# Architecture and plan

## 1. Goals for Milestone 1

One original narrow-body jet that flies on physical forces alone, two complete airports and
two cities on a real route, component damage with detachment, a HUD, a menu, missions, grades
and reset. The flight model has to be testable without Studio, so it is pure Luau.

## 2. Units and conventions

- 1 stud = 0.28 m, so `Workspace.Gravity = 9.81 / 0.28 = 35.0238` studs/s². A 36 m jet is
  about 128 studs long.
- All physics is SI (m, kg, N, s, rad). Conversion happens only at the engine boundary in
  `FlightController`.
- Body axes: x right, y up, z aft (the nose points to -Z, like Roblox `LookVector`).
  +ωx is nose up, +ωy is yaw left, +ωz is roll left. Bank angle is positive right wing down.
- Heading 0 is -Z (north) and 90 is +X (east).

## 3. Flight physics

The **client that owns the aircraft** computes forces every `RunService.PreSimulation` and
writes them into one world-space `VectorForce` (ApplyAtCenterOfMass) and one `Torque` on an
invisible Core part. Roblox's solver integrates them. There is no `LinearVelocity`, no
`AlignOrientation`, no anchoring and no tweening in flight.

- **Mass:** the Core part's box size is derived from the configured inertia tensor, so its
  Roblox inertia has the right proportions. Every visible part is Massless. Forces are scaled by
  `kF = AssemblyMass / (mass_kg * 0.28)`, and torques by `kT = coreMass / (mass_kg * 0.28²)`,
  so Roblox's assembly mass only has to be roughly right.
- **Aero:** strip theory over panels (wing halves, tailplane halves, fin, fuselage). Each panel
  sees local velocity `v + ω × r` plus wind, so roll damping, weathervaning and asymmetric
  damage come out naturally. Lift runs perpendicular to the local flow and drag along it.
  Lift is linear below stall. Past stall it blends by smoothstep into flat-plate behaviour
  (`Cl = 1.15 sin 2α`, `Cd = 1.9 sin² α`), so a stall is recoverable rather than a cliff.
  Flaps add Cl0, Cd0 and a stall-angle change per notch. Ground effect reduces induced drag
  and adds up to 8% lift below one wingspan. Control surfaces scale with dynamic pressure, so
  authority fades as speed drops.
- **Engines:** first-order spool lag, thrust lapse with density and speed, a start sequence,
  reverse thrust on the ground only, fuel burn and failures. Engine thrust is applied at the
  engine's position, so losing an engine yaws the aircraft.
- **Gear:** a raycast spring-damper per wheel. Spring rate comes from the static compression
  and damping ratio. There's rolling friction, braking, nose-wheel steering and a lateral tyre
  force. Wheels don't collide; the fuselage, wings and engines are collidable hull parts, so a
  gear-up landing scrapes on the body.
- **Assisted mode** (`Assist.luau`) shapes the pilot's inputs only. It doesn't add forces:
  auto-trim, turn coordination, bank protection (soft at 33°, hard at 60°), soft stall
  protection and auto ground spoilers. Simulation mode passes inputs through raw.

## 4. Damage

`Damage.luau` keeps a health value (0 to 1) and a state (normal, degraded, failed,
detached) for each component: forward and aft fuselage, wings, tailplane, fin, engines and
gear. The sources are:

- Impact: an unexpected Δv at the component's own contact point, localised with `Touched`.
  Damage grows as `((Δv − threshold) / (destroy − threshold))^1.5`.
- Scraping wear, per second of sliding contact.
- Gear sink rate at touchdown: fine at 400 fpm, degraded at 750, failed at 1100, collapsed
  above that.
- Over-g on the airframe.

A quarter of the health actually removed from a component spreads to its parent. Detaching a
component takes its children with it (a wing takes its engine and main gear). If the main
Fuselage fails, the aircraft breaks up. Damage reduces each panel's effectiveness, so a
damaged left wing makes less lift and the aircraft rolls left.

## 5. Client and server boundaries

| Concern | Client (owner) | Server |
| --- | --- | --- |
| Flight forces | Computes and applies | Never; it watches the speed and position |
| Damage | Detects and reports `ReportDamage` | Checks plausibility against observed speed, then applies |
| Detaching | Asks | Makes a debris Model, enforces budgets |
| Systems (gear, flaps, lights) | Reports `ReportSystems` | Mirrors them as `Sys_*` attributes for other clients |
| Missions and grades | Shows them | Computes them from server-sampled telemetry (10 Hz) |
| Touchdown rate | Reports it | Uses it only if within 250 fpm of its own estimate |
| Progress | None | DataStore, versioned, with retries |

Server checks: spawns are only accepted once `WorldReady` is set and with valid options; every
remote is rate-limited; an impossible speed or a teleport resets the aircraft. Debris is
capped at 24 parts per player and 80 in total, and lives 75 s. Collision groups are
`Aircraft`, `AircraftProtected` (8 s after spawning, aircraft don't collide with each other)
and `Debris`.

## 6. Data schemas

- **Aircraft config** (`Aircraft/Meridian200.luau`): mass and inertia, speeds (vr, vref,
  vmo), panels with area, position, incidence and polar, control surfaces, flaps per notch,
  engines, gear units (position, static compression, damping, retract angle), damage
  components (parent, mass, thresholds, reference point), hull points and the visual build.
- **Airport layout** (`Airports.luau`): runway centre, heading, length and width, idents,
  field elevation, terminal side, gate count. Derived values: thresholds, the glide path,
  gates, and spawn points of kinds gate, runway, approach and air.
- **Mission:** origin, destination, phase (preflight → taxi → takeoff → climb → cruise →
  approach → landing → rollout → taxiToGate → complete, or failed), touchdown record and grade.
- **Saved progress:** `{ version, flights, landings, bestLanding, totalScore }` per user,
  with a migration hook for later schema versions.

## 7. The world

- Terrain is a low-poly triangle mesh of WedgeParts built from a deterministic height field
  (`WorldGen`). The same function tells the tests and the client how high the ground is.
  The land covers x ±130,500 and z −99,000 to +69,000 studs (about 73 × 47 km). The core
  around both airports (x ±64,500, z ±33,000, about 36 × 18 km) uses a 1,500-stud grid; the
  outer ring uses 3,000-stud cells fanned from their centre, and the two grids share heights
  on the seam so there are no cracks. Triangles too big for one wedge pair split in four.
- The land runs down into the sea on every side, and an opaque sea surface made of 25
  mesh-scaled tiles carries on to the horizon (about 410 km across), so the map ends at a
  coast. Atmosphere density is 0.1 on clear days so mountains and skylines show 20+ km out.
- The outer ring has a northern range, eastern highlands and western fells for horizon
  silhouettes, plus three towns: Pinecrest (north), Lakeview (east), Westhaven (west).
- Airports and cities are flattened. Beyond each runway end the terrain is kept below a 2.5%
  surface, so a 3° final has real clearance over the hills.
- **Harbor City International (HBR):** runway 09/27, 3,000 m, on the coast, 6 gates.
- **Ridgeview Regional (RDV):** runway 08/26, 2,600 m, on a plateau about 180 m higher,
  5 gates.
- Harbor City is a metro with a tall spire; Ridgeview is a town. There's a highway, suburbs
  and forests (capped at 3,500 trees).
- **Detail LOD.** Scenery comes in two layers. Building boxes, crowns, the spire, streets,
  parks and highway surfaces are always drawn. Windows, plots, roof units, awnings, houses,
  trees and road dashes are filed into 4,000-stud tile Models in
  `ReplicatedStorage.WorldDetail`; `DetailStreamer` on each client moves tiles within about
  2.5 km of the camera into `Workspace.World.Detail` and back out past about 3 km.

**Streaming trade-off.** StreamingEnabled is off. With streaming on, a jet at 250 kt covers a
streaming radius in seconds, and the directive forbids missing ground under a fast aircraft.
The world is built to be cheap instead: big flat cells, few parts. When the world grows,
streaming should come back with persistent models for airports and approach corridors, plus
`RequestStreamAroundAsync` ahead of the aircraft.

## 8. Decisions

- Client-owned physics with server validation, so control feels immediate and other players
  still see smooth replication.
- Pure-Luau core shared with the tests, so the flight model is tested before Studio.
- One VectorForce and one Torque per aircraft rather than one per panel, which keeps part and
  constraint counts down.
- Part-built placeholder visuals and a parametric builder, so new aircraft are data rather
  than new code.

## 9. Risks

1. Roblox's real inertia for the Core box may differ from what I expect. Watch for sluggish
   or twitchy rotation; `kT` and the box derivation are where to look.
2. Network ownership handover could cause a jolt on spawn. The aircraft stays anchored until
   the client says it's ready.
3. `Touched` for impact location can be noisy or missing at high speed. When no contact is
   reported, the hardest hit is blamed on the leading side, which needs checking in Studio.
4. Performance on mobile with about 15,000 terrain parts is unmeasured.
5. The damage thresholds were tuned offline and may feel too soft or too harsh in play.

## 10. Roadmap

- **M1 (this):** the vertical slice above. Next it needs a Studio playtest pass and fixes.
- **M2:** sound, a real tutorial, AI ground traffic, visual polish of the jet, mobile and
  gamepad controls, streaming with persistent airport models.
- **M3:** the remaining five aircraft classes (light single, turboprop, regional jet,
  wide-body, cargo) and the class differences the directive asks for.
- **M4:** more airports and cities, ATC-style mission flow, passengers, economy.
- **M5:** performance and scalability pass on real hardware, then live-ops.
