# OctoGuide 0.5.17

- Move simple local walking/swimming directions into the next associated quest's instructions, removing the separate Done click. Includes "Swim to the main island" in all four family race/mode variants.
- Keep the approach waypoint under that quest. When reached, navigation continues with the quest target; if the quest has no separate coordinates, the known island waypoint remains available.
- Retain explicit route paths, cross-zone travel and actual boat/flight/hearth actions. Saved original step IDs remain valid.
- Arrival at the approach waypoint does not mark the quest complete.

23 Lua 5.0.3 test suites passed, covering old swim cursors, quest instructions, approach navigation, transport preservation and the locally installed family routes. Live gameplay confirmation remains pending.

Update OctoGuide-downloads in the launcher and use `/reload`. No family pack reinstall is needed.
