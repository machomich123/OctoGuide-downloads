# Crew Next 0.3.7

This release adds connection diagnosis, the owner-selected B3 icon, and a
TortoiseBotsManager catalog entry. It does not change the realm or restart it.

## Connection diagnosis

The previous investigation correlated MICHAEL's Aidolf disconnect with a
relay error, but could not identify the endpoint that closed first. The new
launcher records the first **locally observed** terminal event, not a claim
about the ultimate root cause somewhere on the Internet.

Location: `%LOCALAPPDATA%\TortoiseCrewNext\diagnostics\connections.jsonl`.
One previous rotated file is kept. Each is capped at 256 KiB; the pending
write queue is capped at 32 entries. If storage fails, diagnosis disables
itself for that process and gameplay continues. No telemetry is uploaded.

Each connection has one open and one close record, a random connection ID,
UTC times, standard/prepared path, auth/world mode, lifetime, existing socket
byte counters, allowlisted error code and optional WebSocket close code.
Intentional launcher stop is separate from client EOF or remote EOF/error.
The existing 20-second WebSocket ping supplies optional RTT and coarse
event-loop drift information. Its payload increases by four bytes; no extra
ping timer, polling request or background bandwidth test is added. No packet
payload, password, session key, token, account name, URL or close-reason text
is recorded. Last activity is heartbeat-sampled, not a packet timestamp.

This observes the existing session. It does not forcibly close slow sessions
or attempt to reconnect a broken encrypted WoW TCP stream transparently.
TCP_NODELAY is explicit for new loopback/relay sockets; ordinary TCP keepalive
is enabled on TLS sockets, without adding an application-level timeout.

## Icons and compatibility

The user selected B3 from an imagegen 4x4 sheet. A faithful standalone asset
was generated with real transparency and encoded into a seven-size ICO.
The icon is embedded in a JavaScript source module so existing 0.3.6
updaters can deliver it without changing ZIP extension allowances. Desktop
and Start Menu shortcuts receive a versioned ICO path once, and the app
window receives the same icon through its favicon endpoint. Old application
and shortcut backups are retained by the existing updater/migration path.

## TortoiseBotsManager

Bundled catalog entry: https://github.com/Sagiroth/TortoiseBotsManager.
It is merged once into fresh, cached and offline catalogs without additional
requests. Installation remains an explicit user action; it uses the existing
TOC-aware GitHub installer, backups and running-game guard. The addon requires
the TortoiseBots server module and opens with `/tbm`.

## References

- https://nodejs.org/api/net.html — socket byte counters, events and TCP options.
- https://developers.cloudflare.com/network/websockets/ — keepalive and connection-lifetime limits.
- https://github.com/Sagiroth/TortoiseBotsManager — canonical addon and installation layout.
