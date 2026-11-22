# Tortoise Crew Next — dedicated Windows app window

**Version 0.3.12:** Shows actual installed addon versions from TOC metadata,
compares known installed and available versions in the addon catalog, and
displays unknown versions explicitly instead of confusing WoW interface
compatibility with addon versions. The inactive "Up to date" button uses a
normal cursor rather than suggesting that an update is still in progress.

**Version 0.3.11:** Extends prepared WoW handoff to 90 seconds for slower
native clients; bundled Party Inventory 2026.11.22.6 adds responsive ALT bag
previews and authoritative GUID resolution, item-quality and quest displays.
Local previews are rolled back when server verification disagrees. The server
must also be updated before new protocol features work in production.

**Version 0.3.10:** Includes the independently tested TBM Party Inventory
addon in Discover and a signed-hash-verified GitHub install/update path.
The loader preserves a locally edited addon and attempts non-blocking managed
updates before Play. This release retains the 0.3.9 direct pinned TLS
connection and prepared-login behavior.

**Version 0.3.6:** Fit-to-window realm screen, scrollable addon list, Turtle
catalog (894 entries, of which 882 are directly installable GitHub repositories),
safe repository ZIP installation, local import/repair, GitHub source updates,
recovery backups and hidden Windows startup. Real character-selection login has been tested on Windows. Keep the v1.0.11 recovery EXE.

This is a dedicated Edge/Chrome app window and local Node.js backend, intended
to reduce the need for a different unsigned Windows EXE whenever addon/UI code
changes. It is **not a fully native Win32 app**, but it has its own window with
no browser tabs or address bar, independent of the system default browser.

## Implemented and locally tested

- Dedicated Microsoft Edge/Chrome app window, launched automatically from the
  existing desktop shortcut, with no browser tabs, address bar, dependency on
  the default browser, or newly compiled Windows EXE. This is a browser-engine
  app window, not a native Win32 UI, and needs Edge or Chrome installed.
- Local browser-engine UI bound to 127.0.0.1 with a randomly generated session token,
  request-origin verification, strict CSP and constrained backend actions.
- Read-only migration of legacy settings. Existing DPAPI credentials are not
  decrypted or copied automatically. New data lives in a separate directory
  under %LOCALAPPDATA%/TortoiseCrewNext.
- Four accounts, Crew HTTPS authentication, status/presence, encrypted
  per-Windows-user passwords and password change.
- Build-7272 WoW executable verification, ordinary game start and local TCP
  3724/8085 bridge over TLS WebSockets. A real WoW login and realm session
  remain unverified.
- Turtle WoW registry (GitHub/GitLab), GitHub search, names, descriptions,
  search and sort, installed addons, packs, local client discovery and import.
  GitHub repositories with usable Vanilla/Turtle TOC files can be installed
  directly from checked ZIP archives. Saved addons are backed up, native DLL,
  EXE and MPQ patches are never activated. GitLab entries are listed but not
  directly downloadable. Missing dependencies can be viewed but still require
  manual installation. Details now show GitHub README text, license, project
  metadata and all supported README images in a scrollable gallery.
- Remember/use-saved-password and close-on-play preferences persist separately
  for each of the four accounts. Passwords remain encrypted via Windows DPAPI.
- After launching WoW, the dedicated launcher window closes; Node and the
  authenticated game relay continue running until WoW exits.
- Automatic game login, on by default and optional per account: the launcher
  authenticates through Crew HTTPS, launches the original WoW.exe and waits
  for its exact process to own the foreground window. It preserves the
  remembered account name so Vanilla/Octo GlueXML can focus the password
  field; the Windows-hosted helper enters only the password and presses Enter.
  Passwords travel only through the helper's stdin, never command-line
  arguments, the clipboard, Config.wtf or launcher logs. If the window is not
  safely focused, manual login remains. Windows may hide WoW's executable
  path, so the helper permits an unreadable path for its verified child PID
  while still checking the process name and foreground window ownership.
  No VanillaFixes, ClassicAPI, MPQ patch or new unsigned EXE is necessary.
- Faster auto-login: use supported Windows foreground APIs with a short,
  bounded focus retry before relying on the old AppActivate fallback. The
  helper no longer sleeps 4.7 seconds after WoW first displays its window;
  it checks input readiness and allows the GlueXML interface a shorter
  settling interval. Password + Enter are sent in one escaped SendKeys batch,
  instead of one blocking SendWait call for every character. It still refuses
  to type if the game does not own the active window. Windows can refuse
  foreground activation depending on its focus policy; a click may still be
  necessary in that case. No changes to security policy are made.
- v0.3.6 now authenticates to the real WoW realm in the launcher. Once the
  client has supplied its exact addon metadata on its first launch, later
  launches also prefetch the live character list before Play. No WoW process
  starts before Play. A loopback SRP frontend hands the visible client to the
  prepared world session and translates encrypted packet headers in both
  directions. Addon metadata is preserved unchanged; no server restart or
  authentication bypass is used.
- The old off-screen guardian and 27-second reveal timeout are removed from
  the startup path. The unused login scene is suppressed in GlueXML; the
  normal WoW window starts visibly and receives foreground focus as soon as
  its window exists. There is no branded cover or delayed window reveal.
- Supported clients automatically obtain SHA-256-pinned ClassicAPI 1.15.16
  and VanillaFixes 1.5.3 if missing. Unknown existing modules are preserved.
  Existing dlls.txt entries are preserved and restored on integration removal.
  VanillaFixes retains its ordinary first-use DLL consent. Secrets are kept
  in Windows-protected storage and live session keys stay in memory.
- See INSTANT-LOGIN-0.3.6.md for protocol details and actual Windows validation.
- A separate migration helper that stages the new application, performs a
  loopback UI probe, creates desktop/Start Menu shortcuts and restores originals
  after a failed migration. Default use is a dry run.
- Permanent bootstrap outside the app folder, which checks a versioned source
  release on GitHub before opening the app, verifies SHA-256, health-probes new
  files, atomically swaps app directories and rolls back on failed startup.
  It reuses an already-open app session rather than spawning another backend.
  User settings, backups and account vaults are preserved.
- Hidden startup through Microsoft-signed wscript.exe; no flash of node.exe's
  console should be visible. If Windows blocks Script Host, restore the saved
  shortcut to the existing Node entrypoint rather than changing security policy.

## Development

Requires Windows 11 and official Node.js 26.

1. Change directory to tortoise-crew/next.
2. Run: node --test test/*.test.mjs
3. Run: node src/main.mjs --health-probe
4. Run: node src/main.mjs

To inspect the planned shortcut migration without changing any files:
node src/migrate.mjs

The separate --apply switch is intended only for a disposable Windows test
installation at this stage. Do not run it on the working v1.0.11 installation.

## Existing EXE update path and onboarding all four crew accounts

Version 1.0.13 was published after the exact GitHub-built transition EXE passed
Windows application control and migrated the first PC. It installs this local
Node backend and updates the desktop/start-menu shortcuts. The 1.0.13 bundle
predates this version and does not have the new source updater. MICHAEL,
JAYKE, BERNARD and AUGUST who have already received the old Node app need a
one-time migration via install-once.mjs. The installer requires that the existing
v1.0.13 Node launcher is installed (with Node 26), downloads versioned source
from this repository, checks SHA-256, keeps an app backup and creates hidden
desktop/Start Menu shortcuts.

After onboarding, new releases are distributed as:

1. Edit source and increase package.json version.
2. Generate crew-next-<version>.zip and update.json through
   scripts/Prepare-Next-Update.ps1 (or equivalent release tooling).
3. Commit the matching package and manifest after Windows CI passes.
4. Each crew member clicks the shortcut: bootstrap downloads and validates a
   new package before launch. If Node is already running, use the Settings
   **Restart & apply updates** button to close it first.
5. A rollback backup remains under %LOCALAPPDATA%\TortoiseCrewNext\backups.

The old v1.0.13 Node application cannot update its own source. Users already
on that version must run TortoiseCrew-Upgrade.cmd once. The newer v1.0.14 EXE
transition is designed to install this version directly when launched through
the legacy EXE update button, conditional on Windows accepting the GitHub-built
file. Publishing a Node ZIP alone cannot upgrade older clients lacking an updater.

No Defender/Smart App Control settings are changed. This is not a guarantee
that any future unsigned EXE would be accepted on other computers.

## Remaining release criteria

1. Verify auto-login in a real WoW 1.18.1 session, realm entry and relay
   lifetime on each family PC. Automated tests validate helper launch,
   Windows policy acceptance, input-focus checks and config changes, but
   do not prove credentials were accepted by a live game instance.
2. Verify first-run migration and browser host policy on JAYKE, BERNARD and
   AUGUST's own Windows machines; a successful test on one PC does not certify
   the others.
3. Add automated dependency resolution and improve README formatting in
   addon details, if desired.
4. Keep the update manifest/source packages protected against accidental
   source changes; no promise that all unsigned executables are accepted.

The preview does not modify Altare or the live server.
