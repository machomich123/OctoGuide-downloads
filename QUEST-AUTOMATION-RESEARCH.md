# Quest automation research, 2026-10-13

## 0.5.13 correction

**Superseded generic-training behavior in 0.5.14:** the user clarified that trainer offerings must never become required skills. Only authored spell IDs, explicit skill names and named profession goals can complete automatically. Generic class visits without such a goal remain manual. The runtime no longer reads available trainer services. Spell-ID goals now display the exact spell/rank so the requirement is visible. The tests explicitly exclude unrelated Track Beasts learning from a Concussive Shot goal and verify that not learning Track Beasts does not block that goal.

The user confirmed auto accept/turn-in in-game, but reported `QuestAutomation.lua:72: Unknown link type` and failed reward choice. 0.5.12 passed bare-item-string mock tests; these did not cover colored links returned by the game. The new regression fixture reproduces the error against the released 0.5.12 module. Tooltips receive the extracted raw payload, preserving enchant/suffix/unique fields; a rejected tooltip is contained and leaves the reward manual.

Training continuation listens to SPELLS_CHANGED, LEARNED_SPELL_IN_TAB, SKILL_LINES_CHANGED and trainer/crafting/pet updates. IsPlayerSpell includes learned recipes/passives absent from IsSpellKnown's strict spellbook check. Name/rank checks use actual spellbook entries, not GetSpellInfo's database metadata alone. Generic class-training visits require all originally available services to appear as learned spells. Trainer opening, closing, filtered list changes and rejected purchases are not completion evidence.

Primary references: local ClassicAPI docs/API.md (`IsPlayerSpell`, `IsSpellKnown`, `GetSpellInfo`) and https://github.com/satan666/WOW-UI-SOURCE/blob/master/AddOns/Blizzard_TrainerUI/Blizzard_TrainerUI.lua (`GetTrainerServiceInfo`, trainer updates). Installed pfQuest also uses raw `item:ID:0:0:0` strings for Vanilla SetHyperlink. This release makes no DLL changes.

Sources inspected:

- https://github.com/MickeyPickey/AutoQuest — Vanilla event-based acceptance, completion and highest-vendor-value selection. Its usability check does not compare against equipped/bag gear. No source code copied.
- https://github.com/wealdly/JustQuest — modern-client reward automation; conceptual reference, not a Vanilla API implementation.
- https://github.com/finidigeorge/Pawn — existing Vanilla equipment-scoring approach. This release uses its own class leveling weights and does not require Pawn.
- https://github.com/brues-code/ClassicAPI/blob/master/docs/API.md — C_Item.GetItemInfo (18 returns), GetItemStats, GetItemSellPriceByID, C_GossipInfo quest IDs. Source checkout inspected; no DLL changes.
- https://github.com/satan666/WOW-UI-SOURCE/blob/master/FrameXML/GossipFrame.lua — original two-field Vanilla gossip tuples for both available and active quests.
- https://github.com/satan666/WOW-UI-SOURCE/blob/master/AddOns/Blizzard_TalentUI/Blizzard_TalentUI.lua — Vanilla talent points are the third GetTalentTabInfo result.

Installed ClassicAPI.dll contains the GetItemStats, GetItemInfo, GetItemSellPriceByID and GetAvailableQuests symbols. This is binary evidence, not a live Lua/API test. GetQuestID is absent: NPC menu IDs are used where available; otherwise exact, unambiguous quest titles are required. Stock Vanilla item info uses equipLoc at return eight; C_Item uses return nine.

The posted step is in the private installed family route `rxp-hardcore-1-6-orc-troll`, step 11: level 3, 1120 XP (80 percent of the 1400 XP bar), before Cutting Teeth turn-in. The next accepts have minimum level 1. It is an XP pacing recommendation, not their acceptance requirement. Family content is inspected locally and never included in the public release.

Implementation: no polling/delay timer for quest actions. Events issue eligible actions immediately; the server/client still determines actual response latency. Item cache misses retry on GET_ITEM_INFO_RECEIVED, and closing the quest cancels retries. Guide progress is changed only through existing server-confirmation logic.

Rewards: original weighted class leveling score, with talents selecting hybrid profiles. Compares worn equipment and bag equipment; handles two ring/trinket slots and one/two-hand weapon combinations. Chooses largest positive score gain, otherwise largest unit sell price times reward quantity. This is a practical leveling heuristic, not a full simulation or a promise of best-in-slot gear. Unknown stats, red requirements, unrecognized procs/use/set effects and missing price/data stay manual. The tooltip fallback supports English basic stats; the C_Item stats path is locale-independent.

All three options default OFF. Shift pauses automation. Back review and combat pause it. Multiple-choice rewards remain manual when auto reward is OFF; auto reward alone selects without turning in. No automatic equipping, selling, combat, movement or unattended NPC interaction.
