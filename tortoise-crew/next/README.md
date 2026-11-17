# Tortoise Crew Next — dedicated Windows app window

**Status: browser-engine desktop window built on the published v1.0.13 Node
launcher. Real WoW gameplay testing and the complete online addon catalog are
still outstanding. Keep the previous EXE backup for recovery.**

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
- Local addon imports, dependency reports, folder-name repair, script memory
  configuration, backups and rollback. Native client extensions are excluded.
  The existing online addon library and downloaded source-install workflow
  remain to port.
- A separate migration helper that stages the new application, performs a
  loopback UI probe, creates desktop/Start Menu shortcuts and restores originals
  after a failed migration. Default use is a dry run.
- The old EXE is retired only after verified authenticated game startup.
  User settings, backups and account vaults are preserved.

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

## Existing EXE update path

Version 1.0.13 was published after the exact GitHub-built transition EXE passed
Windows application control and migrated the first PC. It installs this local
Node backend and updates the desktop/start-menu shortcuts. The 1.0.13 bundle
predates the dedicated app-window mode; existing installs must receive the
updated Node source files once before this mode is available. The current Node
launcher does not yet contain a general-purpose self-updater.

No Defender/Smart App Control settings are changed. This is not a guarantee
that any future unsigned EXE would be accepted on other computers.

## Remaining release criteria

1. Verify real WoW login, realm entry, relay lifetime and graceful exit.
2. Port and test the full online addon discovery/download functionality.
3. Verify app window icon and end-to-end shortcut migration on each crew PC.
4. Implement versioned and authenticated Node bundle updates and rollback.
5. Add safe, authenticated, rollback-capable distribution for Node source
   updates to other PCs without rebuilding the native transition EXE.

The preview does not modify Altare or the live server.
