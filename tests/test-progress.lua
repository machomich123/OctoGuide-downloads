-- Objective counts and strict turn-in fallback under the actual Lua 5.0 runtime.
dofile('tests/test-runtime.lua')
dofile('Placement.lua')
local G=OctoGuide
local passed=0
local function check(name,fn) fn();passed=passed+1;print('PASS PROGRESS '..name) end

check('ClassicAPI native turn-in registration is preferred',function()
  G.InitProgress();assert(G.turnInEventAvailable==true and not G.fallbackProgressAvailable)
end)

local route={
  {id='boots',action='objective',text='Collect shipment boots',questID=901,objective=1},
  {id='lens',action='objective',text='Find telescopic lens',questID=901,objective=2},
  {id='reward',action='turnin',text='Turn in shipment',questID=901},
  {id='next',action='travel',text='Continue onward',zone=1,x=.2,y=.2}
}
G.RegisterGuide({id='objective-progress',title='Objective progress',faction='Horde',startLevel=1,endLevel=5},route)
testQuestLog[901]={complete=nil,objectives={{'Collect shipment boots: 2/3',nil},{'Find telescopic lens\239\188\154 1/2',nil}}}
G.Select('objective-progress')

check('objective API returns a separate name and local count',function()
  local list=G.Objectives(G.Current())
  assert(table.getn(list)==2 and list[1].name=='Collect shipment boots' and list[1].current==2 and list[1].required==3 and list[1].id==4001 and list[1].kind=='monster' and not list[1].done)
  assert(list[2].name=='Find telescopic lens' and list[2].current==1 and list[2].required==2)
end)

check('known objective count completion advances that objective only',function()
  assert(not G.Satisfied(G.Current()))
  testQuestLog[901].objectives[1]={'Collect shipment boots: 3/3',nil}
  G.Event('QUEST_LOG_UPDATE');assert(G.Current().id=='lens')
  assert(not G.db.completedQuests[901])
end)

check('unmapped partial objective waits for quest completion',function()
  local step={action='objective',text='Local-only detail',questID=901,objective=3,manual=true}
  assert(not G.Satisfied(step))
  testQuestLog[901].complete=1
  assert(G.Satisfied(step))
  testQuestLog[901].complete=nil
end)

check('full local objective progress reaches turn-in but not reward completion',function()
  testQuestLog[901].objectives[2]={'Find telescopic lens: 2/2',nil}
  testQuestLog[901].complete=1
  G.Event('QUEST_LOG_UPDATE')
  assert(G.Current().id=='reward' and not G.db.completedQuests[901])
end)

-- Force the fallback path to model a runtime where QUEST_TURNED_IN cannot be
-- registered. A dialog plus removal alone is intentionally insufficient.
local register=G.events.RegisterEvent
G.events.RegisterEvent=function(self,name) if name=='QUEST_TURNED_IN' then error('unsupported event') end;return register(self,name) end
GetQuestReward=function(choice) return choice end
G.progressInitialized=false
G.InitProgress()
G.events.RegisterEvent=register

local function fallbackEvent(name,a)
  event=name;arg1=a;G.rewardFallbackFrame.scripts.OnEvent()
end

check('fallback detects dialog plus abandon as unconfirmed',function()
  fallbackEvent('QUEST_COMPLETE')
  testQuestLog[901]=nil
  fallbackEvent('QUEST_REMOVED',901)
  assert(G.Current().id=='reward' and not G.db.completedQuests[901])
end)

check('reward click and removal still wait for server history',function()
  testQuestLog[901]={complete=1,objectives={{'Collect shipment boots: 3/3',1},{'Find telescopic lens: 2/2',1}}}
  fallbackEvent('QUEST_COMPLETE')
  local rewardResult=GetQuestReward(1)
  assert(rewardResult==1 and G.rewardRequestedID==901)
  testQuestLog[901]=nil
  fallbackEvent('QUEST_REMOVED',901)
  assert(G.rewardHistoryPendingID==901 and not G.db.completedQuests[901] and G.Current().id=='reward')
end)

check('fallback advances only after authoritative history confirms the quest',function()
  QueryQuestsCompleted=function() end
  GetQuestsCompleted=function() return {[901]=true} end
  fallbackEvent('QUEST_QUERY_COMPLETE')
  assert(G.db.completedQuests[901] and G.Current().id=='next')
end)

print('ALL '..passed..' QUEST PROGRESS CHECKS PASSED')
