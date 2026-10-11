dofile('tests/test-runtime.lua')
local G=OctoGuide
local methods=getmetatable(G.frame).__index
function methods:SetAlpha(a) self.alpha=a end
dofile('Supplies.lua');dofile('Appearance.lua');dofile('Compact.lua');dofile('LiveTargets.lua');dofile('Reports.lua');dofile('ReportTransport.lua')
G.ready=false;G.Init()
assert(G.frame.arrow.width==55 and G.frame.secondaryArrow.width==25)
G.db.view='minimal';G.db.controlsCollapsed=nil;G.Render()
assert(not G.frame.title:IsShown() and not G.frame.version:IsShown() and not G.frame.route:IsShown())
assert(not G.frame.done:IsShown() and G.frame.controlsToggle:IsShown())
G.frame.controlsToggle.scripts.OnClick();assert(not G.ControlsCollapsed() and G.frame.done:IsShown())
assert(G.frame.close.point[4]==G.frame:GetWidth()-58 and G.frame.close.point[5]==-14)
G.db.view='full';G.Render();assert(G.frame.title:IsShown())
assert(G.menu.scripts.OnDragStart and G.options.scripts.OnDragStop)
G.menu.scripts.OnDragStop();assert(G.db.windowPositions.guides[1]==100)
for _,w in ipairs({26,56,100,410,750}) do
 local b=G.MakeButton(G.frame,'Test',w,function() end)
 assert(table.getn(b.parts)==3 and not b.surface:IsShown())
 assert(b.parts[1].width<=25.4 and b.parts[3].width==b.parts[1].width)
 local count=table.getn(b.parts);G.StyleButton(b);assert(table.getn(b.parts)==count)
end
G.RegisterGuide({id='supplies',faction='Horde',startLevel=1,endLevel=6,routeFamily='rxp',blockNotes={[1]={{text='Buy Refreshing Spring Water'}},[2]={{text='Collect the quest object'}}}},{
 {id='water',action='collect',text='Perform collect 159,15,6394,1.',itemID=159,sourceBlock=1},
 {id='vendor',action='vendor',text='Vendor Trash',sourceBlock=1,manual=true},
 {id='questItem',action='collect',text='Quest item',itemID=159,questID=901,sourceBlock=2},
 {id='questVendor',action='vendor',text='Vendor',sourceBlock=2}})
assert(not G.Allowed(G.guides.supplies.steps[1]))
assert(G.guides.supplies.steps[2].optionalSupply and G.StepButton(G.guides.supplies.steps[2])=='Skip')
assert(G.Allowed(G.guides.supplies.steps[3]),'Real quest collection must remain')
local title=G.Present(G.guides.supplies.steps[2]);assert(string.find(title,'Optional',1,true))
local text=G.ReportJSON({description='quotes " and slash \\ and\nnew line',truth=true,number=5,list={1,2}})
assert(string.find(text,'\\n',1,true)==nil and string.find(text,'\\u000a',1,true))
assert(string.find(text,'[1,2]',1,true) and string.find(text,'\\"',1,true))
local r,why=G.SendReport('Offline test');assert(r and r.upload=='unavailable in this client')
function GetBuildInfo() return '1.12.1','5875','fixture' end
function GetNumAddOns() return 1 end
function GetAddOnInfo() return 'FixtureAddon','Title','Notes',1,1 end
function GetAddOnMetadata() return '2.0' end
function IsAddOnLoaded() return true end
function GetNumQuestLogEntries() return 1 end
r=G.MakeReport('Diagnostics inventory');assert(r.client.version=='1.12.1' and r.addons[1].version=='2.0' and r.addons[1].loaded and table.getn(r.questLog)==1)
function OctoGuideBridgeVersion() return 1 end
local capture=0
function OctoGuideCaptureBegin() capture=0 end
function OctoGuideCaptureUI(name,x,y,w,h) capture=capture+1;assert(name~='chat' and w>0 and h>0);return 1 end
local state='sending'
function OctoGuideSendReport(json) assert(string.len(json)<120000);return 1 end
function OctoGuideReportStatus() return state,'{"received":true,"id":"test"}' end
G.CaptureReportUI();assert(capture>0)
r=G.SendReport('Bridge test');assert(r.status=='sending' and r.upload=='pending')
assert(not G.SendReport('Second report while busy'))
state='sent';G.PollReport();assert(r.status=='received online' and not G.pendingReport)
r=G.SendReport('Failure test');state='failed';G.PollReport();assert(r.status=='saved locally' and r.upload=='failed')
local work={id='observed',action='objective',questID=902,objective=1,zone=1,x=.5,y=.5}
testQuestLog[902]={objectives={{'Target: 0 / 5',false}}}
function GetQuestLogLeaderBoardID() return 3098,'monster' end
function UnitPosition() return 0,0,0,1 end
function OctoGuideClosestLivingUnit(id,state) assert(id==3098);return 0,17,17,'0xF130000000000001' end
local live=G.ReadObservedTarget(work);assert(live and live.yards==17 and live.guid)
assert(G.SecondaryRead(work).label=='Live quest target')
print('PASS 0.5.1 sliced controls, minimal header, movable menus, safe vendor normalization, native observation and report state transitions')
