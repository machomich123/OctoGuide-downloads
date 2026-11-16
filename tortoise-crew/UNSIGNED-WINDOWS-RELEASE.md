# Unsigned launcher releases on Windows

Owner preference: **do not require code signing**. This procedure supersedes the temporary signed-only policy added after the 1.0.12 block. It does not bypass Windows policy and does not promise that an unsigned file will be allowed.

## What actually happened

The installed launcher 1.0.11 is allowed on the affected PC. Windows blocked the exact 1.0.12 update on 2026-11-16 at 20:32:03. Launcher log: `Win32Exception: An Application Control policy has blocked this file`. Code Integrity events 3033/3077 identify `pending-update.exe` and policy `{0283ac0f-fff1-49ae-ada1-8a933130cad6}`.

The blocked artifact is a normal managed launcher EXE with no new login loader/DLL. It passed build, regression tests and desktop startup on a disposable Windows runner. Those checks establish functional evidence, **not approval by the affected PC's Smart App Control**.

Known artifact:

- Version: 1.0.12.0
- SHA-256: `0DFCE6C793D1E7233944A6E6455CA90D01DFEF7077A67141184CAF0572107FCE`
- Bytes: 169984
- Source tested: `ae493ff71fe6f6b27bb970cc40b780df61b100b9`
- Windows CI: https://github.com/machomich123/OctoGuide-downloads/actions/runs/43939914596
- Immutable download: https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/15a2c8f8a0d68fa5eb48b3858be6908172469150/tortoise-crew/TortoiseCrewLauncher.exe
- Public update manifest stays paused until the Windows block is resolved.

## Supported route without signing

Microsoft documents that Smart App Control can allow unsigned software when its app-intelligence services recognize it as safe. Unknown unsigned software can be blocked. SmartScreen download warnings and Smart App Control enforcement are different controls; a clean antivirus scan or a successful CI launch is not proof of either control's approval.

For a clean file that is blocked, request review through the official Microsoft Security Intelligence submission portal. The portal includes **Smart App Control** as a product. A review is a route to request correction, not a promise of approval, a guaranteed timetable, or an automatic allow-list entry. A result that says only 'not malware' must not be treated as proof that Smart App Control now permits execution.

1. Freeze the exact final executable. Keep its hash, source commit and CI evidence. Do not rebuild, pad, repackage, rename or modify executable bytes to obtain a different Windows verdict.
2. Open https://www.microsoft.com/en-us/wdsi/filesubmission. Select **Software developer** and **Smart App Control**. Upload only the exact EXE above. Describe a clean legitimate application blocked by application control; do not invent an antivirus detection name.
3. Use `MICROSOFT-REVIEW-1.0.12.txt` for the additional information. Complete sign-in or human verification if the portal requests it. Retain the submission ID and Microsoft's result. No submission has been made by the agent yet.
4. After review, verify the same hash and perform one real update/startup test on the affected PC with its existing protections intact. Inspect Code Integrity logs and confirm a functioning launcher window and the expected version. Stop if the file remains blocked; do not repeatedly retry or claim success from a scan result.
5. Only after that success, use the unsigned release path below. Publish the exact tested EXE and matching manifest together. Do not substitute a freshly compiled artifact from a later CI run.
6. Re-download the public EXE and manifest and compare hashes. Record the Windows test and submission reference. If a subsequent user is blocked, pause the release and request review for that exact file rather than assuming the previous PC proves acceptance everywhere.

### Release command after actual Windows approval

`Prepare-Release.ps1 -Executable <exact-tested-exe> -AllowUnsigned -WindowsCiRunId <successful-provenance-run> -WindowsPolicyVerifiedSha256 <hash-actually-tested-on-affected-PC>`

The last argument records operator verification, not an OS trust override. The script also verifies CI provenance/source and hash. Supplying a hash without actually performing that test is not acceptable release evidence. The earlier `-AllowUnsigned -WindowsCiRunId` alone is now rejected. If the only change is documentation/release tooling, retain the existing verified executable rather than generating another file solely to change its reputation.

## Never use these as fixes

Do not turn off Defender or Smart App Control, install self-signed trust exceptions, remove protection metadata to influence trust, modify App Control policy, load a blocked assembly inside a trusted host, or use another executable/interpreter as a route around the block. Keep the existing launcher available. Do not present a Microsoft submission as already approved or universally effective.

## Long-term maintenance

Unsigned trust does not carry automatically from 1.0.11 to 1.0.12. Keep normal additive metadata/config/addon updates separate from executable releases so ordinary content changes do not unnecessarily generate new native binaries. New launcher behaviour can still require a new EXE and another reputation decision. There is no supported developer flag guaranteeing that every future unsigned build is accepted with Smart App Control enabled.

Official sources, checked 2026-11-16:

- https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview
- https://www.microsoft.com/en-us/wdsi/filesubmission
- https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation
