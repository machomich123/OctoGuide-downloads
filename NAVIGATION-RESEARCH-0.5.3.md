# Navigation source review, 2026-10-11

ClassicAPI reference: https://github.com/brues-code/ClassicAPI/blob/master/docs/API.md
Coordinate implementations: src/unit/Position.cpp and src/gameobject/ClosestPosition.cpp in https://github.com/brues-code/ClassicAPI
Object scanner: https://github.com/brues-code/ClassicAPI/blob/master/src/object/ClosestByEntry.cpp

Confirmed from the local pinned source and current upstream: UnitPosition deliberately pushes engine y,x (west,north). ClosestGameObjectPosition pushes raw engine x,y (north,west), plus 3D distance. The prior addon swapped these world axes. The standard ClosestUnitPosition enumerates loaded matching objects but does not filter health, so its return alone cannot establish a living target. Installed nameplate and exact-name tokens can be checked with identity, health, death and stand-state APIs. The optional previously installed bridge may enumerate living units, but this release does not require it or update any DLL.

pfQuest comparison: https://github.com/shagu/pfQuest/blob/master/route.lua and https://github.com/shagu/pfQuest/blob/master/README.md
The reviewed route implementation uses database coordinates; it throttles route/distance updates while its arrow has a separate OnUpdate. Its README explicitly describes database-known objects. This is useful for separating scans from visual updates, but cannot establish live loot availability. No code was copied.

Boundary: nearest living target means nearest eligible target among client-observable units. Nameplate exposure depends on existing client capabilities and active plates. Database spawns are not observations. Objects found by the visible-object scanner can still be non-interactable or have a delayed server state. No additive launcher-installable Lua addon can manufacture an observation the installed client does not expose.
