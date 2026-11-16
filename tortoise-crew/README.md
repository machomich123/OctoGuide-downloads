# Tortoise Crew Launcher v1.0.10

## Current unsigned release policy

The owner has explicitly chosen releases without mandatory signing. See [Unsigned Windows release procedure](UNSIGNED-WINDOWS-RELEASE.md) for the durable procedure and [prepared Microsoft review text](MICROSOFT-REVIEW-1.0.12.txt).

Version 1.0.12 is still paused because Smart App Control blocked its exact executable on the affected PC. Installed 1.0.11 is preserved. Microsoft review is an available unsigned route, not a guaranteed approval. CI startup alone is not sufficient release evidence. The release tool permits unsigned publication only with provenance and a recorded successful test of that exact hash on the affected PC, with protection unchanged. No signing subscription is required by this policy.

The older implementation notes below are historical where they conflict with the current procedure. In particular, automatic game login is disabled in 1.0.11/1.0.12; profiles and DLL/MPQ client mods are not copied by addon import.

## Login and account-switch update

The login fix replaces timed SendKeys with a one-shot DPAPI-protected handoff to
the verified client's login UI. It submits as soon as that UI is ready, preserving
password symbols without keyboard-layout or foreground assumptions. Passwords
never enter command lines, logs, XML or plaintext temporary files.

Only the last verified account on this Windows profile can use its saved password.
Switching accounts requires the selected account's current password, even if it
has an older vault entry; further launches of the same account are automatic.
Existing users verify once after upgrading. This does not distinguish people
sharing the same unlocked Windows profile; separate Windows users provide that
boundary. See [native login design](native/README.md).

The published EXE is the exact artifact from the successful
[Windows build, native login tests and real desktop startup test](https://github.com/machomich123/OctoGuide-downloads/actions/runs/43847483392).
Its SHA-256 is `E6159A8781E55FCFDBC1F8C30BEE54836B6C086D626A769A16B083F52DF5E6AB`.
Login UI state-machine tests also passed. A real game login on the user's PC has
not been exercised with this release. Automated Windows tests do not establish
that Smart App Control will accept these unsigned binaries on every user's PC.

One Windows launcher for **MICHAEL, JAYKE, BERNARD and AUGUST**.

**[Download launcher v1.0.10](./TortoiseCrewLauncher.exe)**. This is an unsigned release, validated on Windows CI. The previous v1.0.9 was also opened normally on the user's Windows 11 PC with Smart App Control **On**, Microsoft Defender Antivirus enabled and real-time protection enabled. That earlier result does not establish trust for a changed executable or its new login module. No Windows protection settings or exclusions were changed for this update.

v1.0.9 reads the version from the compiled assembly (v1.0.8 incorrectly reported v1.0.6), treats 1.0.9 and 1.0.9.0 equally, checks the trusted GitHub manifest's SHA-256, validates a signature if one is present, waits for the old process/file to close, and serializes desktop launches with installation. An unsigned file is submitted to normal Windows execution checks; the launcher does not require buying a certificate. Reopening the desktop shortcut activates the existing launcher. The updater records success only after the new UI acknowledges that it opened. Errors keep their actual cause instead of reporting every install failure as a GitHub outage.

If a release is withdrawn, the manifest may advertise `0.0.0` while `updatesPaused` is true: older launchers do not understand the pause flag but never offer a lower version. This pauses offers without downgrading an installed launcher.

## Windows trust and release setup

Windows Smart App Control accepted earlier builds but blocked the v1.0.8 pending update on one PC. Microsoft documents two ways an app can be allowed: a positive safety decision from its cloud service, or a trusted signature when the cloud service cannot decide. A signature is therefore not an absolute requirement. See [Microsoft's Smart App Control FAQ](https://support.microsoft.com/en-us/windows/security/threat-malware-protection/smart-app-control-frequently-asked-questions). No release can promise acceptance under every administrator policy or antivirus product, and file reputation does not reliably carry over between unsigned releases.

The build workflow compiles and tests source updates. Public release now requires `scripts/Prepare-Release.ps1 -Executable <trusted-signed-exe>`. Unsigned publication, including the legacy `-AllowUnsigned` option, is rejected. A matching hash and successful Windows CI run cannot establish publisher trust on another PC.

Signing integration supports SignPath using repository variables `SIGNPATH_ORGANIZATION_ID`, `SIGNPATH_PROJECT_SLUG`, `SIGNPATH_SIGNING_POLICY_SLUG`, and secret `SIGNPATH_API_TOKEN`. Owner enrollment and provider approval are required. Never commit keys or tokens. See https://signpath.org/ for the open-source application route.

For local builds, use `scripts/Build.ps1 -Compiler <Roslyn-csc.exe>` and `scripts/Test.ps1`. Windows may block a new local build; the toolchain never works around that decision. CI covers version comparisons, concurrent launch ownership, signed-only publication defaults, rejection of unsigned updates, valid and invalid embedded signatures, a real desktop shortcut and addon migration.

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
