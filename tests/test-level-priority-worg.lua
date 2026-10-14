dofile('tests/test-sync-manifest.lua')
local G=OctoGuide
-- Near old quests and even an old active quest cannot defeat level chapter.
G.guides={};G.order={};G.hasFamilyRoutes=nil
G.RegisterGuide({id='old-zone',title='Old zone',faction='Horde',startLevel=6,endLevel=13},{
 {id='old-pickup',action='accept',questID=700,text='Old quest',expectedLevel=10,zone=1,x=0,y=0},
 {id='old-work',action='complete',questID=700,text='Old work',expectedLevel=12,zone=1,x=0,y=0}})
G.RegisterGuide({id='silverpine',title='Silverpine',faction='Horde',startLevel=13,endLevel=15},{{id='silverpine-start',action='travel',text='Silverpine appropriate chapter',expectedLevel=13,zone=2,x=.9,y=.9}})
G.RegisterGuide({id='barrens',title='Barrens',faction='Horde',startLevel=15,endLevel=19},{{id='barrens-start',action='travel',text='Barrens appropriate chapter',expectedLevel=15,zone=3,x=.9,y=.9}})
G.player={class='HUNTER',race='Troll',faction='Horde'};G.db={mode='hardcore',progress={},completedQuests={},placements={}};G.state=nil;G.characterScan=nil
local level=14;function UnitLevel() return level end;function UnitXP() return 0 end;function UnitXPMax() return 100 end
function GetNumQuestLogEntries() return 1 end
C_QuestLog={GetQuestIDForLogIndex=function(i) return i==1 and 700 end,GetLogIndexForQuestID=function(q) return q==700 and 1 or 0 end}
function GetQuestLogTitle() return 'Old active quest',6,nil,false,false,false end
function GetNumQuestLeaderBoards() return 0 end
assert(G.FindPlacement().guide.id=='silverpine','Level 14 wins over nearby old active quest')
level=16;assert(G.FindPlacement().guide.id=='barrens','Level 16 wins over Silverpine zone')
assert(G.AutoPlace(false) and G.state.guide.id=='barrens','Actual automatic selection uses level bracket')
G.guides['old-zone'].nextGuide='silverpine';G.Select('old-zone');assert(G.NextStage() and G.state.guide.id=='barrens','Overleveled authored next chapter cannot send level 16 back to Silverpine')
-- Live/private content remains local. Test every actual matching imported step.
local private=os.getenv('OCTOGUIDE_FAMILY_TEST_FILE');assert(private,'Local family fixture required')
G.guides={};G.order={};G.hasFamilyRoutes=nil;G.testAllProfiles=true;dofile(private)
G.db.completedQuests={};G.db.progress={};G.db.placements={};G.state=nil
assert(G.FindPlacement().guide.id=='rxp-hardcore-15-19-the-barrens','Actual family level 16 placement stays in Barrens chapter')
level=14;assert(G.FindPlacement().guide.id=='rxp-hardcore-13-15-silverpine-forest','Actual family level 14 stays in Silverpine chapter')
local repaired=0
for _,gid in ipairs(G.order) do for _,s in ipairs(G.guides[gid].steps) do if s.itemID==3164 and s.action=='collect' then
 assert(s.lootGoal and s.goalQuestID==429 and s.goalQuestName=='Wild Hearts' and not s.manual and s.itemCount)
 repaired=repaired+1
end end end
assert(repaired>=4)
local step
for _,s in ipairs(G.guides['rxp-hardcore-13-15-silverpine-forest'].steps) do if s.itemID==3164 and s.action=='collect' then step=s;break end end
local hearts=2;function GetItemCount(item) return item==3164 and hearts or 0 end
function GetContainerNumSlots() return 0 end;function GetInventoryItemLink() end
C_QuestLog={GetLogIndexForQuestID=function() return 0 end}
local title,body=G.Present(step,true);assert(string.find(title,'Wild Hearts',1,true) and string.find(title,'Prepare:',1,true))
local list=G.Objectives(step);assert(list[1].current==2 and list[1].required==step.itemCount and not list[1].done)
pfDB={items={data={[3164]={U={[1765]=38.92,[1766]=39.18}}}},units={data={[1765]={coords={{20,30,130}}},[1766]={coords={{25,32,130}}}}}}
local entries=G.TargetEntries(step);assert(table.getn(entries)==2 and entries[1].kind=='monster')
hearts=step.itemCount;assert(G.Satisfied(step),'Loot completion is based on actual item count')
hearts=0;G.db.completedQuests[429]=nil
C_QuestLog.GetLogIndexForQuestID=function(q) return q==429 and 1 or 0 end
function GetNumQuestLeaderBoards() return 1 end
function GetQuestLogLeaderBoard() return 'Discolored Worg Heart: 3/6','item',false end
function GetQuestLogLeaderBoardID() return 3164,'item' end
title=G.Present(step,true);assert(title=='Wild Hearts','Active quest is no longer a generic collect title')
list=G.Objectives(step);assert(list[1].current==3 and list[1].id==3164)
-- Exercise the real navigation functions, including live observed mob evidence.
G.state={guide=G.guides['rxp-hardcore-13-15-silverpine-forest'],steps={step},index=1,startIndex=1}
G.db.progress={};G.db.completedQuests={};G.characterScan=nil;G.Travel=nil;G.pathCursors={};G.pauseAuto=false
G.NavTarget=function() return step end;G.RawNavTarget=G.NavTarget;G.PathTarget=function() end
step.zone=130;step.x=.5;step.y=.2;pfDB.units.data[1765].coords={{50.1,20.1,130}}
function UnitPosition(token) if token=='target' then return 210,510,0,130 end;return 200,500,0,130 end
function UnitCreatureID(token) return token=='target' and 1765 or nil end
function UnitHealth() return 100 end;function UnitIsDeadOrGhost() return false end
local target=G.ReadObservedTarget(step);assert(target and target.entry==1765 and target.label=='Live quest target')
UnitCreatureID=nil;G.livePoll=nil;G.areaPoll=nil
local point=G.NavigationRead(step);assert(point and G.navigationEvidence=='Possible quest spawn','Static mob spawn replaces the generic quest-area arrow when no live mob is observed')
print('PASS character level before zone/old quests, all '..repaired..' actual Worg steps, Wild Hearts title/counts and item-to-mob target mapping')
