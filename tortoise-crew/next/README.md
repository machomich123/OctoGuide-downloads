# Tortoise Crew Next — dedicated Windows app window

**Version 0.2.1:** Fit-to-window realm screen, scrollable addon list, Turtle
catalog (894 entries, of which 882 are directly installable GitHub repositories),
safe repository ZIP installation, local import/repair, GitHub source updates,
recovery backups and hidden Windows startup. Real realm login still requires
a person to test in-game. Keep the v1.0.11 recovery EXE.

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
  manual installation; full README screenshot rendering is not yet ported.
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

The original v1.0.13 EXE update button does not update Node code. Publishing a
new ZIP alone does not make older v1.0.13 installations self-updating until
they have completed the one-time migration.

No Defender/Smart App Control settings are changed. This is not a guarantee
that any future unsigned EXE would be accepted on other computers.

## Remaining release criteria

1. Verify real WoW login, realm entry, relay lifetime and graceful exit.
2. Verify first-run migration and browser host policy on JAYKE, BERNARD and
   AUGUST's own Windows machines; a successful test on one PC does not certify
   the others.
3. Add automated dependency resolution and rendered README screenshots in
   addon details, if desired.
4. Keep the update manifest/source packages protected against accidental
   source changes; no promise that all unsigned executables are accepted.

The preview does not modify Altare or the live server.
