# OctoGuide 0.5.0

## Interface

Guides and Settings reuse the existing navy/gold panel art. Buttons use new original imagegen textures with normal, hover and pressed states. The main guide retains its layout. Settings adds a small secondary arrow toggle, transparency toggle and background opacity slider (10–100%). Text and arrows remain opaque. Zoom remains 30–150%, independent of opacity.

There is one main route source: RestedXP when the separately installed route pack is present, otherwise the bundled fallback. Old saved source choices cannot select the fallback while RestedXP is loaded. Hardcore/Normal and Auto/Solo/Group remain independent options.

## Navigation

Same-block quest pickups take priority before objective work, without crossing a turn-in or pulling pickups from future blocks. Level gates, source conditions and explicit skips remain respected.

Unfinished objectives are resolved by the server's objective IDs. Living matching units exposed through target, mouseover, pet target or party targets are eligible. Their current life state and position are checked; dead units are excluded. Polling is limited to four times per second, with a small preference for the previous target to reduce flicker. This does **not** enumerate every visible mob: the installed nearest-unit API provides no death filter or identity. No selection is changed to discover units.

Loaded quest objects use ClosestGameObjectPosition when available. This indicates an observed object, not proof that the object is currently interactable. Item sources can be resolved through an already installed pfQuest database. Missing optional APIs or data fall back to the guide waypoint. Database coordinates are explicitly labelled possible spawns, bounded to the guide's local area.

The optional secondary arrow points to another active concurrent objective, not a speculative future pickup. It is off by default.

## Bug reports and remaining limits

Settings > Report bug opens a description field. Save report captures the current guide step, quest objectives, character race/class/level, detected APIs, settings, UI text/state for the guide and both menus, recent addon events and captured OctoGuide Lua errors. Collection does not open hidden menus or capture chat, account names, passwords or tokens. Reports are per-character, limited to ten; events and errors are bounded.

Reports are **local**, stored in OctoGuideDB.reports and written by WoW with the character's SavedVariables on logout or /reload. UI state snapshots are not pixel screenshots. This client exposes no verified addon-only HTTP uploader or hidden-panel image capture. The UI does not claim delivery to GitHub. A private folder inside a public repository would not provide private storage. An online uploader and pixel capture require an additional client capability; they are not shipped here.

## Verification

Lua 5.0 regression checks cover progression, character isolation, quest pickups, modes, source selection, zoom, resizing, readability, corpse exclusion and report bounds. An isolated native client loads the actual addon sources and textures, checks forty resize combinations and renders the new menus/transparency. Character, quest and world observations in that client test are synthetic. Live gameplay, server data and automatic GitHub receipt are not verified.

Original asset prompt: production transparent texture atlas; dark navy enamel and aged brass gold; three wide text-free normal/hover/pressed buttons with subtle octopus engraving, plus a gold beetle report icon. Generated with the built-in imagegen tool and converted to TGA. Existing high-resolution panel and arrow assets are reused.
