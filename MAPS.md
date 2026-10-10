# Map overlays and travel

Map settings independently control targets, routes, checkpoints and minimap overlays.
Long walking routes require authored checkpoints. When a known flight is estimated
to be faster, the map and arrow lead to its departure flight master. Opening a
taxi map records that character's available destinations. A Hearthstone suggestion
requires a matching recorded inn location and a ready item.

Zone and continent coordinates are projected through ClassicAPI. Invalid or
off-map positions are omitted. pfQuest supplies the route-dot texture when loaded.
The addon does not query the unsupported rotateMinimap CVar.

Map lines are navigation aids, not terrain pathfinding. Walking distance and
taxi geometry provide estimates; real server routing and transport waits can
change travel time. Boats and zeppelins retain authored guide instructions.

The addon saves character progress, observed taxi destinations, bind location and
display settings in its own SavedVariables table. It does not upload them.
No account name, password or launcher login data is needed by OctoGuide.
