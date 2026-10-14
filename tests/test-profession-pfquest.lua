dofile('tests/test-professions.lua')
local G=OctoGuide;local P=G.Professions
local function read(path) local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local source=read('W:/Games/Octowow/Interface/AddOns/pfQuest/map.lua')
local first=assert(string.find(source,'function pfMap:AddNode',1,true));local last=assert(string.find(source,'function pfMap:NodeClick',first,true))
local support="local similar_nodes,unifiedcache={},{};local function IsEmpty(t) for _ in pairs(t) do return false end return true end;local function GetLayerByTexture(t) return 1 end;"
pfMap={nodes={},tooltips={}};pfDatabase={BuildQuestDescription=function() return 'Profession database point' end}
assert(loadstring(support..string.sub(source,first,last-1)))()
local clock=100;function GetTime() return clock end
local updates=0;function pfMap:UpdateNodes() updates=updates+1 end
local opened;function pfMap:ShowMapID(zone) opened=zone;self:UpdateNodes();return true end
local start=assert(string.find(source,'  -- limit all map updates to once per .05 seconds',1,true));local finish=assert(string.find(source,'  -- reset map to current zone once map is closed',start,true))
local tick=assert(loadstring(string.sub(source,start,finish-1)))
local function process() clock=clock+.3;pfMap.throttle=nil;this=pfMap;tick() end
pfMap:AddNode({addon='Unrelated',title='Existing quest',zone=1,x=80,y=90,texture='quest'})
P.State().markerSeconds=120
assert(P.ShowLocation({name='Trainer',id=77,zone=1,x=20,y=30}))
assert(opened==1 and type(pfMap.queue_update)=='number')
local nodes=pfMap:GetNodes('OctoGuideProfessions',P.marker.title)
assert(table.getn(nodes)==1 and nodes[1].spawnid==77 and nodes[1].x==20 and nodes[1].y==30)
process();assert(pfMap.queue_update==nil)
local r,why=OctoGuideNavigation.ReadWaypoint(P.waypoint);assert(r and r.yards>0)
G.professionPanel:Show();arg1=.2;G.professionPanel.scripts.OnUpdate();assert(G.professionPanel.arrow:IsShown() and string.find(G.professionPanel.distance.value,'Trainer',1,true))
G.professionPanel:Hide();clock=221;P.timer.scripts.OnUpdate();assert(not P.marker and not P.waypoint)
assert(table.getn(pfMap:GetNodes('Unrelated','Existing quest'))==1)
process();assert(pfMap.queue_update==nil)
print('PASS installed pfQuest AddNode/GetNodes/DeleteNode and exact map update queue; profession direction and expiry preserve unrelated markers')
