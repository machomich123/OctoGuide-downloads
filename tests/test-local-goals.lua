dofile('tests/test-runtime.lua');dofile('Placement.lua');dofile('Guides.lua');dofile('Goals.lua')
local G=OctoGuide;local passed=0
local function check(name,fn) fn();passed=passed+1;print('PASS LOCAL-GOAL '..name) end
local boots,lens,complete=1,0,false
C_QuestLog={GetLogIndexForQuestID=function(id) return id==888 and 1 or 0 end}
function GetQuestLogTitle() return 'Stolen Booty',16,nil,false,false,complete end
function GetNumQuestLeaderBoards() return 2 end
function GetQuestLogLeaderBoard(i) return i==1 and 'Shipment of Boots: '..boots..'/1' or 'Telescopic Lens: '..lens..'/1','item',i==1 and boots==1 or i==2 and lens==1 end
function GetQuestLogLeaderBoardID(i) return i==1 and 5076 or 5077,'item' end
function UnitLevel() return 16 end
function UnitPosition() return 496,626,0,17 end
local guide,bootStep,lensStep
for _,g in pairs(G.guides) do for _,s in ipairs(g.steps) do if s.questID==888 and s.action=='objective' then guide=g;if s.localGoals[1].id==5076 then bootStep=s else lensStep=s end end end end
check('catalogue links each Stolen Booty container to its actual item ID',function() assert(bootStep and lensStep and bootStep.localGoals[1].id==5076 and lensStep.localGoals[1].id==5077) end)
check('one collected item proves only its matching local checkpoint',function() assert(G.Satisfied(bootStep));assert(not G.Satisfied(lensStep));assert(not G.db.completedQuests[888]) end)
check('mid-playthrough placement chooses missing lens rather than nearer completed boots',function() local p=G.FindPlacement();assert(p and p.steps[p.index].id==lensStep.id) end)
check('missing native objective IDs cannot manufacture local completion',function() local f=GetQuestLogLeaderBoardID;GetQuestLogLeaderBoardID=nil;assert(not G.Satisfied(bootStep));GetQuestLogLeaderBoardID=f end)
check('both items collected clear both local objectives without proving reward',function() lens=1;assert(G.Satisfied(lensStep) and G.Satisfied(bootStep));assert(not G.db.completedQuests[888]) end)
check('whole-quest complete remains a valid fallback for unmapped checkpoints',function() complete=true;assert(G.Satisfied({questID=888,action='objective',manual=true}));complete=false end)
G.RegisterGuide({id='turnin-end',title='Turnin end',faction='Horde',nextGuide='turnin-next'},{{id='reward',action='turnin',questID=888,text='Turn in Stolen Booty'}})
G.RegisterGuide({id='turnin-next',title='Next stage',faction='Horde'},{{id='go',action='travel',text='Follow the next route'}})
check('matching reward leaves manual review and continues to the next chapter',function() G.Select('turnin-end');G.pauseAuto=true;G.db.reviewGuide='turnin-end';G.Event('QUEST_TURNED_IN',888);assert(G.state.guide.id=='turnin-next' and G.Current().id=='go' and not G.pauseAuto and not G.db.reviewGuide) end)
print('ALL '..passed..' LOCAL GOAL CHECKS PASSED')
