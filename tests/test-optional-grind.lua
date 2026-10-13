dofile('tests/test-runtime.lua');dofile('OptionalSteps.lua')
local G=OctoGuide
G.db.progress={};G.db.completedQuests={};G.db.placements={};G.pauseAuto=false
function UnitLevel() return 3 end
function UnitXP() return 500 end;function UnitXPMax() return 1400 end
G.RegisterGuide({id='optional-test',title='XP test',faction='Horde'}, {
 {id='xp',action='level',text='Grind to 1120+/1400xp',level=3,levelXP=1120},
 {id='turn',action='turnin',text='Turn in Cutting Teeth to Gornek.',questID=788,minlevel=1},
 {id='take',action='accept',text='Accept Scorpid from Gornek.',questID=789,minlevel=4},
 {id='hard',action='level',text='Reach level 4',level=4}})
G.Select('optional-test');assert(G.Current().id=='turn')
assert(not G.db.progress[G.Key(G.state.steps[1])],'Optional does not mean completed')
local _,body=G.Present(G.Current());assert(string.find(body,'Optional: Grind to 1120',1,true))
function UnitXP()return 1200 end
assert(table.getn(G.OptionalGrinds(G.Current()))==0,'Reached XP removes suggestion')
G.db.progress[G.Key(G.Current())]='manual';assert(G.Current().id=='take')
local title=G.Present(G.Current());assert(string.find(title,'Reach level 4',1,true),'Real quest minimum remains')
G.db.progress[G.Key(G.Current())]='skipped';assert(G.Current().id=='hard','Non-grind level step remains required')
G.state.startIndex=1;G.state.reviewIndex=1;G.state.reviewReason='back';G.pauseAuto=true
assert(G.Current().id=='xp','Back can still inspect optional step')
print('PASS optional XP advice, truthful progress, XP completion, real minimum level and Back')
