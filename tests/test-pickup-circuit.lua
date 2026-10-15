dofile('tests/test-runtime.lua');dofile('TravelNotes.lua');dofile('LiveTargets.lua')
local family=assert(os.getenv('OCTOGUIDE_FAMILY_TEST_FILE'))
local db=os.getenv('OCTOGUIDE_PFQUEST_TEST_DIR') or 'W:/Games/Octowow/Interface/AddOns/pfQuest'
dofile(family)
pfDB={quests={},units={},objects={}}
dofile(db..'/db/quests.lua');dofile(db..'/db/units.lua');dofile(db..'/db/enUS/units.lua')
local G=OctoGuide;local current
G.Current=function() return current end
local playerX,playerY=.5,.3
function UnitPosition() return playerY*10000,playerX*10000,0,1 end
function GetPlayerFacing() return 0 end
C_Map={GetWorldPosFromMapPos=function(zone,p)return 1,{x=p.x*10000,y=p.y*10000} end}
G.db.progress={};G.pathCursors={}
local count,circuits,checks=0,0,0
for _,guide in pairs(G.guides) do for _,s in ipairs(guide.steps) do
 if s.questID==870 and s.action=='accept' then
  count=count+1;current=s
  local target=G.RawNavTarget()
  assert(target.npc==3448 and target.zone==17 and target.x==.523 and target.y==.319,'870 must point directly to Tonga, not the shared NPC tour')
  if s.path then
   circuits=circuits+1
   s.keepApproachPath=true;assert(not G.PickupCircuitWaypoint(s),'Explicit path preservation overrides a recognized shared circuit');s.keepApproachPath=nil
   for _,p in ipairs(s.path) do
    for _,offset in ipairs({-.002,0,.002}) do
     playerX=p.x+offset;playerY=p.y
     local chosen=G.RawNavTarget();assert(chosen.npc==3448 and chosen.x==.523 and chosen.y==.319)
     G.NavigationRead(s)
     assert(not G.pathCursors[s.page or s.id],'Reading the arrow must not advance the obsolete circuit')
     assert(G.navigationEvidence==chosen.evidence);checks=checks+1
    end
   end
   local title,body=G.Present(s)
   assert(string.find(body,'Talk to Tonga Runetotem.',1,true))
   assert(not string.find(body,'Zargh, Gazrog',1,true),'Do not show an unrelated whole-town pickup list')
  end
 end
end end
assert(count==5 and circuits==4)
-- Every resolvable action in the affected blocks uses its own exact giver.
local affected=0
for _,guide in pairs(G.guides) do for _,s in ipairs(guide.steps) do
 if s.zone==17 and s.path and (s.action=='accept' or s.action=='turnin') then
  local point=G.PickupCircuitWaypoint(s)
  if point then
   affected=affected+1;current=s;assert(G.RawNavTarget().npc==G.QuestNPCWaypoint(s).npc)
  end
 end
end end
assert(affected>10,'Regression covers other pickups, not only 870')
-- A single-giver approach, cross-zone path and explicitly retained route survive.
local route={id='approach',action='accept',questID=870,sourceGuide='approach',sourceBlock=1,zone=17,x=.523,y=.319,path={{zone=17,x=.52,y=.30},{zone=17,x=.523,y=.319}}}
G.guides.approach={steps={route}};current=route
assert(not G.PickupCircuitWaypoint(route));assert(G.RawNavTarget()==route.path[1])
route.keepApproachPath=true;assert(not G.PickupCircuitWaypoint(route))
-- No database means no guessed quest-giver replacement.
pfDB=nil;assert(not G.PickupCircuitWaypoint(route))
print('PASS 5 actual Forgotten Pools pickups; '..checks..' approach/pass-through positions; '..affected..' Barrens pickup/turn-in actions; stable exact NPC and retained genuine approach paths')
