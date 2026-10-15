# OctoGuide 0.6.7 — Less repeated work

This update preserves guide content, objectives, navigation, professions, quest automation and existing settings. It reduces repeated work instead of switching features off.

- Bag/quest-log bursts update character evidence and progression immediately. Their visible panel is rebuilt once before the next drawing. Explicit acceptance, turn-in and level events retain immediate rendering.
- All six delayed client-state checks remain, so delayed quest/item information is still observed. Five synthetic bag events produce seven panel rebuilds instead of eleven.
- Bag events no longer recopy unrelated pfQuest completion history. Inventory and quest objectives are still read live, including item loss and regressed collect goals. Explicit scans and quest/history updates still refresh the history.
- Map highlighting visits each native pfQuest frame once per refresh. Actual width/height is changed only when needed. Native hover, visibility, movement, recycled pins and map options are retained. A synthetic set of 1000 matching pins produces zero unchanged dimension writes per second after setup, versus 8000 previously. This is a test workload, not the observed number of pins in a player's client.
- Quest-giver height lookup reuses identity searches for 0.12 seconds, including unsuccessful searches. It still validates the NPC identity and reads NPC/player positions on every height calculation. Step, waypoint, world-map, database and quest-knowledge changes invalidate the search cache. A synthetic 144 FPS loop drops from 144 to eight unsuccessful searches per second. A newly loaded NPC may be discovered up to 0.12 seconds later; this is consistent with the existing live-target polling interval.
- Primary arrow rotation still updates every frame. Unchanged distance/height/evidence labels are not rewritten, and the height label is anchored once.

All 52 Lua 5.0.3 test suites pass using simulated client events, including full-manifest startup, progression before rendering, delayed checks, inventory loss, quest objective regression, hover restoration, pin recycling, moving heights and wrong NPC identities. An old release-load test's mock was missing real client methods; its mock was completed without changing addon behavior to satisfy it.

These checks prove fewer redundant operations and the tested behavior. The reported live stutter has not been reproduced or measured in-game, so this release does not claim a verified FPS gain or that every source of stutter is fixed.

Update through the existing launcher addon entry. No new dependency or setup is required. Load the new addon on the next login or with /reload outside combat.
