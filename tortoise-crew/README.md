# Tortoise Crew Launcher v1.0.2

A shared Windows launcher for MICHAEL, JAYKE, BERNARD, and AUGUST.

**[Download v1.0.2 ZIP](./TortoiseCrewLauncher-v1.0.2.zip)** · Extract and run the enclosed `TortoiseCrewLauncher.exe`.

## What's new in 1.0.2

- Faster auto-login: the verified WoW window is focused shortly after it becomes visible, with a ~400ms settling delay instead of the previous fixed 4.5-second delay. Username is prefilled from WoW config; only the password is typed once.
- Automatic launcher exit: when WoW starts, a hidden watcher takes over the SSH process. The window then closes. The watcher closes the tunnel only after WoW exits, verified by a Windows integration test.
- Safer self-update: downloads are SHA-256 verified, the replacement runs in a separate invisible helper, and the previous installed EXE is preserved as an NTFS backup. Updates are blocked while WoW is running.
- Supports existing v1.0.1's two-argument update protocol, so existing users can upgrade using their **Update** button. The first upgrade still invokes the old v1.0.1 update implementation.

## Setup

1. Run the EXE. It installs to `%LOCALAPPDATA%\TortoiseCrewLauncher` and creates a desktop shortcut.
2. Choose MICHAEL, JAYKE, BERNARD, or AUGUST. Find or browse to the exact verified WoW 1.18.1 build 7272 executable in a compatible Turtle/Tortoise client folder; Octo client assets are known to cause graphic issues.
3. Each new PC generates its own OpenSSH Ed25519 key. Use **Settings → Copy public SSH key** and send only the public key to the server administrator for one-time approval. Never share private keys.
4. Click **Play**. A private SSH tunnel connects to Altare; the launcher closes when the game starts, with the background watcher monitoring the connection.
5. New versions and changing Altare ports are discovered from the public `manifest.json`. Press **Update** and confirm to upgrade.

If autologin is unreliable on a specific PC, disable it in the launcher. It does not modify or inject into WoW.exe. Log: `%LOCALAPPDATA%\TortoiseCrewLauncher\launcher.log`.

**Security:** All game accounts currently share the weak password `1`; use distinct stronger game passwords when feasible. Public SSH keys grant port-restricted access only after approval.
