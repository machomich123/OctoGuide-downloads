# OctoGuide 0.6.1

Professions now has its own sixth button on the main guide panel, beside
Expand and Settings. The control collapses with the other controls and preserves
the current quest when opening the profession panel.

Fixes misleading early Engineering recommendations that switched from Rough
Blasting Powder to shot/dynamite as the first one or two powder became available.
Source-backed 1-75 stages reserve powder/bolts for later Rough Copper Bombs.
Incomplete estimates follow the current stage; unknown required recipes show
training/refresh guidance. Actual learned recipe colors and tools still apply.

Fast + cheap now considers total ingredient value, including owned materials,
rather than only new cash purchases. Learned intermediate recipes are traced
back to raw materials and divided by their observed craft yield. Missing values
remain unknown; no global optimal 1-300 route is claimed. Complete input estimates
can compare eligible alternatives within the time allowance. Missing-material
cash spending is displayed separately from ingredient value.

Verified under Lua 5.0.3, including the user's exact 0/1/2 powder pattern in
both modes, intermediate valuation/yields, missing recipes/cycles and the actual
main button. Live in-game rendering and server leveling speed remain unmeasured.
