# Source comparison and OctoWoW quest assessment — 2026-10-11

Primary: user-supplied RestedXP Classic / Survival. Compare before adding: Vanilla Questing and VanillaGuide Enhanced, read from their local GitHub checkouts. No union of all quest lists was made.

- Primary route: 1216 distinct quest IDs.
- Vanilla Questing: 985 distinct quest IDs in the compared source snapshot.
- VanillaGuide Enhanced: 512 unambiguous title-to-ID matches. Ambiguous same-title chains stay separate in the audit; title matches do not prove identical steps or route quality.
- Official OctoWoW index: 6404 distinct entries read through 528 category/zone queries, with zero final fetch/parse errors.

Every fetched index entry received a scope, existing-route, prerequisite and coordinate assessment in `All official quest assessments.csv`. Route proximity is a geometric source estimate, not measured travel time. Local coordinates/objectives come from the dated merged pfQuest snapshot and are labeled accordingly. The official root lists are capped; zone indexes can exceed 200 entries, so a list of 206 was not treated as truncated. Exhaustive server-wide coverage cannot be proved without a complete authoritative database export. New categories outside both the menu and fetched snapshots may remain undiscovered.

323 nearby candidates passed the first metadata screen. They include repeatable turn-ins and reward-only steps; they were not all added. Three verified low-detour additions were implemented as optional work:

| Quest | Why it fits | Evidence |
|---|---|---|
| 80384 Pinch of Salt | Coastal crab work during the existing Durotar coast trip | https://octowow.st/db/?quest=80384 |
| 70052 Trader's Misfortune | Tazan while working the Southsea pirates, hand-in in Ratchet | https://octowow.st/db/?quest=70052 |
| 40389 Zalazane's Fall | Follow-up at Master Gadrin, delivery during the planned Grommash Hold visit | https://octowow.st/db/?quest=40389 |

Virulence (60113) stays a reviewed candidate: the prerequisite and a future Solliden visit must both fit before it becomes a route addition. Other guide-only quests remain a candidate list until their chain, danger and return trip justify an addition. No claims of fastest / 100% optimal leveling are made.

The official pages have conflicting XP presentations (RewXP versus Gains). No fixed XP/time saving is promised. Optional additions never manufacture prerequisite completion or mark abandoned quests rewarded.
