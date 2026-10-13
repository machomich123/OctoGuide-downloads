# OctoGuide 0.5.12

- XP grind recommendations appear as optional advice beneath the next quest. Actual quest minimum levels and required level steps remain enforced. Back still opens the original step; no optional step is falsely marked complete.
- Settings → Quest automation settings adds independent guide-only auto accept, auto turn-in and reward selection. All three default OFF; hold Shift to handle a dialog manually.
- Reward selection compares class leveling stats against equipped items and items in bags. Without an upgrade, it chooses the highest total vendor value. Unknown/missing data stays manual. It does not equip or sell items.
- Quest actions are sent directly from dialog events without an intentional delay. Real in-game timing depends on the client and server.
- Compatible with the installed private family route pack without redistributing its content. Update the existing OctoGuide-downloads addon through the launcher.

Verified with Lua 5.0.3 tests and release-manifest loading. Live OctoWoW NPC interactions and perceived timing have not been tested.
