# Launcher 1.0.12

- Addon import selects a single Vanilla/Turtle manifest rather than the first TOC in filesystem order. TBC-only and ambiguous packages are rejected before changing installed addons.
- New **Repair addons** button under Addons: repairs canonical folder names, sets Script Memory to unlimited, saves the original Config.wtf plus a rename record under WTF/CrewRepair-*, and checks remaining declared dependencies.
- Repair preserves saved variables and profiles. Conflicting targets, linked addons and incompatible packages are reported without overwriting them. Completed renames are rolled back if the configuration commit fails.
- Clarifies that client DLLs/MPQs are inventoried for review, not installed, and that Scan clients does not import profiles or memory settings.
- Normal WoW process startup retained. No injected DLL, loader, password typing or Windows protection changes. See AUTOLOGIN-RESEARCH.md for instant-login findings and signing requirements.

After updating: close WoW, open Addons, choose Repair addons, review the result, then start WoW. In-game verification is still required; automated tests do not prove the appearance or behaviour of every installed addon.
