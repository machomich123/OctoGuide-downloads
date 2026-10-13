# OctoGuide 0.5.15

- Normal progress now rechecks earlier active unfinished quests before following a later saved position. Old automatic progress flags cannot hide incomplete objectives or a ready turn-in.
- Regression tests cover Thwarting Kolkar Aggression: destroy the plans, return to Sen'jin, then continue to Razor Hill after server-confirmed turn-in. Includes the locally installed family route without redistributing private content.
- Explicit Done/Skip, Back review and manually selected starting points remain user choices. Authored background work stays in the background.
- Keeps the reward and guide-only skill fixes from earlier releases.

20 Lua 5.0.3 test suites passed. The exact sequence from the user's live session could not be replayed because the saved quest is already turned in; the stale-cursor/automatic-flag failure mode is covered by the tests. Live confirmation of the new behavior remains pending.

The separate SGroupPtr/SMem3 exit error is confirmed in the October 12 and October 13 client logs with identical call stacks. This addon release does not claim to fix that native crash; no game DLLs or graphics mods were changed.

Update OctoGuide-downloads in the launcher and use `/reload` in-game.
