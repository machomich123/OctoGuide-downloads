# OctoGuide 0.6.10

- Tightened free-arrow captions, smaller distance text, and no duplicate task/title line.
- Accept-step short text names the NPC interaction when available. Concurrent kill/collection objectives remain separate from the acceptance waypoint.
- All auxiliary windows share background opacity and the guide close icon.
- Auxiliary windows can be dragged and resized using the lower-right grip; resizing scales the complete contents together to avoid clipping. Position and size are saved independently.
- Future card-based menus inherit the same controls.

Verified with Lua 5.0 regression tests. Live game rendering and mouse interaction still require an in-game check; no active client was controlled or reloaded.
