# Tortoise Crew Launcher v1.0.4

One Windows launcher for **MICHAEL, JAYKE, BERNARD and AUGUST**.

## First-time setup and play

1. Run `TortoiseCrewLauncher.exe`. Existing installations detect the update through the verified GitHub manifest.
2. Select your WoW account and locate the approved WoW.exe if it is not found automatically.
3. The first time on each PC, enter the account's *existing* game password (currently `1` unless you changed it).
4. Press **Play**. The launcher authenticates to the private Crew HTTPS service, starts local 3724/8085 game relays over TLS-protected WebSockets, configures WoW, and signs in with your locally encrypted personal password. No SSH key needs to be sent to Michael.

## Account and player status

- **Change password** directly below the account selector asks for current, new, and confirmation. Press **Done** to update the live server and then the local encrypted Windows DPAPI password vault. No in-game chat commands or arbitrary complexity rules. Vanilla WoW supports passwords of 1–16 printable characters.
- The sidebar shows **Online / Offline** from live realm account state for Michael, Jayke, Bernard and August. An unreachable backend shows **Unknown** rather than incorrectly showing Offline.
- The former per-PC SSH tunnel is retained in source as a legacy fallback for installations using older routing. Bernard's existing SSH key is not deleted or replaced by this update.

## Preview service and operational limitation

The initial Crew HTTPS endpoint uses a free **Cloudflare Quick Tunnel**, which has **no uptime guarantee and changes address whenever cloudflared restarts**. It is a functional early-access test, not a permanent hosted production endpoint. The launcher reads the current endpoint from the GitHub manifest at startup; if it changes, the manifest must be updated before users can reconnect. To make it reliably plug-and-play across restarts, provision a **named Cloudflare Tunnel** or another persistent HTTPS hostname.

Current local logs: `%LOCALAPPDATA%\TortoiseCrewLauncher\launcher.log`.

Source: [src](./src). The previous validated v1.0.3 binary is retained in this repository and private ops artifacts for recovery.
