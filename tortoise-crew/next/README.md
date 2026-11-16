# Tortoise Crew Next — isolated Windows launcher preview

**Status: prototype only. Do not activate the legacy EXE update manifest or delete v1.0.11.**

This is a new browser interface and local Node.js backend, intended to reduce
the need for a different unsigned Windows EXE whenever addon/UI code changes.

## Implemented and locally tested

- Local browser UI bound to 127.0.0.1 with a randomly generated session token,
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

## Blocker: updating via the existing EXE

Version 1.0.11 downloads one fixed EXE path, verifies the expected SHA-256 and
starts it with the --replace argument. It cannot directly install a Node bundle
or update Windows shortcuts. A compatible transition EXE must first be tested
on the affected PC with Smart App Control unchanged. The 1.0.12 EXE was blocked.
Local development and Windows CI success do not establish acceptance of an
EXE downloaded and run through the existing launcher.

Therefore public automatic updates remain paused. The manifest retains
updatesPaused=true. Neither Defender nor Smart App Control is disabled, no
Microsoft submission occurs and no signing purchase is required.

## Remaining release criteria

1. Verify real WoW login, realm entry, relay lifetime and graceful exit.
2. Port and test the full online addon discovery/download functionality.
3. Verify shortcut migration, icon and rollback in a disposable Windows user.
4. Implement versioned and authenticated Node bundle updates and rollback.
5. Build a transition EXE accepted by the existing --replace protocol and
   Windows application-control policy.
6. Test that exact fetched artifact on the affected PC, then and only then
   activate the production update manifest for v1.0.11 users.

The preview does not modify Altare or the live server.
