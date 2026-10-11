# OctoGuide 0.5.1

Buttons now use fixed endcaps and a plain center instead of stretching the decorative art across the whole button. The same treatment is used in the guide, Guides, Settings and report form.

Minimal view hides the logo, title, version and route header. A small bottom arrow expands or collapses the controls; the close button is at the upper left. The main action is Skip for automatically tracked quest steps or optional supplies, and Done for manual tasks. A separate recovery action, Skip current step, is available in Guides. Guides and Settings can be dragged and their positions are saved per character. Both navigation arrows are 25% larger.

Existing RestedXP route packs are normalized when loaded. Matching supply collection and vendor actions in one source block become one visit, without changing stable progress IDs. Ordinary food/drink purchases are marked optional; quest-associated collection remains required. Generic collect directives are given readable titles.

Both arrows prefer read-only observations and label database fallbacks as possible spawns or quest areas. The optional ClassicAPI update adds enumeration of currently loaded living creatures and a sleeping-state filter for Lazy Peons. Objects are observed client objects; this does not establish that every object is interactable. Unloaded targets cannot be confirmed alive.

## Bug reports

With the updated ClassicAPI: Settings → Report bug → describe the problem → Send. Visible OctoGuide windows are cropped before the report form opens. PNG encoding and HTTPS upload happen on a background thread. Closed windows have structured UI snapshots rather than fabricated screenshots. Character race/class/level, route, objectives, settings, recent addon events and OctoGuide errors are included; account credentials and chat logs are not collected.

Reports are stored privately in the owner's Cloudflare D1 database, not in a public GitHub folder. The public service has no report-reading endpoint. Success is shown only after a confirmed server receipt. A failed send leaves the diagnostic report locally in per-character SavedVariables. SavedVariables are flushed by logout or reload; captured pixel data is not persisted locally across restart. Reports expire after 30 days; bounded intake protects storage.

## Updating

Launcher update installs the Lua/UI changes. For living-unit enumeration, UI screenshots and background upload, update the existing ClassicAPI once. The updated existing RestedXP installer includes this DLL update, preserves the original DLL and addons in AddonBackups, and checks the supported WoW.exe before replacing a native component. Exit WoW before running it. It does not create a resident helper application. The standalone native ZIP is also available in the public release.

ClassicAPI must already be enabled through VanillaFixes/dlls.txt. The extension targets the verified OctoWoW 1.12 client (WoW.exe SHA-256 183cd1128bcb9fa7d1bc7b3eaaa3ab384f71fdaadfa1be3ad8d458e93587d4bd). It is an optional integration fork; it is not an upstream ClassicAPI release.

## Verification

The release manifest and runtime suites, actual RestedXP supply block, per-character route chains, 60 simulated resize combinations and native offline rendering are checked. The separate native client exercises 40 resize cases. Real UI crops have been sent from that client and decoded after retrieval from the private online store. The native liveness predicate checks living/dead/sleeping states in compiled tests. No logged-in world session was used: observation of real mobs and general stability in gameplay remain to be confirmed by the family testers.
