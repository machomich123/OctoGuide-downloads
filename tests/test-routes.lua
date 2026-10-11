dofile('tests/test-runtime.lua')
local G=OctoGuide;local passed=0
local function check(name,fn) fn();passed=passed+1;print('PASS ROUTE '..name) end
G.player={class='HUNTER',race='Troll',faction='Horde'};G.db.progress={};G.db.completedQuests={};G.db.mode='hardcore'
G.RegisterGuide({id='simultaneous',title='1-6 Durotar',faction='Horde',routeFamily='baseline'}, {
 {id='scorpid',action='complete',questID=789,objective=1,text='Collect scorpid tails',sourceBlock=1,background=true,parallelUntil=2},
 {id='apples',action='complete',questID=4402,objective=1,text='Collect cactus apples',sourceBlock=2},
 {id='tails',action='complete',questID=789,objective=1,text='Finish scorpid tails',sourceBlock=3},
 {id='reward',action='turnin',questID=789,text='Turn in Sting of the Scorpid',sourceBlock=4}
})
testQuestLog[789]={objectives={{'Scorpid Worker Tail: 2/10',false}}}
testQuestLog[4402]={objectives={{'Cactus Apple: 1/10',false}}}
check('scorpid tails and cactus apples appear simultaneously',function()
 assert(G.Select('simultaneous'));assert(G.Current().id=='apples')
 local c=G.Concurrent(G.Current());assert(table.getn(c)==1 and c[1].questID==789)
 local o=G.DisplayObjectives(G.Current());assert(table.getn(o)==2)
 local title,body=G.Present(G.Current());assert(string.find(body,'Do alongside this step'))
end)
check('one finished quest cannot complete the other concurrent goal',function()
 testQuestLog[4402].objectives[1][2]=true;G.Sync();assert(G.Current().id=='tails');assert(not G.db.completedQuests[789])
 testQuestLog[789].objectives[1][2]=true;G.Sync();assert(G.Current().id=='reward')
end)
check('personal class unlocks remain individual in a party',function()
 G.db.partyMode='group'
 assert(G.Allowed({personalClass='HUNTER',profiles={'Troll:HUNTER'}}))
 assert(not G.Allowed({profiles={'Troll:SHAMAN'}}))
 local title,body=G.Present({action='use',text='Tame your first pet',personalClass='HUNTER'});assert(string.find(body,'each player'))
end)
check('automatic party detection and explicit overrides are independent',function()
 function GetNumPartyMembers() return 2 end
 G.db.partyMode='auto';assert(G.PartyMode()=='group')
 G.db.partyMode='solo';assert(G.PartyMode()=='solo')
 assert(not G.Allowed({groupOnly=true}));assert(G.Allowed({personalClass='HUNTER'}))
end)
check('level menu is numerically sorted and can filter a chosen level',function()
 G.RegisterGuide({id='late',title='40-41 Example',faction='Horde',startLevel=40,endLevel=41},{{action='note',text='Late'}})
 G.RegisterGuide({id='early',title='5-10 Example',faction='Horde',startLevel=5,endLevel=10},{{action='note',text='Early'}})
 local list=G.LevelGuides(6);local found=false;for _,id in ipairs(list) do assert(id~='late');if id=='early' then found=true end end;assert(found)
 assert(G.RouteLabel(G.guides.early)=='Level 5-10 Example')
end)
check('new routes cannot silently erase saved baseline progress',function()
 G.db.progress['simultaneous:reward']='manual';local old=G.db.progress['simultaneous:reward']
 assert(G.SetRouteSource('baseline'));assert(G.db.progress['simultaneous:reward']==old)
end)
check('long route notes remain available inside a bounded scroll area',function()
 local g=G.guides.simultaneous;g.blockNotes={[4]={{text=string.rep('Instruction ',300)}}}
 G.state={guide=g,steps=g.steps,startIndex=4};G.db.progress['simultaneous:reward']=nil;G.Render()
 assert(string.len(G.frame.details.value)>3000 and G.frame.detailsScroll:GetHeight()<=220 and G.frame.detailsScroll.maxScroll>0)
 local scroll=G.frame.detailsScroll;this=scroll;arg1=-1;scroll.scripts.OnMouseWheel();assert(scroll:GetVerticalScroll()==36)
 this=nil;arg1=nil
end)
check('class-specific coordinates select only the player location',function()
 local s={action='travel',text='Trainer',profiles={'Troll:HUNTER','Troll:SHAMAN'},locations={['Troll:HUNTER']={zone=14,x=.4,y=.6},['Troll:SHAMAN']={zone=14,x=.5,y=.7}}}
 G.player.class='HUNTER';assert(G.Allowed(s) and s.x==.4)
 G.player.class='SHAMAN';assert(G.Allowed(s) and s.x==.5)
 G.player.class='HUNTER'
end)
check('an item-use quest step advances only when its own quest goal is complete',function()
 testQuestLog[6082]={complete=false};testQuestLog[6083]={complete=true}
 assert(not G.Satisfied({action='use',manual=true,goalQuestID=6082,text='Use the taming rod'}))
 testQuestLog[6082].complete=true;assert(G.Satisfied({action='use',manual=true,goalQuestID=6082,text='Use the taming rod'}))
 assert(not G.db.completedQuests[6082])
end)
check('removing the family addon preserves a usable baseline and the source preference',function()
 G.db.routeSource='rxp';G.hasFamilyRoutes=nil
 assert(G.RouteSource()=='baseline' and G.db.routeSource=='rxp')
 G.db.routeSource='baseline'
end)
print('ALL '..passed..' ROUTE CHECKS PASSED')
