# Route repair evidence, 2026-10-14

The screenshots report a repeated Hornwood Recurve Bow vendor instruction despite prior Done and equipped ownership, and a missing Lost Deathstalkers prerequisite before Wild Hearts.

Inspection found three vendor instructions followed by item 2506 collection in each of the Normal/Hardcore Durotar family routes. Vendor steps had no item goal, so owning the bow did not satisfy them. FindPlacement's final forward scan did not honor manual Done/Skip, so a manually completed instruction could be selected again. Repairs link each bow vendor to its existing adjacent item goal and honor explicit progress marks when finding a step. Equipped items are counted independently of GetItemCount.

Both family Silverpine routes included Wild Hearts (429) with requires={428}, but lacked any Lost Deathstalkers (428) action. Catch-up could not find the missing quest within the active route family. Original public baseline routes did contain this chain.

Primary server source: https://octowow.st/db/?quest=428 lists Lost Deathstalkers -> Wild Hearts -> Return to Quinn, with pickup High Executor Hadrec and turn-in Rane Yorick. https://octowow.st/db/?quest=449 lists Escorting Erland -> The Deathstalkers' Report as a separate chain. Local pfQuest quest records confirm 429.pre={428}; its NPC catalogue supplies Hadrec (1952), Silverpine 43.4/40.9, and Rane (1950), 53.5/13.4. NPC coordinates are catalogue data, not observed live positions.

An original public runtime correction adds prerequisite actions when registering family routes that lack them. No private route source is republished or edited. Original step IDs remain stable. Newly added actions do not inherit unrelated private block conditions. An already active/rewarded Wild Hearts makes the added prerequisite actions unnecessary without inventing a completed 428 flag.

Automated validation is distinct from live testing on either brother's character. 22 Lua 5.0.3 suites passed; gameplay confirmation remains pending.
