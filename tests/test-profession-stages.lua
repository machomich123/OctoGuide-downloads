dofile('tests/test-professions.lua')
local G=OctoGuide;local P=G.Professions
local powder={key='powder',name='Rough Blasting Powder',item=4357,color='optimal',yield=1,cooldown=0,reagents={{id=2835,name='Rough Stone',quantity=1}},tools={}}
local shot={key='shot',name='Crafted Light Shot',item=2516,color='optimal',yield=200,cooldown=0,reagents={{id=4357,name='Rough Blasting Powder',quantity=1},{id=2840,name='Copper Bar',quantity=1}},tools={}}
local dynamite={key='dynamite',name='Rough Dynamite',item=4358,color='optimal',yield=2,cooldown=0,reagents={{id=4357,name='Rough Blasting Powder',quantity=2},{id=2589,name='Linen Cloth',quantity=1}},tools={}}
local bolts={key='bolts',name='Handful of Copper Bolts',item=4359,color='optimal',yield=1,cooldown=0,reagents={{id=2840,name='Copper Bar',quantity=1}},tools={}}
local recipes={powder,shot,dynamite,bolts}
for _,mode in ipairs({'fast','cheap'}) do for stock=0,2 do
 local state={mode=mode,tolerance=20,inputs={},vendorPrices={},craftTimes={}}
 local plan=P.EngineeringPlan(10,recipes,{[4357]=stock,[2840]=30,[2589]=30},state)
 assert(plan.choice.recipe==powder and plan.choice.stage.untilRank==30,'First 0/1/2 powder must not redirect to shot/dynamite')
end end
local state={mode='cheap',tolerance=20,inputs={[2835]={price=20},[2840]={price=100},[2589]={price=10}},vendorPrices={},craftTimes={}}
assert(P.UnitValue(4357,state,recipes,{})==20)
local value=P.UnitValue(4358,state,recipes,{});assert(value==25,'Dynamite batch value must include two powder and cloth, divided by actual yield')
state.valueRecipes=recipes
local a=P.Evaluate(dynamite,{[4357]=100,[2589]=100},state);assert(a.cash==0 and a.value==50 and a.valueKnown,'Owned intermediates retain value even with no new purchases')
state.valueRecipes=nil
local plan=P.EngineeringPlan(30,recipes,{[4357]=60},state);assert(plan.choice.recipe==bolts and plan.stage.untilRank==50)
local missing=P.EngineeringPlan(30,{powder,shot,dynamite},{},state);assert(missing.missingRecipe,'Unknown required recipe must show training, not manufacture a learned recipe')
-- Cyclic reagent definitions remain unknown rather than recurse forever.
local cyclic={{item=900,key='a',yield=1,reagents={{id=901,quantity=1}}},{item=901,key='b',yield=1,reagents={{id=900,quantity=1}}}}
assert(P.UnitValue(900,state,cyclic,{})==nil)
local f=G.frame;G.db.controlsCollapsed=false;G.db.view='minimal';G.Render()
local b=f.professionsButton;assert(b and b:IsShown() and b.point[5]==f.settingsButton.point[5] and b.point[4]>f.settingsButton.point[4])
assert(b.point[4]+b.width<f.width)
b.scripts.OnClick();assert(G.professionPanel:IsShown())
G.db.controlsCollapsed=true;G.Render();assert(not b:IsShown())
print('PASS early Engineering stage persistence at 0/1/2 powder, raw-material value/yields, missing recipes/cycles and actual sixth main button')
