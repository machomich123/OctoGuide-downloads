-- Functional invalidation AND operation budgets; deliberately no wall-time assertions.
local file=assert(io.open('tests/test-runtime.lua'));local source=file:read('*a');file:close()
local first=assert(string.find(source,"dofile('Core.lua')",1,true));assert(loadstring(string.sub(source,1,first-1)))()
local methods=getmetatable(UIParent).__index
for _,key in ipairs({'SetNumeric','SetAutoFocus','SetJustifyV'}) do methods[key]=function()end end
local clock=0;function GetTime()return clock end
local toc=assert(io.open('OctoGuide-downloads.toc'));for line in toc:lines() do if string.find(line,'%.lua$') then dofile(line) end end;toc:close()
local G=OctoGuide;G.Init();assert(G.ready)
local steps={}
for i=1,100 do steps[i]={id='past'..i,questID=100000+i,action='accept',text='Past'} end
steps[101]={id='a',action='note',text='Current',manual=true};steps[102]={id='b',action='note',text='Next',manual=true}
G.RegisterGuide({id='budget',title='Budget',faction='Horde'},steps)
G.db.progress={};G.db.completedQuests={}
for i=1,100 do G.db.progress['budget:past'..i]='observed';G.db.completedQuests[100000+i]=true end
G.Select('budget');G.refreshRemaining=nil;G.renderPending=nil
local key=G.Key;local reads=0
G.Key=function(s)reads=reads+1;return key(s)end
for frame=1,144 do
 clock=frame/144
 assert(G.RunProtected(function()for i=1,20 do assert(G.Current()==steps[101]) end end,'budget read'))
end
assert(reads<5000,'Long-guide scans must not scale with 20 reads x every display frame')
assert(G.runtimeReads==nil and G.questLookupCache==nil,'Read scopes must not leak')
assert(G.RunProtected(function()G.Mark('manual');assert(G.Current()==steps[102])end,'manual change'))
assert(G.RunProtected(function()G.Back();assert(G.Current()==steps[101])end,'Back change'))
G.pauseAuto=false;G.state.reviewIndex=nil;G.db.progress['budget:a']=nil
assert(G.RunProtected(G.Event,'event QUEST_LOG_UPDATE','QUEST_LOG_UPDATE'))
assert(G.Current()==steps[101],'Events invalidate prior progress snapshots')
local modeKey={id='same',action='note',modes={normal=true,hardcore=true}}
assert(G.Key(modeKey)=='budget:same');modeKey.modes.normal=nil;assert(string.find(G.Key(modeKey),':mode:',1,true),'In-place mode restrictions cannot reuse a different key')
print('PASS bounded route reads, immediate Mark/Back/event invalidation and mode-key isolation; '..reads..' key reads')
-- pfQuest's native pin callbacks are outside our ordinary OnUpdate scope.
-- They must not walk the whole guide separately for every recycled pin.
pfMap={pins={},mpins={},UpdateNode=function(self,f,node)f.defsize=14;f.node=node end}
OctoGuideMap.Install();local pin={defsize=14,SetWidth=function()end,SetHeight=function()end}
local before=reads
for i=1,1000 do pfMap:UpdateNode(pin,{{questid=987654,QTYPE='OBJECTIVE'}}) end
assert(reads-before<1000,'Native pin updates must share the route model too')
print('PASS 1000 native pfQuest callbacks share one bounded route model')

-- Same native unit list/identity/closest query shared across concurrent quests.
local identities,plates,names,closest=0,0,0,0
local list={};for i=1,40 do list[i]={} end
C_NamePlate={GetNamePlates=function()plates=plates+1;return list end}
function UnitCreatureID()identities=identities+1;return 999999 end
function UnitTokenFromName()names=names+1;return nil end
function UnitIsDeadOrGhost()return false end
function UnitHealth()return 100 end
function OctoGuideClosestLivingUnit()closest=closest+1;return nil end
function GetQuestLogLeaderBoardID()return 777,'monster' end
pfDB={units={loc={[777]='Creature'},data={[777]={coords={{10,0,1}}}}},quests={data={}}}
local targets={}
for i=1,6 do local id=900+i;testQuestLog[id]={objectives={{'Creature slain: 0/8',nil}}};targets[i]={id='q'..i,questID=id,action='objective',zone=1,x=.1,y=0} end
assert(G.RunProtected(function()for _,s in ipairs(targets) do assert(G.ReadObservedTarget(s)==nil)end end,'concurrent samples'))
assert(identities==48 and plates==1 and names==1 and closest==1,'Concurrent quests must not repeat world/identity scans for the same targets')
identities=0
assert(G.RunProtected(function()G.ReadObservedTarget(targets[1])end,'next frame'))
assert(identities==48,'No native evidence is reused beyond the frame/read boundary')
print('PASS six concurrent quests share 48 identity reads and one nameplate/name/closest query')

-- No periodic full cache flush after 100 refreshes of the SAME objective.
local resolve=G.ResolveSecondary;G.ResolveSecondary=function()return nil end
G.secondaryPoll={};G.secondaryPollCount=0
G.ResolveSecondary=function(s)return {label=s.sourceGuide}end
assert(G.SecondaryRead({id='same-pin',sourceGuide='one'}).label=='one')
assert(G.SecondaryRead({id='same-pin',sourceGuide='two'}).label=='two','Pins from different guides cannot collide on a reused step ID')
G.ResolveSecondary=function()return nil end
G.secondaryPoll={};G.secondaryPollCount=0
for i=1,250 do clock=clock+.13;G.SecondaryRead(targets[1]) end
local n=0;for k in pairs(G.secondaryPoll) do n=n+1 end
assert(n==1 and G.secondaryPollCount==1)
for i=1,140 do clock=clock+.13;G.SecondaryRead({id='unique'..i}) end
n=0;for k in pairs(G.secondaryPoll) do n=n+1 end
assert(n==100 and G.secondaryPollCount==100,'Evict one old key; never clear all active targets together')
G.ResolveSecondary=resolve
print('PASS secondary cache remains warm across refreshes and bounded at 100 distinct keys')

-- Graph preparation is bounded per display tick; same-value targets share plans.
local T=G.Travel;T.nodes=nil;T.edges=nil;T.loading=nil;T.observePending=nil
Enum={FlightPathFaction={Horde=1,Neutral=2}}
local paths={};for i=1,40 do paths[i]={fromNodeID=1,toNodeID=2,pathID=i,cost=10} end
local calls=0
C_TaxiMap={GetTaxiNodesForMap=function()return {{nodeID=1,faction=1,areaID=1,mapX=1,mapY=0,name='A'},{nodeID=2,faction=1,areaID=1,mapX=80,mapY=0,name='B'}}end,
 GetTaxiPaths=function()return paths end,
 GetTaxiPathWaypoints=function()calls=calls+1;return {{x=0,y=0,z=0},{x=32,y=0,z=0}}end}
assert(not T.Load() and calls==4)
for i=1,20 do assert(not T.Load())end;assert(calls==4,'Repeated requests within one tick cannot defeat the load budget')
local loaded=false
while not loaded do local before=calls;clock=clock+1/144;loaded=T.Load();assert(calls-before<=4)end
assert(calls==40)
-- A deferred flight capture must never query a closed native taxi window.
T.nodes=nil;T.loading=nil;T.observePending=true;calls=0
local taxiReads=0;TaxiFrame={IsShown=function()return false end}
C_TaxiMap.GetAllTaxiNodes=function()taxiReads=taxiReads+1;error('closed taxi window')end
loaded=false
while not loaded do clock=clock+1/144;loaded=T.Load()end
assert(taxiReads==0 and not T.observePending,'Do not read native taxi state after the window closed')
TaxiFrame=nil
G.db.travel={known={[1]=true,[2]=true},reachable={[1]={[2]=true}}};T.cache=nil;T.graphRuns=0
function GetMoney()return 100 end
local plan=T.Plan({zone=1,x=.9,y=0});assert(plan and plan.mode=='flight')
for i=1,200 do assert(T.Plan({zone=1,x=.9,y=0})==plan)end
assert(T.graphRuns<=2,'Fresh tables with identical coordinates cannot rebuild all flight paths')
function GetMoney()return 0 end;clock=clock+1.01
assert(T.Plan({zone=1,x=.9,y=0})==nil,'Recomputed plan must respect changed money')
print('PASS four-path loading budget, coordinate-value cache, single-source graph reuse and flight cost validation')

-- Records remain bounded and distinguish frame interval from addon duration.
local ms=0;function debugprofilestop()return ms end
arg1=.1
assert(G.RunProtected(function()ms=ms+.25 end,'refresh'))
assert(G.performance.slowFrames>=1 and G.performance.lastRefreshMs==.25)
arg1=.006
for i=1,100 do assert(G.RunProtected(function()ms=ms+3 end,'refresh'))end
assert(G.performance.slowOwn>=100 and table.getn(G.performance.recent)<=32)
for i=1,100 do G.RunProtected(function()end,'custom '..i)end
assert(G.performance.phaseCount<=32)
local snapshot=G.PerformanceSnapshot();local calls=snapshot.phases.refresh.calls
G.RunProtected(function()end,'refresh');assert(snapshot.phases.refresh.calls==calls,'Reports must not retain a live growing measurement table')
debugprofilestop=nil;G.RunProtected(function()end,'refresh');assert(not G.performance.timerAvailable and string.find(G.PerformanceText(),'unavailable',1,true))
for _,pool in ipairs(G.callbackPools) do for _,bucket in pairs(pool.reads) do if type(bucket)=='table' and bucket.slots then assert(table.getn(bucket.slots)<=128,'Callback record pools must remain bounded') end end end
print('PASS bounded local timing log, separate frame/own measurements, absent-timer handling and immutable report snapshots')
