dofile('tests/test-runtime.lua');dofile('LiveTargets.lua')
local G=OctoGuide
local step={action='accept',questID=812,zone=14,x=.4154,y=.1859,text='Accept Need for a Cure.'}
local target=G.QuestNPCWaypoint(step);assert(target.x==.431 and target.y==.193 and target.npc==3190)
local old=G.Current;G.Current=function() return step end
assert(G.RawNavTarget().x==.431 and G.NavTarget().y==.193)
G.NavigationRead(step);assert(G.navigationEvidence=='Quest NPC (database)')
pfDB={quests={data={[812]={start={U={3190}},['end']={U={3190}}}}},units={data={[3190]={coords={{43.1,19.3,14},{43.1,19.3,14}}}},loc={[3190]='Rhinag'}}}
target=G.QuestNPCWaypoint(step);assert(target.x==.431 and target.evidence=='Quest NPC (pfQuest)')
step.action='turnin';assert(G.QuestNPCWaypoint(step).npc==3190)
step.action='complete';assert(not G.QuestNPCWaypoint(step));step.action='accept'
local x,y=step.x,step.y;G.QuestNPCWaypoint(step);assert(step.x==x and step.y==y,'Source route is not rewritten')
pfDB.units.data[3190].coords[3]={45,20,14};assert(not G.QuestNPCWaypoint(step),'Multiple spawns stay ambiguous')
pfDB.units.data[3190].coords={{43.1,19.3,15}};assert(not G.QuestNPCWaypoint(step),'Do not replace destination with another zone')
pfDB.quests.data[812].start.U={3190,3191};assert(not G.QuestNPCWaypoint(step),'Do not choose between multiple NPCs')
pfDB.quests.data[812].start={O={77}};pfDB.objects={data={[77]={coords={{10,20,14}}}},loc={[77]='Quest Object'}}
assert(G.QuestNPCWaypoint(step).evidence=='Quest object (pfQuest)')
G.Current=old;pfDB=nil
local fixture=os.getenv('OCTOGUIDE_FAMILY_TEST_FILE');assert(fixture);dofile(fixture)
local n=0
for _,guide in pairs(G.guides) do for _,s in ipairs(guide.steps or {}) do if s.questID==812 then n=n+1;assert(G.QuestNPCWaypoint(s).x==.431 and G.QuestNPCWaypoint(s).y==.193) end end end
assert(n==6)
print('PASS quest-location regression: all six actual 812 steps, accept/turnin, objects, ambiguity, zone constraints and immutable source routes. Private data not exported.')
