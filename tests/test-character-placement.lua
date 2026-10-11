dofile('tests/test-runtime.lua')
dofile('Placement.lua')
local G=OctoGuide
G.guides={};G.order={};G.hasFamilyRoutes=nil
dofile('Guides.lua')
function UnitLevel() return 2 end
function UnitXP() return 0 end
function UnitXPMax() return 100 end
function UnitName() return 'Benito' end
function GetRealmName() return 'TestRealm' end
G.player={race='Orc',class='WARLOCK',faction='Horde'}
G.db={progress={},completedQuests={},mode='hardcore',routeSource='baseline'}
pfQuest_history={[788]={1,2},[789]={1,3},[4402]={1,3},[804]={1,4},[790]={1,3},[791]={1,3}}
G.RefreshHistory(false)
local p=G.FindPlacement()
assert(p and p.steps[p.index].questID==4641,'External history must not place a new character at Thazzril')
assert(not next(G.db.completedQuests),'External cache is not player completion')
G.db.characterOwner='TestRealm:Rogue';G.db.progress={rogue=true};G.db.completedQuests={[788]=true};G.db.guide='rogue-guide';G.db.placements={old={stepID='late'}}
G.BindCharacter()
assert(G.db.characterOwner=='TestRealm:Benito' and not next(G.db.progress) and not next(G.db.completedQuests) and not G.db.guide)
assert(G.db.characterArchives['TestRealm:Rogue'].progress.rogue,'Old character progress must remain recoverable')
G.db.progress.benito=true;G.BindCharacter();assert(G.db.progress.benito,'Same-character reload preserves progress')
local title,body=G.Present({action='accept',text="Accept Thazzril's Pick from Foreman Thazzril.",minlevel=3})
assert(string.find(title,'Reach level 3',1,true) and string.find(body,'not available',1,true))
print('ALL 5 CHARACTER PLACEMENT REGRESSION CHECKS PASSED')
