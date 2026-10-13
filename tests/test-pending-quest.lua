dofile('tests/test-runtime.lua')
local G=OctoGuide;G.Render=function()end;G.db.progress={};G.db.completedQuests={};G.db.placements={};G.pauseAuto=false
G.RegisterGuide({id='senjin-regression',faction='Horde'}, {
 {id='take',action='accept',text='Accept Thwarting Kolkar Aggression.',questID=786},
 {id='plans',action='complete',text='Destroy the attack plans.',questID=786,zone=14,x=.5,y=.8},
 {id='turn',action='turnin',text='Return to Senjin.',questID=786,zone=14,x=.55,y=.74},
 {id='razor',action='travel',text='Travel to Razor Hill.',manual=true,zone=14,x=.52,y=.42}})
local guide=G.guides['senjin-regression'];testQuestLog[786]={complete=false}
G.db.placements[guide.id]={stepID='razor',reason='old automatic cursor'}
G.db.progress[guide.id..':plans']='observed';G.db.progress[guide.id..':turn']='observed'
G.Select(guide.id,'restore');assert(G.Current().id=='plans','Live incomplete quest must recover behind cursor/stale flags')
assert(not G.db.completedQuests[786] and G.db.placements[guide.id].reason=='unfinished active quest')
testQuestLog[786].complete=1;G.Event('QUEST_LOG_UPDATE');assert(G.Current().id=='turn','Complete objectives need return to quest giver')
assert(not G.db.completedQuests[786],'Ready is not rewarded')
testQuestLog[786]=nil;G.Event('QUEST_TURNED_IN',786);assert(G.Current().id=='razor','Confirmed turn-in releases Razor Hill')
-- Explicit manual choices and direct jumps remain user decisions.
G.db.completedQuests={};G.db.progress={[guide.id..':plans']='skipped'};testQuestLog[786]={complete=false};G.db.placements[guide.id]={stepID='razor'}
G.Select(guide.id,'restore');assert(G.Current().id=='razor','Explicit skip must be respected')
G.db.progress={};G.db.placements[guide.id]={stepID='razor',reason='manual step selection'}
G.Select(guide.id,'restore');assert(G.Current().id=='razor','Explicit jump does not rewind past manual start')
-- Conditional exclusions can become eligible; old observed marks must not hide them.
G.db.progress={[guide.id..':plans']='observed'};G.db.placements[guide.id]={stepID='razor',reason='automatic'}
G.Select(guide.id,'restore');assert(G.Current().id=='plans')
G.db.progress={[guide.id..':plans']='observed',[guide.id..':turn']='observed',[guide.id..':razor']='manual'}
G.state.startIndex=table.getn(G.state.steps)+1;assert(G.Current().id=='plans','Route end must not hide an active unfinished quest')
print('PASS Senjin plans -> ready turn-in -> Razor Hill, stale cursor/flags and explicit choices')
