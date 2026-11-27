# TBM Party Inventory

Separate Lua addon for the Tortoise WoW 1.18.1 family realm. Requires the **TortoiseBotsManager** addon and matching server-side ALT inventory commands.

Install or update from **Tortoise Crew Launcher → Addons → Discover**. The launcher verifies all five file SHA-256 hashes from `release.json`, keeps backups in the client WTF folder and automatically checks for an update before Play.
Local modifications are never overwritten automatically.

**Release:** 2026.11.27.2

For the local test client, copy this addon folder into `Interface/AddOns` with
WoW closed. The candidate uses the native inventory path on right-click for
locally identified wearable items and ordinary equipment removal. Equipped
bags and items awaiting eligibility verification use the server protocol.
Duplicate inventory notifications no longer rebuild an unchanged outfit.
Pay All starts the next purchase as soon as the previous item's GUID, receipt,
and payment have been verified. The standard TBM transport throttle still applies.

This update adds native-quality borders, unusable-equipment tinting, quest
markers, reversible optimistic ALT bag previews and a smaller exact-stack
GUID handshake with newer Living Azeroth servers. Older realms keep the
previous full-inventory fallback. Quest items and failed native trades remain
protected: this is never a client-side item ownership bypass.


Version .7 waits for the server's automatic inventory snapshot after a placement acknowledgement (with a delayed recovery query), keeps each ALT's placement acknowledgements separate without extra snapshots, and recovers pending ALTs after an ambiguous placement error. Self gear commands and Auto Sort are serialized through server receipts to protect slot changes during rapid actions. When the server advertises vendorable/unvendorable item flags, known unsellable items cannot be marked.


Version .8 makes the five-party fullscreen inventory adapt its bag cells to at least 34 physical pixels when a large screen allows it; additional rows stay reachable through the existing scrollbar. Normal-size windows and smaller party layouts retain their earlier behavior.
