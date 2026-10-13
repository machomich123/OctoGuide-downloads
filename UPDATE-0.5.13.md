# OctoGuide 0.5.13

- Fix automatic reward choice failing with `QuestAutomation.lua:72: Unknown link type`. Vanilla tooltips now receive the raw item payload instead of the colored chat link, preserving enchant/random-suffix data. Unsupported tooltip data stays manual without breaking the addon.
- Continue training steps automatically after the relevant spell/skill is actually learned. Listen to spellbook, skill, trainer and crafting updates; support manual-authored spell-ID steps, learned professions/recipes and higher spell ranks. Already-known exact skills reconcile immediately.
- Generic class-training visits finish after all initially trainable services have been learned. Opening/closing the trainer, a partial or rejected purchase and changing the trainer filters do not count as learning. Back review remains fixed.
- Keep auto accept/turn-in and their existing settings. Auto reward remains OFF by default.

Reproduced the reported error using the 0.5.12 reward module and Vanilla-style colored links. The regression passes with this release. Verified with 18 Lua 5.0.3 test suites and complete release-manifest callbacks. The user's in-game report confirms 0.5.12 auto accept/turn-in; the reward fix and training continuation still need live in-game confirmation.

Update OctoGuide-downloads in the launcher, then `/reload` in-game to load the new addon code.
