# Tortoise Crew Launcher v1.0.9 (source candidate; not released)

One Windows launcher for **MICHAEL, JAYKE, BERNARD and AUGUST**.

**Downloads and automatic launcher updates are paused.** The existing public EXE is the withdrawn, unsigned v1.0.8; do not install it as a fix for Windows Smart App Control. The v1.0.9 source is a release candidate, not a signed public release. Server routing remains available through the manifest.

v1.0.9 reads the version from the compiled assembly (v1.0.8 incorrectly reported v1.0.6), treats 1.0.9 and 1.0.9.0 equally, verifies Authenticode trust as well as SHA-256 before updating, waits for the old process/file to close, and serializes desktop launches with installation. Reopening the desktop shortcut activates the existing launcher. An updater records success only after the new process opens a window. Errors keep their actual cause instead of reporting every install failure as a GitHub outage.

The manifest deliberately advertises `0.0.0` while `updatesPaused` is true: older launchers do not understand the pause flag but also never offer a lower version. This does not downgrade an installed launcher. The EXE checksum is retained for traceability; it is not an installation recommendation.

## Signed release setup

Windows Smart App Control accepted earlier builds but blocked the v1.0.8 pending update on one PC. A successful compile, GitHub commit signature, SHA-256 match, or a self-signed certificate does not establish Windows publisher trust. No release can promise acceptance under every administrator policy or antivirus product.

The build workflow compiles and runs regression tests without publishing its unsigned artifact. To enable public releases, the project owner must provision a trusted signing service. MIT-licensed open-source projects may apply to the [SignPath Foundation](https://signpath.org/); acceptance is external and not automatic. A traditional Windows-trusted code-signing provider is another option. See [Microsoft's signing options](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options).

The workflow supports SignPath once the owner has configured its GitHub connector, an EXE artifact configuration, and signing policy. Add repository variables `SIGNPATH_ORGANIZATION_ID`, `SIGNPATH_PROJECT_SLUG`, `SIGNPATH_SIGNING_POLICY_SLUG`, and secret `SIGNPATH_API_TOKEN` through the provider's normal account setup. Do not commit keys or tokens. The signed artifact must include an embedded, timestamped, Windows-trusted code-signing signature. `scripts/Prepare-Release.ps1` verifies this before changing the public EXE or manifest. Only a successful signed release restores the advertised version to 1.0.9 and unpauses updates.

For local builds, use `scripts/Build.ps1 -Compiler <Roslyn-csc.exe>` and `scripts/Test.ps1`. Do not install or distribute the unsigned `out` artifact on Smart App Control-protected machines. After signing through a trusted provider, `scripts/Prepare-Release.ps1 -Executable <signed-exe>` prepares the EXE/manifest pair for one atomic Git commit. Local tests cover versions, concurrent launch ownership, unsigned-file rejection, a valid embedded signature, tamper detection, and addon migration.

## First-time setup and play

1. Run `TortoiseCrewLauncher.exe`. Existing installations detect the update through the verified GitHub manifest.
2. Select your WoW account and locate the approved WoW.exe if it is not found automatically.
3. The first time on each PC, enter the account's *existing* game password.
4. Press **Play**. The launcher authenticates to the private Crew HTTPS service, starts local 3724/8085 game relays over TLS-protected WebSockets, configures WoW, and signs in with your locally encrypted personal password. No SSH key needs to be sent to Michael.


## Addon Library (v1.0.6)

**Maintenance update:** filenames such as `!OctoScope.toc` are now accepted, while traversal and reserved Windows names remain blocked. GitHub README details render as readable headings, paragraphs and clickable image thumbnails rather than raw Markdown. The Discover page supports 6–500 cards per page, filtering and sorting by stars, name, recency and download count where published. Most GitHub addons do not expose a reliable total-download figure, so unavailable download counts are not fabricated. Local addon/DLL/MPQ import now reports skipped files explicitly, preserves unique backups and can be tested without writing to a real WoW install.

Open **ADDONS** in the left sidebar; use **BACK TO REALM** to return to the game page.

- **Discover:** browse the community Turtle WoW add-on registry (approximately 894 records, maintained by [turtlectl](https://github.com/bnema/turtlectl)) or choose **GitHub search** and press Enter. Every entry has quick **Install** and **Details** buttons; details show the repository README and screenshots.
- **Addon sites:** shortcuts to Turtle WoW Wiki, GitHub, OctoWoW modding, Legacy WoW and CurseForge. External sources open in the browser; only supported GitHub repositories install automatically.
- **Installed:** review installed AddOns and any declared missing required dependencies. Existing WTF settings are untouched.
- **Packs & DLLs:** import visual patches, locally installed Comfy Atmosphere/HD packs, recognized compatible client DLLs, dlls.txt, and VanillaFixes from a previous game folder or extracted patch collection.
- **Scan clients:** locate previous WoW/OctoWoW folders, select the source, and choose whether to import client modifications alongside Lua addons. The scanner excludes the active client.
- **Safety:** online GitHub installations extract only .toc addons, enforce archive limits, prevent ZIP path traversal, and back up existing addon directories. Local DLL/MPQ import requires confirmation and a closed game. Importing incompatible patches may cause crashes.
- **HD Switch note:** [OctoWoW HD Switch](https://github.com/fmustafayaman/OctoWoW-HD-Switch) is specific to the OctoWoW realm and **not guaranteed to function on the private Tortoise realm**.
- **Compatibility:** current Retail/Classic addons from other sites are often not compatible with WoW 1.18.1/build 7272. Listing is not certification.

## Account and player status

- **Change password** directly below the account selector asks for current, new, and confirmation. Press **Done** to update the live server and then the local encrypted Windows DPAPI password vault. No in-game chat commands or arbitrary complexity rules. Vanilla WoW supports passwords of 1–16 printable characters.
- The sidebar shows **Online / Offline** from live realm account state for Michael, Jayke, Bernard and August. An unreachable backend shows **Unknown** rather than incorrectly showing Offline.
- The former per-PC SSH tunnel is retained in source as a legacy fallback for installations using older routing. Bernard's existing SSH key is not deleted or replaced by this update.

## Preview service and operational limitation

The initial Crew HTTPS endpoint uses a free **Cloudflare Quick Tunnel**, which has **no uptime guarantee and changes address whenever cloudflared restarts**. It is a functional early-access test, not a permanent hosted production endpoint. The launcher reads the current endpoint from the GitHub manifest at startup; if it changes, the manifest must be updated before users can reconnect. To make it reliably plug-and-play across restarts, provision a **named Cloudflare Tunnel** or another persistent HTTPS hostname.

Current local logs: `%LOCALAPPDATA%\TortoiseCrewLauncher\launcher.log`.

Source: [src](./src). The previous validated v1.0.3 binary is retained in this repository and private ops artifacts for recovery.
