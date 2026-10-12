# OctoGuide 0.5.10

Find step now prints a short placement result instead of the full inventory/bank/travel diagnostic paragraph. `/octoguide scan` retains the full details. Missing client support for completed-quest history is distinguished from a failed request or timeout. The message still clearly states when full earlier history is unavailable.

The current inspected OctoWoW client and installed ClassicAPI do not expose QueryQuestsCompleted/GetQuestsCompleted or IsQuestFlaggedCompleted. An addon cannot invent historical server data. OctoGuide continues using active quests and its locally recorded, server-confirmed turn-ins, and retains unknown required starter work. Guide-action counts are now explicitly distinguished from separate completed quests.

Free addon update; no new DLL or installer. Existing startup protections, step selection and starter placement checks are retained. Automated Lua 5.0 checks cover unsupported history, request failures and concise default output.
