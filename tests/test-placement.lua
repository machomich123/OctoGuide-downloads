-- Real Lua 5.0 execution, controlled character/quest APIs; no server claimed.
dofile('tests/test-runtime.lua')
dofile('Placement.lua')
local G=OctoGuide
local passed=0
local function check(name,fn) fn();passed=passed+1;print('PASS PLACEMENT '..name) end
local level,xp=16,0
function UnitLevel() return level end
function UnitXP() return xp end
function UnitXPMax() return 100 end
local active={}
C_QuestLog={GetLogIndexForQuestID=function(id) return active[id] and id or 0 end}
function GetQuestLogTitle(id) return 'Quest',level,nil,false,false,active[id] and active[id].complete end
G.guides={};G.order={}
G.RegisterGuide({id='early',faction='Horde',title='Early',startLevel=1,endLevel=10},{{id='pre',action='accept',text='Prerequisite',questID=40,expectedLevel=8},{id='finish-pre',action='turnin',text='Turn in prerequisite',questID=40,expectedLevel=8}})
G.RegisterGuide({id='mid',faction='Horde',title='Middle',startLevel=10,endLevel=20},{
 {id='first',action='travel',text='Previous page',page='p1',expectedLevel=12},
 {id='take',action='accept',text='Take current quest',questID=50,requires={40},page='p2',expectedLevel=16,zone=1,x=.1,y=0},
 {id='work',action='complete',text='Current objective',questID=50,requires={40},page='p2',expectedLevel=16,zone=1,x=.2,y=0},
 {id='reward',action='turnin',text='Turn in current quest',questID=50,requires={40},page='p2',expectedLevel=16,zone=1,x=.1,y=0},
 {id='chain',action='accept',text='Follow-up',questID=51,requires={50},page='p2',expectedLevel=16.5},
 {id='death',action='death',text='Normal shortcut',mode='normal',requiresDeath=true,branch='shortcut',page='p3',expectedLevel=18},
 {id='walk',action='travel',text='Hardcore alternate',mode='hardcore',branch='shortcut',page='p3',expectedLevel=18}})
G.RegisterGuide({id='late',faction='Horde',title='Later',startLevel=20,endLevel=30},{{id='late',action='travel',text='Later page',expectedLevel=22}})
local function reset()
 active={};pfQuest_history=nil;GetQuestsCompleted=nil;QueryQuestsCompleted=nil
 G.db={progress={},completedQuests={},mode='hardcore',placements={}};OctoGuideDB=G.db;G.state=nil;G.historyHints={};G.historyRequested=nil;G.autoplacePending=nil;G.initialQuestSyncPending=nil;G.player={class='HUNTER',race='Orc',faction='Horde'};G.ready=true;level=16;xp=0
end
check('active objective selects matching step within correct chapter',function() reset();active[50]={};assert(G.AutoPlace(true));assert(G.state.guide.id=='mid' and G.Current().id=='work') end)
check('active quest proves availability without claiming prerequisite completion',function() assert(not G.db.completedQuests[40] and not next(G.db.progress)) end)
check('completed active quest selects actual reward step',function() reset();active[50]={complete=1};G.AutoPlace(true);assert(G.Current().id=='reward') end)
check('whole quest log completion proves manual quest work but not its reward',function() assert(G.Satisfied({questID=50,action='objective',manual=true}) and not G.Satisfied({questID=50,action='turnin',manual=true})) end)
check('confirmed turn-in chooses follow-up and leaves earlier progress unknown',function() reset();G.db.completedQuests[50]=true;G.AutoPlace(true);assert(G.Current().id=='chain' and not next(G.db.progress)) end)
check('unknown chain prerequisites cause catch-up instead of invented completion',function() reset();G.AutoPlace(true);assert(G.state.guide.id=='early' and G.Current().id=='pre');assert(not G.db.completedQuests[40]) end)
check('unverified pfQuest history cannot advance the cursor',function() reset();pfQuest_history={[50]={100,16}};G.AutoPlace(true);assert(not G.db.completedQuests[50] and G.Current().id=='pre' and not next(G.db.progress)) end)
check('unverified prerequisite cannot skip catch-up',function() reset();pfQuest_history={[40]={100,8}};G.AutoPlace(true);assert(G.state.guide.id=='early' and G.Current().id=='pre' and not G.db.completedQuests[40]) end)
check('server response imports only valid confirmed quest IDs',function() reset();GetQuestsCompleted=function() return {[50]=true,[51]=false,[55]=1,[9.5]=true,[-1]=true,['56']=true} end;G.RefreshHistory(true);assert(G.db.completedQuests[50] and G.db.completedQuests[55] and not G.db.completedQuests[51] and not G.db.completedQuests[9.5] and not G.db.completedQuests['56']) end)
check('output-table completion API is supported',function() reset();GetQuestsCompleted=function(t) t[50]=true end;G.RefreshHistory(true);assert(G.db.completedQuests[50]) end)
check('history API errors do not create completion facts',function() reset();GetQuestsCompleted=function() error('unavailable') end;G.RefreshHistory(true);assert(not next(G.db.completedQuests)) end)
check('completed history is only refreshed on confirmed server event',function() reset();GetQuestsCompleted=function() return {[50]=true} end;G.RefreshHistory(false);assert(not G.db.completedQuests[50]);G.Event('QUEST_QUERY_COMPLETE');assert(G.db.completedQuests[50]) end)
check('server history request is optional and sent only once',function() reset();local calls=0;QueryQuestsCompleted=function() calls=calls+1 end;GetQuestsCompleted=function() return {} end;G.RequestHistory();G.RequestHistory();assert(calls==1 and G.events.events.QUEST_QUERY_COMPLETE) end)
check('missing history API still supports active-log placement',function() reset();active[50]={};G.RequestHistory();G.AutoPlace(true);assert(G.Current().id=='work') end)
check('Back exposes earlier unknown step without marking it completed',function() reset();active[50]={};G.AutoPlace(true);G.Back();assert(G.Current().id=='take' and G.pauseAuto and not next(G.db.progress));G.Event('QUEST_LOG_UPDATE');assert(G.Current().id=='take') end)
check('late history response cannot override manual review',function() GetQuestsCompleted=function() return {[50]=true} end;G.Event('QUEST_QUERY_COMPLETE');assert(G.Current().id=='take' and not G.autoplacePending) end)
check('saved placement and manual Back survive character reload',function() G.ready=false;G.Init();assert(G.state.guide.id=='mid' and G.Current().id=='take' and G.pauseAuto) end)
check('obsolete installed guide ID triggers fresh placement rather than first step',function() reset();G.db.guide='old-generated-route';active[50]={complete=1};G.ready=false;G.Init();assert(G.state.guide.id=='mid' and G.Current().id=='reward') end)
check('quest log arriving after initial world entry triggers one fresh reconciliation',function() reset();G.ready=false;G.Init();assert(G.Current().id=='pre');active[50]={};G.Event('QUEST_LOG_UPDATE');assert(G.Current().id=='work' and not G.initialQuestSyncPending) end)
check('later log updates do not repeatedly relocate the guide',function() active[50]=nil;G.Event('QUEST_LOG_UPDATE');assert(G.Current().id=='work') end)
check('mode switching never auto-places onto death step in hardcore',function() reset();G.db.completedQuests[40]=true;G.db.completedQuests[50]=true;G.db.completedQuests[51]=true;G.Select('mid');for i=1,5 do G.Mark() end;G.SetMode('normal');G.SetMode('hardcore');local s=G.Current();assert(not s or not s.requiresDeath) end)
check('placement cursor selects paired alternative when switching modes',function() reset();G.db.placements.mid={stepID='walk'};G.Select('mid','restore');assert(G.Current().id=='walk');G.SetMode('normal');assert(G.Current().id=='death');G.SetMode('hardcore');assert(G.Current().id=='walk') end)
check('manual guide selection cancels pending automatic replacement',function() reset();active[50]={};G.AutoPlace(true);G.Select('late');GetQuestsCompleted=function() return {[50]=true} end;G.Event('QUEST_QUERY_COMPLETE');assert(G.state.guide.id=='late') end)
check('explicit sync recomputes from current character state',function() reset();active[50]={};G.Select('early');G.Slash('sync');assert(G.state.guide.id=='mid' and G.Current().id=='work') end)
check('visible Find step button uses current state and closes guide picker',function() reset();active[50]={};G.Select('early');G.ToggleMenu();this=G.menu.findStep;this.scripts.OnClick();assert(G.Current().id=='work' and not G.menu:IsShown()) end)
check('low-level stale active quest does not dominate current level route',function() reset();level=27;active[50]={};G.AutoPlace(true);assert(G.state.guide.id=='late') end)
check('fractional XP affects matching without recording false quest facts',function() reset();level=15;xp=95;active[50]={};G.AutoPlace(true);assert(G.Current().id=='work' and not next(G.db.completedQuests)) end)
check('faction restriction applies to automatic placement',function() reset();G.player.faction='Alliance';assert(not G.AutoPlace(true)) end)
print('ALL '..passed..' PLACEMENT CHECKS PASSED (plus original runtime checks)')
