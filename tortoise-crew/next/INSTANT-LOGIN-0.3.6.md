# Crew Next 0.3.6: prepared WoW sessions

The launcher authenticates to the real realm before Play without starting WoW.
On repeat launches, it also authenticates the world connection and retrieves the
live character list. Play starts a normal visible client, grants it foreground
focus when its window exists, and connects it to the prepared session locally.
There is no window parking, branded cover, or wait-for-file reveal timeout.

## Why the previous implementation waited

The previous preflight verified a Crew HTTPS token, not a WoW SRP session.
WoW still performed remote authentication after Play. A PowerShell guardian
parked its window and could wait 27 seconds for a flag. The GlueXML attempted
to write that flag with AppendToFile, which is not supplied by ClassicAPI.
The installed log recorded FALLBACK_VISIBLE rather than a confirmed ready event.
Its CharacterSelect_OnEvent wrapper also omitted the original event arguments.

## Session handoff

1. Crew HTTPS verification and Windows Credential Manager provisioning.
2. Actual SRP6 authentication over the existing authenticated TLS relay.
3. World socket preparation. After learning the client's exact addon handshake,
   world authentication and character enumeration also finish before Play.
4. After Play, a loopback-only SRP frontend authenticates the original client.
   It uses an independent local session key and never updates the server's key.
5. The original client's world proof is verified. Headers are decrypted and
   re-encrypted in both directions; packet bodies are preserved. The client's
   first character-enumeration request receives the prefetched live response.

The pinned Turtle executable reports 7272 to realmd but 5875 in its world
handshake. These are explicitly supported; arbitrary client builds are refused.
The server's SRP proof is checked. No authentication, IP, or version check is
disabled on the server. Warden payload encryption is not supported: a Warden
message aborts this prepared path rather than weakening anti-cheat.

Addon metadata is taken from the actual client's compressed authentication
payload, never guessed. Its cache contains no credentials. Installation changes
invalidate the cache. Byte-identical .toc/.pub rewrites do not invalidate it.
If metadata changes during startup, the world connection is recreated using the
client's exact new payload. First launch therefore performs a small amount of
remaining world authentication after Play; later launches can fully prefetch.

Prepared sessions expire after 90 seconds and are refreshed while the launcher
UI is present. Closing the UI stops refreshing and disposes preparation. A live
game owns its relay until it exits. Passwords and session keys are not written
to game files or logs. The only persisted handshake cache is addon metadata.

## Shared installation

The same updater package serves all four Crew accounts. Supported clients can
automatically obtain SHA-pinned ClassicAPI v1.15.16 and VanillaFixes v1.5.3.
Unknown existing modules are preserved. Existing dlls.txt entries are preserved;
integration removal restores its original contents. Runtime DLLs are retained
because other addons may use them. VanillaFixes retains its normal first-use
consent. WoW.exe is not modified.

Upstream runtimes and source:
- https://github.com/brues-code/ClassicAPI/tree/v1.15.16 (GPL-3.0)
- https://github.com/hannesmann/vanillafixes/releases/tag/v1.5.3

## Validation on 17 November 2026

- Independent wow_srp regression vectors for SRP interleave and client proof.
- Local end-to-end SRP/world handoff, independent local and upstream keys,
  header fragmentation, continued encrypted traffic, exact addon metadata,
  changed-addon recovery, expiration, and account/URL cache isolation.
- Real realm authentication and four live characters retrieved without WoW.
- Real client reached character selection repeatedly in a disposable copy.
  Native screenshots were triggered by a visible character-select frame with
  a nonempty live character list. A separate frame probe would capture the
  account-login scene if it became visible; successful captures show characters.
- Foreground ownership was positively confirmed using the production focus
  helper. Earlier failed focus retries were corrected by waiting for window
  creation and using bounded standard Win32 foreground APIs.
- Real prefetch example: character list ready about 1.8 seconds into launcher
  preparation; local client attach about 5 ms after its world auth arrived.
- Actual client startup to captured character screen: approximately 6–7 seconds
  in an 800x600 test copy capped at 20 FPS. These are test measurements, not a
  promise of zero-time client loading or a benchmark of normal graphics settings.
- Verified upstream runtime downloads, installation, integration removal, and
  byte-exact restoration of pre-existing loader settings.

No characters were entered into the game world, moved, edited, or deleted.
No realm restart or server configuration change was needed.
