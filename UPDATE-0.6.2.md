# OctoGuide 0.6.2

- Add a line below the main arrow with Up/Down in yards, Same height, or Height unknown. Heights come from observed matching NPCs, live quest targets, or explicitly supplied waypoint height; 2D map coordinates never imply altitude.
- Explain the lower Apothecarium level in Undercity quest directions.
- Check authored Fly steps against this character's observed destinations. If unconfirmed, show a travel alternative rather than assuming the flight is available. Undercity includes road/ruins/elevator directions. The arrow uses the destination taxi node rather than the original departure point. Other destinations receive general travel advice, not a claimed complete safe walking route.
- Copy pfQuest history into a separate character-local record with timestamp, level and provenance. `/octoguide history` refreshes it and explains `/db journal` and `/db query`. Manual pfQuest marks are not silently promoted to server-confirmed completions.
- Announce the version when a new version successfully loads. Updating files still requires login or `/reload`; the loaded addon does not silently replace its running code or perform a GitHub background update check.

Validation: 30 Lua 5.0.3 suites, including the complete release manifest, flight status changing in both directions, positive/negative/unknown height, NPC identity mismatch, and pfQuest provenance. Actual in-game observations are recorded separately in the delivery verification.
