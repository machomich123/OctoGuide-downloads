dofile('tests/test-runtime.lua')
local G=OctoGuide;local checked=0
local function body(s) local title,text=G.Present(s);return text end
local ordinary={action='accept',questID=812,text='Accept Need for a Cure.',personalClass='HUNTER',profiles={'Orc:HUNTER','Troll:HUNTER'}}
assert(not string.find(body(ordinary),'Personal HUNTER',1,true))
for _,action in ipairs({'accept','complete','objective','turnin','collect','use','travel','fly','buy'}) do
 assert(not string.find(body({action=action,text='Ordinary route step',questID=812,personalClass='HUNTER'}),'Personal HUNTER',1,true));checked=checked+1
end
assert(string.find(body({action='accept',text='Taming the Beast',questID=6062,personalClass='HUNTER'}),'Personal HUNTER quest',1,true))
assert(string.find(body({action='train',text='Train skills',personalClass='HUNTER'}),'HUNTER training',1,true))
assert(not G.PersonalClassTask({action='travel',text='Walk',personalClass='HUNTER'}))
assert(G.PersonalClassTask({action='use',personalClass='HUNTER',personalUnlock=true})=='unlock')
pfDB={quests={data={[6062]={class=0},[999001]={class=4},[999002]={class=8}}}}
assert(not G.PersonalClassTask({action='accept',questID=6062,personalClass='HUNTER'}),'Active database can remove an old class restriction')
assert(G.PersonalClassTask({action='accept',questID=999001,personalClass='HUNTER'})=='quest')
assert(not G.PersonalClassTask({action='accept',questID=999002,personalClass='HUNTER'}));pfDB=nil
local privateFile=os.getenv('OCTOGUIDE_FAMILY_TEST_FILE');assert(privateFile,'Actual local family fixture required')
dofile(privateFile)
local found,ordinaryCount,classCount=0,0,0
for _,guide in pairs(G.guides) do for _,s in ipairs(guide.steps or {}) do
 if s.questID==812 then found=found+1;assert(not G.PersonalClassTask(s) and not string.find(body(s),'Personal HUNTER',1,true)) end
 if s.personalClass=='HUNTER' then
  if G.PersonalClassTask(s)=='quest' then classCount=classCount+1;assert(string.find(body(s),'Personal HUNTER quest',1,true))
  elseif not G.PersonalClassTask(s) then ordinaryCount=ordinaryCount+1;assert(not string.find(body(s),'Personal HUNTER',1,true)) end
 end
end end
assert(found>0 and ordinaryCount>0 and classCount>0)
print('PASS class-label regression: '..found..' actual Need for a Cure steps; '..ordinaryCount..' ordinary Hunter-route steps without false labels; '..classCount..' real Hunter class-quest steps retain labels. Private data not exported.')
