# TBM Party Inventory

Separate Lua addon for the Tortoise WoW 1.18.1 family realm. Requires the **TortoiseBotsManager** addon and matching server-side ALT inventory commands.

Install or update from **Tortoise Crew Launcher → Addons → Discover**. The launcher verifies all five file SHA-256 hashes from `release.json`, keeps backups in the client WTF folder and automatically checks for an update before Play.
Local modifications are never overwritten automatically.

**Release:** 2026.11.22.7

This update adds native-quality borders, unusable-equipment tinting, quest
markers, reversible optimistic ALT bag previews and a smaller exact-stack
GUID handshake with newer Living Azeroth servers. Older realms keep the
previous full-inventory fallback. Quest items and failed native trades remain
protected: this is never a client-side item ownership bypass.


Version .7 waits for the server's automatic inventory snapshot after a placement acknowledgement (with a delayed recovery query), keeps each ALT's placement acknowledgements separate without extra snapshots, recovers ALL pending ALTs after an ambiguous placement error, and reduces unnecessary character-model reloads. When the server explicitly advertises SELF_ITEM_CAP, the player's quick equip, unequip and gear drag actions use the same server item commands as owned ALTs. Self gear commands are serialized through server receipts to protect slot changes during rapid actions. When the server advertises vendorable/unvendorable item flags, known unsellable items cannot be marked; old servers remain compatible. A server update may still be required for native trade and marked vendor sale fixes.
