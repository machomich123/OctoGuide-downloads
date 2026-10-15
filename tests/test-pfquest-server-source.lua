dofile('tests/test-runtime.lua');dofile('Placement.lua');dofile('CharacterScan.lua');dofile('QuestAutomation.lua');dofile('LiveTargets.lua');dofile('QuestKnowledge.lua')
local G=OctoGuide;local K=G.knowledge;local clock=100
function GetTime()return clock end
G.db.completedQuests={};G.db.progress={};G.ready=true;G.pauseAuto=false
G.AutoPlace=function()return true end;G.ReconcileCharacter=function()end
QueryQuestsCompleted=nil;GetQuestsCompleted=nil
pfDB={quests={data={[1001]={pre={1002},close={1003}},[1002]={},[1003]={}}}}
pfQuest_history={[888]={0,0}};local resets=0
pfQuest={ResetAll=function()resets=resets+1 end};pfDatabase={}
local dispatched=0
function SendChatMessage(message,channel)assert(message=='.queststatus' and channel=='GUILD');dispatched=dispatched+1 end
local file=assert(io.open('W:/Games/Octowow/Interface/AddOns/pfQuest-turtle/patchtable.lua'))
local source=file:read('*a');file:close()
local start=assert(string.find(source,'local function strsplit(',1,true))
local finish=assert(string.find(source,'-- Automatically clear quest cache',start,true))
local create=CreateFrame;local query
CreateFrame=function(...)query=create(unpack(arg));return query end
assert(loadstring(string.sub(source,start,finish-1)))();CreateFrame=create
query.UnregisterEvent=function(self,name)self.events[name]=nil end
-- Mock only native frame dispatch; execute the installed pfQuest handlers.
query.Show=function(self)self.shown=true;local prior=this;this=self;self.scripts.OnShow();this=prior end
query.Hide=function(self)self.shown=false;local prior=this;this=self;self.scripts.OnHide();this=prior end
assert(G.InstallPFHistoryHook())
assert(G.FindStep(false));assert(dispatched==1 and K.history)
event='CHAT_MSG_ADDON';arg1='TWQUEST';arg2='1001';this=query;query.scripts.OnEvent();this=nil
K.frame.scripts.OnEvent()
assert(query.history[1002] and query.history[1003],'Installed pfQuest recursively expands pre/close records')
clock=104;this=query;query.scripts.OnUpdate();this=nil
assert(resets==1 and pfQuest_history[1001] and pfQuest_history[1002] and pfQuest_history[1003])
G.UpdateFindStep(3.6)
assert(G.db.completedQuests[1001] and G.db.pfServerHistory.count==1)
assert(not G.db.completedQuests[1002] and not G.db.completedQuests[1003] and not G.db.completedQuests[888],'Derived and manual entries cannot become server facts')
-- Upstream replaces its cache even on an empty timed-out request. Keep facts.
assert(G.FindStep(false));clock=108;this=query;query.scripts.OnUpdate();this=nil
assert(next(pfQuest_history)==nil);G.UpdateFindStep(8.1)
assert(G.db.completedQuests[1001] and G.db.pfServerHistory.count==1 and not G.pendingFind)
print('PASS installed pfQuest-turtle query/packet/finalization source with mocked server; inferred pre/close excluded; empty upstream cache cannot erase confirmed history')
