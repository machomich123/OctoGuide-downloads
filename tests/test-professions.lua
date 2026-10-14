-- Release TOC and actual button callbacks, Lua 5.0 / Classic client API fixtures.
dofile('tests/test-sync-manifest.lua')
local G=OctoGuide;local P=G.Professions;local passed=0
local function test(name,fn) fn();passed=passed+1;print('PASS profession: '..name) end
local methods=getmetatable(UIParent).__index
function methods:SetAutoFocus() end
local ranks={Mining={rank=150,cap=225},Alchemy={rank=20,cap=75},Survival={rank=130,cap=150},Enchanting={rank=40,cap=75}}
local order={'Mining','Alchemy','Survival','Enchanting'}
function GetNumSkillLines() return table.getn(order) end
function GetSkillLineInfo(i) local r=ranks[order[i]];return order[i],false,false,r.rank,0,0,r.cap end
local bag={[765]=1,[2447]=1}
function GetContainerNumSlots(b) return b==0 and 2 or 0 end
function GetContainerItemLink(b,s) return '|Hitem:'..(s==1 and 765 or 2447)..':0:0:0|h[Material]|h' end
function GetContainerItemInfo(b,s) return 'texture',bag[s==1 and 765 or 2447] end
local recipes={
 {name='Fast potion',color='optimal',item=1001,mats={{765,'Silverleaf',2}}},
 {name='Cheap potion',color='optimal',item=1002,mats={{2447,'Peacebloom',1}}},
 {name='Gray potion',color='trivial',item=1003,mats={{2447,'Peacebloom',1}}}}
function GetTradeSkillLine() return 'Alchemy',ranks.Alchemy.rank,75 end
function GetNumTradeSkills() return table.getn(recipes) end
function GetTradeSkillInfo(i) local r=recipes[i];return r.name,r.color,0 end
function GetTradeSkillItemLink(i) return '|Hitem:'..recipes[i].item..'|h[Item]|h' end
function GetTradeSkillNumReagents(i) return table.getn(recipes[i].mats) end
function GetTradeSkillReagentInfo(i,j) local r=recipes[i].mats[j];return r[2],'texture',r[3],0 end
function GetTradeSkillReagentItemLink(i,j) return '|Hitem:'..recipes[i].mats[j][1]..'|h[Material]|h' end
function GetTradeSkillTools() return 'Tool',1 end
function GetTradeSkillCooldown() return 0 end
local s=P.State();s.selected='Alchemy';s.goal=300
test('all fourteen professions and sources load',function()
 assert(table.getn(G.ProfessionData.order)==14)
 for _,name in ipairs(G.ProfessionData.order) do local p=G.ProfessionData.professions[name];assert(p and p.source and p.bands[table.getn(p.bands)][1]==300);local prev=0;for _,b in ipairs(p.bands) do assert(b[1]>prev);prev=b[1] end end
end)
test('captures learned recipes using reagent item IDs',function()
 assert(P.Capture('trade'));assert(s.recipes.Alchemy.rank==20 and table.getn(s.recipes.Alchemy.recipes)==3)
 assert(s.recipes.Alchemy.recipes[1].reagents[1].id==765)
 assert(P.Bags()[765]==1)
end)
test('fast and cheap make different bounded choices',function()
 local list=s.recipes.Alchemy.recipes
 s.craftTimes[list[1].key]=1;s.craftTimes[list[2].key]=12
 s.inputs[765]={price=100,seconds=9};s.inputs[2447]={price=0,seconds=0}
 s.mode='fast';local r=P.Choose(list,P.Bags(),s);assert(r.recipe.name=='Fast potion' and r.perPointSeconds==10 and r.perPointCash==100)
 s.mode='cheap';s.tolerance=20;r=P.Choose(list,P.Bags(),s);assert(r.recipe.name=='Cheap potion' and r.perPointSeconds==12 and r.perPointCash==0)
 s.tolerance=10;r=P.Choose(list,P.Bags(),s);assert(r.recipe.name=='Fast potion')
end)
test('unknown prices are not treated as zero',function()
 s.inputs[765]={};local r=P.Evaluate(s.recipes.Alchemy.recipes[1],P.Bags(),s);assert(not r.cashKnown and not r.timeKnown)
 assert(P.Money(nil)=='unknown');assert(not P.SetInput(765,-1,1));assert(not P.SetInput(765,1,-1));assert(P.SetInput(765,nil,nil))
end)
test('gray and cooldown recipes are excluded',function()
 local r=s.recipes.Alchemy.recipes[3];assert(not P.Evaluate(r,P.Bags(),s));r=s.recipes.Alchemy.recipes[1];r.cooldown=60;assert(not P.Evaluate(r,P.Bags(),s));r.cooldown=0
end)
test('aggregate duplicate reagents and missing tools',function()
 local r={name='Duplicate',color='optimal',key='duplicate',cooldown=0,reagents={{id=765,name='Silverleaf',quantity=1},{id=765,name='Silverleaf',quantity=2}},tools={{name='Anvil',present=false}}}
 local a=P.Evaluate(r,P.Bags(),s);assert(a.materials[1].quantity==3 and a.materials[1].missing==2 and not a.toolsReady and not a.timeKnown)
end)
test('stale colors require reopening recipes; skill caps require training',function()
 ranks.Alchemy.rank=21;assert(P.Advice('Alchemy').action=='scan');ranks.Alchemy.rank=75;assert(P.Advice('Alchemy').action=='train');ranks.Alchemy.rank=20
end)
test('uncached reagent links cannot overwrite useful data',function()
 local before=s.recipes.Alchemy;local old=GetTradeSkillReagentItemLink;GetTradeSkillReagentItemLink=function() end;assert(not P.Capture('trade'));assert(s.recipes.Alchemy==before);GetTradeSkillReagentItemLink=old
end)
test('same-name variants retain distinct reagent identity',function()
 local before=recipes[2].name;recipes[2].name=recipes[1].name;assert(P.Capture('trade'));assert(s.recipes.Alchemy.recipes[1].key~=s.recipes.Alchemy.recipes[2].key);recipes[2].name=before;P.Capture('trade')
end)
test('Vanilla Enchanting name-only skill line is captured; pet training rejected',function()
 function GetCraftDisplaySkillLine() return 'Enchanting' end
 function GetNumCrafts() return 1 end
 function GetCraftInfo() return 'Enchant Bracer','', 'optimal',0 end
 function GetCraftNumReagents() return 1 end
 function GetCraftReagentInfo() return 'Strange Dust','texture',1,1 end
 function GetCraftReagentItemLink() return '|Hitem:10940|h[Dust]|h' end
 assert(P.Capture('craft'));assert(s.recipes.Enchanting.rank==40)
 GetCraftDisplaySkillLine=function() return 'Beast Training' end;assert(not P.Capture('craft'))
end)
local nodes={
 copper={key='copper',id=1,cat='ore',name='Copper Vein',skill=1,zone=1,x=1,y=0},
 iron={key='iron',id=2,cat='ore',name='Iron Deposit',skill=125,zone=1,x=20,y=0},
 hidden={key='hidden',id=3,cat='ore',name='Iron Deposit',skill=125,zone=1,x=2,y=0},
 high={key='high',id=4,cat='ore',name='Mithril Deposit',skill=175,zone=1,x=3,y=0},
 simple={key='simple',id=5,cat='wood',name='Simple Wood Tree',skill=5,zone=1,x=1,y=0},
 bright={key='bright',id=6,cat='wood',name='Bright Wood Tree',skill=125,zone=1,x=10,y=0}}
OctoGather={ready=true,byKey=nodes,MapVisible=function(n) return n.key~='hidden' end}
P.ClearMarker()
test('leveling avoids gray, hidden and high-skill ore',function() assert(P.FindResource('ore',true));assert(G.gatherTarget.key=='iron') end)
test('material gathering allows gray Copper; bars map to raw ore',function()
 local map=P.MaterialResource({id=2840,name='Copper Bar'});assert(map.cat=='ore' and map.note)
 assert(P.FindResource(map.cat,false,map.names));assert(G.gatherTarget.key=='copper')
end)
test('Survival targets latest eligible wood tier',function() assert(P.FindResource('wood',true));assert(G.gatherTarget.key=='bright');assert(P.MaterialResource({id=99999,name='Bright Wood'}).cat=='wood');assert(not P.MaterialResource({id=99998,name='Bundle of Bright Wood Sticks'})) end)
test('tracking is called only by explicit action',function()
 local used=0;OctoGather.TrackingList=function() return {{name='Find Minerals'}} end;OctoGather.Track=function(row) used=used+1;assert(row.name=='Find Minerals') end
 P.Advice('Mining');assert(used==0);assert(P.Track('ore') and used==1);assert(not P.Track('wood'))
end)
test('actual slash and UI choices preserve current quest',function()
 local before=G.Current();local guide=G.db.guide;local progress=G.db.progress
 G.Slash('professions');assert(G.professionPanel:IsShown())
 local b=G.professionPanel.professions[14];this=b;b.scripts.OnClick();assert(s.selected=='Survival')
 G.professionPanel.cheap.scripts.OnClick();assert(s.mode=='cheap');G.professionPanel.fast.scripts.OnClick();assert(s.mode=='fast')
 P.ReturnToQuests();assert(G.Current()==before and G.db.guide==guide and G.db.progress==progress)
end)
test('marker avoids SetTarget boolean defect and expires while panel closed',function()
 local clock=100;function GetTime() return clock end
 local added,deleted=0,0;pfMap={AddNode=function() added=added+1;pfMap.queue_update=true end,DeleteNode=function() deleted=deleted+1 end,ShowMapID=function() end}
 P.ClearMarker();assert(P.ShowLocation({name='Trainer',id=1,zone=1,x=20,y=0}));assert(type(pfMap.queue_update)=='number' and added==1 and P.waypoint)
 G.professionPanel:Hide();clock=221;P.timer.scripts.OnUpdate();assert(not P.marker and not P.waypoint and deleted==1)
 pfMap=nil
end)
test('new controls fit inside panel and actual parent dialogs',function()
 local p=G.professionPanel
 for _,b in ipairs(p.professions) do assert(b.point[4]+b.width<=p.width and -b.point[5]+b.height<=p.height) end
 for _,b in ipairs({p.fast,p.cheap,p.tolerance,p.node,p.track,p.trainers,p.source,p.lifetime}) do assert(b.point[4]+b.width<=p.width and -b.point[5]+b.height<=p.height) end
 assert(p.scroll.name=='OctoGuideProfessionScroll' and not p.locations:IsShown() and not p.editor:IsShown())
end)
test('prices and time editor saves actual typed values',function()
 P.EditMaterial({id=765,name='Silverleaf'});local editor=G.professionPanel.editor;editor.price:SetText('125');editor.seconds:SetText('42')
 assert(editor.material.id==765 and editor.price:GetText()=='125');editor.save.scripts.OnClick()
 assert(s.inputs[765].price==125 and s.inputs[765].seconds==42);editor:Hide()
 P.EditMaterial({id=765,name='Silverleaf'});editor.price:SetText('bad');editor.save.scripts.OnClick();assert(editor:IsShown() and s.inputs[765].price==125);editor:Hide()
end)
test('missing/unlearned and achieved professions have explicit next actions',function()
 assert(P.Advice('Fishing').action=='learn');local old=s.goal;s.goal=150;assert(P.Advice('Mining').action=='done');s.goal=old
end)
test('node disappearance clears profession waypoint and marker',function()
 local clock=100;GetTime=function() return clock end
 assert(P.FindResource('ore',true));assert(P.marker.resourceKey=='iron')
 local visible=OctoGather.MapVisible;OctoGather.MapVisible=function() return false end
 P.timer.scripts.OnUpdate();assert(not P.marker and not P.waypoint and not G.gatherTarget);OctoGather.MapVisible=visible
end)
test('NPC pack prices use per-item values and reject extended currency',function()
 function GetMerchantNumItems() return 2 end
 function GetMerchantItemLink(i) return '|Hitem:'..(i==1 and 159 or 160)..'|h[Vendor]|h' end
 function GetMerchantItemInfo(i) return 'Vendor','texture',100,5,10,true,i==2 end
 P.CaptureVendor();assert(s.vendorPrices[159].price==20 and not s.vendorPrices[160])
end)
print('PASS '..passed..' profession scenarios')
