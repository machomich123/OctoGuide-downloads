# OctoGuide 0.5.11

Direct step selection now resumes normal following when quest/bag progress changes. Previously, Skip to step reused Back's locked review mode and could keep the guide on a killing objective after completion. Back still retains stable review. A manually chosen starting step is respected without redirecting to unrelated earlier pickups.

A Lua 5.0 regression test selects a killing step, keeps it while incomplete, then verifies that a completed quest moves to the turn-in step with its different destination. Turn-in is not recorded until rewarded, and Back stays stable. Existing startup, placement and navigation checks pass. Actual family-character behavior remains to be checked, particularly if a different quest has intermediate objectives or route stops.

Free update; no DLL or installer changes.
