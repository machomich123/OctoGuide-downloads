local file=assert(io.open('tests/test-runtime.lua'));local source=file:read('*a');file:close()
assert(loadstring(string.sub(source,1,assert(string.find(source,"dofile('Core.lua')",1,true))-1)))()
dofile('Core.lua');dofile('Route.lua');dofile('RouteRepairs.lua')
local privateFile=os.getenv('OCTOGUIDE_FAMILY_TEST_FILE');if not privateFile then print('SKIP local family fixture unavailable');return end
OctoGuide.testAllProfiles=true;dofile(privateFile)
local G=OctoGuide;G.player={class='HUNTER',race='Orc',faction='Horde'};G.Render=function()end;G.ready=true
G.db={progress={},completedQuests={},placements={},mode='hardcore'}
function UnitLevel()return 13 end
function GetItemCount()return 0 end;function GetContainerNumSlots()return 0 end
function GetInventoryItemLink(_,slot)return slot==18 and 'item:2506:0:0:0'end
for _,id in ipairs({'rxp-hardcore-6-13-orc-troll','rxp-normal-6-10-durotar'}) do
 local g=G.guides[id];local n=0
 for _,s in ipairs(g.steps)do if s.action=='vendor' and string.find(s.text,'Hornwood',1,true)then n=n+1;assert(s.goalItemID==2506 and G.Satisfied(s),'Every actual repeated Hornwood vendor goal sees equipped bow')elseif s.action=='collect' and s.itemID==2506 then assert(G.Satisfied(s),'Equipped bow is counted even when client GetItemCount returns zero')end end
 assert(n==3)
end
for _,id in ipairs({'rxp-hardcore-13-15-silverpine-forest','rxp-normal-12-14-silverpine-forest'})do
 local g=G.guides[id];local accept,turn,wild
 for i,s in ipairs(g.steps)do if s.questID==428 then if s.action=='accept'then accept=i else turn=i end elseif s.questID==429 and s.action=='accept'then wild=i end end
 assert(accept==1 and turn<wild and g.steps[accept].entity==1952 and g.steps[turn].entity==1950)
end
local g=G.guides['rxp-hardcore-13-15-silverpine-forest']
G.db.placements[g.id]={stepID='b6-l4',reason='automatic'};G.Select(g.id,'restore')
assert(G.Current().questID==428 and G.Current().action=='accept','Existing Wild Hearts cursor recovers actual missing prerequisite')
print('PASS all six actual bow stops and both family Wild Hearts routes with stable original step IDs')
