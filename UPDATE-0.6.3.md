# OctoGuide 0.6.3

Includes 0.6.2 height, flight fallback and pfQuest history changes. The first in-game inspection of 0.6.2 exposed that corrected quest NPC waypoints are separate tables. This release retains quest identity for height lookup at those points, and includes a regression test. Apothecarium instructions no longer depend on an obsolete authored zone id. When exact height is unavailable, its lower-level destination is labelled without inventing a numeric height.

Update the existing GitHub addon through the launcher, then log in or /reload. A successful new-version load is announced locally in chat. This is a loaded-version notification, not a background GitHub update-availability check.
