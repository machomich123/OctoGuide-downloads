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
