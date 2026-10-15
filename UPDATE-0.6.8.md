# OctoGuide 0.6.8 — Free arrow and quest-event work reduction

Open **Settings -> Arrow settings**. Choose **Free arrow** to detach the main arrow while keeping the guide window open, or **Window + free arrow** to show both arrows. Existing characters keep the window arrow by default.

The optional free arrow includes short task text based on the actual guide instruction or live objective wording, target name, distance and height. Each text line can be toggled. Set arrow scale and text size, unlock to drag, then lock to let clicks pass through. Position is saved separately from the guide window. You can keep the arrow visible when the guide window is hidden and reset its position in settings. The arrow uses the existing pfQuest 108-direction sprite sheet with the retained MIT notice; it does not start pfQuest's route scanner or require TomTom.

Both guide-following views share one navigation calculation. The usual guide progression, observed target checks, transport handling and secondary arrow remain. Arrival does not complete quests or manual steps. Direction colors describe facing, not danger or a safe walking route.

Ctrl-click a step in the guide step list to point at that step without moving progression. Clear the selection using **Follow guide** in Arrow settings. An active selected quest can switch to its turn-in when the live log confirms completion; confirmed turn-in or abandoning a previously active selected quest clears the selection. Map-icon shortcuts are not changed.

Quest-event fix:

- The native quest-ID lookup can authoritatively report that a quest is absent. Previously the addon then scanned every log entry again. A synthetic 1000-miss test performed 25000 unnecessary entry reads; the new version performs zero.
- Repeated lookups share results only inside one protected update/event. New event revisions invalidate them; cache state never survives that operation. The inverse-only fallback remains for older clients or a failing native API.
- Already confirmed completed pickups are skipped before looking in the quest log. A synthetic quest-accept event with 400 previously completed pickups dropped from 2402 native lookups plus 60000 fallback entry reads to one native lookup and no fallback reads. These are operation counts in Lua 5.0.3 mocks, not an in-game frame-time measurement.

Validation covers full-manifest startup, all 108 arrow angles, window/free shared results, independent position/settings, optional task text including non-kill objectives, a hidden guide, manual navigation without progression changes, arrival and failure containment, quest-event invalidation, and legacy lookup fallback. All 54 Lua 5.0.3 test suites pass for this release.

The reported extreme live lag spike has not been captured/reproduced in-game. The confirmed redundant-work paths are fixed and tested, but this does not prove every live cause is gone or that the free arrow's native rendering has been visually tested in the client. Load with /reload outside combat or on the next login.
