# Instant login and Windows application control — 2026-11-16

## Conclusion

Do not restore the old unsigned loader/DLL approach. Release 1.0.12 keeps normal WoW startup while fixing addon import and adding repair. It does not claim to implement instant login.

The best candidate for a future implementation is a client-compatible login-screen integration that calls the game's login function once the screen is ready, obtains credentials from Windows-protected storage, and requires verification when switching accounts. A small, trusted signed native integration may be needed; a normal in-game addon cannot run before account login.

## Investigated alternatives

- Timed SendKeys: focus/layout/timing problems; does not meet the reliability requirement.
- Reintroducing CrewLogin + wowreeb: repeats the untrusted binary load that was removed in 1.0.11. Signing only the launcher would not establish trust in every loaded DLL/helper.
- Original turtle-autologin: stores passwords in Config.wtf. Do not integrate this plaintext credential format.
- MarcelineVQ/turtle-autologin 3: requires Nampower >=3.2.0 or SuperWoW >=1.4; Nampower supports DPAPI-encrypted saved passwords. A candidate, but the exact build-7272 GlueXML compatibility, credential handoff, loaded extension version, and Windows trust must be validated first. Do not copy a different client's GlueXML or patch executable signature checks as part of addon repair.
- ClassicAPI: documents SaveAccount/GetSavedAccounts/LoginWithSavedAccount with Windows Credential Manager and realm-scoped entries. Upstream describes a DLL for 1.12.1; that is not evidence of compatibility with this Turtle 7272 client. Candidate for a separate compatibility test, not a drop-in release.
- Plaintext password arguments, clipboard automation, or Config.wtf password saving: unnecessary exposure and/or unreliable focus; not selected.

## Implementation and release requirements

1. Validate exact build 7272 against a disposable client and test account; no production server change is necessary.
2. Use an explicit opt-in. Keep one verified selected account, encrypted storage, and password verification when switching. Do not expose all locally saved accounts automatically.
3. Hand credentials to the ready login screen once; never log them, store them in configuration, or pass them on the command line. Do not retry failed logins automatically.
4. Sign every newly shipped executable/native helper through a publicly trusted publisher and timestamp signatures. Run Windows tests against the exact release artifact, including account switching, punctuation in passwords, failed auth and manual fallback.
5. Keep manual login available; do not change Defender, Smart App Control, certificate trust stores, or exclusions.

No code-signing certificate with private key was available in the current user's code-signing certificate store, and the repository exposes no configured signing variables/secrets. A tested unsigned executable can still be blocked by a particular Windows installation. CI success is not a guarantee of Smart App Control acceptance. Obtaining/enrolling a trusted signing identity requires the owner's identity/account setup; no identity or certificate was invented for this release.

Sources:

- https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/code-signing-for-smart-app-control
- https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview
- https://github.com/Haaxor1689/turtle-autologin
- https://github.com/MarcelineVQ/turtle-autologin
- https://github.com/brues-code/ClassicAPI
