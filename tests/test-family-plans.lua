local file=assert(io.open('tests/test-runtime.lua'));local source=file:read('*a');file:close()
assert(loadstring(string.sub(source,1,assert(string.find(source,"dofile('Core.lua')",1,true))-1)))()
dofile('Core.lua');dofile('Route.lua')
local privateFile=os.getenv('OCTOGUIDE_FAMILY_TEST_FILE');if not privateFile then print('SKIP local family fixture unavailable');return end
dofile(privateFile)
function UnitLevel()return 8 end
local G=OctoGuide;G.player={class='HUNTER',race='Orc',faction='Horde'};G.Render=function()end
G.db={progress={},completedQuests={},placements={},mode='hardcore'};G.ready=true
local guide=G.guides['rxp-hardcore-6-13-orc-troll'];assert(guide)
for _,s in ipairs(guide.steps) do G.db.progress[guide.id..':'..s.id]='manual' end
local razor
for _,s in ipairs(guide.steps) do
 if s.questID==786 then G.db.progress[guide.id..':'..s.id]='observed' end
 if s.id=='b47-l3' then razor=s;G.db.progress[guide.id..':'..s.id]=nil end
end
assert(razor and razor.zone==14)
testQuestLog[786]={complete=false,objectives={{'First plan',false},{'Second plan',false},{'Third plan',false}}}
G.db.placements[guide.id]={stepID=razor.id,reason='old automatic cursor'};G.Select(guide.id,'restore')
assert(G.Current().questID==786 and G.Current().action=='complete','Actual family plans recover before Razor Hill')
testQuestLog[786].complete=1;for _,o in ipairs(testQuestLog[786].objectives)do o[2]=1 end
G.Event('QUEST_LOG_UPDATE');assert(G.Current().questID==786 and G.Current().action=='turnin','Actual family return to Senjin')
testQuestLog[786]=nil;G.Event('QUEST_TURNED_IN',786);assert(G.Current()==razor,'Actual family Razor Hill only after reward')
print('PASS actual local family plans recovery, Senjin turn-in and Razor Hill progression')
