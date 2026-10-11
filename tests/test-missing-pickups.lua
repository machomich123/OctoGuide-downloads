dofile('tests/test-runtime.lua')
dofile('Placement.lua')
local G=OctoGuide
local active={}
local function reset()
 active={};G.guides={};G.order={};G.state=nil;G.pauseAuto=false;G.hasFamilyRoutes=true
 C_QuestLog={GetLogIndexForQuestID=function(id) return active[id] and id or 0 end}
 G.player={race='Troll',class='ROGUE',faction='Horde'}
 G.db={progress={},completedQuests={},mode='hardcore',routeSource='rxp',placements={}}
 G.RegisterGuide({id='senjin',title='Level 6-13',faction='Horde',mode='hardcore',routeFamily='rxp',startLevel=6,endLevel=13},{
 {id='prey',action='accept',text='Prey',questID=817,expectedLevel=6.03},
 {id='skull',action='accept',text='Skull',questID=808,expectedLevel=6.03},
 {id='work',action='complete',text='Complete Skull',questID=808,expectedLevel=8,zone=1,x=.1,y=.1}})
end
function UnitLevel() return 8 end
function UnitXP() return 0 end
function UnitXPMax() return 100 end
function GetQuestLogTitle(id) return 'Quest',8,nil,false,false,active[id] and active[id].complete end
reset();local p=G.FindPlacement();assert(p.steps[p.index].id=='prey','Level estimate skipped pickup')
reset();G.db.placements.senjin={stepID='work'};G.Select('senjin','restore');assert(G.Current().id=='prey','Saved cursor skipped independent pickup')
active[817]={};G.Sync();assert(G.Current().id=='skull');active[808]={};G.Sync();assert(G.Current().id=='work')
active[808]=nil;G.Sync();assert(G.Current().id=='skull','Abandon should return to pickup')
reset();G.db.completedQuests[817]=true;active[808]={};G.db.placements.senjin={stepID='work'};G.Select('senjin','restore');assert(G.Current().id=='work','Confirmed history rewound')
reset();G.db.progress['senjin:prey']='skipped';G.db.progress['senjin:skull']='manual';G.db.placements.senjin={stepID='work'};G.Select('senjin','restore');assert(G.Current().id=='work','Explicit decision ignored')
reset();C_QuestLog=nil;G.db.placements.senjin={stepID='work'};G.Select('senjin','restore');assert(G.Current().id=='work','Missing API treated as absence')
local f=io.open('FamilyGuides.lua','r')
if f then f:close()
 for _,class in ipairs({'ROGUE','HUNTER','MAGE','SHAMAN'}) do
  reset();G.guides={};G.order={};G.player.class=class
  function UnitClass() return class,class end
  function UnitRace() return 'Troll','Troll' end
  dofile('FamilyGuides.lua')
  local id='rxp-hardcore-6-13-orc-troll';local target
  for _,s in ipairs(G.guides[id].steps) do if s.action=='complete' and s.questID==808 then target=s.id;break end end
  assert(target);G.db.placements[id]={stepID=target};G.Select(id,'restore')
  assert(G.Current().action=='accept' and G.Current().questID==786,'Real route entrance missing')
  active[786]={};G.Sync();assert(G.Current().action=='accept' and G.Current().questID==817,'Real Senjin pickup missing for '..class)
 end
end
print('PASS missing pickups, saved cursors, abandon recovery, history, explicit skips and real Troll profiles')
