dofile('tests/test-runtime.lua')
dofile('Placement.lua');dofile('CharacterScan.lua');dofile('StepBrowser.lua')
local G=OctoGuide;local passed=0
local methods=getmetatable(UIParent).__index
for _,name in ipairs({'SetNumeric','SetAutoFocus','EnableMouseWheel','SetBackdropColor'}) do methods[name]=methods[name] or function() end end
local function check(name,fn) fn();passed=passed+1;print('PASS SCAN '..name) end
local steps={
 {id='a',action='accept',questID=101,text='Accept one',expectedLevel=15},
 {id='b',action='complete',questID=101,text='Work one',expectedLevel=15},
 {id='c',action='turnin',questID=101,text='Turn in one',expectedLevel=15},
 {id='d',action='accept',questID=102,text='Accept two',expectedLevel=15},
 {id='e',action='complete',questID=102,text='Work two',expectedLevel=15},
 {id='f',action='turnin',questID=102,text='Turn in two',expectedLevel=15},
 {id='g',action='accept',questID=103,text='Next quest',expectedLevel=15},
 {id='h',action='collect',itemID=500,itemCount=3,text='Collect',expectedLevel=15},
 {id='i',action='bind',inn='Crossroads',text='Bind',expectedLevel=15},
 {id='j',action='flightpath',taxiNodeID=23,text='Flight',expectedLevel=15},
 {id='k',action='turnin',questID=104,text='Active reward',expectedLevel=15},
}
local function reset()
 local route={};for _,s in ipairs(steps) do table.insert(route,s) end
 G.guides={};G.order={};G.RegisterGuide({id='scan',faction='Horde',title='15-19',startLevel=15,endLevel=19},route)
 G.player={class='HUNTER',race='Troll',faction='Horde'};G.db={progress={},completedQuests={},mode='normal',travel={known={[23]=true}}}
 G.state=nil;G.pauseAuto=false;G.pendingFind=nil;G.characterScan=nil;G.historyReady=false;G.historyFailure=nil
 function UnitLevel() return 15 end;function UnitXP() return 0 end;function UnitXPMax() return 100 end
 function GetNumQuestLogEntries() return 1 end
 C_QuestLog={GetQuestIDForLogIndex=function(i) return i==1 and 104 or 0 end,GetLogIndexForQuestID=function(q) return q==104 and 1 or 0 end}
 function GetQuestLogTitle() return 'Active',15,nil,false,false,1 end
 function GetNumQuestLeaderBoards() return 1 end;function GetQuestLogLeaderBoard() return '3/3', 'item',1 end
 function GetContainerNumSlots(b) return b==0 and 1 or 0 end
 function GetContainerItemLink() return 'item:500:0:0:0' end;function GetContainerItemInfo() return 'texture',3 end
 GetInventoryItemLink=nil;GetInventoryItemCount=nil;function GetBindLocation() return 'Crossroads' end
 GetQuestsCompleted=nil;QueryQuestsCompleted=nil;G.historyRequested=nil;G.ready=true
end
check('server set metadata and false values are handled without trusting pfQuest',function()
 reset();GetQuestsCompleted=function() return {[101]={1,15},[102]=true,[999]=false} end
 assert(G.ReadCompletedHistory());assert(G.db.completedQuests[101] and G.db.completedQuests[102] and not G.db.completedQuests[999])
end)
check('server arrays and output-table APIs are both supported',function()
 reset();GetQuestsCompleted=function() return {1,101,102} end;assert(G.ReadCompletedHistory() and G.db.completedQuests[102] and G.db.completedQuests[1])
 G.db.completedQuests={};GetQuestsCompleted=function(out) assert(out);out[101]=1 end
 assert(G.ReadCompletedHistory() and G.db.completedQuests[101])
end)
check('invalid server history responses stay unknown',function()
 reset();GetQuestsCompleted=function() return 'invalid' end
 assert(not G.ReadCompletedHistory() and not G.historyReady and not G.db.completedQuests[101])
end)
check('closed flight-master state is never read through native taxi APIs',function()
 reset();local old=G.Travel;G.Travel={ObserveTaxi=function() error('Unsafe closed taxi map') end}
 C_TaxiMap={GetAllTaxiNodes=function() error('Unsafe closed taxi map') end};TaxiFrame=nil
 local s=G.ScanCharacter();assert(s.flight[23] and s.flightStatus=='previously observed only')
 G.Travel=old;C_TaxiMap=nil
end)
check('whole active log, objectives, items, bind and observed flight paths are scanned',function()
 reset();local s=G.ReconcileCharacter();assert(s.quests[104].complete and s.quests[104].objectives[1].done)
 assert(s.items[500]==3 and s.hearth=='Crossroads' and s.flight[23]);assert(s.bankStatus=='closed; not scanned')
 assert(G.StepEvidence(steps[8]) and G.StepEvidence(steps[9]) and G.StepEvidence(steps[10]));assert(not G.StepEvidence(steps[11]))
end)
check('Find step waits for server and scans completed quests out of order',function()
 reset();local calls=0;QueryQuestsCompleted=function() calls=calls+1 end;GetQuestsCompleted=function() return {[101]=true,[102]=true} end
 assert(G.FindStep(false));assert(G.pendingFind and not G.state and calls==1)
 G.Event('QUEST_QUERY_COMPLETE');assert(not G.pendingFind and G.state)
 assert(G.db.completedQuests[102] and G.Satisfied(steps[4]) and G.Satisfied(steps[6]));assert(not G.Satisfied(steps[11]))
end)
check('timeout reports missing history and still chooses from current character',function()
 reset();QueryQuestsCompleted=function() end;GetQuestsCompleted=function() error('No reply') end
 assert(G.FindStep(false));G.UpdateFindStep(9);assert(not G.pendingFind and G.state)
 assert(string.find(G.ScanSummary(),'timed out',1,true) and not G.db.completedQuests[101])
end)
check('Back after six automatic steps visits each step and preserves explicit Skip',function()
 reset();G.db.completedQuests={[101]=true,[102]=true};G.Select('scan');assert(G.Current().id=='g')
 G.JumpToStep('scan',1);G.state.reviewIndex=nil;G.pauseAuto=true;G.state.startIndex=1;G.db.progress={};G.db.completedQuests={[102]=true}
 G.db.progress['scan:b']='observed';G.db.progress['scan:c']='observed'
 G.Mark('skipped');G.Sync();assert(G.Current().id=='g')
 for _,wanted in ipairs({'f','e','d','c','b','a'}) do G.Back();assert(G.Current().id==wanted);G.Event('QUEST_LOG_UPDATE');assert(G.Current().id==wanted) end
 assert(G.db.progress['scan:a']=='skipped');G.Advance();assert(G.Current().id=='b');G.Advance();assert(G.Current().id=='c')
end)
check('manual jump rejects bad numbers and retains earlier progress and Back',function()
 reset();G.db.progress['scan:a']='skipped';assert(not G.JumpToStep('scan',0));assert(not G.JumpToStep('scan',2.5));assert(not G.JumpToStep('scan',99))
 assert(G.JumpToStep('scan',9));assert(G.Current().id=='i' and G.db.progress['scan:a']=='skipped');G.Back();assert(G.Current().id=='h')
 local saved=G.db.reviewStep;G.Select('scan','restore');assert(G.Current().id=='h' and G.db.reviewStep==saved)
end)
check('late history cannot replace a manual jump',function()
 reset();QueryQuestsCompleted=function() end;GetQuestsCompleted=function() return {[101]=true} end
 G.FindStep(false);assert(G.JumpToStep('scan',8));G.Event('QUEST_QUERY_COMPLETE');assert(G.Current().id=='h')
end)
check('browser row click and typed Go both choose exact steps',function()
 reset();G.OpenStepBrowser('scan');local p=G.stepBrowser
 assert(p.rows[1].stepNumber==1);this=p.rows[3];p.rows[3].scripts.OnClick();assert(G.Current().id=='c')
 G.OpenStepBrowser('scan');p.input:SetText('8');p.go.scripts.OnClick();assert(G.Current().id=='h')
 G.OpenStepBrowser('scan');p.input:SetText('99');p.input.scripts.OnEnterPressed();assert(string.find(p.error:GetText(),'1 to',1,true))
end)
check('browser next and previous pages expose every step with stable numbering',function()
 reset();for i=12,40 do table.insert(G.guides.scan.steps,{id='extra'..i,action='note',text='Extra '..i}) end
 G.OpenStepBrowser('scan');local p=G.stepBrowser;p.next.scripts.OnClick();assert(p.rows[1].stepNumber==13)
 this=p.rows[1];p.rows[1].scripts.OnClick();assert(G.Current().id=='extra13')
 G.OpenStepBrowser('scan');p.next.scripts.OnClick();p.previous.scripts.OnClick();assert(p.rows[1].stepNumber==1)
end)
check('inventory loss is refreshed and text-based bind / known flight steps work',function()
 reset();G.db.travel.knownNames={[23]='Thunder Bluff, Mulgore'};G.ReconcileCharacter()
 assert(G.StepEvidence({action='bind',text='Set your Hearthstone to Crossroads'}))
 assert(G.StepEvidence({action='flightpath',text='Get the Thunder Bluff flight path'}))
 assert(not G.StepEvidence({action='flightpath',text='Get the Ratchet flight path'}))
 GetContainerItemLink=function() return nil end;G.Event('BAG_UPDATE');assert(not G.StepEvidence(steps[8]))
end)
check('starter placement preserves boars, unlearned training and scorpions across chapters',function()
 reset();G.guides={};G.order={};function UnitLevel() return 4 end;function UnitXP() return 95 end
 G.RegisterGuide({id='starter-first',faction='Horde',startLevel=1,endLevel=3}, {
  {id='boar-pickup',questID=90001,action='accept',text='Boar quest',expectedLevel=1},
  {id='boar-work',questID=90001,action='complete',text='Boars',expectedLevel=1},
  {id='training',action='train',spellID=90010,text='Learn a skill',expectedLevel=2},
  {id='scorpion-pickup',questID=90002,action='accept',text='Scorpion quest',expectedLevel=2},
  {id='scorpion-work',questID=90002,action='complete',text='Scorpions',expectedLevel=2}})
 G.RegisterGuide({id='starter-later',faction='Horde',startLevel=3,endLevel=6}, {{id='later',questID=90003,action='complete',text='Later quest',expectedLevel=4}})
 C_QuestLog={GetLogIndexForQuestID=function(q) return q==90003 and 1 or 0 end}
 function GetQuestLogTitle() return 'Later quest',4,nil,false,false,false end
 local known=false;IsSpellKnown=function() return known end
 assert(G.FindPlacement().steps[G.FindPlacement().index].id=='boar-pickup')
 G.db.completedQuests[90001]=true;local p=G.FindPlacement();assert(p.steps[p.index].id=='training')
 known=true;p=G.FindPlacement();assert(p.steps[p.index].id=='scorpion-pickup')
 G.db.completedQuests[90002]=true;p=G.FindPlacement();assert(p.steps[p.index].id=='later')
 IsSpellKnown=nil
end)
print('ALL '..passed..' CHARACTER SCAN AND STEP BROWSER CHECKS PASSED')
