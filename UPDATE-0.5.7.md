# OctoGuide 0.5.7

OctoGuide remains free and MIT-licensed. This release adds character scanning and direct step selection using existing client capabilities. There is no paid service, subscription, new installer or DLL requirement. The bundled fallback routes remain available without a private family route pack.

## Find step

- Reads the entire quest-log entry list, objective completion, carried items and equipped inventory, the current Hearthstone bind name, and flight paths confirmed by previous flight-master observations.
- Requests completed quest history when the client/server exposes it. Find step waits up to eight seconds for the response before falling back to available information. It supports set, list and output-table history APIs.
- Uses confirmed turn-ins to satisfy earlier and later quest actions, including quests completed out of the guide's order. Active quests are distinguished from quests ready for turn-in and quests already rewarded.
- Explains the data used and the unavailable observations in chat. `/octoguide scan` repeats the latest scan summary; `/octoguide sync` runs Find step.
- Inventory never proves a quest reward or turn-in. A closed bank cannot be scanned. Flight paths cannot all be reconstructed from static map data: reachable nodes are remembered when the flight-master map is actually opened. Unknown completion history remains unknown.

## Step list and Back

Click a guide in Guides to browse all steps applicable to your character and route mode. Click a step, or enter its number in **Skip to step** and press Go/Enter. Previous/Next steps and the mouse wheel navigate long lists; only twelve row controls are created.

Direct selection moves the view without marking earlier quests complete. Back enters a stable review position, including steps crossed by automatic progress. Done/Skip in review advances one displayed step at a time. Quest-log refreshes and late server replies do not override manual review. Find step returns to automatic placement.

## Loading diagnostics

Includes the previously local 0.5.6 loading diagnostics. `/octocheck` reports missing required files/API functions and limited optional features. Missing data is not presented as a completed guide. Alliance characters are explicitly informed that the installed route content is Horde-only.

## Verification

Lua 5.0 checks cover asynchronous replies/timeouts, history formats, out-of-order quests, inventory changes, six-step automatic skips followed by Back, direct row selection, typed step numbers, paging and full TOC initialization. Existing progress, prerequisite, mode, resize and control checks were also run.

Automated tests and isolated native UI checks do not prove that a particular live server supplies complete historical data. The actual character scan and route placement still require a gameplay check. This release does not include or redistribute private paid guide text.
