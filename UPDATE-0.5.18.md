# OctoGuide 0.5.18

- Prevent failed startup from leaving an empty guide panel over the game. The guide starts hidden and is shown after successful initialization.
- Capture startup/event/refresh failures, hide partial panels, stop duplicate failed initialization and repeated failing refreshes, and retain the latest five failures in character SavedVariables.
- `/octoguide` reports the captured failure when startup is unavailable. `/octoguide hide` remains available even when the guide is not ready. Close buttons target the actual clicked frame.
- Preserve route progress, completed quests and existing settings.

24 Lua 5.0.3 suites passed, including injected constructor/refresh failures and actual slash/close callbacks. Full-manifest startup with the locally installed family pack and last saved character settings also passed in the mock client. The installed 0.5.17 files matched the release, but the precise live failure in the screenshot could not be reproduced or identified from saved logs. This update adds verified failure containment and diagnostics; it does not claim that unknown underlying cause is fixed.

Update OctoGuide-downloads through the launcher. At the next login the new code loads automatically; if already logged in, use `/reload`. If initialization still fails, `/octoguide` shows the captured error and character SavedVariables retain it for diagnosis.
