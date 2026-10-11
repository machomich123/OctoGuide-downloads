# ClassicAPI OctoGuide integration 0.5.1

This is an integration fork for the verified OctoWoW 1.12 executable. It keeps ClassicAPI's GPL-3.0-or-later license. Full corresponding source, including pinned build dependencies, is included as a release archive. This is not an upstream release.

Corresponding source: https://github.com/machomich123/OctoGuide-downloads/releases/download/v0.5.1/ClassicAPI-OctoGuide-0.5.1-source.zip

Added APIs: OctoGuideBridgeVersion(), OctoGuideClosestLivingUnit(entry, requiredStandState), OctoGuideCaptureViewport(), OctoGuideCaptureBegin(), OctoGuideCaptureUI(name,left,bottom,width,height), OctoGuideSendReport(json), OctoGuideReportStatus(). Unit enumeration is read-only and never targets a unit. World access is gated on the object registry. A required standstate of 3 selects sleeping creatures; dead/zero-health units are excluded.

Screenshot coordinates are actual client pixels from the bottom left. Lua converts Vanilla's 768-reference-height coordinates using the native viewport. Only the guide/guides/settings crop names are accepted, with bounded dimensions and three captures maximum. Presented OpenGL/D3D9 pixels are used where available, with a client-DC fallback. Uniform blank captures are rejected. PNG processing and fixed-host HTTPS sending happen on a background thread. Redirects are disabled. No arbitrary URLs, filesystem reads, login fields or GitHub credentials are exposed.

Report service: https://octoguide-reports.machomich.workers.dev/reports (write only). Owner retrieval uses authenticated Cloudflare D1 administration. No public read API is provided.

Build: CMake Win32 preset, then Release target ClassicAPI. Dependencies: minhook 05c06c5bbca226b72ffb40fc0caaef33bcaf6f74, picojson 25fc213cca61ea22b3c2e4db8def9927562ba5f7, tinycbor d393c16f3eb30d0c47e6f9d92db62272f0ec4dc7. The CMake DEF path is quoted to support a source path containing spaces.

Replace only the existing ClassicAPI.dll with WoW closed, preserving the original first. The existing updated RestedXP installer performs backup and verified-client checks. The offline native probe demonstrates GUI loading, actual UI crops and confirmed network receipt, with no account login. It cannot establish real-world creature observations or gameplay stability.
