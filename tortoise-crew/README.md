# Tortoise Crew Launcher v1.0.3

One shared Windows launcher for MICHAEL, JAYKE, BERNARD and AUGUST.

**[Download v1.0.3 ZIP](./TortoiseCrewLauncher-v1.0.3.zip)** · Extract and run `TortoiseCrewLauncher.exe`. Existing v1.0.2 users can press **Update v1.0.3**.

## What's new

- Each player can save their own game-account password using **Account & Password**. Credentials are stored locally with Windows DPAPI; no passwords are sent to GitHub.
- When personal passwords are configured, the game's auto-login uses them instead of hard-coded `1`.
- To **change** a game-account password, use **Account & Password → Change my password using the in-game command**. Enter the current and new password (12–16 alphanumeric characters). The launcher copies the normal player command to the clipboard. Log in with your current password, paste the command into WoW chat, wait for server confirmation, then return to **Account & Password → Remember my existing account password** and save the new one. It is not changed merely by saving it in the launcher.
- Launcher still finds the exact approved WoW.exe, creates the desktop shortcut, connects using SSH, and closes the window while the background watcher retains the tunnel until WoW exits.
- GitHub manifest handles server routing and update verification using SHA-256.

## Important SSH security limitation

The Altare public SSH gateway was confirmed to ignore OpenSSH `authorized_keys` forced-command and `restrict` options. **Automatic public key enrollment is intentionally disabled in this release.** No shared SSH bootstrap credential is distributed in the EXE. Players without SSH access still need administrator-assisted provisioning until a properly isolated relay or service is deployed. Do not assume existing tunnel keys prevent remote shell access on Altare.

Current local logs: `%LOCALAPPDATA%\TortoiseCrewLauncher\launcher.log`.

Source code: [src](./src).
