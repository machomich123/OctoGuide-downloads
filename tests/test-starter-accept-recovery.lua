dofile('tests/test-runtime.lua');dofile('RouteRepairs.lua');dofile('QuestAutomation.lua')
local G=OctoGuide;local A=G.automation
local family=assert(os.getenv('OCTOGUIDE_FAMILY_TEST_FILE'));dofile(family)
G.db.progress={};G.db.completedQuests={};G.pauseAuto=false
testQuestLog[819]={complete=false};local starts=0
for _,g in pairs(G.guides) do for _,s in ipairs(g.steps) do
 if s.itemID==4926 and (s.action=='use' or s.action=='collect') then
  starts=starts+1;assert(s.startsQuestID==819 and G.Satisfied(s),'Every actual Chen starter is satisfied by active quest 819')
 end
end end
assert(starts==10)
testQuestLog[819]=nil
local use={id='starter',action='use',itemID=4926,text='Start Chen quest',manual=true}
local collect={id='collect',action='collect',itemID=4926,text='Loot Chen keg',manual=true}
local accept={id='npc',action='accept',questID=10,text='Accept Guide Quest from NPC.'}
G.RegisterGuide({id='starter-test',faction='Horde'},{use,collect,accept})
assert(not G.Satisfied(use) and not G.Satisfied(collect),'Without quest evidence keep starter')
G.db.completedQuests[819]=true;assert(G.Satisfied(use) and G.Satisfied(collect))
G.db.completedQuests[819]=nil
G.state.steps={use,collect,accept};G.ready=true;G.db.autoAccept=true
G.state.reviewReason=nil;G.pauseAuto=false
pfDB={quests={enUS={[819]={T="Chen's Empty Keg"},[10]={T='Guide Quest'}}}}
local dialog=819;local accepts=0;local shown=true;local combat=false;local questCount=4
function GetQuestID() return dialog end
function GetTitleText() return dialog==819 and "Chen's Empty Keg" or 'Guide Quest' end
local exactID=GetQuestID;GetQuestID=nil;A.selected={id=819,action='accept'}
assert(A.DialogID('accept')==819,'Item starter retains exact selected ID when direct dialog ID is unavailable');GetQuestID=exactID
function GetNumQuestLogEntries() return questCount+1,questCount end
function UnitAffectingCombat() return combat end
function IsShiftKeyDown() return false end
QuestFrameDetailPanel={IsShown=function() return shown end}
function AcceptQuest() accepts=accepts+1 end
local function event(ev) A.Event(ev) end
event('QUEST_FINISHED');event('QUEST_DETAIL');assert(accepts==1,'Starter dialog accepts immediately by exact ID')
event('QUEST_DETAIL');assert(accepts==1,'Duplicate event cannot duplicate initial request')
A.UpdateAccept(.5);assert(accepts==2,'Retry unconfirmed request while same dialog remains open')
testQuestLog[819]={complete=false};event('QUEST_LOG_UPDATE')
assert(G.db.lastAutoAccept.status=='Confirmed in quest log')
A.UpdateAccept(5);assert(accepts==2,'Stop immediately after observed acceptance')
-- Observed progress can be stale after abandoning a quest. Explicit skips remain protected.
dialog=10;G.db.progress[G.Key(accept)]='observed';event('QUEST_FINISHED');event('QUEST_DETAIL');assert(accepts==3)
G.db.progress[G.Key(accept)]='skipped';event('QUEST_FINISHED');event('QUEST_DETAIL');assert(accepts==3)
G.db.progress[G.Key(accept)]=nil
event('QUEST_FINISHED');questCount=25;event('QUEST_DETAIL');assert(accepts==3 and string.find(G.db.lastAutoAccept.status,'full',1,true))
questCount=4;event('QUEST_FINISHED');combat=true;event('QUEST_DETAIL');A.UpdateAccept(.5);assert(accepts==3)
combat=false;A.UpdateAccept(.5);assert(accepts==4,'Recover after combat ends while dialog is still open')
shown=false;A.UpdateAccept(.5);assert(accepts==4,'Closed panel cancels retries')
shown=true;event('QUEST_FINISHED');event('QUEST_DETAIL');A.UpdateAccept(.5);A.UpdateAccept(.5);A.UpdateAccept(.5)
local capped=accepts;A.UpdateAccept(50);assert(accepts==capped and A.acceptAttempts==3,'Maximum three requests per open dialog')
event('QUEST_FINISHED');G.db.autoAccept=false;event('QUEST_DETAIL');A.UpdateAccept(10);assert(accepts==capped)
print('PASS all 10 actual Chen starters, active/rewarded/absent evidence, item acceptance, observed vs skipped, confirmed vs requested, full 25-slot log, combat, closed dialog, bounded retries and disabled option')
