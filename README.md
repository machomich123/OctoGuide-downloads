# OctoGuide — launcher distribution

Install through OctoLauncher using this Git repository URL:

https://github.com/machomich123/OctoGuide-downloads

The launcher installs the folder **OctoGuide-downloads** and loads
**OctoGuide-downloads.toc**. This contains the same OctoGuide 0.3.6 runtime,
with asset paths adapted to the launcher's folder name. Updates are detected
from new commits on main. ZIP release downloads remain available separately.

Requires the OctoWoW client with ClassicAPI. pfQuest is recommended.
Enable only one OctoGuide installation: disable an older manually installed
OctoGuide before enabling this launcher distribution. Both use /octoguide.
Saved character state is stored under the installed addon's folder name;
switching from the manual edition does not automatically transfer that state.

This is a testing release. Lua tests and native rendering have been checked;
actual travel recommendations require gameplay testing. Open a flight map
to record learned destinations and bind at an inn to record its location.
Travel times are estimates, not a measured fastest-route guarantee.

The private development repository and its history are not published here.
This public distribution necessarily includes the Lua files the game runs.
No credentials, login helper, launcher patch, character saves or local logs
are included. See the bundled content attribution and license notices.
