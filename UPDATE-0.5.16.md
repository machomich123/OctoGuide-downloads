# OctoGuide 0.5.16

- Recognize Hornwood Recurve Bow in bags or equipped before repeating the vendor/sell-weapon instruction. All repeated instances in the Normal and Hardcore family routes share this real item goal. Collection steps also count worn items when the client item-count API does not.
- Find step now respects explicit Done/Skip while moving past previously completed manual actions.
- Repair both family Silverpine routes: accept Lost Deathstalkers from High Executor Hadrec at the Sepulcher, turn it in to Rane Yorick, then accept Wild Hearts. Escorting Erland alone does not satisfy that prerequisite. Existing step IDs and saved progress are retained.
- If Wild Hearts is already accepted or rewarded, the new prerequisite steps are not forced again; missing completion history is not fabricated.

22 Lua 5.0.3 test suites passed, including all six actual repeated bow vendor instructions, equipped/bag possession, Done followed by Find step, and both locally installed family Wild Hearts routes. Live confirmation remains pending. No game files or saved character data were modified.

Update OctoGuide-downloads through the launcher and use `/reload` in-game. No family-route reinstall is required.
