-- Local compatibility check. Private route content is not redistributed.
local file=assert(io.open('tests/test-runtime.lua'));local source=file:read('*a');file:close()
assert(loadstring(string.sub(source,1,assert(string.find(source,"dofile('Core.lua')",1,true))-1)))()
dofile('Core.lua');dofile('Route.lua');dofile('OptionalSteps.lua');dofile('Presentation.lua')
local privateFile=os.getenv('OCTOGUIDE_FAMILY_TEST_FILE')
if not privateFile then print('SKIP private family compatibility fixture unavailable');return end
dofile(privateFile)
local G=OctoGuide;G.player={class='HUNTER',race='Orc',faction='Horde'};G.ready=true
G.db={progress={},completedQuests={},mode='hardcore',placements={}}
function UnitLevel()return 3 end;function UnitXP()return 500 end;function UnitXPMax()return 1400 end
G.Render=function()end
local id='rxp-hardcore-1-6-orc-troll';local guide=G.guides[id]
assert(guide.steps[11].text=='Grind to 1120+/1400xp' and guide.steps[11].levelXP==1120)
G.db.placements[id]={stepID=guide.steps[11].id};G.Select(id,'restore')
for i=1,10 do G.db.progress[G.Key(guide.steps[i])]='manual' end
testQuestLog[788]={complete=1}
local s=G.Current();assert(s and s~=guide.steps[11] and G.IsOptionalGrind(guide.steps[11]))
if s.action=='note' then G.db.progress[G.Key(s)]='manual';s=G.Current() end
assert(s.action=='turnin' and s.questID==788)
local _,body=G.Present(s);assert(string.find(body,'Optional: Grind to 1120+/1400xp',1,true))
assert(not G.db.progress[G.Key(guide.steps[11])])
print('PASS actual locally installed family XP step moves beneath Cutting Teeth turn-in')
