# OctoGuide 0.5.10

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
