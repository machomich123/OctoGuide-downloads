dofile('tests/test-runtime.lua')
local G=OctoGuide
local methods=getmetatable(G.frame).__index
function methods:SetAlpha(a) self.alpha=a end
dofile('Appearance.lua');dofile('LiveTargets.lua');dofile('Reports.lua')
G.ready=false;G.Init()
assert(G.options:GetHeight()==650 and G.menu.panelSkin)
assert(G.menu.panelSkin[1].point[2]==G.menu,'Menu skin must anchor to menu, not guide')
G.db.transparent=true;G.SetOpacity(35)
assert(G.frame.bg.alpha==.35 and G.menu.panelSkin[1].alpha==.35)
assert(not G.frame.title.alpha,'Text must not inherit opacity')
G.db.transparent=false;G.ApplyOpacity();assert(G.frame.bg.alpha==1 and G.db.opacity==35)
G.hasFamilyRoutes=true;G.db.routeSource='baseline';assert(G.RouteSource()=='rxp');G.hasFamilyRoutes=nil
G.RegisterGuide({id='live',faction='Horde',startLevel=1,endLevel=6},{
 {id='work',action='objective',text='Kill',questID=801,objective=1,zone=1,x=.5,y=.5},
 {id='pickup',action='accept',text='Accept parallel',questID=802,zone=1,x=.1,y=.1},
 {id='turn',action='turnin',text='Turn in',questID=801}})
G.db.progress={};G.db.completedQuests={};testQuestLog[801]={objectives={{'Mottled Boar: 0 / 10',false}}}
G.Select('live');assert(G.Current().id=='pickup','Grouped pickup must precede work')
testQuestLog[802]={};G.Sync();assert(G.Current().id=='work')
function GetQuestLogLeaderBoardID() return 3098,'monster' end
local alive=true;local distance=12
function UnitCreatureID(token) return token=='target' and 3098 or 0 end
function UnitIsDeadOrGhost() return not alive end
function UnitHealth() return alive and 50 or 0 end
function UnitPosition(token) return 0,token=='target' and distance or 0,0,1 end
local r=G.ReadObservedTarget(G.Current());assert(r and r.yards==12 and r.label=='Live quest target')
alive=false;assert(not G.ReadObservedTarget(G.Current()),'Never select corpses')
G.livePoll=nil;G.NavigationRead(G.Current());assert(G.navigationEvidence=='Quest area')
pfDB={units={data={[3098]={coords={{40,40,1},{49,49,1},{1,1,1}}}}}}
G.livePoll=nil;G.NavigationRead(G.Current());assert(G.navigationEvidence=='Possible quest spawn')
pfDB=nil
alive=true;testQuestLog[801].objectives[1][2]=true;assert(not G.ReadObservedTarget(G.Current()),'Completed objectives must not navigate')
testQuestLog[801].objectives[1][2]=false
local concurrent=G.Concurrent;G.Concurrent=function() return {{action='objective',text='Cactus apples',zone=1,x=.2,y=.2}} end
G.db.secondaryArrow=true;G.UpdateSecondaryArrow();assert(G.frame.secondaryArrow:IsShown() and G.frame.secondaryArrow.width==20)
G.db.secondaryArrow=false;G.UpdateSecondaryArrow();assert(not G.frame.secondaryArrow:IsShown());G.Concurrent=concurrent
local before=G.menu:IsShown();local report=G.MakeReport('Resize shifted after changing zoom')
assert(report and report.apis.UnitPosition and report.ui.guides.rows and report.status=='saved locally')
assert(report.upload=='unavailable in this client' and report.images~='screenshots')
assert(G.menu:IsShown()==before and not report.chat and not report.account)
for i=1,125 do G.ReportEvent('QUEST_LOG_UPDATE') end
assert(table.getn(G.reportEvents)==100 and table.getn(report.events)<100,'Reports must retain frozen event copies')
for i=1,15 do G.MakeReport('Bounded reports') end;assert(table.getn(G.db.reports)==10)
assert(not G.MakeReport('   '));G.ShowReport();assert(G.reportWindow:IsShown())
print('PASS 0.5.0 appearance, source, grouped pickups, living targets and bounded private diagnostics')
