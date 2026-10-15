# OctoGuide 0.6.7

Reduces repeated panel rebuilds, pfQuest map resizing, NPC identity searches and stationary arrow-label writes. Live inventory/objective evidence, quest automation, delayed client-state checks and per-frame arrow rotation remain active. See [performance update and verification limits](UPDATE-0.6.7.md).

Adds a main-panel Professions button and stable early Engineering stages; owned/intermediate materials retain ingredient value in Fast + cheap. See [0.6.1 changes](UPDATE-0.6.1.md).

Adds all 14 profession guides, Fastest / Fast + cheap next-step advice, OctoGather material/skill navigation, trainer/vendor map locations and imagegen artwork. Open **Guides -> Professions** or /octoguide professions. Open the profession recipe window to read learned recipes. See [profession behavior and limitations](PROFESSIONS.md) and [release notes](UPDATE-0.6.0.md).

Fixes quest-giver navigation using unambiguous quest data and corrects the Rhinag destination. See UPDATE-0.5.21.md.

Fixes personal Hunter-task text appearing under ordinary quests. Class-only route eligibility is distinct from a class quest or unlock; see UPDATE-0.5.21.md.

Fixes the confirmed `/octocheck` error at UIPanelTemplates.lua:245 by giving its scroll frame the name required by the Vanilla template. Checks now report captured guide failures instead of only saying requirements are loaded. Includes protected startup from 0.5.18. The underlying cause of the blank 0.5.17 guide still requires the captured live failure. See [0.5.21 notes](UPDATE-0.5.21.md).

Startup and refresh failures now stop safely, hide partial panels, retain bounded error history and leave `/octoguide` diagnostics and `/octoguide hide` available. Close buttons hide their own frame. This protects against blocked empty windows; the precise cause of the reported live 0.5.17 failure has not been reproduced. See [0.5.18 notes](UPDATE-0.5.18.md).

Simple local walking/swimming directions can appear beneath the next quest instead of requiring a separate Done click. The island-swimming instruction is included in all four family variants, with its approach waypoint retained. Explicit route paths, cross-zone travel and actual transport remain separate. See [0.5.17 update notes](UPDATE-0.5.17.md).

Hornwood Recurve Bow vendor instructions now recognize the bow in bags or equipped, including repeated visits. Find step respects prior Done/Skip. Family Wild Hearts routes now include Lost Deathstalkers pickup and turn-in, matching OctoWoW's quest chain. See [0.5.16 update notes](UPDATE-0.5.16.md).

Recover earlier active unfinished quests before following a later saved cursor. Old automatic marks cannot hide the quest's unfinished work or ready turn-in; explicit Done/Skip and manual starting points remain user choices. See [0.5.15 update notes](UPDATE-0.5.15.md).

Automatically continues only after the specific skill requested by the guide is learned. Other trainer offerings are never added as requirements. Training steps with a spell ID display the actual spell and rank; generic visits without a specific goal remain manual. Keeps the reward-link fix from 0.5.13. See [0.5.14 update notes](UPDATE-0.5.14.md). Update through the launcher and use `/reload` to load the new addon code.

XP grind recommendations now appear as optional advice below the next quest. In **Settings â†’ Quest automation settings**, enable guide-only quest acceptance, turn-in or gear-aware reward selection independently. All three default OFF. Hold Shift for manual control. Reward selection compares class leveling stats against worn and bag gear, then uses total vendor value when no upgrade exists. Missing data or uncertain equipment stays manual; items are never equipped or sold. See [update notes](UPDATE-0.5.12.md) and [research/limitations](QUEST-AUTOMATION-RESEARCH.md).

Horde leveling guidance for OctoWoW / WoW 1.12.1. Normal and Hardcore remain separate choices. The original Vanilla Questing baseline is retained with its MIT notices and saved progress.

## New behavior

- Concurrent quest objectives appear together, each with its own observed progress.
- Personal class unlocks remain individual when playing in a party.
- Settings offers Auto / Solo / Group. Auto follows the current party.
- Guides are sorted by level; use Current level / All, or `/octoguide level 10` for a chosen level.
- Long written instructions remain available in a bounded, scrollable area.
- Pinch of Salt, Trader's Misfortune and Zalazane's Fall are optional OctoWoW additions attached to existing visits. Skip an absent target rather than wait indefinitely. Confirmed quest history gates the Zalazane prerequisite.

## Installation

This update uses the ClassicAPI capabilities already installed with your client. Update OctoGuide through the existing GitHub link in the launcher or mod tab; no EXE, manual DLL update or separate setup is required. pfQuest / pfMap remain recommended for map integration. Enable only one runtime: OctoGuide or OctoGuide-downloads.

Launcher users update OctoGuide-downloads through the same configured GitHub link. `/octoguide check` reports detected quest support and whether the family route pack is loaded. There is one main guide source: RestedXP when installed, otherwise the bundled fallback. OctoGuide remains free. Find step now scans available character information and waits for supported quest-history replies; guide selection opens a clickable step list with **Skip to step**. See [0.5.7 changes and limits](UPDATE-0.5.7.md).

## Family pack

The private family package adds the user's supplied RestedXP Classic / Survival routes as the primary source. The public launcher repository does not distribute the paid guide prose. The standalone OctoGuideFamily addon can be installed alongside either runtime and survives runtime updates. Extract its folder into Interface/AddOns, enable it, and restart the client. It uses optional dependency ordering for both runtime names.

## Verification boundary

Automated checks run under Lua 5.0.3 with mocked client APIs. They are evidence of source behavior and packaging, not an in-game performance measurement. Native OctoWoW loading, server interactions, XP rates, combat risk and UI rendering still need a short gameplay check. No leveling run to 60 was performed or required for this source comparison.
