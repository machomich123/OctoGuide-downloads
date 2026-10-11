# OctoGuide 0.5.4

- Lazy Peons uses its sleep aura (17743), rather than requiring a particular standing animation. Explicit targetAura requirements are reusable for other use-item quests. Legacy stand-state fallback is used only when aura reads are unavailable.
- Nearby eligible targets retain a small distance tolerance to avoid rapid switching; invalid targets are rechecked and discarded.
- Secondary navigation textures and text belong to the current-objective card overlay. Background opacity does not dim navigation labels.
- Dedicated imagegen controls: complete framed close and footer chevrons, and a circular slider grip. Preserved high-resolution original; uniform reductions, no stretched borders.
- Close control placed inside header; minimal view leaves space for its control. Internal ClassicAPI/report status notice removed from Settings.

Delivery: existing GitHub launcher/mod workflow. No new executable or required DLL update. Reporting transport remains unchanged.

Validation: 27 automated suites including full route hygiene and Hardcore auction exclusions. Offline native client rendered actual UI sources and passed 40 resize cases. World behavior of sleeping peons still requires gameplay confirmation; synthetic checks do not prove server behavior.

Reference: https://github.com/vmangos/core/blob/development/src/scripts/kalimdor/durotar/durotar.cpp
