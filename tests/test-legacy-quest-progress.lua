dofile('tests/test-runtime.lua')
dofile('Placement.lua')
local G=OctoGuide
local inverse=C_QuestLog.GetLogIndexForQuestID
C_QuestLog.GetLogIndexForQuestID=nil
GetNumQuestLogEntries=function() return 902 end
C_QuestLog.GetQuestIDForLogIndex=function(i) if testQuestLog[i] then return i else return 0 end end
G.RegisterGuide({id='legacy-progress',faction='Horde',title='Legacy progress'}, {
 {id='accept',action='accept',questID=901,text='Accept'},
 {id='objective',action='objective',questID=901,objective=1,text='Objective'},
 {id='turnin',action='turnin',questID=901,text='Turn in'},
 {id='next',action='note',text='Next'}
})
testQuestLog[901]={objectives={{'Same title target: 0/1',nil}}}
testQuestLog[902]={complete=1,objectives={{'Same title target: 1/1',1}}}
G.Select('legacy-progress')
assert(G.QuestIndex(901)==901 and G.QuestIndex(999)==nil)
G.Event('QUEST_LOG_UPDATE')
assert(G.Current().id=='objective')
testQuestLog[901].objectives[1]={'Same title target: 1/1',1}
testQuestLog[901].complete=1
G.Event('QUEST_LOG_UPDATE');assert(G.Current().id=='turnin')
GetQuestReward=function() return 'reward requested' end
G.progressInitialized=false;G.InitProgress()
assert(G.turnInEventAvailable and G.fallbackProgressAvailable)
event='QUEST_COMPLETE';G.rewardFallbackFrame.scripts.OnEvent()
assert(GetQuestReward(1)=='reward requested')
testQuestLog[901]=nil
event='QUEST_LOG_UPDATE';G.rewardFallbackFrame.scripts.OnEvent()
assert(not G.db.completedQuests[901] and G.Current().id=='turnin')
GetQuestsCompleted=function() return {[901]=true} end
event='QUEST_QUERY_COMPLETE';G.rewardFallbackFrame.scripts.OnEvent()
assert(G.db.completedQuests[901] and G.Current().id=='next')
C_QuestLog.GetQuestIDForLogIndex=function() error('unavailable') end
assert(G.QuestIndex(901)==nil)
C_QuestLog.GetLogIndexForQuestID=inverse
print('PASS older ClassicAPI acceptance, objectives, exact IDs and silent turn-in event fallback')
