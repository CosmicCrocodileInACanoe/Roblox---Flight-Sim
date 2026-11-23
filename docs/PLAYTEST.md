# Studio playtest checklist (Milestone 1)

Nothing below has been run yet. Tick each item in Studio, and write down what you saw when an
item fails. Turn on the debug panel with F3 for numbers (IAS, AoA, forces, gear loads).
When an item asks for numbers, record them; don't estimate.

Setup: build the place (`rojo build default.project.json -o build/OpenSkies.rbxlx`), open it,
and press Play. Watch the Output window throughout. Any red error is a fail.

## A. Engine-level checks (things the offline tests can't see)

These are the most likely places for first-run bugs, so check them first.

- [ ] Output shows `[World] built N parts (terrain …, scenery …)` within about 20 s and no
      errors. Write down N and the time.
- [ ] Terrain triangles meet without visible gaps or flipped faces (WedgePart orientation).
- [ ] Runway numbers, signs and gate labels read the right way round and aren't mirrored
      (SurfaceGui and Decal faces).
- [ ] PAPI lights show two white and two red on a 3° final, and turn all red when low.
- [ ] The windsock points downwind and droops in calm weather.
- [ ] The jet spawns on its wheels: no bounce, no sink into the ground, no spin.
- [ ] The character sits in the cockpit seat (`Seat:Sit`), and the character can't be knocked out of it.
- [ ] Network ownership: in a Server view during play, the aircraft is owned by the player
      (Studio: Model > Physics > "Show Network Owner").
- [ ] Control surfaces move the right way: W lowers the elevator trailing edge, D raises the
      right aileron, E moves the rudder right. Gear and flaps animate and end in the right
      place (Motor6D hinge signs).
- [ ] The engine fans spin when the engines run.
- [ ] HUD: the attitude indicator's horizon tilts the right way in a bank (CanvasGroup
      clipping), and speed, altitude, heading and vertical speed tapes all update.
- [ ] Menu: every dropdown works; the Fly button spawns an aircraft; M toggles the menu
      while parked and while flying.
- [ ] Sound with every ID empty: no errors or `[Audio]` warnings in Output. With IDs filled
      in: the engine whine rises and falls with throttle, wind grows with speed, the gear horn
      sounds low with the gear up, touchdown thumps, cockpit view sounds muffled, and nothing
      keeps playing after Reset or returning to the menu.
- [ ] Reset (R) respawns cleanly, with no leftover aircraft and no error.
- [ ] Progress: with API services on, fly one landing, leave, rejoin; the Flights and Best
      Landing leaderstats are kept. With API services off, there's a warning and no error.

## B. The 12 mandatory playtests from the directive

1. **Full flight, no rails.** Spawn at an HBR gate. Start the engines, taxi to runway 09,
   take off, climb, turn, cruise to RDV, descend, flare, land, brake and park at a gate.
   Pass if nothing teleports, snaps or moves on rails.
2. **Novice takeoff and landing.** Someone new tries the README's "first flight" steps in
   Assisted mode and then lands from the "4 nm final" spawn. Record how many tries it took.
3. **Stall.** At 5,000 ft, idle the engines and hold full back stick in Simulation mode
   (T). Record the stall speed and angle of attack from the debug panel. Release the stick and add
   power: the aircraft recovers. In Assisted mode, stall protection should soften this.
4. **Flaps, gear, throttle, wind, mass.** Compare liftoff speed and roll with flaps 1 and
   flaps 3; feel the drag from the gear and speedbrake; take off in "Crosswind 15 kt"; and
   compare roll with fuel full and nearly empty. Record what you see.
5. **The fleet (16 aircraft).** For each aircraft in the menu:
   - It spawns on the runway sitting level on its wheels, with no parts floating or buried.
   - Glass looks like glass from outside (tinted, a little shiny), and from the cockpit view
     the windscreen or canopy is see-through but still faintly visible.
   - Jet engines: the intake and spinning fan face forward, the nozzle and cone face back.
     Propellers spin with the throttle.
   - Fighters, trainer and stunt plane: the canopy shows a pilot; fighters have a HUD glass.
   - Bumble: both wings, struts and wires are attached and move together when damaged.
   - Puffin: it floats on the sea, takes off from the water and lands back on it.
   - Hauler 4 and Arrowstar: all four engines spin and show smoke when failed.
6. **Damage.**
   - Land at under 300 fpm: no damage.
   - Land at about 800 fpm: gear is degraded but holds.
   - Land at over 1,200 fpm: gear fails or collapses.
   - Strike the left wingtip on the ground in a steep bank: only the left wing is damaged.
   - Fly nose-first into a building at speed (the "Crash test" spawn): much more damage, and
     the aircraft breaks up.
   - With a damaged wing (sandbox failure "Left wing damaged"): the aircraft still flies but
     needs right aileron.
   - **No breaking apart (default).** Fly nose-first into a building at speed: the plane
     crumples, bends and comes to rest in one piece. The nose is shortened and the fuselage
     sags. Nothing should fall off unless you hit something very hard (100 kt or more).
   - Land at over 1,400 fpm: the gear folds up under the plane, and it slides on its belly.
   - Drag a wing along the ground until it's wrecked: it droops from the root and stays on.
   - **Bending.** Hit a wingtip hard on a hangar or the ground: the outer wing visibly bends up
     or down and stays bent. A second hit on the same wing bends it further, up to about 28°.
     A nose-first hit into a building shortens the nose (crush) rather than bending it.
     The ailerons should follow the bent wing; if they float in place, report it.
   - **Mesh dents (needs "Allow Mesh / Image APIs").** After a hard hit, look closely at the
     panel that got hit: it should bow inward around the impact rather than move as one
     block. Output must not show `[MeshSkins] off`. If it does, the API setting is off or
     EditableMesh failed; paste the message. Check a second player sees the dent too.
     If faces look inside-out (see-through from outside), report it: the triangle winding
     needs flipping.
   - **Crash feel.** Clip a wingtip on the ground at about 70 kt: sparks, a few shards, and the
     outer wing tears off while the inner wing stays on. The aircraft rolls toward that side.
   - Belly-scrape a building corner: the panels near the contact visibly dent inward and
     darken. Hitting the same spot again dents it a bit more, but it never caves in absurdly.
   - Watch a torn-off wing tumble: it carries on in the direction the aircraft was moving and
     splits again when it slams into the ground hard. A second player sees the same pieces.
   - Look for hitches: the dent re-weld should not jerk the aircraft. If it does, lower
     `GameConfig.crash.maxCrumplesPerSecond`.
7. **Debris.** Crash ten times in a row with the sandbox. Frame rate recovers; debris
   disappears after about 75 s; the debris part count never exceeds 80 (in Explorer,
   Workspace > Debris).
8. **Two cities, two airports, one route.** Fly from HBR to RDV. Both airports have a runway,
   taxiways, an apron, gates, a terminal and a tower, and both cities are visible on the way.
9. **No missing ground.** At top speed and low altitude, fly over the terrain, both airports
   and both cities. No holes or missing geometry. StreamingEnabled is off, so this should hold.
   Also fly across the seam about 18 km east or west of the map centre (x ±64,500) and
   check there are no cracks where the fine and coarse terrain meet.
   **View distance and map edge.** Climb to 3,000 m over HBR: the northern mountains, Ridgeview
   and Harbor City's skyline should all be visible. Fly out past any edge: the land should run
   down into a sea that reaches the horizon. Fly low over Harbor City and its suburbs: windows,
   houses and trees should appear within about 2.5 km and drop away as you leave or climb.
   Graphics quality in Roblox settings limits view distance, so test on a high setting too.
10. **Multiplayer.** Test > Clients and Servers > 2 players. Both fly at once. Each sees the
    other's aircraft move smoothly, with gear and flaps animated. Neither can apply damage to
    the other's aircraft. Grades and rewards appear only for the player who landed.
11. **Performance.** Using the MicroProfiler (Ctrl+F6) and the Developer Console's memory tab,
    record frame time and memory: parked at HBR, over Harbor City at low altitude, and right
    after a crash with debris. State the device you used.
12. **End to end.** Join, pick the aircraft and Airline mode from HBR to RDV, spawn, taxi,
    take off, fly, land, park at a gate, see the results screen, then pick the next flight
    from the menu.
13. **Minimap.** While flying, a round map sits top right under the Controls button and does
    not cover any HUD panel. Check: sea is blue and the coastline matches what you see out of
    the window; both cities are named; each airport shows a runway strip lined up with the
    real runway; your yellow plane points the way you fly; - and + zoom; the middle button
    switches "North up" / "Plane up" (in Plane up, whatever is ahead is at the top and the
    city names stay upright); N hides and shows the map. In Airline mode the destination has a
    gold ring and "Fly here!" tag, and a gold arrow sits on the rim when it is off the map. With
    two players, each sees the other as a blue plane with their name. Note whether the Output
    shows "[Minimap] could not draw the base map", and whether the map looks smooth
    (EditableImage) or blocky (Frame fallback).

14. **Stunts ring race.** Menu: Mode > "Stunts: Ring Race", FLY. You start in the air east of
    HBR runway 09 in the Zephyr R1, heading at a green START ring. Check: 12 orange neon rings
    with numbers are visible (high and low, none buried in the ground or in trees, none in
    the runway 27 approach); the next ring is green and outlined through hills, the one after
    yellow; the arrow at the screen edge points at the next ring and turns into a circle
    marker with a distance when it is on screen; the clock starts at START; a cheer shows
    for each ring; flying past a ring shows "MISSED! +3 s"; FINISH shows the results card
    with time, medal and best time; FLY AGAIN and R restart at the start; touching the ground
    shows "CRASHED!". With two players, both race at once and pass through each other.
    Note any Output errors from StuntsHud or MissionService.

## C. Report back

For each failing item, note the item number, what you did, what happened, the Output text,
and a screenshot if it's visual. That's enough for me to fix it.
