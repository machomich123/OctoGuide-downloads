local file=assert(io.open('tests/test-runtime.lua'));local source=file:read('*a');file:close()
assert(loadstring(string.sub(source,1,assert(string.find(source,"dofile('Core.lua')",1,true))-1)))()
dofile('Core.lua');dofile('Route.lua');dofile('RouteRepairs.lua');dofile('Placement.lua');dofile('CharacterScan.lua')
local G=OctoGuide;G.player={class='HUNTER',race='Orc',faction='Horde'};G.ready=true;G.Render=function()end
G.db={progress={},completedQuests={},placements={},mode='hardcore'}
function UnitLevel()return 8 end;function UnitXP()return 0 end;function UnitXPMax()return 100 end
local bag,worn=false,false
GetItemCount=nil
function GetContainerNumSlots(b)return b==0 and bag and 1 or 0 end
function GetContainerItemLink()return bag and 'item:2506:0:0:0'end
function GetContainerItemInfo()return 'icon',1 end
function GetInventoryItemLink(_,slot)return worn and slot==18 and '|cff1eff00|Hitem:2506:0:0:0|h[Bow]|h|r'end
function GetInventoryItemCount()return 1 end
function GetNumQuestLogEntries()return 0 end
G.RegisterGuide({id='bow-fix',title='Bow test',faction='Horde',startLevel=6,endLevel=10}, {
 {id='sell1',action='vendor',text='Vendor trash for [Hornwood Recurve Bow]',manual=true},
 {id='buy1',action='collect',text='Collect bow',itemID=2506,itemCount=1},
 {id='sell2',action='vendor',text='Vendor trash for [Hornwood Recurve Bow]',manual=true},
 {id='buy2',action='collect',text='Collect bow',itemID=2506,itemCount=1},
 {id='next',action='note',text='Continue route',manual=true}})
G.Select('bow-fix');assert(G.Current().id=='sell1')
worn=true;G.Event('BAG_UPDATE');assert(G.Satisfied(G.state.steps[1]) and G.Satisfied(G.state.steps[3]),'Equipped bow satisfies every related vendor stop')
assert(G.Current().id=='next','Equipped bow also satisfies collect steps without GetItemCount')
local scan=G.ScanCharacter();assert(G.StepEvidence(G.state.steps[1],scan)=='required item already carried or equipped')
-- Done remains Done after Find step, including for a generic manual vendor stop.
G.RegisterGuide({id='manual-test',faction='Horde',startLevel=8,endLevel=9},{{id='sold',action='vendor',text='Sell trash',manual=true},{id='next',action='note',text='Continue',manual=true}})
G.guides['bow-fix'].mode='normal';G.characterScan=nil;G.db.placements={};G.Select('manual-test');G.Mark('manual')
assert(G.Current().id=='next');assert(G.FindStep(false));assert(G.Current().id=='next','Find step must not repeat Done vendor')
-- With neither bow nor prior Done, the vendor instruction remains a real step.
G.guides['bow-fix'].mode='hardcore';G.guides['manual-test'].mode='normal';G.db.progress={};G.db.placements={};G.characterScan=nil;worn=false;bag=false
G.Select('bow-fix');assert(G.Current().id=='sell1' and not G.GoalItemCarried(G.Current()))
bag=true;assert(G.GoalItemCarried(G.Current()),'Bag possession also satisfies vendor goal')
-- Family routes missing Lost Deathstalkers receive the required pickup and return.
G.guides={};G.order={};G.hasFamilyRoutes=nil;G.characterScan=nil;G.db.progress={};G.db.placements={};G.db.completedQuests={}
G.RegisterGuide({id='wild-fix',routeFamily='rxp',faction='Horde',startLevel=13,endLevel=15}, {
 {id='escort',action='turnin',text='Turn in Escorting Erland',questID=435},
 {id='wild',action='accept',text='Accept Wild Hearts.',questID=429,requires={428}},
 {id='next',action='note',text='Continue',manual=true}})
local g=G.guides['wild-fix'];assert(g.steps[1].questID==428 and g.steps[1].action=='accept')
G.db.completedQuests[435]=true;G.db.placements[g.id]={stepID='wild',reason='automatic'}
function UnitLevel()return 13 end
G.Select(g.id,'restore');assert(G.Current().questID==428 and G.Current().action=='accept','Escort alone is insufficient')
testQuestLog[428]={complete=false};G.Event('QUEST_ACCEPTED',428);assert(G.Current().questID==428 and G.Current().action=='turnin','Accepted delivery prerequisite returns to Rane even without a ready flag')
assert(not G.db.completedQuests[428]);G.Event('QUEST_FINISHED');assert(G.Current().questID==428)
testQuestLog[428]=nil;G.Event('QUEST_TURNED_IN',428);assert(G.Current().id=='wild','Only confirmed Lost Deathstalkers turn-in unlocks Wild Hearts step')
G.db.progress={};G.db.completedQuests={};G.db.placements[g.id]={stepID='wild',reason='automatic'};testQuestLog[429]={complete=false}
G.Select(g.id,'restore');assert(G.Current().id=='next','Already accepted Wild Hearts needs no invented prerequisite replay')
assert(not G.db.completedQuests[428],'Inferring access does not manufacture quest reward history')
print('PASS bow equipped/bag ownership, repeated vendor goals, Done + Find step, and Lost Deathstalkers prerequisite')
