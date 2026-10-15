-- Performance assertions count actual work, without claiming game FPS.
dofile('tests/test-runtime.lua')
local G=OctoGuide
testQuestLog[777]={objectives={{'Collect',nil}}}
G.RegisterGuide({id='perf-progress',title='Perf',faction='Horde'},{{id='work',questID=777,action='objective',objective=1,text='Work',zone=1,x=.1,y=0},{id='reward',questID=777,action='turnin',text='Turn in',zone=1,x=.1,y=0}})
G.Select('perf-progress');assert(G.Current().id=='work')
testQuestLog[777].objectives[1][2]=1;G.Event('QUEST_LOG_UPDATE')
assert(G.Current().id=='reward','Progression must remain immediate before the visual flush')
arg1=.01;G.events.scripts.OnUpdate()
local title=G.Present(G.Current());assert(G.frame.step:GetText()==title,'Next drawing must show the final live step')
G.refreshRemaining=nil
local labelWrites,anchors,rotations=0,0,0
local f=G.frame
for _,label in ipairs({f.distance,f.heightLabel}) do
 local set=label.SetText;label.SetText=function(self,text)labelWrites=labelWrites+1;set(self,text)end
end
local clear=f.heightLabel.ClearAllPoints;f.heightLabel.ClearAllPoints=function(self)anchors=anchors+1;clear(self)end
local rotate=f.arrow.SetRotation;f.arrow.SetRotation=function(self,a)rotations=rotations+1;rotate(self,a)end
G.UpdateArrow(.01);labelWrites=0
for i=1,144 do G.UpdateArrow(1/144) end
assert(labelWrites==0 and anchors==0 and rotations==145,'Keep smooth arrow animation without rewriting stationary labels/anchors')
print('PERF stationary primary arrow: no repeated label writes/anchor resets; rotation still updates every frame')
local saved={Sync=G.Sync,Render=G.Render,ScanCharacter=G.ScanCharacter,UpdateArrow=G.UpdateArrow}
local scans,syncs,renders=0,0,0
G.characterScan={};G.TrainingEvent=nil
G.ScanCharacter=function()scans=scans+1 end
G.Sync=function()syncs=syncs+1 end;G.Render=function()renders=renders+1 end
G.UpdateArrow=function()end
for i=1,5 do G.Event('BAG_UPDATE',i-1) end
assert(scans==5 and syncs==5 and renders==0,'Keep evidence/progression immediate, defer only visual work')
arg1=.01;G.events.scripts.OnUpdate()
assert(renders==1 and not G.renderPending,'One visible rebuild for an event burst')
for i=1,124 do arg1=.01;G.events.scripts.OnUpdate() end
assert(renders==7,'Retain all six delayed client-state checks')
print('PERF five bag events: 11 -> '..renders..' panel rebuilds; all delayed checks retained')
renders=0;G.Event('QUEST_ACCEPTED',987);assert(renders==1,'Explicit quest events remain immediate')
for k,v in pairs(saved) do G[k]=v end

-- A bag event still reads live inventory AND regressed collection objectives.
dofile('CharacterScan.lua')
local histories,quests,inventory=0,0,0
pfQuest_history={[123]={10,5}};G.characterScan=nil
local readHistory=G.ReadPFQuestHistory
G.ReadPFQuestHistory=function()histories=histories+1;return readHistory() end
function GetNumQuestLogEntries()quests=quests+1;return 1 end
C_QuestLog.GetQuestIDForLogIndex=function()return 123 end
local complete=true
function GetQuestLogTitle()return 'Collect',1,nil,false,false,complete end
function GetNumQuestLeaderBoards()return 0 end
function GetContainerNumSlots(b)if b==0 then return 1 else return 0 end end
local carried=true
function GetContainerItemLink()inventory=inventory+1;if carried then return 'item:999:0:0:0' end end
function GetContainerItemInfo()return nil,1 end
function GetInventoryItemLink()return nil end
G.ScanCharacter();carried=false;complete=false
for i=1,5 do G.ScanCharacter('BAG_UPDATE') end
assert(histories==1 and quests==6 and inventory==6,'Skip only unrelated history copies; keep mutable evidence live')
assert(not G.characterScan.items[999] and not G.characterScan.quests[123].complete)
pfQuest_history[124]={20,6};G.ScanCharacter('QUEST_LOG_UPDATE');assert(histories==2 and G.characterScan.pfQuestCount==2)
print('PERF five bag events: history copies 5 -> 0; inventory/objectives remain fresh')

-- Native map dimensions must be checked after hover/native changes.
local current={questID=123,action='accept'};local currentReads,writes=0,0
G.Current=function()currentReads=currentReads+1;return current end
G.db.mapOptions={targets=true,minimap=true}
pfMap={pins={},mpins={},UpdateNode=function(self,f,node)f.defsize=14;f.node=node;f.width=14;f.height=14 end}
for i=1,1000 do
 local f={defsize=14,width=14,height=14,node={{questid=123,QTYPE='NPC_START'}}}
 function f:GetWidth()return self.width end
 function f:GetHeight()return self.height end
 function f:SetWidth(n)self.width=n;writes=writes+1 end
 function f:SetHeight(n)self.height=n;writes=writes+1 end
 pfMap.pins[i]=f
end
dofile('Map.lua');G.BuildMaps();G.UpdateMaps(true)
local matches=0;local match=OctoGuideMap.Matches
OctoGuideMap.Matches=function(s,n)matches=matches+1;return match(s,n) end
writes=0;currentReads=0
for i=1,2 do arg1=.5;OctoGuideMap.driver.scripts.OnUpdate() end
assert(writes==0 and matches==2000 and currentReads==2,'Each frame once; no unchanged dimensions rewritten')
local f=pfMap.pins[1];assert(f.defsize==17.5,'Initial highlight never compounds')
pfMap.highlight='test';pfMap.highlightdb={[f]={test=true}};f.width=30;G.UpdateMaps();assert(f.width==30)
pfMap.highlight=nil;G.UpdateMaps();assert(f.width==17.5,'Native hover reset remains correct')
pfMap:UpdateNode(f,{{questid=999,QTYPE='NPC_START'}});assert(f.width==14 and not OctoGuideMap.highlighted[f])
current={questID=999,action='accept'};G.UpdateMaps();assert(f.width==17.5 and pfMap.pins[2].width==14)
G.SetMapOption('targets',false);assert(f.width==14)
print('PERF 1000 highlighted pins/second: 8000 -> 0 unchanged dimension writes; hover/recycling/step changes retained')

-- Cache searches; always re-read and verify the identity and moving positions.
dofile('LiveTargets.lua');dofile('Height.lua')
local clock,lookups,npcZ,playerZ,entry=0,0,30,10,2055
function GetTime()return clock end
local found=false
function UnitTokenFromName()lookups=lookups+1;if found then return 'npc' end end
function UnitCreatureID()return entry end
function UnitPosition(token)if token=='player' then return 10,20,playerZ,0 else return 12,24,npcZ,0 end end
pfDB={quests={data={[447]={['end']={U={2055}}},[448]={['end']={U={2055}}}}},units={loc={[2055]='Faranell'}}}
C_Map.GetWorldPosFromMapPos=function()return 0,{x=24,y=12} end
local s={questID=447,action='turnin',zone=1497,x=.5,y=.5}
for i=1,144 do assert(G.WaypointHeight(s)==nil);clock=clock+1/144 end
assert(lookups<=9,'Negative name lookups are bounded independently of FPS')
print('PERF 144 FPS missing NPC: 144 -> '..lookups..' identity searches/second')
clock=2;found=true;assert(G.WaypointHeight(s)==20)
npcZ=35;playerZ=12;assert(G.WaypointHeight(s)==23,'Do not cache moving heights')
entry=999;assert(G.WaypointHeight(s)==nil,'Reused token cannot supply another NPC height')
entry=2055;found=false;clock=3;assert(G.WaypointHeight(s)==nil)
found=true;s.questID=448;assert(G.WaypointHeight(s)==23,'Step changes invalidate negative lookup')
found=false;G.knowledge={revision=1};assert(G.WaypointHeight(s)==nil)
found=true;G.knowledge.revision=2;assert(G.WaypointHeight(s)==23,'Quest updates invalidate negative lookup')
print('PASS performance regressions, delayed observations, live inventory/objectives, map behavior and NPC identity/height')
