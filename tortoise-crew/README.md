# Tortoise Crew Launcher v1.0.1

Download [TortoiseCrewLauncher-v1.0.1.zip](./TortoiseCrewLauncher-v1.0.1.zip), extract, and run the EXE. Windows 10/11 with built-in OpenSSH Client required. The launcher installs per-user and creates a desktop shortcut. No console window is shown during gameplay.

1. Choose your account: MICHAEL, JAYKE, BERNARD, or AUGUST. Each player has their own Windows installation and SSH private key; never share it.
2. The launcher scans for the exact verified WoW 1.18.1 build 7272 executable. It prefers the Tortoise/Turtle client folder over a modified Octo client. If not found, browse to WoW.exe manually.
3. Open **Settings → Copy public SSH key** and send only the public key to the server administrator. Approval is required once per machine before **Play** works.
4. Press **Play**. Login is attempted once by typing only the shared password into WoW's normally focused password field; the username is prefilled using WTF/Config.wtf. Automatic login has not yet been verified interactively on every Windows/game configuration; uncheck auto-login if it misbehaves.
5. Use **Update** when a new launcher version is shown. The launcher fetches the public manifest and verifies SHA-256 before replacing itself. The Altare host and port values are synced automatically from the manifest when available.

**Troubleshooting:** Log is stored in `%LOCALAPPDATA%\TortoiseCrewLauncher\launcher.log`. If auto-login types into the wrong field, disable auto-login in the launcher and report the issue; nothing is injected into or patched in WoW.exe. The existing WoW game folder is backed up before changes to `realmlist.wtf` and `WTF\Config.wtf`.

**Security:** The current shared game password is weak. SSH restricts the exposed game ports, but unique passwords per game account should be configured when convenient.

Source: [src](./src).
