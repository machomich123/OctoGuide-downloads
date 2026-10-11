# OctoGuide 0.5.3

New imagegen button artwork uses navy enamel, restrained antique gold edges and a clear center for text. Original aspect is preserved through uniform reduction and fixed decorative endcaps; small controls use the plain border region. Named footer actions have enough width for their labels.

Next Steps previews show concrete quests, travel and personal class tasks. Routine food/drink and vendor stops are informational, with a short optional reminder attached to a nearby relevant stop; they no longer require Done/Skip. XP/level checkpoints retain their safety role but do not occupy the upcoming quest preview. Auction-house utility steps and auction-house note text are excluded in Hardcore. Normal mode retains eligible auction actions. These are load-time rules and also apply to already installed RestedXP route packs through level 60.

Fixed a world-coordinate mismatch: UnitPosition returns west/north, while ClosestGameObjectPosition returns north/west. A near cactus could consequently be displayed thousands of yards away. Object observations now use the correct axis order and reject a position inconsistent with the API-reported distance.

Living mob observations now also consider available nameplates and exact-name lookup, using installed ClassicAPI capabilities. Every eligible unit must match the objective entry, be alive and have positive health. Lazy Peons must be sleeping. The closest eligible observed candidate wins. No target selection is changed and no native component is installed. If the client cannot expose the required unit, database locations remain explicitly labeled possible spawns. A visible game object is not proof that the server currently permits looting it.

Secondary target selection is bounded to a 0.12-second cadence; cached world targets are projected from the player's current position and facing on every frame, with the same angle smoothing as the primary arrow. This avoids freezing the secondary bearing during target scans.

Update exclusively through the existing launcher GitHub link or mod tab. No EXE or manual DLL update. Reporting is unchanged and deferred.

Verification: 25 Lua test suites, 79 source routes / 16,429 steps audited through level 60, 40 race/class/mode route chains, 60 resize combinations, and an isolated native client's 40 resize cases and real button rendering. Navigation regression fixtures include nonzero unequal world axes, inconsistent distances, dead/living nameplates and awake/sleeping peons. No logged-in world test was performed; live server interaction availability remains outside these tests.
