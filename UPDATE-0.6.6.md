# OctoGuide 0.6.6

Auto quest selection now prioritizes the current guide quest ID over other quests at the same NPC. Back permits automation only for the selected step. Same-title chains can use an identity-checked NPC lookup when gossip does not expose an ID; ambiguous matches remain manual.

Map and minimap use pfQuest's own pins. The current matching pin is 25% larger, with native movement, visibility, clicks and hover retained. Duplicate OctoGuide map overlays are removed.

37 Lua 5.0.3 suites pass, including gossip selection through acceptance for Samophlange, Trader's Misfortune versus Wharfmaster turn-in, and native pin reuse/restoration. Tests simulate client events; the active game was not controlled or reloaded. Installed files need /reload outside combat. No new addon dependency; marker emphasis requires the existing pfQuest.
