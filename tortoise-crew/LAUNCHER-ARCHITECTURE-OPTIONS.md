# Launcher architecture alternatives — 2026-11-16

## Conclusion

A rewrite can avoid generating a new custom native launcher EXE for every application update. That is different from guaranteeing exemption from Defender or application-control policy.

The strongest candidate investigated is a local browser interface plus an unmodified, officially distributed Node.js runtime and a JavaScript backend. The official runtime is signed by its upstream publisher; the owner does not need to sign our application code or submit it to Microsoft. This is a new implementation, not a way to execute the blocked C# assembly through another process.

A limited capability check succeeded on this PC with Smart App Control On, AntivirusEnabled true, and RealTimeProtectionEnabled true. It is evidence for feasibility, not a production launcher test or a universal Windows-acceptance guarantee.

## Comparison

| Architecture | Current launcher features | Update model | Assessment |
| --- | --- | --- | --- |
| Existing C# executable | Existing UI, addon management, DPAPI vault and private relay | Replacing custom EXE for program changes | Current 1.0.12 executable is blocked. Content/config updates can still be separate. |
| Packaged Electron | Can implement desktop UI, file management, process startup, network relay and OS-backed secret storage | Typically ships native Electron binaries plus application resources | Functionally suitable, but ordinary Electron packaging does not inherently resolve Smart App Control. Official downloaded Electron binaries examined below include unsigned components. |
| Tauri / WebView2 host | Suitable for a desktop launcher with a custom native backend | Custom host EXE plus resources | The native host still needs Windows acceptance. Tauri explicitly documents unknown unsigned app blocking with SAC enabled. |
| Browser/PWA only | UI/status/account interactions and some user-granted local file access | Web app updates | Cannot alone replace arbitrary process startup and the present local TCP game relay. Browser native messaging requires a separately installed host. |
| Browser UI + official Node.js runtime | Local file operations, process startup and network services are available; UI can reproduce current layout | Update JS/HTML/CSS and data; update upstream runtime separately when necessary | Recommended candidate for a disposable prototype. Initial local capability check passed. Credential storage, full relay, updater and background/desktop UX remain to implement and validate. |

## Measurements and checks performed

### Official Electron runtime

Downloaded the official `electron-v45.3.3-win32-x64.zip` and verified its SHA-256 against the release's SHASUMS256.txt.

- Archive bytes: 158325836
- SHA-256: `49DD2D3875944F08DE03D34595CD30093C588B9EDCABB41A0AC481028A3A5A8A`
- Authenticode status: electron.exe, electron_wer.dll, dxcompiler.dll, ffmpeg.dll, vk_swiftshader.dll and vulkan-1.dll were NotSigned. d3dcompiler_47.dll had a valid Microsoft signature.
- These files were inspected, not executed. This does not prove that Electron would be blocked on this PC; it disproves the assumption that using stock Electron necessarily supplies a fully trusted signed distribution.

Electron's own documentation supports separating application code into resources/app or app.asar, but it also recommends signing packaged applications. Its ability to load app resources is not an OS acceptance guarantee. Rebranding or repackaging is not a verified solution to the recorded block.

Official assets: https://github.com/electron/electron/releases/tag/v45.3.3

### Official Node.js runtime

Selected the first LTS Windows x64 ZIP from Node's official distribution index. Downloaded it from nodejs.org and verified the archive checksum against that version's SHASUMS256.txt.

- Runtime: Node.js v26.13.1, LTS Lithium
- Archive SHA-256: `E2EDDA75BFB089654705CF65A13B58933BFD5F57148E8EBDA916F58A2474F1F7`
- node.exe SHA-256: `F5109DC868EC38703AD8F305E0ACEECE717CB60D4889873F434017AF4E96CCCB`
- Authenticode: Valid, OpenJS Foundation.
- No Windows policy, trust store, Defender setting or exception was changed.

Ran a small source-code capability check using only built-in Node APIs:

1. Create/read/write a fixture in a new temporary folder: passed.
2. Start an HTTP listener bound to 127.0.0.1 and request it locally: passed.
3. Start an existing Windows program, cmd.exe with an immediate exit command and hidden window: passed.
4. Close the listener and remove only the temporary fixture: completed.

No WoW process was launched, no real account/password was read, no production client file was changed by this check, and no game server connection was made. A browser UI was not built or opened. The research runtime is not registered as a service or installed as the new launcher.

Official distribution: https://nodejs.org/dist/v26.13.1/

## Mapping our actual requirements

- **Appearance:** recreate the existing launcher layout in HTML/CSS. No reason to change its main user flow merely because the backend language changes.
- **Scan/import/repair:** port the validated manifest selection, backups, rollback, conflict handling and memory-setting changes to filesystem code. The successful fixture test proves filesystem availability, not that this full port is implemented.
- **Play:** use a constrained process-start operation for the chosen verified WoW client. The check started a Windows fixture program, not WoW. Full startup/exit handling remains to test.
- **Private game connection:** current code owns local TCP listeners on 3724/8085 and relays through TLS WebSockets. Node has the necessary socket/process primitives. The existing relay protocol, session lifetime and reconnection behaviour need a faithful port and an integration test; a browser alone cannot own these listeners.
- **Credentials:** Node's standard library is not a drop-in replacement for the existing DPAPI vault. Select and test OS-backed storage or an explicit passphrase/session design before claiming parity. Do not store plaintext passwords or add an unsigned native dependency casually. Account switching must still require verification.
- **Instant game login:** remains a separate, unsolved client-login integration issue. Changing launcher framework does not automatically add an API to WoW's login screen.
- **Updates:** stage a versioned application bundle, verify provenance/integrity, swap only when idle, and retain rollback. Prefer ordinary source/data updates over creating a custom EXE. Do not treat a checksum alone as proof of publisher identity. Runtime security updates still need to be maintained and validated.
- **Clean desktop experience:** single-click launch, console-window handling, browser/app-window appearance, backend lifetime and cleanup need a real prototype. The command-line check does not prove a polished desktop UX.

## Recommended next experiment

Build a separate prototype with the official Node runtime, a local-only authenticated backend and a browser UI. Limit the backend to explicit launcher operations; do not expose arbitrary commands or filesystem access to arbitrary web pages. Start with a disposable client fixture and no real credentials. Test addon repair, update/rollback, browser launch, backend lifetime, and finally WoW/relay integration with a test account.

A successful prototype would justify a migration. It would not justify promising that all Windows security products ignore the application. Do not overwrite the working 1.0.11 launcher or alter the realm while evaluating it.

## Sources

- Electron packaging and application resources: https://www.electronjs.org/docs/latest/tutorial/application-distribution
- Electron code-signing guidance: https://www.electronjs.org/docs/latest/tutorial/code-signing
- Electron privileged/remote-content guidance: https://www.electronjs.org/docs/latest/tutorial/security
- Electron OS-backed secret storage: https://www.electronjs.org/docs/latest/api/safe-storage
- Tauri Windows/SAC constraints: https://tauri.app/distribute/sign/windows/
- Browser local file access and permission model: https://developer.chrome.com/docs/capabilities/web-apis/file-system-access
- Browser native messaging host: https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
- Node filesystem: https://nodejs.org/api/fs.html
- Node process creation: https://nodejs.org/api/child_process.html
- Node network listeners: https://nodejs.org/api/net.html

The architectural recommendation is an inference from these documented capabilities plus the limited local test. It is not an upstream promise or a finished replacement launcher.
