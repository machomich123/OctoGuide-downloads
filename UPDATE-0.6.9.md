# OctoGuide 0.6.9 — Continuous runtime performance review

This update addresses repeated work during ordinary navigation, in addition to quest events. Guide content, progression, quest automation, manual review, objectives, map pins and free-arrow options remain.

## Findings and changes

- The current route was repeatedly walked from the beginning inside one display frame, often thousands of step-key reads per frame. Reads now share a callback-local model. A route result can additionally be retained for at most 0.12 seconds; quest, inventory, XP, money, skill, group, zone, progression and review changes invalidate it. Arrow bearing/position painting still runs every display frame. New event subscriptions cover XP/money/equipment/bank changes; the short expiry also handles a delayed/missing client event.
- Guide-step keys are reused within the selected route/mode. Callback storage is pooled with generation checks, so pooling never keeps old native quest answers across callbacks. Memo record pools are capped at 128 records per function/callback depth. Mutable progress writes, nested quest revisions and NPC-offer changes invalidate reads.
- Concurrent quests formerly enumerated nameplates and read the same unit identities repeatedly. Unit identity, position/health, name lookup, native closest-unit and object queries are now shared inside the same callback. They are not retained as living-unit evidence across frames. Existing 0.12-second target-poll cadence, corpse/identity checks, target-aura checks and selection hysteresis remain.
- Secondary results used to clear the entire cache after every 100 refresh operations, repeatedly synchronizing fresh scans. The cache now counts distinct keys and evicts only the oldest key above 100.
- Travel plans used a table's identity as a cache key. Identical newly constructed NPC coordinates could therefore rebuild a flight search repeatedly. Keys now use coordinate values, bind location, world-map and conversion API identity. Local/unknown results are cached too. Each departure's shortest routes are calculated once, rather than once per destination. Static flight-node world positions are reused.
- A local destination no longer initializes the whole flight network. When the network is needed, preparation reads at most four paths per tick. Deferred flight-master observation checks that the native taxi window is still open before reading it.
- Periodic map checks no longer walk every pin when the matching step/options are unchanged. Native pfQuest UpdateNode callbacks share a short-lived route model instead of independently walking the whole guide for every pin; new and recycled pins are still handled. Captions and secondary-arrow anchors are updated only when needed. Profession marker polling is idle when no marker exists.

## Evidence

The same Lua 5.0.3 mock workload compared 0.6.8 with this update: 400 previous pickups, a live quest, optional 20 concurrent quests, 40 nameplate tokens, 1000 map frames, panel/free arrow combinations, hidden UI and a flight network. Work counts, rather than mock wall times, are the regression evidence:

| Work over the same 288 simulated display frames | 0.6.8 | 0.6.9 |
| --- | ---: | ---: |
| Step-key reads, panel arrow | 3,468,786 | 13,299 |
| Step-key reads, both arrows and 20 concurrent quests | 3,702,513 | 15,334 |
| Native unit-identity reads, concurrent case | 16,272 | 768 |
| Nameplate enumerations, concurrent case | 339 | 16 |

All 55 Lua 5.0.3 suites pass, including functional behavior and operation budgets. Tests verify immediate Mark/Back/quest changes, mode-key changes, callback cache isolation, shared observations, bounded cache/pool sizes, warm repeated secondary polling, four-path loading limits, closed-taxi safety and flight-money constraints. A sustained synthetic 4320-frame case covers repeated polling and cache reuse. These are not game FPS or measured live frame-time improvements.

## Automatic local evidence for any remaining issue

The addon keeps a bounded local log of slow own callbacks/stages and UI frame intervals. It uses the client's high-resolution timer when available and does not start external tracing, change game settings, send data automatically or scan other addons. Own callback time and a slow frame interval are separate measurements; neither alone proves the cause of all frame stalls. Route resolution, target observation, layout and flight preparation/planning are measured separately. Stages overlap their enclosing callback and must not be summed as independent CPU time. Report bug includes a snapshot, and `/octoguide perf` prints a short summary. The recent-record ring and phase table are each capped at 32; one previous saved session is retained.

Update/reload outside combat. Confirm the loaded version with `/octoguide check`. The reported random in-game stutters have not been captured or verified absent on the user's/brother's client. This release fixes the demonstrated repeated work and adds regression/diagnostic coverage; it does not promise zero stutters from the whole client, other addons, graphics, disk or server behavior.
