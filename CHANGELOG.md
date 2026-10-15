# 0.6.8

- Add an optional free arrow with independent saved position, scale, text size, short task text and label/lock settings. Guide window can remain open.
- Share navigation between window/free arrows; keep current users on the existing window arrow. Ctrl-click a guide step to point at it without changing progress.
- Avoid rescanning the quest log after authoritative native misses. Reuse quest lookups within a protected update/event and invalidate them at quest-state boundaries.
- Skip quest-log lookups for already confirmed completed pickups. Retain inverse-only and failing-native API fallback.

# 0.6.7

- Combine bag/quest-log panel rebuilds before the next drawing; keep immediate evidence/progression and all delayed client-state checks.
- Stop recopying unrelated pfQuest history for bag events; keep inventory and quest objectives live.
- Visit each pfQuest pin once per refresh and only change dimensions when needed; preserve hover, recycling and native updates.
- Cache quest-giver identity searches for 0.12 seconds, including misses; still validate identity and read moving positions/heights each frame.
- Stop clearing/reanchoring and rewriting unchanged primary arrow labels every frame; keep smooth rotation.
- Add operation-count and behavior tests. No in-game FPS/stutter improvement is claimed from mock tests.

# 0.5.18

- Keep the guide hidden until startup completes and capture startup/event/refresh exceptions without leaving blocking partial UI.
- Prevent repeated failed initialization, stop repeated failing updates and save bounded failure history.
- Keep slash diagnostics and emergency hiding available after a failure; close the clicked frame rather than a replaced global reference.
- Validate healthy full-manifest startup plus injected constructor/refresh failures. Exact reported live cause remains unconfirmed.

# 0.5.17

- Show simple local walking/swimming instructions beneath the associated quest without a separate Done step.
- Preserve approach waypoints and original saved step IDs; arrival never completes the quest itself.
- Verify all four family island-swimming variants and retain explicit path/cross-zone/transport steps.

# 0.5.16

- Link repeated Hornwood Recurve Bow vendor instructions to the actual item goal; count equipped items when reconciling collection/buy goals.
- Preserve explicit Done/Skip when Find step advances past satisfied steps.
- Add missing Lost Deathstalkers pickup/turn-in to family Wild Hearts routes; escort completion alone does not unlock Wild Hearts.
- Validate all six repeated bow stops, both family Silverpine routes and existing progress/automation with 22 Lua 5.0.3 suites.

# 0.5.15

- Recheck earlier active quest work and ready turn-ins before following a later saved cursor or treating a route as finished.
- Recover from stale automatic progress marks while respecting explicit Done/Skip, Back and manual starting points.
- Verify Sen'jin plans -> Sen'jin turn-in -> Razor Hill with both a regression fixture and the locally installed private family route.

# 0.5.14

- Require only guide-authored skill goals for automatic training progress; remove inference from all available trainer services.
- Display the actual spell/rank for authored spell-ID steps. Generic visits without explicit targets stay manual.
- Verify that learning Track Beasts cannot satisfy another skill goal and leaving it unlearned cannot block that goal.

# 0.5.13

- Fix Vanilla reward tooltips receiving colored chat links instead of item payloads; preserve random suffixes and contain rejected tooltip data.
- Advance training from actual learned spells/skills, including recipes and higher ranks; subscribe to spell, skill and trainer events.
- Complete generic class visits only after all originally available services are learned. Preserve Back review and default-OFF reward selection.
- Reproduce the 0.5.12 link failure and verify the fix plus training with 18 Lua 5.0.3 test suites.

# 0.5.12

- Move recommended XP grinds beneath the next quest as optional advice; preserve actual quest minimum levels.
- Add separate, default-OFF guide quest auto accept, auto turn-in and gear/bag-aware reward choice settings.
- Dispatch quest actions directly from events; keep unknown items and ambiguous quests manual.
- Validate original Vanilla tuples, installed family route behavior and the complete release manifest with Lua 5.0.3.

## 0.4.10

- Fix resize coordinates: Vanilla SetPoint uses the positioned region scale, not the relative parent scale. Native position regression reproduces the old jump and checks no jump plus fixed opposite corner.
- Remove added yellow corner markers while retaining constant-size hit areas.
- Keep route header above the border; separate upcoming task titles from indented instructions using different colors.

## 0.4.9

- Resize uses resolved screen geometry and UIParent rather than dereferencing the native relative-region returned by GetPoint. Captured handles avoid global callback context dependency. Resize release saves its computed anchor directly.
- Native crash at 0x0070211C reported during resize; exact in-world fault not reproduced offline. This release removes the suspect path, with native resize stress and geometry checks.

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
