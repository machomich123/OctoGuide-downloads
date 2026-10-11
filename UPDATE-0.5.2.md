# OctoGuide 0.5.2

Fix guide layout regressions: compact buttons use a clear text surface; close is larger and at the upper right; route mode moves to Settings; the centered bottom toggle removes the hidden controls and their height. Old surplus height is reset once and manual heights are bounded by the viewport. No secondary-arrow space is reserved when there is no secondary target.

Upcoming previews omit quests already tracked concurrently and do not repeat their alongside instructions. Preview rows are limited to the available screen height. Duplicate RestedXP use directives in the same source block as a tracked quest objective are folded into that objective without changing stable IDs. Remaining generic use directives receive readable item instructions. The overlapping decorative bug icon is removed from the report button.

This is an addon-only update through the launcher. No ClassicAPI update is required for these fixes. Native report capture/upload and live target accuracy are explicitly deferred to a later investigation.

Verification: Lua 5.0 runtime and regression checks, release manifest load and isolated native client rendering/resize checks. No logged-in gameplay session was used.
