dofile('tests/test-runtime.lua');dofile('Placement.lua');dofile('CharacterScan.lua');dofile('QuestAutomation.lua');dofile('LiveTargets.lua');dofile('QuestKnowledge.lua');dofile('QuestGiverPositions.lua')
local G=OctoGuide;local K=G.knowledge
G.db.completedQuests={};G.db.progress={};G.pauseAuto=false;G.ready=true
local clock=100;function GetTime()return clock end
function UnitLevel()return 15 end
function UnitClass()return 'Hunter','HUNTER' end
function UnitRace()return 'Orc','Orc' end
local npc=3448;function UnitCreatureID(token) if token=='npc' or token=='visible' then return npc end end
pfDB={quests={data={
 [100]={min=10,start={U={3448}}},[101]={min=10,pre={100},start={U={3448}}},
 [102]={min=20,start={U={3448}}},[103]={min=1,start={U={3448}}},
 [104]={min=1,start={U={3448}}},[200]={min=1,start={U={3448}}}
},loc={[100]={T='First'},[101]={T='Follow-up'}}},units={data={[3448]={coords={{52.3,31.9,17}}}},loc={[3448]='Tonga Runetotem'}}}
pfDatabase={QuestFilter=function()return false end,GetBitByRace=function()return 1 end,GetBitByClass=function()return 4 end}
pfQuest_history={[999]={0,0}};QueryQuestsCompleted=nil;GetQuestsCompleted=nil
pfDatabase.QueryServer=function()end
local placed=0;G.AutoPlace=function()placed=placed+1;return true end
G.ReconcileCharacter=function()end
assert(G.InstallPFHistoryHook())
assert(G.FindStep(false) and K.history and placed==0)
G.ReceivePFHistory('UNRELATED','999');G.ReceivePFHistory('TWQUEST','100 103')
-- pfQuest's finalized list contains both inferred prerequisites and manual data.
pfQuest_history={[100]={0,0},[103]={0,0},[104]={0,0},[999]={0,0}}
G.UpdateFindStep(3.6)
assert(placed==1 and G.db.completedQuests[100] and G.db.completedQuests[103])
assert(not G.db.completedQuests[104] and not G.db.completedQuests[999],'Only raw server IDs become facts')
assert(G.db.pfServerHistory.count==2 and G.historyReady and not G.pendingFind)
assert(G.QuestAvailability(100).state=='completed')
assert(G.QuestAvailability(101).state=='expected','Confirmed predecessor unlocks prediction')
assert(G.QuestAvailability(101).mapMarker==false,'Cosmetic map filter does not imply unavailable')
assert(G.QuestAvailability(102).state=='blocked','Known level requirement stops travel')
assert(G.QuestAvailability(999).state=='unknown','No data is not nonexistence')
local current={id='missing',questID=999,action='accept',zone=17,x=.5,y=.3,text='Accept unknown'}
G.Current=function()return current end
assert(G.RawNavTarget().blockedQuestID==999,'No confident arrow for unsupported pickup')
pfDB.quests.data[101].pre={500};assert(G.QuestAvailability(101).state=='needs_check')
current.questID=101;assert(G.RawNavTarget().blockedQuestID==101)
assert(not G.db.completedQuests[101] and not G.db.progress[G.Key(current)],'Blocking must never complete or skip a quest')
testQuestLog[101]={complete=false};assert(G.QuestAvailability(101).state=='active')
testQuestLog[101]=nil
local offered={{questID=101}};local active={}
C_GossipInfo={GetAvailableQuests=function()return offered end,GetActiveQuests=function()return active end}
G.ObserveQuestGiver();assert(G.QuestAvailability(101).state=='offered','Actual NPC offer overrides uncertain database prerequisite')
assert(G.QuestAvailability(200).state=='blocked','Same observed giver did not offer it')
clock=161;assert(G.QuestAvailability(200).state=='expected','Expired observation is unknown again, not permanent absence')
clock=170;G.ObserveQuestGiver();G.KnowledgeInvalidate();assert(G.QuestAvailability(200).state=='expected','Quest/level changes invalidate old offers')
local rows=G.AreaQuestList(17);assert(table.getn(rows)==6 and G.areaQuestSnapshot.zone==17)
assert(G.AreaQuestList(99) and table.getn(G.AreaQuestList(99))==0)
-- Real callback order: automation reads the offer before selecting it closes gossip.
G.db.autoAccept=true;G.db.progress={};G.state.steps={{id='offer',action='accept',questID=101,text='Accept Follow-up from Tonga.'}}
G.state.reviewReason=nil;G.pauseAuto=false
offered={{questID=101}};active={};local selected=0
C_GossipInfo.SelectAvailableQuest=function(id) assert(id==101);selected=selected+1;offered={} end
G.automation.Event('GOSSIP_SHOW')
assert(selected==1 and G.QuestAvailability(101).state=='offered','Observe before automatic selection closes the session')
event='GOSSIP_SHOW';K.frame.scripts.OnEvent()
assert(G.QuestAvailability(101).state=='offered','Later observer callback must not overwrite offer with stale empty lists')
G.db.autoAccept=false
-- Timeouts and malformed packets preserve confirmed history and never promote a cache.
pfDatabase.QueryServer(pfDatabase);G.PollPFHistory(8.1);assert(G.db.completedQuests[100] and G.db.pfServerHistory.count==2)
pfDatabase.QueryServer(pfDatabase);G.ReceivePFHistory('TWQUEST','104 corrupt');pfQuest_history={};G.PollPFHistory(8.1)
assert(not G.db.completedQuests[104] and G.db.completedQuests[100])
-- Live position changes follow only a loaded NPC of the correct entry and map.
local loaded=true;local north,west=5200,3100
function UnitTokenFromName()return loaded and 'visible' or nil end
function UnitPosition(token)if token=='player' then return 3000,5000,0,1 end;return west,north,-12,1 end
C_Map={GetMapPosFromWorldPos=function(map,p,zone)return zone,{x=p.x/10000,y=p.y/10000} end}
local s={questID=200,action='accept',zone=17,x=.523,y=.319}
local p=G.QuestNPCWaypoint(s);assert(p.x==.52 and p.y==.31 and p.height==-12 and p.evidence=='Observed quest giver position')
clock=171;north=5300;assert(G.QuestNPCWaypoint(s).x==.53)
clock=172;loaded=false;p=G.QuestNPCWaypoint(s);assert(p.x==.523 and p.evidence=='Quest NPC (pfQuest)','Unloaded NPC falls back to labelled database location')
clock=173;loaded=true;npc=999;p=G.QuestNPCWaypoint(s);assert(p.npc==3448 and p.x==.523,'Wrong same-name NPC cannot move waypoint')
print('PASS direct vs inferred/manual history, query timeout/corruption, live quest state, remote eligibility, cosmetic filters, NPC offers/absence/expiry, area catalogue and identity-checked live positions')
