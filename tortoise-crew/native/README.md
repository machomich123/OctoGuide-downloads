# Login bridge v3

The verified 1.18.1/build 7272 client receives credentials through its actual
GlueXML login function, on its UI thread, after the login frame is visible and
no modal dialog is open. There is no SendKeys, clipboard or foreground dependency.
The native hook addresses and call-byte checks follow the existing private
realm-login module for this exact SHA-256-pinned game build. An unsupported hook
falls back to manual login without typing anything.

For each launch the launcher creates a random directory restricted to the current
Windows SID. It writes a DPAPI CurrentUser-encrypted account/password pair, with
dedicated entropy `TortoiseCrew/one-shot-login/v3`. No password is written to the
command line, environment, XML, logs or plaintext files. The game consumes the
encrypted payload once, deletes it on close of the file handle, checks its age
(120 seconds maximum) and clears temporary native buffers. The launcher removes
the temporary directory after consumption or timeout. The environment contains
only the random directory path. Lua strings cannot be securely zeroed; the Lua
password reference is dropped immediately after DefaultServerLogin.

`vendor/` contains wowreeb 3.5's x86 loader EXE, DLL and its MIT license, copied
without modification from the upstream release archive:
https://github.com/namreeb/wowreeb/releases/download/3.5/wowreeb-3.5.zip
Archive SHA-256: A6CEB3782AD8E67DD7CA4E2EDC4D0029C0A1A8175FE99311EE940B5E85550DEB.
Upstream source: https://github.com/namreeb/wowreeb/tree/3.5

Build-Native.ps1 compiles our source with x86 Visual C++ on Windows CI, or an
explicit x86 MinGW compiler locally. Binaries are embedded as launcher resources.
Windows application-control policy is always respected: no exclusions,
self-signed trust roots, alternate-host execution or protection changes.

Account verification remembers only the last successfully verified game account
on this Windows profile. Changing to another account (including switching back)
requires that account's password again. Reopening the same account remains
automatic. Existing v1 vault entries require verification once after upgrading.
This is not isolation between people sharing the same unlocked Windows profile;
use separate Windows accounts for that boundary.
