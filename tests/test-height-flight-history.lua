dofile('tests/test-runtime.lua')
dofile('CharacterScan.lua');dofile('LiveTargets.lua');dofile('Travel.lua');dofile('Height.lua');dofile('FlightFallback.lua')
local G=OctoGuide
assert(G.HeightText(15.4)=='Up 15 yd');assert(G.HeightText(-22)=='Down 22 yd')
assert(G.HeightText(2)=='Same height');assert(G.HeightText(nil)=='Height unknown')
pfDB={quests={data={[447]={['end']={U={2055}}}}},units={loc={[2055]='Faranell'}}}
function UnitTokenFromName(name,exact) assert(name=='Faranell' and exact);return 'npc' end
function UnitCreatureID(token) return 2055 end
local npcHeight=-50;local playerHeight=10
function UnitPosition(token) if token=='player' then return 10,20,playerHeight,0 end;return 12,24,npcHeight,0 end
C_Map={GetWorldPosFromMapPos=function() return 0,{x=24,y=12} end}
local quest={questID=447,action='turnin',zone=1497,x=.5,y=.5}
assert(G.WaypointHeight(quest)==-60)
npcHeight=30;assert(G.WaypointHeight(quest)==20)
function UnitCreatureID() return 999 end;assert(G.WaypointHeight(quest)==nil,'Wrong NPC must not supply height')
assert(G.WaypointHeight({zone=1497,x=.5,y=.5})==nil,'2D waypoint cannot imply altitude')
G.db.travel={known={},knownNames={}};G.Travel.nodes={[11]={name='Undercity, Tirisfal',areaID=1497,mapX=63,mapY=48}};G.Travel.Load=function()return true end
local fly={id='fly',action='fly',text='Fly to Undercity',zone=130,x=.45,y=.42,manual=true}
local f=G.FlightFallback(fly);assert(f and f.target.zone==1497 and string.find(f.body,'elevator',1,true))
local title,body=G.Present(fly);assert(title=='Travel to Undercity')
G.db.travel.known[11]=true;G.db.travel.knownNames[11]='Undercity, Tirisfal'
assert(G.FlightFallback(fly)==nil);assert(G.Present(fly)=='Fly to Undercity')
G.db.travel.known[11]=nil;assert(G.FlightFallback(fly),'Both directions must update without stale cache')
local other=G.FlightFallback({action='fly',text='Fly to Orgrimmar',zone=130,x=.4,y=.4});assert(other and not other.target.zone,'Unknown destination must not reuse departure')
pfQuest_history={[447]={12345,15},[999]={0,0},bad={0,0},[888]=false}
G.db.completedQuests={};assert(G.ReadPFQuestHistory()==2)
assert(G.db.pfQuestHistory[447].timestamp==12345 and not G.db.completedQuests[447],'pfQuest manual history is separate from server proof')
print('PASS height signs, unknown and mismatched NPC, flight fallback both directions, no departure arrow, pfQuest provenance')
