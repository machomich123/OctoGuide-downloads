# Deferred: Missing dependencies / Repair addons report false success

Status: DEFERRED — documented at the user's request on 2026-11-17. Do not implement or release this launcher change as part of the local client repair. Revisit when dependency detection, addon import/repair, or native DLL startup is next changed.

## Observed in Crew Next 0.3.7

- pfUI 8.3.0 reports `Nampower Not Found`, requiring Nampower >= 3.0.
- pfUI `libs/libcast.lua:68` and `modules/castbar.lua:113` call missing `GetUnitGUID`.
- Missing dependencies reports `{ "missing": [] }`.
- Repair addons reports `renamed: 0`, `warnings: []`, `missingDependencies: []` and `repair completed`.
- Nampower 4.6.2 is already on disk, but `dlls.txt` contains only `ClassicAPI.dll`. Historical Nampower logs show successful initialization on November 13; current November 17 execution has no new Nampower initialization.
- Scanning 39 installed addon TOCs and recursively reachable XML manifests also finds three missing file references: pfUI `skins/blizzard/custom_merchant.lua`, pfUI `skins/blizzard/arena_score.lua`, Bagshui `Components/Ui.Skin.lua`. Required addon metadata alone does not reveal these.

## Diagnosis and scope

`next/src/addons.mjs::missingDependencies` examines required addon metadata and folder names. It does not check native capabilities, DLL activation, DLL versions, recursive TOC/XML file integrity, or runtime API availability. An empty list only means no missing declared addon names were found; it is not proof of a healthy installation.

Earlier launcher native setup wrote a ClassicAPI-only DLL list. Current native setup inspected on November 17 already preserves existing DLL entries when appending ClassicAPI. Do not regress that behavior or claim that the current implementation necessarily caused this existing installation state. Historical crash isolation also moved client components aside: restoration must be selective, with backups and compatibility checks.

## Local workaround performed separately

Backed up the three edited files; preserved ClassicAPI and appended the already installed `nampower.dll` to the loader list. Removed the three broken XML Include references (no replacement implementations fabricated). No launcher code or release changed. Static rescan: 39 addons, 83 manifests, 1007 file references; no unresolved traversed file references or declared required addons. Core PE/header checks and 22 MPQ header checks passed. This is not a gameplay test, a complete MPQ integrity check, or confirmation that Nampower initialized in a new session.

## Proposed future work / acceptance criteria

1. Distinguish missing addon, missing referenced file, missing native DLL, installed-but-disabled DLL, unsupported version/client, and unverified runtime API.
2. Maintain reviewed capability requirements for integrations such as this pfUI fork / Nampower instead of assuming all native requirements are expressed in TOCs. Never download or enable every DLL found on disk.
3. Recursively validate active TOC/XML references with comment handling, case-insensitive Windows paths, cycle detection, path containment, and built-in/MPQ resource awareness.
4. Verify configured game path, DLL list, loader usage and supported native versions. Use fresh logs or an in-game probe to distinguish disk presence from actual API registration (`GetNampowerVersion`, `GetUnitGUID`).
5. Repair should explain exactly what it checked and changed; `renamed: 0` must not imply full repair. Return unresolved warnings explicitly, support preview, preserve existing DLL entries/preferences, back up changes and refuse edits while WoW is running.
6. Add focused regression cases for installed-but-disabled Nampower, missing required addon, missing nested Lua include, absent/old native component, already-correct installation, preserved ClassicAPI/other entries, crash-isolated native components, and rollback.
7. Keep this deferred until the user requests launcher implementation; do not conflate local remediation with a shipped fix.

## Discoverability

Issues were disabled in this repository when recorded. This tracked backlog file is the durable GitHub record. Search for `Nampower`, `GetUnitGUID`, `missingDependencies`, `Missing dependencies`, `Repair addons`, or `DEFERRED` to find it.
