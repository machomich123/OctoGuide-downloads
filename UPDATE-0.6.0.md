# OctoGuide 0.6.0

Adds a dedicated Professions panel with all 14 professions, including Survival
and Octo Jewelcrafting. Fastest and Fast + cheap compare the next skill-up from
visible learned recipes, bag materials, observed NPC prices and manual
acquisition estimates. Unknown inputs remain visible; no global fastest-route
claim is made. See PROFESSIONS.md for the comparison and its limits.

OctoGather integration distinguishes skill leveling from collecting a specific
material, supports Survival wood/Find Trees, and respects hidden/missing nodes.
Trainer/vendor locations get independently owned timed pfQuest map markers and
a direction arrow. Default flag lifetime is two minutes, selectable in the panel.
New profession art was generated with imagegen and converted to native TGA assets.

Open Guides -> Professions or /octoguide professions. Open the profession recipe
window to populate learned recipes. Existing quest progress and the separate
private family pack are preserved.

Also fixes level priority: Find step selects the closest applicable level
chapter before old active quests or zone proximity. An overleveled authored
next chapter is replaced by the current level chapter where one is available.
Explicit required quest-chain catch-up remains supported. Discolored Worg Heart
steps now show Wild Hearts, actual item/quest counts and database-backed mob
targets, including intentional pre-collection before quest acceptance.

Offline verification: 26 existing suites plus new profession/pfQuest and
level-priority/Worg scenarios
under Lua 5.0.3. Package/source hashes are recorded with the release. In-game
rendering and server skill-up behavior still require a live reload/check.
