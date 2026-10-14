# Profession guidance in 0.6.0

Open **Guides -> Professions** or `/octoguide professions`. All 14 professions
have an original skill-band baseline and trainer candidates, including Octo
Survival and Jewelcrafting. Profession settings/recipe observations live under
the existing per-character saved variables, separately from quest progress.

Choose **Fastest** or **Fast + cheap**, a target skill, and an extra-time allowance
(default 20%). Open the selected profession's normal recipe window to read the
actual learned recipes, current colors, reagent item IDs, quantities and tools.
Clear filters and expand headers for a broader comparison. The addon does not
change filters or claim it has seen hidden/unknown recipes. Enchanting uses the
Vanilla Craft API; Hunter pet training is rejected.

The next action is learn a profession, train the next rank, refresh recipes,
prepare materials, make one selected recipe, gather, or fish/skin in a suitable
area. It refreshes after recipe, skill, bag and relevant merchant changes. It
does not craft, purchase, gather, move, equip or trade automatically. Recipes
can be opened and tracking activated only through explicit button clicks.

## What the two choices mean

The comparison is **the next skill-up among currently visible learned recipes**,
not a globally optimal 1-300 route. For each candidate it estimates craft time
plus the time to obtain missing materials, divided by estimated skill-up chance.
Fast + cheap minimizes expected ingredient value among candidates
within the selected extra-time percentage of the fastest comparable candidate.

Use **Price / time** beside a reagent to enter copper and acquisition seconds
per item, including travel. Blank means unknown. Observed NPC buy prices supply
an alternative unit-price estimate; manually entered prices take precedence.
Vendor packs are divided by their quantity; extended-currency items are ignored.
Observed quotes are not proof of present stock or today's discounts. Owned bag
materials reduce immediate purchases. Fast + cheap separately considers ingredient
value, including owned materials and learned intermediates traced to raw materials.
It does not predict auction resale revenue. Bank contents are deliberately excluded.

Unmeasured cast duration defaults to 3 seconds and is labeled as an estimate.
A matching observed SPELLCAST_START duration replaces it. Orange/yellow/green
use 100%/50%/25% approximate probabilities; these are **not measured Octo rates**.
Gray recipes, cooldowns and missing required tools are excluded from a complete
time comparison. Unknown acquisition times/prices remain unknown. Incomplete
comparisons show a candidate with a visible limitation instead of inventing
an optimum. Make one at a time; actual skill/color changes refresh the advice.
No time estimate is invented for an unknown trainer trip or rank unlock.

Survival's cheap choice also explains woodcutting as a low-cash alternative
when craft materials are missing. Woodcutting skill-up/time is not measured,
so it is not falsely included as a quantified competitor to crafting.

Hardcore works without AH. NPC quotes, owned materials, gathering and permitted
trade are usable; this version does not import AH data or automate chat trading.

## Gathering and map guidance

**Leveling node** uses the selected gathering profession (or Survival trees).
**Sources -> Find gathering node** instead seeks the particular material, so
gray Copper can be useful for crafting while being unsuitable for Mining skill.
Ore/herb material IDs are mapped to resource families, including raw ore for
bars; custom wood is matched to exact wood names read from the client. Bundles
of sticks are not treated as raw wood. Skinning uses corpse/area guidance, and
Fishing explicitly permits safe open-water leveling rather than requiring pools.

OctoGather must be ready. Its hidden/missing node rules and skill requirements
are respected. Selection stays within the current named zone where supported,
then chooses nearest straight-line coordinates on the same world map. This is
not terrain pathfinding or a safety guarantee. Unknown ore cutoffs are excluded;
known Classic ore gray cutoffs and approximate herb cutoffs are baselines.
Survival uses Octo's latest available wood tier, not proven exact gray thresholds.
Known nodes are possible spawn locations, never live spawn guarantees.

**Find skill** activates learned Find Minerals/Find Herbs/Find Trees through
OctoGather. It can replace your current tracker. Nothing activates it on a timer.

**Sources -> Vendor locations** uses OctoBoard's faction-compatible database.
Trainer candidates use pfQuest names/coordinates; check the actual trainer's
services, books, character-level requirements and unlock quests before travel.
Candidates are not assertions that every named trainer teaches every rank.

Location clicks create an independently owned pfQuest map marker plus the
profession panel's direction arrow. They do not call pfQuest.route.SetTarget
or replace its quest target. Marker lifetime defaults to 120 seconds; the
**Flag** button selects 1/2/5 minutes for future selections. Expiry runs even
with the panel closed. Hidden/missing resource nodes cancel their target.
**Back to quests** removes this profession target and retains quest progress.

## Stable early Engineering stages

The 1-75 baseline uses powder toward 30, bolts toward 50, a missing spanner
for the next point, then Rough Copper Bombs toward 75. Powder/bolts needed by
those later bombs are reserved against unrelated consumers. Incomplete estimates
follow that stage; gray/unlearned recipes do not become invented skill-up advice.
Known cost/time inputs may compare eligible alternatives. Preparation targets
and skill-up quantities are estimates, not a global optimal 1-300 proof.

## Sources and provenance

- Twelve Classic profession baselines and trainer facts: https://www.wow-professions.com/classic
- Octo Survival: https://octowow.st/forum/viewtopic.php?p=8840
- Octo Jewelcrafting: https://octowow.st/forum/viewtopic.php?t=1664
- Octo Hardcore rules: https://octowow.st/challenges
- Installed OctoGather and pfQuest/pfQuest-turtle provide resource and NPC evidence.

Each profession stores its individual source URL in ProfessionData.lua and
shows it with **Guide source**. This is original concise advice plus factual
references; complete external guide prose and CraftRoute code/data are not
redistributed. Server-specific recipe identity/reagent/tool evidence is read
from the player's recipe window rather than copied from a different server.

## Verification boundary

Lua 5.0.3 tests cover the complete release TOC and actual callbacks, 14 metadata
entries, pricing/time choices, missing inputs, duplicate reagent identity,
gray/cooldown/tool exclusion, cache invalidation, Enchanting and pet-training
separation, gathering, tracking, quest return, source dialogs and marker expiry.
The installed pfQuest AddNode/GetNodes/DeleteNode and exact map-update queue are
exercised separately. Existing quest/navigation suites remain required.

These checks do not prove native in-game rendering, exact server skill-up
probabilities or a globally fastest profession route. After updating and
`/reload`, open the panel and a profession window, then test one node and one
trainer/vendor marker before relying on it during a leveling session.
