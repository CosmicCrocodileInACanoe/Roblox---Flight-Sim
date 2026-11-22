# Credits and references

All code, geometry, liveries, names and text in this project are original.

## FableFlight

The directive pointed to FableFlight as a reference. It is published under the MIT License.
I looked at it for design ideas only: how a browser flight game splits flight model, input,
camera and HUD, and what a short first-flight flow looks like. No code, assets or data from
FableFlight were copied or adapted, so its license terms don't apply to this repository.

## Roblox documentation

API choices (VectorForce, Torque, network ownership, PreSimulation, collision groups,
ContextActionService, DataStoreService) follow the official Roblox Creator documentation at
https://create.roblox.com/docs.

## Physics references

The aerodynamic model uses textbook relations: thin-aerofoil lift slope with finite-wing
correction, parabolic drag polar, flat-plate post-stall approximation, the ISA standard
atmosphere and the Wieselsberger-style ground-effect factor. Aircraft numbers are invented
for a generic 150-seat twin jet and tuned for play.
