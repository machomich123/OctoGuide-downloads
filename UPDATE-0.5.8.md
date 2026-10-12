# OctoGuide 0.5.8

Fixes the startup scanning path introduced in 0.5.7. Full character scanning now runs only after an explicit Find step request. Initial bag and quest-log events no longer start a full scan. Native flight-master state is read only while the flight-master window is open; previously observed flight paths remain available when it is closed.

Michael's affected character loaded successfully with OctoGuide disabled, and then loaded successfully with 0.5.8 enabled. This verifies the corrected startup path on that installation, not a universal cause for every client crash. The exact failing native call was not captured. Another family installation was able to load 0.5.7.

All eleven relevant Lua 5.0 test suites pass, including new checks that startup events never perform a full scan and a closed taxi map never invokes native taxi-state APIs. Find step, the step browser, direct step selection and stable Back review remain included. The actual character's Find step scan still needs a gameplay test.

OctoGuide remains free. No new DLL or installer is required.
