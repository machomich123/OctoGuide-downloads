## 0.4.8

- Recover missing earlier RestedXP quest pickups, including saved cursors after Senjin and abandoned quests. Preserve explicit Done/Skip and confirmed history.
- Stop choosing RestedXP source pages from interpolated level estimates.

## 0.4.7

- Give the full OctoGuide title adequate measured width, a separate version line and wrapped route text.
- Resize preserves the original anchor and opposite corner at every zoom instead of converting GetLeft/GetBottom again. Corner hit areas keep 24 display units across zoom and have visible markers.

## 0.4.6

- Show RestedXP route installation and selected source in the guide header.

## 0.4.5

- Validate saved window anchors before SetPoint, recover malformed positions automatically, and handle four/five-value GetPoint results. Drag and resize share the same validated saving. Startup is ready only after UI construction; partial frames cannot crash arrow updates.

## 0.4.4

- Zoom range is now 30-150 percent. Settings stay at a fixed scale so dragging cannot move the slider under the cursor. Slider callbacks do not write back to the slider being dragged.

## 0.4.3

- Fix Current level / All getting stuck on the current-level filter. The button now names the action: Show current level or Show all levels.

## 0.4.2

- Show the loaded runtime version beside OctoGuide in the header, in both views.

## 0.4.1

- External pfQuest history no longer skips quests during automatic placement.
- Starter characters below level 5 keep route order unless their own quest log or confirmed history gives a placement.
- Saved progress is checked against character name and realm; mismatched progress is archived separately.
- Old automatic placement cursors are discarded once, with a recoverable copy. Manual progress is retained.
- Unavailable acceptance steps explicitly show the required level.
- Regression reproduced against 0.4.0 placement and passed after correction. Native gameplay remains unverified.

# 0.4.0

- Concurrent quest goals, personal class tasks, Auto/Solo/Group settings and level navigation.
- Optional verified OctoWoW quest additions.
- Support a separate private family route pack without shipping paid prose publicly.
- Preserve the 0.3.6 exact-ID quest-progress fix.

# 0.3.6

- Support older ClassicAPI quest-log ID lookup.
- Keep verified quest turn-in fallback active when registered native events are silent.
- Preserve saved progress and exact quest-ID matching.

# Changelog

## 0.3.5
- The /octoguide and /oguide commands clear and close their own submitted chat input. Unrelated drafts are left intact and command errors remain visible.


## 0.3.4
- Removed the unsupported rotateMinimap CVar lookup that caused repeated client errors.
- Route dots use pfQuest's route texture when pfQuest is present.
- Long straight lines with no authored checkpoints are no longer displayed as walking routes.
- Added conservative flight travel suggestions based on observed taxi-map destinations, flight geometry, walking distance and available money. Open a flight master's map to record destinations for this character.
- Added Hearthstone suggestions when the bound inn's position has been recorded and the item is ready. Binding at an inn while this version is loaded allows recording; old bind locations without coordinates are not guessed.
- The arrow points to the suggested departure flight master. Flights and Hearthstones are never activated automatically.
- Mirrored the right panel edge onto the left to keep both sides consistent.

Travel times are estimates. Terrain, mount state, server taxi routing, transport waits and previously unseen shortcuts can affect the actual fastest route. Boat/zeppelin travel continues to use the authored guide steps. This release is for family testing, not a measured fastest-route guarantee.
